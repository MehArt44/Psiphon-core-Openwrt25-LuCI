#!/bin/sh
# ---------------------------------------------------------------------------
# Test_Full.sh - full test suite for luci-app-psiphon (Psiphon VPN for OpenWrt)
# Companion of Psiphon_VPN_2_0_42_manual_setup.sh
#
# Sections (run in this order):
#   env        router prerequisites (packages, tun, TLS, flash, nftables)
#   files      installed files, permissions, syntax, JSON, core binary flags
#   config     UCI values, firewall zone, dnsmasq confdir, sysupgrade entries
#   helper     offline unit tests of psiphon-helper (config generator, parsers,
#              CIDR/IP logic, MTU/MSS, nft rulesets in --check mode: nothing is applied)
#   live       checks against the running service (tunnel, routes, DNS, leaks)
#   net        light network tests (TLS probe of an edge IP; CDN scanner with --full)
#   lifecycle  (only with --full) restart -> connect -> checks -> stop -> verify
#              cleanup -> restore the previous state. This interrupts the VPN.
#
# Usage: sh Test_Full.sh [options]
#   -q, --quick        only env + files + config (static, instant)
#   -f, --full         also run lifecycle test and CDN scanner test
#   -y, --yes          do not ask before the lifecycle test
#   --only a,b,c       run only the named sections (see list above)
#   -v, --verbose      print extra details for passed tests
#   --no-color         disable colors
#   -h, --help         show this help
#
# Exit code: 0 = no failures (warnings allowed), 1 = at least one failure.
# ---------------------------------------------------------------------------

HELPER="${PSI_HELPER:-/usr/bin/psiphon-helper}"
INIT="${PSI_INIT:-/etc/init.d/psiphon}"
CORE="${PSI_CORE:-/usr/bin/psiphon-core}"
HOTPLUG=/etc/hotplug.d/iface/90-psiphon
MENU=/usr/share/luci/menu.d/luci-app-psiphon.json
ACL=/usr/share/rpcd/acl.d/luci-app-psiphon.json
VIEW=/www/luci-static/resources/view/vpn/psiphon.js
UCIFILE=/etc/config/psiphon
SUCONF=/etc/sysupgrade.conf
RUN=/tmp/psiphon
LOG=/tmp/psiphon.log
TUN=tun0
RT=100

PASS=0; FAIL=0; WARN=0; SKIP=0
FULL=0; QUICK=0; YES=0; VERBOSE=0; NOCOLOR=0; ONLY=""

usage() {
	cat <<'USAGE'
Usage: sh Test_Full.sh [options]
  -q, --quick        only env + files + config (static, instant)
  -f, --full         also run lifecycle test (restart/stop the VPN) and CDN scanner test
  -y, --yes          do not ask before the lifecycle test
  --only a,b,c       run only these sections: env files config helper live net lifecycle
  -v, --verbose      print extra details for passed tests
  --no-color         disable colors
  -h, --help         show this help
USAGE
}

while [ $# -gt 0 ]; do
	case "$1" in
		-q|--quick) QUICK=1 ;;
		-f|--full) FULL=1 ;;
		-y|--yes) YES=1 ;;
		-v|--verbose) VERBOSE=1 ;;
		--no-color) NOCOLOR=1 ;;
		--only) shift; ONLY="$1" ;;
		--only=*) ONLY="${1#--only=}" ;;
		-h|--help) usage; exit 0 ;;
		*) echo "unknown option: $1" >&2; usage; exit 2 ;;
	esac
	shift
done
[ "$QUICK" = 1 ] && [ -z "$ONLY" ] && ONLY="env,files,config"

# default sections; lifecycle only on request
want() {
	if [ -z "$ONLY" ]; then
		[ "$1" = lifecycle ] && [ "$FULL" != 1 ] && return 1
		return 0
	fi
	case ",$ONLY," in *",$1,"*) return 0 ;; esac
	return 1
}

# ---- output -----------------------------------------------------------------
if [ -t 1 ] && [ "$NOCOLOR" != 1 ]; then
	C_R=$(printf '\033[31m'); C_G=$(printf '\033[32m'); C_Y=$(printf '\033[33m')
	C_B=$(printf '\033[36m'); C_D=$(printf '\033[2m');  C_N=$(printf '\033[0m')
else
	C_R=""; C_G=""; C_Y=""; C_B=""; C_D=""; C_N=""
fi

TMPD=$(mktemp -d /tmp/psiphon-test.XXXXXX 2>/dev/null) || { echo "mktemp failed" >&2; exit 1; }
: > "$TMPD/failed"; : > "$TMPD/warned"
cleanup_tmp() { rm -rf "$TMPD"; }
trap cleanup_tmp EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

section() { printf '\n%s== %s ==%s\n' "$C_B" "$*" "$C_N"; }
pass() { PASS=$((PASS+1)); printf '  %s[PASS]%s %s\n' "$C_G" "$C_N" "$1"; }
fail() { FAIL=$((FAIL+1)); printf '  %s[FAIL]%s %s\n' "$C_R" "$C_N" "$1"; echo "$1" >> "$TMPD/failed"; }
warn() { WARN=$((WARN+1)); printf '  %s[WARN]%s %s\n' "$C_Y" "$C_N" "$1"; echo "$1" >> "$TMPD/warned"; }
skip() { SKIP=$((SKIP+1)); printf '  %s[SKIP]%s %s\n' "$C_D" "$C_N" "$1"; }
info() { [ "$VERBOSE" = 1 ] && printf '         %s%s%s\n' "$C_D" "$1" "$C_N"; return 0; }

have() { command -v "$1" >/dev/null 2>&1; }
T() { local _s="$1"; shift; if have timeout; then timeout "$_s" "$@"; else "$@"; fi; }
U() { uci -q get "psiphon.config.$1" 2>/dev/null; }
jf() { printf '%s' "$1" | jsonfilter -e "$2" 2>/dev/null; }
valid_json() { printf '%s' "$1" | jsonfilter -e '@' >/dev/null 2>&1; }
bool_on() { case "$1" in 1|on|true|yes|enabled) return 0 ;; esac; return 1; }

# t_eq "description" actual expected
t_eq() {
	if [ "$2" = "$3" ]; then pass "$1"; info "= $2"; else fail "$1 (expected '$3', got '$2')"; fi
}
# t_ok "description" command...   (passes when the command succeeds)
t_ok() {
	local _d="$1"; shift
	if "$@" >/dev/null 2>&1; then pass "$_d"; else fail "$_d"; fi
}

valid_ipv4() {
	echo "$1" | awk -F. 'NF==4 { for (i=1;i<=4;i++) if ($i !~ /^[0-9]+$/ || $i+0 > 255) exit 1; exit 0 } { exit 1 }'
}
valid_host() {
	[ -n "$1" ] && [ ${#1} -le 253 ] && echo "$1" | grep -Eq '^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}$'
}
cidr_ok() {
	echo "$1" | awk -F'[./]' 'NF==5 { for (i=1;i<=4;i++) if ($i !~ /^[0-9]+$/ || $i+0 > 255) exit 1; if ($5 !~ /^[0-9]+$/ || $5+0 > 32) exit 1; exit 0 } { exit 1 }'
}
# ip_in_any IP CIDR...   -> success when IP lies inside one of the CIDRs
ip_in_any() {
	local _ip="$1"; shift
	echo "$*" | tr ' ' '\n' | awk -v ip="$_ip" '
		function toi(a,   o) { split(a, o, "."); return ((o[1]*256 + o[2])*256 + o[3])*256 + o[4] }
		BEGIN { x = toi(ip) }
		NF { split($1, p, "/"); b = toi(p[1]); s = 2^(32 - p[2]); lo = b - (b % s)
		     if (x >= lo && x < lo + s) { f = 1; exit } }
		END { exit !f }'
}
# udp/tcp port listening on loopback or any address (reads /proc/net)
port_listening() { # proto port
	local _hp _f _st _d="${PSI_PROC_NET:-/proc/net}"
	_hp=$(printf '%04X' "$2" 2>/dev/null) || return 1
	for _f in "$1" "${1}6"; do
		[ -r "$_d/$_f" ] || continue
		case "$_f" in tcp*) _st=0A ;; *) _st="" ;; esac
		awk -v hp="$_hp" -v st="$_st" 'NR > 1 { n = split($2, a, ":"); if (toupper(a[n]) == hp && (st == "" || $4 == st)) { hit = 1; exit } } END { exit !hit }' "$_d/$_f" 2>/dev/null && return 0
	done
	return 1
}
# resolves_public HOST [SERVER]  -> success when the answer contains a non-private IPv4
resolves_public() {
	T 6 nslookup -type=A "$1" "${2:-127.0.0.1}" 2>/dev/null | awk '
		/^Name:/ { a = 1; next }
		a && /[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/ {
			s = $0
			while (match(s, /[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/)) {
				ip = substr(s, RSTART, RLENGTH)
				if (ip !~ /^(127|10|0)\./ && ip !~ /^192\.168\./ && ip !~ /^172\.(1[6-9]|2[0-9]|3[01])\./ && ip !~ /^169\.254\./) { f = 1; exit }
				s = substr(s, RSTART + RLENGTH)
			}
		}
		END { exit !f }'
}
lan_dev_() {
	local d
	d=$(ubus call network.interface.lan status 2>/dev/null | jsonfilter -e '@.l3_device' 2>/dev/null)
	echo "${d:-br-lan}"
}
wan_dev_() {
	local d
	d=$(ubus call network.interface.wan status 2>/dev/null | jsonfilter -e '@.l3_device' 2>/dev/null)
	[ -z "$d" ] && d=$(ip -4 route show default 2>/dev/null | awk -v t="$TUN" '$0 !~ t { for (i=1;i<=NF;i++) if ($i=="dev") { print $(i+1); exit } }')
	echo "$d"
}
lan_ip_() {
	ubus call network.interface.lan status 2>/dev/null | jsonfilter -e '@["ipv4-address"][0].address' 2>/dev/null
}
connected_now() { # echoes "port tunnels" when the tunnel is up
	local st
	st=$("$HELPER" status 2>/dev/null)
	[ "$(jf "$st" '@.running')" = 1 ] || return 1
	[ "$(jf "$st" '@.tunnels')" -ge 1 ] 2>/dev/null || return 1
	[ "$(jf "$st" '@.port')" -gt 0 ] 2>/dev/null || return 1
	return 0
}
# ---------------------------------------------------------------------------
# env
# ---------------------------------------------------------------------------
t_env() {
	section "Environment"
	local _c _v _free

	[ "$(id -u 2>/dev/null)" = 0 ] && pass "running as root" || fail "not running as root (some tests will fail)"

	if [ -r /etc/openwrt_release ]; then
		. /etc/openwrt_release
		case "$DISTRIB_RELEASE" in
			25.*|SNAPSHOT*) pass "OpenWrt $DISTRIB_RELEASE ($DISTRIB_ARCH)" ;;
			*) warn "OpenWrt $DISTRIB_RELEASE - this installer targets 25.x (apk)" ;;
		esac
	else
		warn "/etc/openwrt_release not found - this does not look like OpenWrt"
	fi

	if have apk; then pass "package manager: apk"
	elif have opkg; then warn "package manager: opkg (OpenWrt < 25) - supported by the installer, but untested here"
	else warn "no package manager found"; fi

	for _c in nft ip uci jsonfilter; do
		have "$_c" && pass "required command: $_c" || fail "required command missing: $_c (apk add nftables ip-full jsonfilter)"
	done
	for _c in ubus curl awk nslookup pidof sysctl; do
		have "$_c" && pass "command: $_c" || warn "optional command missing: $_c (some features degrade)"
	done
	have timeout && pass "command: timeout" || warn "timeout (coreutils/busybox) missing - helper calls run without time limits"
	have https-dns-proxy && pass "https-dns-proxy installed (DoH available)" || warn "https-dns-proxy missing - DNS falls back to plain UDP through the tunnel (often fails)"
	have tcpdump && pass "tcpdump installed" || warn "tcpdump missing (installer adds it; only needed for debugging)"

	if apk info -e ca-bundle >/dev/null 2>&1 || opkg list-installed ca-bundle 2>/dev/null | grep -q ca-bundle || [ -s /etc/ssl/certs/ca-certificates.crt ]; then
		pass "ca-bundle present (TLS / DoH)"
	else
		fail "ca-bundle missing - DoH and HTTPS checks will fail (apk add ca-bundle)"
	fi

	if [ -e /dev/net/tun ]; then
		pass "/dev/net/tun present (kmod-tun)"
	else
		if bool_on "$(U tun)" || bool_on "$(U enabled)"; then fail "/dev/net/tun missing but Full Tunnel is enabled (apk add kmod-tun)"
		else warn "/dev/net/tun missing - Full Tunnel mode will not work (apk add kmod-tun)"; fi
	fi

	have ip && { ip rule show >/dev/null 2>&1 && pass "ip rule works (ip-full)" || fail "ip rule broken - install ip-full"; }
	have ip && { ip -6 rule show >/dev/null 2>&1 && pass "ip -6 rule works" || warn "ip -6 rule not available (IPv6 leak guard degraded)"; }

	if have nft; then
		nft list ruleset >/dev/null 2>&1 && pass "nftables usable" || fail "nft list ruleset failed (nftables kernel modules?)"
	fi

	_free=$(df -k /overlay 2>/dev/null | awk 'NR==2{print $4}')
	[ -n "$_free" ] || _free=$(df -k / 2>/dev/null | awk 'NR==2{print $4}')
	if [ -n "$_free" ]; then
		if [ "$_free" -ge 1024 ] 2>/dev/null; then pass "free flash: ${_free} KB"; else fail "free flash below 1 MB (${_free} KB)"; fi
	else
		skip "free flash could not be determined"
	fi

	for _c in dnsmasq uhttpd rpcd; do
		[ -x "/etc/init.d/$_c" ] && pass "service present: $_c" || warn "service not found: $_c"
	done
	[ -d /www/luci-static ] && pass "LuCI static files present" || fail "LuCI not installed (/www/luci-static missing)"

	if have curl; then
		_v=$(curl -sI -m 8 https://api.github.com/zen 2>/dev/null | head -n1)
		case "$_v" in
			HTTP*) pass "router has working HTTPS to the internet (WAN path)" ;;
			*) warn "router could not reach https://api.github.com (WAN down? DNS? ca-bundle?)" ;;
		esac
	fi
}

# ---------------------------------------------------------------------------
# files
# ---------------------------------------------------------------------------
t_files() {
	section "Installed files"
	local _f _x _out _flag _sz _perm

	for _x in "$INIT:x" "$HELPER:x" "$HOTPLUG:x" "$UCIFILE:f" "$MENU:f" "$ACL:f" "$VIEW:f" "$CORE:x"; do
		_f=${_x%:*}
		case "${_x##*:}" in
			x) if [ -x "$_f" ]; then pass "$_f (executable)"
			   elif [ -e "$_f" ]; then fail "$_f exists but is not executable (chmod +x)"
			   else fail "$_f missing"; fi ;;
			*) [ -s "$_f" ] && pass "$_f" || fail "$_f missing or empty" ;;
		esac
	done

	for _f in "$INIT" "$HELPER" "$HOTPLUG"; do
		[ -f "$_f" ] || continue
		sh -n "$_f" 2>"$TMPD/syn" && pass "shell syntax OK: $_f" || fail "shell syntax error in $_f: $(head -n1 "$TMPD/syn")"
	done

	for _f in "$HELPER" "$INIT" "$HOTPLUG" "$MENU" "$ACL" "$VIEW"; do
		[ -e "$_f" ] || continue
		_perm=$(find "$_f" -perm -0002 2>/dev/null)
		[ -z "$_perm" ] && pass "not world-writable: $_f" || fail "world-writable file: $_f"
	done

	if [ -f "$INIT" ]; then
		grep -q 'USE_PROCD=1' "$INIT" && pass "init script uses procd" || fail "init script does not set USE_PROCD=1"
		grep -q 'psiphon-helper' "$INIT" && pass "init script references the helper" || fail "init script does not reference psiphon-helper"
	fi
	if [ -f "$HOTPLUG" ]; then
		grep -q 'fw-refresh' "$HOTPLUG" && pass "hotplug script calls fw-refresh" || fail "hotplug script does not call fw-refresh"
	fi

	if have jsonfilter; then
		if [ -f "$MENU" ]; then
			t_eq "menu.d: admin/vpn/psiphon view path" "$(jsonfilter -i "$MENU" -e '@["admin/vpn/psiphon"].action.path' 2>/dev/null)" "vpn/psiphon"
			t_eq "menu.d: admin/vpn alias target" "$(jsonfilter -i "$MENU" -e '@["admin/vpn"].action.path' 2>/dev/null)" "admin/vpn/psiphon"
		fi
		if [ -f "$ACL" ]; then
			t_eq "ACL: uci read access to psiphon" "$(jsonfilter -i "$ACL" -e '@["luci-app-psiphon"].read.uci[0]' 2>/dev/null)" "psiphon"
			t_eq "ACL: uci write access to psiphon" "$(jsonfilter -i "$ACL" -e '@["luci-app-psiphon"].write.uci[0]' 2>/dev/null)" "psiphon"
			t_eq "ACL: helper may be executed" "$(jsonfilter -i "$ACL" -e '@["luci-app-psiphon"].write.file["/usr/bin/psiphon-helper"][0]' 2>/dev/null)" "exec"
		fi
	else
		skip "JSON checks (jsonfilter missing)"
	fi

	if [ -f "$VIEW" ]; then
		_sz=$(wc -c < "$VIEW")
		[ "${_sz:-0}" -gt 10000 ] && pass "LuCI view is complete (${_sz} bytes)" || fail "LuCI view looks truncated (${_sz} bytes)"
		grep -q "view.extend" "$VIEW" && pass "LuCI view defines view.extend" || fail "LuCI view has no view.extend"
		grep -q "/usr/bin/psiphon-helper" "$VIEW" && pass "LuCI view calls /usr/bin/psiphon-helper" || fail "LuCI view does not reference the helper"
		if have node; then
			node --check "$VIEW" >/dev/null 2>&1 && pass "LuCI view JavaScript syntax OK (node)" || fail "LuCI view has a JavaScript syntax error"
		else
			skip "JavaScript syntax check (node not installed on the router)"
		fi
	fi

	if [ -x "$CORE" ]; then
		_out=$(T 8 "$CORE" -h 2>&1)
		if echo "$_out" | grep -qiE 'exec format error|not found|cannot execute|illegal instruction'; then
			fail "psiphon-core cannot run on this CPU: $(echo "$_out" | head -n1)"
		elif echo "$_out" | grep -qE '^[[:space:]]+-[A-Za-z]'; then
			pass "psiphon-core runs and prints its flags"
			for _flag in config notices; do
				echo "$_out" | grep -Eq "^[[:space:]]+-$_flag([[:space:]]|\$)" && pass "core supports -$_flag" || fail "core does not support -$_flag (init script needs it)"
			done
			for _flag in tunDevice tunBindInterface tunAddress tunGateway; do
				if echo "$_out" | grep -Eq "^[[:space:]]+-$_flag([[:space:]]|\$)"; then pass "core supports -$_flag"
				elif [ "$_flag" = tunDevice ] && bool_on "$(U tun)"; then fail "core does not support -tunDevice but Full Tunnel is on"
				else warn "core does not support -$_flag (feature skipped by init script)"; fi
			done
		else
			warn "psiphon-core -h printed nothing recognisable: $(echo "$_out" | head -n1)"
		fi
		for _flag in CdnFrontingCustomIpList CdnFrontingCustomSni UpstreamDNSServer BeastMode; do
			grep -qa "$_flag" "$CORE" 2>/dev/null && info "core knows config key $_flag" || warn "core binary has no '$_flag' string - that setting is ignored"
		done
		if [ -n "$PSI_CORE_SHA256" ]; then
			_x=$(sha256sum "$CORE" 2>/dev/null | cut -d' ' -f1)
			t_eq "psiphon-core SHA256 matches PSI_CORE_SHA256" "$_x" "$PSI_CORE_SHA256"
		else
			skip "core SHA256 (set PSI_CORE_SHA256=... to verify)"
		fi
	fi

	pidof rpcd >/dev/null 2>&1 && pass "rpcd is running" || warn "rpcd is not running (LuCI calls will fail)"
	pidof uhttpd >/dev/null 2>&1 && pass "uhttpd is running" || warn "uhttpd is not running"
	if have ubus; then
		ubus list 2>/dev/null | grep -qx 'service' && pass "procd service interface available" || fail "ubus 'service' object missing (procd?)"
	fi
}

# ---------------------------------------------------------------------------
# config
# ---------------------------------------------------------------------------
t_config() {
	section "UCI configuration and system integration"
	local _k _v _en _tun _ks _de _cm _ta _lip _cd _f _need _cfgfile

	if ! have uci; then skip "uci not available"; return; fi
	if ! uci -q show psiphon.config >/dev/null 2>&1; then
		fail "UCI section psiphon.config missing ($UCIFILE)"
		return
	fi
	pass "UCI section psiphon.config exists"
	[ "$(uci -q get psiphon.config 2>/dev/null)" = "psiphon" ] && pass "section type is 'psiphon'" || warn "psiphon.config has an unexpected section type"

	for _k in enabled tun kill_switch psiphon_dns dns_enabled force_router_dns beast_mode cdn_fronting cdn_probe; do
		_v=$(U "$_k")
		case "$_v" in
			''|0|1|on|off|true|false|yes|no|enabled|disabled) info "$_k=${_v:-<unset>}" ;;
			*) warn "$_k has an unexpected value '$_v' (expected 0/1)" ;;
		esac
	done

	_v=$(U transport | tr 'a-z' 'A-Z')
	case "$_v" in ''|STANDARD|QUIC|SSH|TLS) pass "transport = ${_v:-STANDARD (default)}" ;; *) warn "transport '$_v' is unknown - the helper falls back to STANDARD" ;; esac

	_cm=$(U conn_mode)
	case "$_cm" in ''|auto|traffic_dns_https|traffic_dns_udp) pass "conn_mode = ${_cm:-auto (default)}" ;; *) warn "conn_mode '$_cm' is unknown - the helper falls back to auto" ;; esac

	_v=$(U dns_preset)
	case "$_v" in
		''|custom|google|opendns|cloudflare|norton|comodo_sec|comodo|dns_watch|adguard_noblock|adguard_block|adguard_family|quad9_sec|quad9_nosec) pass "dns_preset = ${_v:-<unset>}" ;;
		*) warn "dns_preset '$_v' is not a known preset" ;;
	esac

	_de=$(U dns_enabled)
	for _k in dns1 dns2; do
		_v=$(U "$_k")
		if [ -n "$_v" ]; then
			valid_ipv4 "$_v" && pass "$_k = $_v (valid IPv4)" || fail "$_k '$_v' is not a valid IPv4 address"
		elif bool_on "$_de"; then
			fail "$_k is empty but Custom DNS is on"
		fi
	done

	_v=$(U tun_mtu)
	case "$_v" in
		''|auto) pass "tun_mtu = ${_v:-auto (default)}" ;;
		*[!0-9]*) fail "tun_mtu '$_v' is not numeric or 'auto'" ;;
		*) if [ "$_v" -ge 1280 ] && [ "$_v" -le 1500 ]; then pass "tun_mtu = $_v"; else fail "tun_mtu $_v is outside 1280..1500 (the helper ignores it)"; fi ;;
	esac

	_ta=$(U tun_addr)
	if [ -n "$_ta" ]; then
		if valid_ipv4 "$_ta"; then
			pass "tun_addr = $_ta"
			_lip=$(lan_ip_)
			if [ -n "$_lip" ] && [ "${_ta%.*}" = "${_lip%.*}" ]; then fail "tun_addr $_ta is in the same /24 as the LAN ($_lip) - routing conflict"; fi
		else
			fail "tun_addr '$_ta' is not a valid IPv4 (the helper falls back to 10.255.255.1)"
		fi
	fi

	_v=$(U country)
	if [ -z "$_v" ]; then pass "region: best performance (no EgressRegion)"
	else echo "$_v" | grep -Eq '^[A-Za-z]{2}$' && pass "region = $_v" || warn "country '$_v' is not a 2-letter code - ignored by the helper"; fi

	for _k in propagation_channel_id sponsor_id; do
		_v=$(U "$_k")
		[ -z "$_v" ] || { echo "$_v" | grep -Eq '^[0-9A-Fa-f]{16}$' && pass "$_k is 16 hex chars" || warn "$_k '$_v' is not 16 hex chars - the helper uses its default"; }
	done

	_v=$(U cdn_sni)
	[ -z "$_v" ] || { valid_host "$_v" && pass "cdn_sni = $_v" || fail "cdn_sni '$_v' is not a valid hostname"; }
	_v=$(U cdn_edge_ips | tr ',;' '  ')
	if [ -n "$_v" ]; then
		_need=0
		for _k in $_v; do valid_ipv4 "$_k" || { fail "cdn_edge_ips contains invalid IPv4 '$_k'"; _need=1; }; done
		[ "$_need" = 0 ] && pass "cdn_edge_ips: $(echo $_v | wc -w) valid IPv4 address(es)"
	fi
	if bool_on "$(U cdn_fronting)"; then
		if [ -n "$(U cdn_sni)" ] && [ -n "$(U cdn_edge_ips)" ]; then pass "CDN fronting: SNI + edge IPs configured"
		else warn "CDN fronting is on without SNI+edge IPs - Psiphon's built-in fronting providers are used"; fi
	fi

	# consistency between options
	_en=$(U enabled); _tun=$(U tun); _ks=$(U kill_switch)
	if bool_on "$_en" && ! bool_on "$_tun"; then warn "enabled=1 but tun=0 (LuCI keeps them in sync; Full Tunnel will not start)"; fi
	if ! bool_on "$_en" && bool_on "$_tun"; then warn "tun=1 while enabled=0 (inconsistent state)"; fi
	if bool_on "$_ks" && ! bool_on "$_tun"; then warn "kill_switch=1 has no effect without Full Tunnel (tun=1)"; fi
	if bool_on "$_de" && ! bool_on "$_tun"; then warn "dns_enabled=1 has no effect without Full Tunnel"; fi
	if bool_on "$(U force_router_dns)" && ! bool_on "$_tun"; then warn "force_router_dns=1 has no effect without Full Tunnel"; fi
	if bool_on "$_de" && [ -n "$_cm" ] && [ "$_cm" != traffic_dns_udp ]; then info "dns_enabled=1 forces conn_mode to UDP at runtime (stored conn_mode=$_cm)"; fi
	if [ "$_cm" = traffic_dns_https ] && ! have https-dns-proxy; then fail "conn_mode=traffic_dns_https needs https-dns-proxy (not installed)"; fi
	if bool_on "$_ks" && bool_on "$_tun"; then info "Kill Switch is armed: after Stop the LAN stays blocked until you disable it and press Stop"; fi

	# firewall zone
	if [ "$(uci -q get firewall.psiphon.name 2>/dev/null)" = "psiphon" ]; then
		pass "firewall zone 'psiphon' exists"
		t_eq "zone psiphon: device" "$(uci -q get firewall.psiphon.device)" "$TUN"
		t_eq "zone psiphon: masquerading" "$(uci -q get firewall.psiphon.masq)" "1"
		t_eq "zone psiphon: MSS clamping (mtu_fix)" "$(uci -q get firewall.psiphon.mtu_fix)" "1"
		t_eq "zone psiphon: input policy" "$(uci -q get firewall.psiphon.input)" "REJECT"
		t_eq "zone psiphon: forward policy" "$(uci -q get firewall.psiphon.forward)" "REJECT"
		t_eq "forwarding lan -> psiphon: src" "$(uci -q get firewall.psiphon_forwarding.src)" "lan"
		t_eq "forwarding lan -> psiphon: dest" "$(uci -q get firewall.psiphon_forwarding.dest)" "psiphon"
		if have nft && nft list chains inet fw4 2>/dev/null | grep -q 'forward_psiphon'; then pass "fw4 has the psiphon zone chains loaded"
		else warn "fw4 does not show psiphon zone chains (run: /etc/init.d/firewall reload)"; fi
	else
		fail "firewall zone 'psiphon' missing (NAT through tun0 will not work)"
	fi

	# dnsmasq conf-dir must be tmpfs, otherwise psiphon_dns.conf is never read
	_cd=$(uci -q get 'dhcp.@dnsmasq[0].confdir' 2>/dev/null | awk '{print $1}')
	case "$_cd" in
		/tmp/*|/var/*|/run/*)
			pass "dnsmasq confdir on tmpfs: $_cd"
			_cfgfile=$(ls /var/etc/dnsmasq.conf.* 2>/dev/null | head -n1)
			if [ -n "$_cfgfile" ]; then
				grep -q "^conf-dir=$_cd" "$_cfgfile" 2>/dev/null && pass "running dnsmasq config includes conf-dir $_cd" || warn "generated dnsmasq config has no conf-dir=$_cd (restart dnsmasq)"
			fi ;;
		'') fail "dnsmasq confdir is not set (installer should set /tmp/dnsmasq.d)" ;;
		*) fail "dnsmasq confdir '$_cd' is not on tmpfs - tunnelled DNS will not be applied" ;;
	esac
	local _fu
	_fu=""
	for _f in $(uci -q get 'dhcp.@dnsmasq[0].server' 2>/dev/null); do case "$_f" in /*) ;; *) _fu="$_fu $_f" ;; esac; done
	[ -z "$_fu" ] && pass "no non-tunnelled dnsmasq upstream servers" || warn "dnsmasq has extra upstream servers:$_fu (they bypass the tunnel; the service isolates them while connected)"

	# survive sysupgrade
	if [ -f "$SUCONF" ]; then
		_need=0
		for _f in /etc/config/psiphon /etc/init.d/psiphon /usr/bin/psiphon-helper /etc/hotplug.d/iface/90-psiphon \
		          /usr/share/luci/menu.d/luci-app-psiphon.json /usr/share/rpcd/acl.d/luci-app-psiphon.json \
		          /www/luci-static/resources/view/vpn/psiphon.js /usr/bin/psiphon-core /etc/psiphon /etc/rc.d/S99psiphon; do
			grep -qxF "$_f" "$SUCONF" || { warn "$_f missing from $SUCONF (lost on sysupgrade)"; _need=1; }
		done
		[ "$_need" = 0 ] && pass "all Psiphon paths are listed in $SUCONF"
	else
		warn "$SUCONF not found"
	fi

	# autostart link
	if [ -x "$INIT" ]; then
		if "$INIT" enabled >/dev/null 2>&1; then
			[ -e /etc/rc.d/S99psiphon ] && pass "service enabled at boot (S99psiphon)" || warn "init reports enabled but /etc/rc.d/S99psiphon is missing"
		else
			bool_on "$_en" && warn "enabled=1 in UCI but the service is not enabled at boot (run: /etc/init.d/psiphon enable)" || pass "service not enabled at boot (UCI enabled=0)"
		fi
	fi
	[ -d /tmp/dnsmasq.d ] && pass "/tmp/dnsmasq.d exists" || warn "/tmp/dnsmasq.d missing (created again on service start)"
}

# ---------------------------------------------------------------------------
# helper (offline unit tests - nothing is applied to the live system)
#
# The helper is split at its command dispatcher: everything above it is sourced
# in a throw-away shell with stubbed uci/ubus/ip/nft, RUN/LOG redirected to a temp
# dir, so config generation, parsers and nft rulesets (nft --check) can be tested
# without touching the running VPN.
# ---------------------------------------------------------------------------
STUB="$TMPD/stub"; LIB="$TMPD/helper_lib.sh"; FAKECORE="$TMPD/fakecore"; EMPTYCORE="$TMPD/emptycore"
REAL_NFT=""; REAL_IP=""

mk_stubs() {
	mkdir -p "$STUB" "$TMPD/run" "$TMPD/net"
	REAL_NFT=$(command -v nft); REAL_IP=$(command -v ip)

	cat > "$STUB/uci" <<'EOF'
#!/bin/sh
[ "$1" = "-q" ] && shift
[ "$1" = get ] || exit 1
case "$2" in
	psiphon.config.*) _k=${2#psiphon.config.}; eval "_v=\${T_$_k}"; [ -n "$_v" ] && { echo "$_v"; exit 0; }; exit 1 ;;
	'dhcp.@dnsmasq[0].confdir') [ -n "$T_confdir" ] && { echo "$T_confdir"; exit 0; }; exit 1 ;;
	'dhcp.@dnsmasq[0].server') [ -n "$T_servers" ] && { echo "$T_servers"; exit 0; }; exit 1 ;;
esac
exit 1
EOF
	cat > "$STUB/ubus" <<'EOF'
#!/bin/sh
[ "$1" = call ] || exit 1
case "$2" in
	network.interface.lan) echo '{"l3_device":"br-lan","ipv4-address":[{"address":"192.168.1.1","mask":24}]}' ;;
	network.interface.wan) echo '{"l3_device":"eth1","ipv4-address":[{"address":"203.0.113.5","mask":24}]}' ;;
	*) exit 1 ;;
esac
EOF
	cat > "$STUB/ip" <<EOF
#!/bin/sh
case "\$*" in
	"-4 -o addr show dev br-lan") echo "2: br-lan    inet \${T_lanaddr:-192.168.1.1/24} brd 192.168.1.255 scope global br-lan" ;;
	*) exec ${REAL_IP:-false} "\$@" ;;
esac
EOF
	# nft stub: only "nft -f -" is accepted and is turned into "nft -c -f -" (syntax/kernel check, nothing applied)
	cat > "$STUB/nft" <<EOF
#!/bin/sh
case "\$*" in
	"-f -") exec ${REAL_NFT:-false} -c -f - ;;
esac
exit 1
EOF
	printf '#!/bin/sh\nexit 1\n' > "$STUB/iptables"
	chmod +x "$STUB/uci" "$STUB/ubus" "$STUB/ip" "$STUB/nft" "$STUB/iptables"

	printf 'CdnFrontingCustomIpList\nCdnFrontingCustomSni\nUpstreamDNSServer\nBeastMode\n' > "$FAKECORE"
	: > "$EMPTYCORE"

	# fake /proc/net for doh_port_busy (5454=0x154E udp, 8080=0x1F90 tcp LISTEN, 9000=0x2328 tcp ESTABLISHED)
	_hdr='  sl  local_address rem_address   st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode'
	printf '%s\n   1: 0100007F:154E 00000000:0000 07 00000000:00000000 00:00000000 00000000     0        0 11 2 0 0\n' "$_hdr" > "$TMPD/net/udp"
	printf '%s\n' "$_hdr" > "$TMPD/net/udp6"
	printf '%s\n   1: 00000000:1F90 00000000:0000 0A 00000000:00000000 00:00000000 00000000     0        0 12 1 0 100\n   2: 0100007F:2328 0100007F:9999 01 00000000:00000000 00:00000000 00000000     0        0 13 1 0 100\n' "$_hdr" > "$TMPD/net/tcp"
	printf '%s\n' "$_hdr" > "$TMPD/net/tcp6"
}

# run_lib 'code' [VAR=value ...]  - run code with the helper's functions loaded
run_lib() {
	local _code="$1"; shift
	{
		echo ". '$LIB' >/dev/null 2>&1"
		echo "RUN='$TMPD/run'; LOG='$TMPD/lib.log'; CONF=\"\$RUN/psiphon.config\"; DNSCONF=\"\$RUN/dns.conf\"; PROG=\"\${PSI_TEST_CORE:-$FAKECORE}\""
		echo 'mkdir -p "$RUN"'
		printf '%s\n' "$_code"
	} > "$TMPD/case.sh"
	env PATH="$STUB:$PATH" "$@" sh "$TMPD/case.sh" 2>&1
}
# run_raw 'code' [VAR=value ...]  - same but WITHOUT overriding RUN/LOG/DNSCONF
run_raw() {
	local _code="$1"; shift
	{ echo ". '$LIB' >/dev/null 2>&1"; printf '%s\n' "$_code"; } > "$TMPD/raw.sh"
	env PATH="$STUB:$PATH" "$@" sh "$TMPD/raw.sh" 2>&1
}
lib_yes() { local d="$1" c="$2"; shift 2; [ "$(run_lib "if $c; then echo YES; else echo NO; fi" "$@")" = YES ] && pass "$d" || fail "$d"; }
lib_no()  { local d="$1" c="$2"; shift 2; [ "$(run_lib "if $c; then echo YES; else echo NO; fi" "$@")" = NO ] && pass "$d" || fail "$d"; }
lib_eq()  { local d="$1" c="$2" e="$3"; shift 3; t_eq "$d" "$(run_lib "$c" "$@")" "$e"; }

gen() { rm -f "$TMPD/run/psiphon.config"; : > "$TMPD/lib.log"; run_lib 'gen_config; echo "rc=$?"' "$@" > "$TMPD/gen.out"; }
gj() { jsonfilter -i "$TMPD/run/psiphon.config" -e "$1" 2>/dev/null; }

t_helper() {
	section "Helper unit tests (offline; nothing is applied)"
	local _o _rc _c _v _p _r _n _bad _provs _ips _ip _st _hl _k _sample _lines _base

	if [ ! -r "$HELPER" ]; then skip "helper not found at $HELPER"; return; fi
	if ! have jsonfilter; then skip "jsonfilter missing - helper tests need it"; return; fi
	mk_stubs
	sed '/^case "\$1" in$/,$d' "$HELPER" > "$LIB"
	if grep -q '^cmd_status() {' "$LIB" && grep -q '^gen_config() {' "$LIB"; then
		pass "helper function library extracted ($(wc -l < "$LIB") lines)"
	else
		fail "could not split the helper at its dispatcher - helper layout changed?"
		return
	fi

	# ---- dispatcher / access control (the guarded commands must refuse to run without PSI_INTERNAL) ----
	_o=$("$HELPER" 2>&1); _rc=$?
	[ "$_rc" -eq 1 ] && echo "$_o" | grep -q usage && pass "no argument -> usage, exit 1" || fail "no argument should print usage and exit 1 (rc=$_rc)"
	_o=$("$HELPER" bogus-command 2>&1); _rc=$?
	[ "$_rc" -eq 1 ] && echo "$_o" | grep -q usage && pass "unknown command -> usage, exit 1" || fail "unknown command should print usage and exit 1 (rc=$_rc)"
	if grep -q 'PSI_INTERNAL:-0' "$HELPER"; then
		for _c in prepare cleanup watch run-core; do
			_o=$(PSI_INTERNAL=0 "$HELPER" "$_c" 2>&1); _rc=$?
			[ "$_rc" -eq 1 ] && echo "$_o" | grep -q forbidden && pass "'$_c' is refused without PSI_INTERNAL=1" || fail "'$_c' must be forbidden without PSI_INTERNAL=1 (rc=$_rc)"
		done
	else
		fail "helper has no PSI_INTERNAL guard - internal commands could be run by anyone with exec rights"
	fi

	# ---- input validation of user-reachable commands ----
	if have curl; then
		_o=$("$HELPER" scan 2>&1); _rc=$?;                         t_eq "scan without SNI -> no-sni (rc 1)" "$_o/$_rc" "no-sni/1"
		_o=$("$HELPER" scan 'bad host!' 2>&1); _rc=$?;             t_eq "scan with invalid SNI -> invalid-sni (rc 1)" "$_o/$_rc" "invalid-sni/1"
		_o=$("$HELPER" scan example.com nosuchprovider 2>&1); _rc=$?; t_eq "scan with unknown provider -> unknown-provider (rc 1)" "$_o/$_rc" "unknown-provider/1"
		_o=$("$HELPER" scan-start 'bad_host' 2>&1); _rc=$?;        t_eq "scan-start with invalid SNI -> invalid-sni (rc 1)" "$_o/$_rc" "invalid-sni/1"
		_o=$("$HELPER" probe 'bad_host' 1.1.1.1 2>&1); _rc=$?;     t_eq "probe with invalid SNI -> 'invalid-sni 0' (rc 1)" "$_o/$_rc" "invalid-sni 0/1"
	else
		skip "scan/probe validation (curl missing)"
	fi
	_o=$("$HELPER" diag nonsense 2>&1); _rc=$?
	[ -z "$_o" ] && [ "$_rc" -eq 0 ] && pass "diag with unknown target prints nothing" || fail "diag nonsense should be silent (got '$_o', rc=$_rc)"

	# ---- JSON endpoints used by LuCI ----
	_st=$("$HELPER" status 2>/dev/null)
	if valid_json "$_st"; then
		pass "status returns valid JSON"
		for _k in running port tunnels rx tx; do
			case "$(jf "$_st" "@.$_k")" in ''|*[!0-9]*) fail "status.$_k is not a number" ;; *) info "status.$_k ok" ;; esac
		done
		pass "status has numeric running/port/tunnels/rx/tx"
	else
		fail "status did not return valid JSON: $_st"
	fi
	_hl=$("$HELPER" health 2>/dev/null)
	if valid_json "$_hl"; then
		pass "health returns valid JSON"
		for _k in running tun socks socks_ms dns; do
			case "$(jf "$_hl" "@.$_k")" in ''|*[!0-9]*) fail "health.$_k is not a number" ;; esac
		done
		pass "health has numeric running/tun/socks/socks_ms/dns"
	else
		fail "health did not return valid JSON: $_hl"
	fi

	# ---- is_ipv4 / is_host / json_escape / B ----
	for _v in 1.2.3.4 0.0.0.0 255.255.255.255 10.255.255.1; do lib_yes "is_ipv4 accepts $_v" "is_ipv4 '$_v'"; done
	for _v in 256.1.1.1 1.2.3 a.b.c.d 1.2.3.4.5 '' 1.2.3.-4; do lib_no "is_ipv4 rejects '$_v'" "is_ipv4 '$_v'"; done
	for _v in vercel.com cdnjs.cloudflare.com a.b.example.org x-y.io; do lib_yes "is_host accepts $_v" "is_host '$_v'"; done
	for _v in localhost -bad.com a..com bad_host.com 'a b.com' 1.2.3.4 'x.com;rm' ''; do lib_no "is_host rejects '$_v'" "is_host '$_v'"; done
	lib_eq "json_escape escapes quote and backslash" "json_escape 'a\"b\\c'" 'a\"b\\c'
	for _v in 1 on true yes enabled; do lib_yes "B treats '$_v' as true" "B kill_switch 0" "T_kill_switch=$_v"; done
	for _v in 0 off no false disabled junk; do lib_no "B treats '$_v' as false" "B kill_switch 0" "T_kill_switch=$_v"; done
	lib_yes "B uses the default (1) when the option is unset" "B cdn_probe 1"
	lib_no  "B uses the default (0) when the option is unset" "B kill_switch 0"

	# ---- MTU / MSS / tunnel address / dnsmasq conf path ----
	lib_eq "tun_mtu auto -> 1400/1360, not forced" 'echo "$TUN_MTU $TUN_MSS $TUN_MTU_FORCE"' "1400 1360 0" T_tun_mtu=auto
	lib_eq "tun_mtu unset -> 1400/1360, not forced" 'echo "$TUN_MTU $TUN_MSS $TUN_MTU_FORCE"' "1400 1360 0"
	lib_eq "tun_mtu 1280 -> forced, MSS 1240" 'echo "$TUN_MTU $TUN_MSS $TUN_MTU_FORCE"' "1280 1240 1" T_tun_mtu=1280
	lib_eq "tun_mtu 1500 -> forced, MSS 1460" 'echo "$TUN_MTU $TUN_MSS $TUN_MTU_FORCE"' "1500 1460 1" T_tun_mtu=1500
	for _v in 1279 1501 abc 14x0 -1; do
		lib_eq "tun_mtu '$_v' is ignored (default 1400)" 'echo "$TUN_MTU $TUN_MSS $TUN_MTU_FORCE"' "1400 1360 0" "T_tun_mtu=$_v"
	done
	lib_eq "tun_addr 10.9.9.1 accepted" 'echo "$TUN_ADDR"' "10.9.9.1" T_tun_addr=10.9.9.1
	lib_eq "tun_addr 999.1.1.1 rejected -> default" 'echo "$TUN_ADDR"' "10.255.255.1" T_tun_addr=999.1.1.1
	lib_eq "tun_addr unset -> default" 'echo "$TUN_ADDR"' "10.255.255.1"

	t_eq "dnsmasq confdir /tmp/dnsmasq.d -> psiphon_dns.conf there" "$(run_raw 'echo "$DNSCONF"' T_confdir=/tmp/dnsmasq.d)" "/tmp/dnsmasq.d/psiphon_dns.conf"
	t_eq "dnsmasq confdir /var/dnsmasq.d accepted (tmpfs)" "$(run_raw 'echo "$DNSCONF"' T_confdir=/var/dnsmasq.d)" "/var/dnsmasq.d/psiphon_dns.conf"
	t_eq "dnsmasq confdir /run/x accepted (tmpfs)" "$(run_raw 'echo "$DNSCONF"' T_confdir=/run/dnsmasq.d)" "/run/dnsmasq.d/psiphon_dns.conf"
	t_eq "dnsmasq confdir on flash falls back to /tmp/dnsmasq.d" "$(run_raw 'echo "$DNSCONF"' T_confdir=/etc/dnsmasq.d)" "/tmp/dnsmasq.d/psiphon_dns.conf"
	t_eq "dnsmasq confdir unset falls back to /tmp/dnsmasq.d" "$(run_raw 'echo "$DNSCONF"')" "/tmp/dnsmasq.d/psiphon_dns.conf"
	t_eq "dnsmasq confdir keeps only the first word" "$(run_raw 'echo "$DNSCONF"' 'T_confdir=/tmp/a b')" "/tmp/a/psiphon_dns.conf"

	# ---- LAN subnet calculation (awk bit math) ----
	for _v in 192.168.1.1/24:192.168.1.0/24 10.1.2.3/16:10.1.0.0/16 172.16.5.9/20:172.16.0.0/20 192.168.1.130/25:192.168.1.128/25 \
	          10.20.30.40/8:10.0.0.0/8 192.168.1.5/30:192.168.1.4/30 192.168.77.200/23:192.168.76.0/23 192.168.1.1/32:192.168.1.1/32; do
		lib_eq "lan_subnet ${_v%:*} -> ${_v#*:}" "lan_subnet" "${_v#*:}" "T_lanaddr=${_v%:*}"
	done
	t_eq "lan_dev falls back/parses to br-lan" "$(run_lib 'lan_dev')" "br-lan"
	t_eq "lan_ip parsed from ubus" "$(run_lib 'lan_ip')" "192.168.1.1"
	t_eq "wan_dev parsed from ubus" "$(run_lib 'wan_dev')" "eth1"

	# ---- conn_mode / dns_list / foreign upstreams ----
	lib_eq "conn_mode default -> auto" 'conn_mode' "auto"
	lib_eq "conn_mode traffic_dns_https kept" 'conn_mode' "traffic_dns_https" T_conn_mode=traffic_dns_https
	lib_eq "conn_mode traffic_dns_udp kept" 'conn_mode' "traffic_dns_udp" T_conn_mode=traffic_dns_udp
	lib_eq "conn_mode junk -> auto" 'conn_mode' "auto" T_conn_mode=weird
	lib_eq "Custom DNS (dns_enabled) forces UDP mode" 'conn_mode' "traffic_dns_udp" T_dns_enabled=1 T_conn_mode=traffic_dns_https
	lib_eq "dns_list uses dns1+dns2" 'dns_list' "9.9.9.9 149.112.112.112" T_dns1=9.9.9.9 T_dns2=149.112.112.112
	lib_eq "dns_list drops invalid entries, keeps valid" 'dns_list' "149.112.112.112" T_dns1=bad T_dns2=149.112.112.112
	lib_eq "dns_list falls back to Cloudflare" 'dns_list' "1.1.1.1 1.0.0.1"
	lib_eq "dns_list falls back when both invalid" 'dns_list' "1.1.1.1 1.0.0.1" T_dns1=x T_dns2=999.1.1.1
	lib_eq "dns_foreign_upstreams ignores domain-scoped servers" 'dns_foreign_upstreams' "8.8.8.8 1.1.1.1#53" "T_servers=/lan/192.168.1.1 8.8.8.8 1.1.1.1#53"
	lib_eq "dns_foreign_upstreams empty when only scoped servers" 'dns_foreign_upstreams' "" "T_servers=/lan/192.168.1.1"

	# ---- log parsers ----
	cat > "$TMPD/log.sample" <<'EOF'
[System] Starting Psiphon...
[psiphon] core restarted
{"data":{"port":1080},"noticeType":"ListeningSocksProxyPort","timestamp":"2026-01-01T10:00:00Z"}
{"data":{"protocol":"OSSH","serverEntry":"1.2.3.4 x"},"noticeType":"ConnectingServer","timestamp":"2026-01-01T10:00:01Z"}
{"data":{"protocol":"FRONTED-MEEK-OSSH","serverEntry":"1.2.3.4 x"},"noticeType":"ConnectedServer","timestamp":"2026-01-01T10:00:02Z"}
{"data":{"count":1},"noticeType":"Tunnels","timestamp":"2026-01-01T10:00:02Z"}
{"data":{"received":1000,"sent":10},"noticeType":"BytesTransferred","timestamp":"2026-01-01T10:00:10Z"}
{"data":{"received":500,"sent":20},"noticeType":"BytesTransferred","timestamp":"2026-01-01T10:00:20Z"}
EOF
	cp "$TMPD/log.sample" "$TMPD/lib.log"
	lib_eq "sock_port parsed from the log" 'sock_port' "1080"
	lib_eq "tun_count parsed from the log" 'tun_count' "1"
	lib_eq "latest_protocol prefers ConnectedServer" 'latest_protocol' "FRONTED-MEEK-OSSH"
	lib_eq "bt_sum adds BytesTransferred lines" 'bt_sum' "1500 30"
	lib_eq "cmd_status JSON matches the log (+ stored base)" 'core_pid() { echo 4242; }; echo "100 5" > "$RUN/bt_base"; cmd_status' \
		'{"running":1,"port":1080,"tunnels":1,"rx":1600,"tx":35,"protocol":"FRONTED-MEEK-OSSH"}'
	valid_json "$(run_lib 'core_pid() { echo 4242; }; cmd_status')" && pass "cmd_status output is valid JSON" || fail "cmd_status output is not valid JSON"
	printf '%s\n%s\n' '[psiphon] core restarted' '{"data":{"count":0},"noticeType":"Tunnels"}' >> "$TMPD/lib.log"
	lib_eq "log parsers only look after the last 'core restarted' (tunnels -> 0)" 'tun_count' "0"
	lib_eq "log parsers only look after the last 'core restarted' (no stale SOCKS port)" 'sock_port' ""

	# trim_log: big log is cut to ~500 lines and the dropped traffic is folded into bt_base
	awk 'BEGIN { print "[psiphon] core restarted"; pad = sprintf("%380s", ""); gsub(/ /, "x", pad)
	             for (i = 1; i <= 700; i++) printf "{\"data\":{\"received\":100,\"sent\":10,\"pad\":\"%s\"},\"noticeType\":\"BytesTransferred\"}\n", pad }' > "$TMPD/lib.log"
	rm -f "$TMPD/run/bt_base"
	_o=$(run_lib 'core_pid() { :; }; trim_log; echo "$(wc -l < "$LOG") $(cat "$RUN/bt_base" 2>/dev/null)"')
	_n=${_o%% *}; _base=${_o#* }
	if [ "$_n" -ge 450 ] 2>/dev/null && [ "$_n" -le 560 ] 2>/dev/null; then pass "trim_log keeps about 500 lines (kept $_n of 701)"; else fail "trim_log result unexpected: '$_o'"; fi
	t_eq "trim_log folds dropped traffic into bt_base (200 lines x 100/10)" "$_base" "20000 2000"
	run_lib 'trim_log' >/dev/null
	cp "$TMPD/log.sample" "$TMPD/lib.log"

	# ---- doh_port_busy against a fake /proc/net ----
	lib_yes "doh_port_busy: UDP 5454 in use" "doh_port_busy 5454 udp" "PSI_PROC_NET=$TMPD/net"
	lib_no  "doh_port_busy: UDP 5455 free" "doh_port_busy 5455 udp" "PSI_PROC_NET=$TMPD/net"
	lib_yes "doh_port_busy: TCP 8080 LISTEN counts as busy (any proto)" "doh_port_busy 8080" "PSI_PROC_NET=$TMPD/net"
	lib_no  "doh_port_busy: TCP 9000 ESTABLISHED is not a listener" "doh_port_busy 9000" "PSI_PROC_NET=$TMPD/net"
	lib_no  "doh_port_busy: 'udp' only looks at UDP tables" "doh_port_busy 8080 udp" "PSI_PROC_NET=$TMPD/net"
	lib_yes "doh_port_busy: non-numeric port is treated as busy" "doh_port_busy abc" "PSI_PROC_NET=$TMPD/net"
	lib_yes "doh_port_busy: empty port is treated as busy" "doh_port_busy ''" "PSI_PROC_NET=$TMPD/net"

	# ---- CDN range data and sampler ----
	_provs=$(run_lib 'echo "$CDN_PROVIDERS"')
	_bad=0; _n=0
	for _p in $_provs; do
		_r=$(run_lib "cdn_ranges $_p")
		if [ -z "$_r" ]; then fail "cdn_ranges $_p returned nothing"; _bad=1; continue; fi
		for _c in $_r; do cidr_ok "$_c" || { fail "cdn_ranges $_p: malformed CIDR '$_c'"; _bad=1; }; done
		_n=$((_n+1))
	done
	[ "$_bad" = 0 ] && pass "CDN ranges: $_n providers, every CIDR is well-formed"
	t_eq "cdn_ranges for an unknown provider fails" "$(run_lib 'cdn_ranges nosuchcdn; echo "rc=$?"')" "rc=1"
	for _p in cloudflare akamai fastly github vercel; do
		_r=$(run_lib "cdn_ranges $_p")
		_ips=$(run_lib "cdn_sample 12 \$(cdn_ranges $_p)")
		_bad=0; _n=0
		for _ip in $_ips; do
			_n=$((_n+1))
			valid_ipv4 "$_ip" && ip_in_any "$_ip" $_r && [ "${_ip##*.}" != 0 ] && [ "${_ip##*.}" != 255 ] || { fail "cdn_sample($_p) produced bad IP '$_ip'"; _bad=1; }
		done
		[ "$_n" -ge 1 ] && [ "$_bad" = 0 ] && pass "cdn_sample($_p): $_n IPs, all inside the provider ranges, no .0/.255"
		[ "$_n" -ge 1 ] || fail "cdn_sample($_p) returned no IPs"
	done
	_ips=$(run_lib 'cdn_sample 6 1.2.3.0/24 bogus 300.1.1.0/24 9.9.9.9/33 5.6.0.0/7')
	_bad=0; _n=0
	for _ip in $_ips; do _n=$((_n+1)); ip_in_any "$_ip" 1.2.3.0/24 || _bad=1; done
	[ "$_n" -ge 1 ] && [ "$_bad" = 0 ] && pass "cdn_sample ignores malformed / out-of-range CIDRs (custom list)" || fail "cdn_sample with malformed CIDRs gave: '$_ips'"

	# ---- gen_config: the JSON handed to psiphon-core ----
	gen
	t_eq "gen_config default run succeeds" "$(cat "$TMPD/gen.out")" "rc=0"
	valid_json "$(cat "$TMPD/run/psiphon.config" 2>/dev/null)" && pass "gen_config writes valid JSON" || fail "gen_config wrote invalid JSON"
	t_eq "default: Transport" "$(gj '@.Transport')" "STANDARD"
	t_eq "default: no LimitTunnelProtocols" "$(gj '@.LimitTunnelProtocols[0]')" ""
	t_eq "default: no EgressRegion" "$(gj '@.EgressRegion')" ""
	t_eq "default: BeastMode off" "$(gj '@.BeastMode')" "false"
	t_eq "default: IPv6 disabled in core" "$(gj '@.DisableIPv6')" "true"
	t_eq "default: PropagationChannelId" "$(gj '@.PropagationChannelId')" "92AACC5BABE0944C"
	t_eq "default: SponsorId" "$(gj '@.SponsorId')" "1BC527D3D09985CF"
	t_eq "default: DataRootDirectory follows RUN" "$(gj '@.DataRootDirectory')" "$TMPD/run"
	[ -n "$(gj '@.ServerEntrySignaturePublicKey')" ] && pass "default: ServerEntrySignaturePublicKey present" || fail "ServerEntrySignaturePublicKey missing"
	t_eq "default: byte notices enabled" "$(gj '@.EmitBytesTransferred')" "true"

	gen T_transport=QUIC;  t_eq "transport QUIC -> QUIC-OSSH" "$(gj '@.LimitTunnelProtocols[0]')" "QUIC-OSSH"
	gen T_transport=quic;  t_eq "transport is case-insensitive" "$(gj '@.Transport')" "QUIC"
	gen T_transport=SSH;   t_eq "transport SSH -> SSH, OSSH" "$(gj '@.LimitTunnelProtocols[0]') $(gj '@.LimitTunnelProtocols[1]')" "SSH OSSH"
	gen T_transport=TLS;   t_eq "transport TLS -> FRONTED-MEEK-OSSH, TLS-OSSH" "$(gj '@.LimitTunnelProtocols[0]') $(gj '@.LimitTunnelProtocols[1]')" "FRONTED-MEEK-OSSH TLS-OSSH"
	gen T_transport=xyz;   t_eq "unknown transport -> STANDARD without limits" "$(gj '@.Transport')/$(gj '@.LimitTunnelProtocols[0]')" "STANDARD/"

	gen T_country=de;      t_eq "country 'de' -> EgressRegion DE" "$(gj '@.EgressRegion')" "DE"
	gen T_country=xyz;     t_eq "country 'xyz' ignored" "$(gj '@.EgressRegion')" ""
	gen T_country=D;       t_eq "country 'D' ignored" "$(gj '@.EgressRegion')" ""

	gen T_beast_mode=1;    t_eq "beast_mode=1 -> BeastMode true" "$(gj '@.BeastMode')" "true"
	gen T_propagation_channel_id=0123456789abcdef T_sponsor_id=FEDCBA9876543210
	t_eq "valid PropagationChannelId/SponsorId are kept" "$(gj '@.PropagationChannelId') $(gj '@.SponsorId')" "0123456789abcdef FEDCBA9876543210"
	gen T_propagation_channel_id=zz T_sponsor_id=123
	t_eq "invalid ids fall back to the defaults" "$(gj '@.PropagationChannelId') $(gj '@.SponsorId')" "92AACC5BABE0944C 1BC527D3D09985CF"

	gen T_dns_enabled=1 T_dns1=9.9.9.9 T_dns2=149.112.112.112
	t_eq "Custom DNS -> UpstreamDNSServer list" "$(gj '@.UpstreamDNSServer')" "9.9.9.9,149.112.112.112"
	gen T_dns_enabled=1 T_dns1=9.9.9.9 T_dns2=bad
	t_eq "Custom DNS drops an invalid server" "$(gj '@.UpstreamDNSServer')" "9.9.9.9"
	gen T_dns_enabled=0 T_dns1=9.9.9.9
	t_eq "no UpstreamDNSServer when Custom DNS is off" "$(gj '@.UpstreamDNSServer')" ""
	gen T_dns_enabled=1 T_dns1=9.9.9.9 PSI_TEST_CORE="$EMPTYCORE"
	t_eq "no UpstreamDNSServer when the core lacks the key" "$(gj '@.UpstreamDNSServer')" ""

	gen T_cdn_fronting=1 T_cdn_probe=0 T_cdn_sni=vercel.com 'T_cdn_edge_ips=76.76.21.21, bad, 76.76.19.1'
	t_eq "CDN: SNI pinned" "$(gj '@.CdnFrontingCustomSni')" "vercel.com"
	t_eq "CDN: only valid edge IPs kept" "$(gj '@.CdnFrontingCustomIpList')" "76.76.21.21,76.76.19.1"
	t_eq "CDN: protocols forced to fronted" "$(gj '@.LimitTunnelProtocols[0]') $(gj '@.LimitTunnelProtocols[1]')" "FRONTED-MEEK-OSSH FRONTED-MEEK-HTTP-OSSH"
	grep -q "invalid IP 'bad'" "$TMPD/lib.log" && pass "CDN: invalid IP is reported in the log" || fail "CDN: invalid IP was not logged"
	gen T_cdn_fronting=1 T_cdn_probe=0 T_cdn_sni=vercel.com T_cdn_edge_ips=76.76.21.21 T_transport=QUIC
	t_eq "CDN fronting overrides Transport protocols" "$(gj '@.LimitTunnelProtocols[0]')" "FRONTED-MEEK-OSSH"
	gen T_cdn_fronting=1 T_cdn_probe=0 'T_cdn_sni=bad host' T_cdn_edge_ips=76.76.21.21
	t_eq "CDN: invalid SNI is ignored (no pinning)" "$(gj '@.CdnFrontingCustomSni')" ""
	gen T_cdn_fronting=1 T_cdn_probe=0 T_cdn_sni=vercel.com
	t_eq "CDN: SNI without IPs -> built-in providers (no pinning)" "$(gj '@.CdnFrontingCustomIpList')/$(gj '@.LimitTunnelProtocols[0]')" "/FRONTED-MEEK-OSSH"
	gen T_cdn_fronting=1 T_cdn_probe=0 T_cdn_sni=vercel.com T_cdn_edge_ips=76.76.21.21 PSI_TEST_CORE="$EMPTYCORE"
	t_eq "CDN: pinning disabled when the core lacks the keys" "$(gj '@.CdnFrontingCustomSni')" ""
	gen T_cdn_fronting=0 T_cdn_sni=vercel.com T_cdn_edge_ips=76.76.21.21
	t_eq "CDN settings ignored while fronting is off" "$(gj '@.CdnFrontingCustomSni')" ""

	# ---- nft rulesets in check mode (nothing is applied) ----
	if [ -n "$REAL_NFT" ] && echo 'add table inet psiphon_probe' | "$REAL_NFT" -c -f - >/dev/null 2>&1; then
		_o=$(run_lib 'printf "no-resolv\nserver=1.1.1.1\n" > "$DNSCONF"; rm -f "$RUN/ks_wan" "$RUN/stopping"; ks_apply; _rc=$?; echo "rc=$_rc wan=$(cat "$RUN/ks_wan" 2>/dev/null)"' T_kill_switch=1)
		t_eq "Kill Switch ruleset (with DNS override) passes nft --check" "$_o" "rc=0 wan=eth1"
		_o=$(run_lib 'rm -f "$DNSCONF" "$RUN/ks_wan" "$RUN/stopping"; ks_apply; _rc=$?; echo "rc=$_rc wan=$(cat "$RUN/ks_wan" 2>/dev/null)"' T_kill_switch=1)
		t_eq "Kill Switch ruleset (without DNS override) passes nft --check" "$_o" "rc=0 wan=eth1"
		_o=$(run_lib 'ks_hold; echo "rc=$?"')
		t_eq "Kill Switch HOLD ruleset passes nft --check" "$_o" "rc=0"
		_o=$(run_lib 'rm -f "$LOG"; apply_mss_clamp; grep -c "MSS clamping applied" "$LOG"; grep -c "MSS clamp not applied" "$LOG"' )
		t_eq "MSS clamp ruleset passes nft --check" "$(echo "$_o" | tr '\n' ' ')" "1 0 "
		_o=$(run_lib 'rm -f "$RUN/stopping" "$RUN/strict_wan" "$LOG"; fw_strict_on; _rc=$?; echo "rc=$_rc strict=$(cat "$RUN/strict_wan" 2>/dev/null) log=$(grep -c "strict DNS enforcement on (nftables)" "$LOG")"')
		t_eq "Strict DNS ruleset (redirect + WAN reject) passes nft --check" "$_o" "rc=0 strict=eth1 log=1"
	else
		skip "nft --check not available - nftables ruleset syntax tests"
	fi
}

# ---------------------------------------------------------------------------
# live checks against the running service (shared by "live" and "lifecycle")
# ---------------------------------------------------------------------------
live_checks() {
	local st port tunnels proto tunmode ks lan wan svc connected=0 _o n cd file mode pinned flags fu real vpn p m exp cur dp dport cm

	tunmode=0; bool_on "$(U tun)" && tunmode=1
	ks=0; bool_on "$(U kill_switch)" && ks=1
	lan=$(lan_dev_); wan=$(wan_dev_)

	st=$("$HELPER" status 2>/dev/null)
	if ! valid_json "$st"; then fail "helper status returned invalid JSON: $st"; return; fi
	if [ "$(jf "$st" '@.running')" = 1 ]; then pass "core process running (pid $(pidof psiphon-core | awk '{print $1}'))"
	else fail "core process is not running"; return; fi
	port=$(jf "$st" '@.port'); tunnels=$(jf "$st" '@.tunnels'); proto=$(jf "$st" '@.protocol')
	if [ "${tunnels:-0}" -ge 1 ] 2>/dev/null && [ "${port:-0}" -gt 0 ] 2>/dev/null; then
		connected=1
		pass "tunnel established: $tunnels tunnel(s), protocol ${proto:-unknown}, SOCKS port $port"
	else
		warn "core is running but no tunnel yet (tunnels=${tunnels:-0}, port=${port:-0}) - connection-dependent checks skipped"
	fi

	if have ubus; then
		svc=$(ubus call service list '{"name":"psiphon"}' 2>/dev/null)
		t_eq "procd: core instance is running" "$(jf "$svc" '@.psiphon.instances.core.running')" "true"
		t_eq "procd: watcher instance is running" "$(jf "$svc" '@.psiphon.instances.watcher.running')" "true"
	fi

	# log health since the last core start
	_o=$(awk '/^\[psiphon\] core restarted/ { n = NR } { l[NR] = $0 } END { for (i = (n ? n : 1); i <= NR; i++) print l[i] }' "$LOG" 2>/dev/null | grep -aE '\bERROR\b|FAILED|INVALID|refusing' | head -n 3)
	if [ -z "$_o" ]; then pass "no ERROR/FAILED lines in $LOG since the last start"
	else warn "log contains problems: $(echo "$_o" | head -n 1 | cut -c1-140)"; fi

	[ "$connected" = 1 ] || return 0

	# traffic through the SOCKS proxy
	if have curl; then
		_o=$(curl -sL -m 12 --socks5-hostname "127.0.0.1:$port" -o /dev/null -w '%{http_code} %{time_total}' https://api.github.com/zen 2>/dev/null)
		set -- $_o
		case "${1:-000}" in
			2??|3??|4??) pass "HTTPS through the SOCKS proxy works (HTTP $1 in ${2:-?}s)" ;;
			*) fail "HTTPS through the SOCKS proxy failed (code ${1:-none})" ;;
		esac
		real=$("$HELPER" realip 2>/dev/null); vpn=$("$HELPER" vpnip 2>/dev/null)
		real=$(jf "$real" '@.ip'); vpn=$(jf "$vpn" '@.ip')
		if [ -n "$real" ] && [ -n "$vpn" ]; then
			if [ "$real" != "$vpn" ]; then pass "exit IP ($vpn) differs from the WAN IP ($real)"
			else fail "exit IP equals the WAN IP ($real) - traffic is not leaving through Psiphon"; fi
		else
			warn "could not read both IPs (real='${real:-?}' vpn='${vpn:-?}') - geo-IP services unreachable?"
		fi
	fi
	for p in icmp tcp url; do
		_o=$("$HELPER" diag "$p" 2>/dev/null)
		if [ -n "$_o" ] && [ "$_o" -gt 0 ] 2>/dev/null; then pass "diag $p: ${_o} ms"; else warn "diag $p returned no value (ICMP via the tunnel is often blocked)"; fi
	done

	if [ "$tunmode" != 1 ]; then info "proxy mode (tun=0): routing/DNS/kill-switch checks do not apply"; return 0; fi

	# ---- Full Tunnel: interface, policy routing, kill switch, IPv6, MSS ----
	if ip link show "$TUN" >/dev/null 2>&1; then
		pass "$TUN exists"
		ip link show "$TUN" 2>/dev/null | head -n1 | grep -q '<[^>]*UP' && pass "$TUN is UP" || fail "$TUN is not UP"
		ip -4 addr show dev "$TUN" 2>/dev/null | grep -q 'inet ' && pass "$TUN has an IPv4 address ($(ip -4 addr show dev "$TUN" | sed -n 's/.*inet \([0-9./]*\).*/\1/p' | head -n1))" || fail "$TUN has no IPv4 address (masquerade will not work)"
		m=$(U tun_mtu); case "$m" in ''|*[!0-9]*) exp=1400 ;; *) if [ "$m" -ge 1280 ] && [ "$m" -le 1500 ]; then exp=$m; else exp=1400; fi ;; esac
		cur=$(cat "/sys/class/net/$TUN/mtu" 2>/dev/null)
		if [ -n "$cur" ] && [ "$cur" -le "$exp" ] 2>/dev/null; then pass "$TUN MTU $cur (limit $exp)"; else warn "$TUN MTU is ${cur:-?}, expected <= $exp (the watcher corrects it within a few seconds)"; fi
	else
		fail "$TUN does not exist although Full Tunnel is on and a tunnel is connected"
	fi

	ip rule show 2>/dev/null | grep -Eq "iif $lan .*lookup $RT" && pass "policy rule: LAN ($lan) -> table $RT" || fail "policy rule iif $lan lookup $RT missing"
	n=$(ip rule show 2>/dev/null | awk '$1=="990:"' | wc -l)
	[ "${n:-0}" -ge 6 ] && pass "$n LAN/RFC1918 return rules (pref 990) present" || fail "expected >= 6 return rules at pref 990, found ${n:-0} (LAN could lose access to the router)"
	ip route show table "$RT" 2>/dev/null | grep -q "default dev $TUN" && pass "table $RT: default route via $TUN" || fail "table $RT has no default route via $TUN"
	if [ "$ks" = 1 ]; then
		ip route show table "$RT" 2>/dev/null | grep -q blackhole && pass "table $RT: blackhole fallback (Kill Switch)" || fail "Kill Switch is on but table $RT has no blackhole route"
	fi
	ip -6 rule show 2>/dev/null | grep -Eq "iif $lan .*prohibit" && pass "IPv6 from LAN is prohibited (no leaks)" || warn "no IPv6 'prohibit' rule for $lan"

	if have nft; then
		nft list table inet psiphon_mss >/dev/null 2>&1 && pass "nft table psiphon_mss (MSS clamp) loaded" || warn "psiphon_mss table absent (fw4 zone mtu_fix still clamps)"
		if [ "$ks" = 1 ]; then
			nft list table inet psiphon_ks >/dev/null 2>&1 && pass "nft table psiphon_ks (Kill Switch) loaded" || fail "Kill Switch is on but nft table psiphon_ks is missing"
		else
			nft list table inet psiphon_ks >/dev/null 2>&1 && warn "psiphon_ks table present although Kill Switch is off" || pass "no Kill Switch table (feature is off)"
		fi
	fi
	if [ "$ks" = 1 ] && [ -f "$RUN/ipv6_owned_wan" ]; then
		t_eq "Kill Switch: IPv6 disabled on WAN ($wan)" "$(cat "/proc/sys/net/ipv6/conf/$wan/disable_ipv6" 2>/dev/null)" "1"
	fi

	# ---- DNS ----
	cd=$(uci -q get 'dhcp.@dnsmasq[0].confdir' 2>/dev/null | awk '{print $1}')
	case "$cd" in /tmp/*|/var/*|/run/*) ;; *) cd=/tmp/dnsmasq.d ;; esac
	file="$cd/psiphon_dns.conf"
	if [ -f "$file" ]; then
		grep -q '^no-resolv' "$file" && pass "DNS override written ($file)" || fail "$file lacks no-resolv"
		info "$(grep '^server=' "$file" | tr '\n' ' ')"
	else
		warn "DNS override $file not written yet (the watcher applies it 10-60 s after connect)"
	fi
	if have nslookup; then
		resolves_public example.com 127.0.0.1 && pass "router DNS (dnsmasq) resolves example.com" || fail "router DNS does not resolve example.com while the tunnel is up"
	fi

	cm=$(U conn_mode); bool_on "$(U dns_enabled)" && cm=traffic_dns_udp
	if have https-dns-proxy && [ "$cm" != traffic_dns_udp ]; then
		dp=$(cat "$RUN/doh.pid" 2>/dev/null); dport=$(cat "$RUN/doh.port" 2>/dev/null)
		if [ -n "$dp" ] && kill -0 "$dp" 2>/dev/null && tr '\000' ' ' < "/proc/$dp/cmdline" 2>/dev/null | grep -q https-dns-proxy; then
			pass "DoH engine running (pid $dp)"
			[ -n "$dport" ] && { port_listening udp "$dport" && pass "DoH engine listens on 127.0.0.1:$dport (UDP)" || fail "DoH engine pid is alive but nothing listens on UDP $dport"; }
			[ -f "$file" ] && { grep -q "^server=127.0.0.1#$dport" "$file" && pass "dnsmasq forwards to the DoH engine" || warn "dnsmasq is not (yet) pointed at the DoH engine"; }
		else
			[ "$cm" = traffic_dns_https ] && fail "conn_mode=traffic_dns_https but the DoH engine is not running" || warn "DoH engine not running (plain resolvers through the tunnel are used)"
		fi
	fi

	_o=$("$HELPER" dnsleak 2>/dev/null)
	if valid_json "$_o"; then
		mode=$(jf "$_o" '@.mode'); pinned=$(jf "$_o" '@.pinned'); flags=$(jf "$_o" '@.flags'); fu=$(jf "$_o" '@.foreign')
		if [ "$mode" = none ]; then
			warn "DNS leak check: no tunnelled upstream configured yet (mode none)"
		else
			pass "DNS leak check: mode $mode, upstreams $(jf "$_o" '@.upstreams')"
			[ "$pinned" = true ] && pass "DNS upstream route is pinned to $TUN" || fail "DNS upstream route is NOT pinned to $TUN (DNS leaves via the WAN)"
		fi
		[ -z "$flags" ] || warn "dnsleak flags: $flags"
		[ -z "$fu" ] || warn "extra dnsmasq upstreams bypass the tunnel: $fu"
	else
		fail "dnsleak did not return valid JSON"
	fi

	if bool_on "$(U force_router_dns)"; then
		if have nft && nft list table inet psiphon_dns >/dev/null 2>&1; then pass "Strict DNS Enforcement active (nft table psiphon_dns)"
		elif have iptables && iptables -t nat -C PREROUTING -j psiphon_dns_nat >/dev/null 2>&1; then pass "Strict DNS Enforcement active (iptables)"
		else fail "Strict DNS Enforcement is on but no redirect/reject rules are loaded"; fi
	fi
	return 0
}

t_live() {
	section "Live service"
	if ! [ -x "$HELPER" ]; then skip "helper not installed"; return; fi
	if ! pidof psiphon-core >/dev/null 2>&1; then
		skip "psiphon-core is not running (start it in LuCI, or use --full for the lifecycle test)"
		return
	fi
	live_checks
}

# ---------------------------------------------------------------------------
# net
# ---------------------------------------------------------------------------
t_net() {
	section "Network tools"
	local _o _i _tries=0 _st _done=0 _head _rows
	if [ ! -x "$HELPER" ] || ! have curl; then skip "helper or curl missing"; return; fi

	_o=$("$HELPER" probe one.one.one.one 1.1.1.1 bad.ip 2>/dev/null)
	echo "$_o" | awk '$1=="1.1.1.1" && $2+0 > 0 { f = 1 } END { exit !f }' && pass "probe: TLS handshake with 1.1.1.1 / SNI one.one.one.one ($(echo "$_o" | awk '$1=="1.1.1.1"{print $2}') ms)" \
		|| warn "probe: no handshake with 1.1.1.1 (Internet down or TLS to 1.1.1.1 blocked): $(echo "$_o" | tr '\n' ' ')"
	echo "$_o" | grep -q '^bad.ip 0$' && pass "probe: a non-IP entry is reported as unreachable (0), not executed" || fail "probe handled an invalid IP entry wrongly: $(echo "$_o" | tr '\n' ' ')"

	if [ "$FULL" != 1 ]; then skip "CDN scanner (run with --full)"; return; fi

	_o=$("$HELPER" scan-start cdnjs.cloudflare.com cloudflare quick 2>&1)
	if [ "$_o" != started ]; then fail "scan-start did not start: $_o"; return; fi
	pass "scan-start: scanner started in the background"
	_o=$("$HELPER" scan-start cdnjs.cloudflare.com cloudflare quick 2>&1)
	t_eq "second scan-start while running is refused" "$_o" "scan-already-running"
	while [ "$_tries" -lt 60 ]; do
		_st=$("$HELPER" scan-result 2>/dev/null)
		_head=$(echo "$_st" | head -n1)
		case "$_head" in done*) _done=1; break ;; esac
		sleep 2; _tries=$((_tries+1))
	done
	if [ "$_done" = 1 ]; then
		set -- $_head
		pass "scan finished: $2/$3 IPs checked"
		_rows=$(echo "$_st" | sed '1d' | awk 'NF==2 && $1 ~ /^[0-9.]+$/ && $2+0 > 0' | wc -l)
		if [ "$_rows" -ge 1 ]; then pass "scan result: $_rows reachable Cloudflare edge IP(s), best $(echo "$_st" | sed -n '2p' | awk '{print $1" ("$2" ms)"}')"
		else warn "scan finished but no edge IP completed a TLS handshake (network blocks Cloudflare?)"; fi
		[ ! -d "$RUN/scan.lock" ] && pass "scan lock released after completion" || fail "scan lock directory left behind"
	else
		fail "scan did not finish within 120 s"
	fi
}

# ---------------------------------------------------------------------------
# lifecycle (restart -> connect -> live checks -> stop -> verify cleanup -> restore)
# ---------------------------------------------------------------------------
wait_connected() { # seconds
	local i=0
	while [ "$i" -lt "$1" ]; do
		connected_now && return 0
		sleep 3; i=$((i+3))
	done
	return 1
}

t_lifecycle() {
	section "Lifecycle: restart, connect, stop, cleanup, restore"
	local was_run=0 tunmode=0 ks=0 wan v6_before _a _o i

	if ! { [ -x "$INIT" ] && [ -x "$HELPER" ] && [ -x "$CORE" ]; }; then skip "service not fully installed"; return; fi
	pidof psiphon-core >/dev/null 2>&1 && was_run=1
	bool_on "$(U tun)" && tunmode=1
	bool_on "$(U kill_switch)" && ks=1
	wan=$(wan_dev_)
	v6_before=$(cat "/proc/sys/net/ipv6/conf/$wan/disable_ipv6" 2>/dev/null)

	if [ "$YES" != 1 ]; then
		echo "  This restarts the Psiphon service. LAN internet may be interrupted for up to a minute."
		[ "$ks" = 1 ] && [ "$tunmode" = 1 ] && echo "  Kill Switch is ON: the stop/cleanup verification is skipped (LAN would stay blocked)."
		if [ -r /dev/tty ]; then
			printf '  Continue? [y/N] ' > /dev/tty
			read -r _a < /dev/tty
			case "$_a" in y|Y|yes|YES) ;; *) skip "lifecycle test cancelled by the user"; return ;; esac
		else
			skip "no terminal for confirmation - use --yes to run the lifecycle test"
			return
		fi
	fi

	# 1. (re)start and wait for a tunnel
	_o=$("$HELPER" restart 2>&1)
	t_eq "helper restart accepted" "$_o" "started"
	if wait_connected 150; then
		pass "service (re)started and connected"
		live_checks
	else
		fail "no tunnel within 150 s after restart (see: tail -n 30 $LOG)"
		tail -n 8 "$LOG" 2>/dev/null | cut -c1-160 | while IFS= read -r _a; do printf '         %s%s%s\n' "$C_D" "$_a" "$C_N"; done
	fi

	# 2. stop and verify that every trace is gone
	if [ "$ks" = 1 ] && [ "$tunmode" = 1 ]; then
		skip "stop/cleanup verification (Kill Switch is armed - stopping would keep the LAN blocked by design)"
		[ "$was_run" = 1 ] || warn "service was stopped before the test and is left RUNNING (Kill Switch prevents a safe stop)"
		return
	fi
	"$HELPER" stop >/dev/null 2>&1
	i=0; while [ "$i" -lt 20 ] && pidof psiphon-core >/dev/null 2>&1; do sleep 1; i=$((i+1)); done
	pidof psiphon-core >/dev/null 2>&1 && fail "psiphon-core still running 20 s after stop" || pass "core stopped"
	sleep 2
	grep -q 'Stopping Psiphon' "$LOG" 2>/dev/null && pass "log shows the stop marker" || warn "stop marker not found in $LOG"
	if [ "$tunmode" = 1 ]; then
		ip link show "$TUN" >/dev/null 2>&1 && fail "$TUN still exists after stop" || pass "$TUN removed"
		ip rule show 2>/dev/null | grep -Eq "lookup $RT([[:space:]]|\$)" && fail "ip rules for table $RT left behind" || pass "no ip rules for table $RT"
		ip rule show 2>/dev/null | awk '$1=="990:"' | grep -q . && fail "pref 990 return rules left behind" || pass "no pref 990 return rules"
		[ -z "$(ip route show table "$RT" 2>/dev/null)" ] && pass "routing table $RT is empty" || fail "routing table $RT not empty after stop"
		ip -6 rule show 2>/dev/null | grep -Eq "iif .*prohibit" && fail "IPv6 prohibit rule left behind" || pass "no IPv6 prohibit rule"
		if [ -n "$v6_before" ]; then t_eq "IPv6 on WAN restored (disable_ipv6)" "$(cat "/proc/sys/net/ipv6/conf/$wan/disable_ipv6" 2>/dev/null)" "$v6_before"; fi
	fi
	if have nft; then
		for _a in psiphon_dns psiphon_ks psiphon_mss; do
			nft list table inet "$_a" >/dev/null 2>&1 && fail "nft table $_a left behind" || pass "nft table $_a removed"
		done
	fi
	_a=$(uci -q get 'dhcp.@dnsmasq[0].confdir' 2>/dev/null | awk '{print $1}'); case "$_a" in /tmp/*|/var/*|/run/*) ;; *) _a=/tmp/dnsmasq.d ;; esac
	[ ! -f "$_a/psiphon_dns.conf" ] && pass "DNS override removed" || fail "$_a/psiphon_dns.conf left behind"
	[ ! -f /etc/psiphon-dnsmasq-servers.bak ] && pass "dnsmasq upstream backup restored/removed" || fail "/etc/psiphon-dnsmasq-servers.bak left behind (dnsmasq upstreams not restored)"
	if [ -f "$RUN/doh.pid" ]; then
		kill -0 "$(cat "$RUN/doh.pid")" 2>/dev/null && fail "DoH engine still running" || pass "DoH engine stopped"
	else
		pass "DoH engine stopped"
	fi
	have nslookup && { resolves_public example.com 127.0.0.1 && pass "router DNS works after stop" || fail "router DNS broken after stop"; }
	if have curl; then
		case "$(curl -sI -m 10 https://api.github.com/zen 2>/dev/null | head -n1)" in HTTP*) pass "router HTTPS over the normal WAN works after stop" ;; *) fail "router has no HTTPS access after stop" ;; esac
	fi

	# 3. restore the previous state
	if [ "$was_run" = 1 ]; then
		"$HELPER" restart >/dev/null 2>&1
		if wait_connected 150; then pass "previous state restored (service running and connected)"; else warn "service was restarted but has not connected yet (still connecting)"; fi
	else
		pass "previous state kept (service was stopped before the test)"
	fi
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
echo "Psiphon VPN test suite - $(date '+%Y-%m-%d %H:%M:%S')  (helper: $HELPER)"

want env       && t_env
want files     && t_files
want config    && t_config
want helper    && t_helper
want live      && t_live
want net       && t_net
want lifecycle && t_lifecycle

echo
printf '%s============================================================%s\n' "$C_B" "$C_N"
printf ' Summary:  %s%d passed%s   %s%d failed%s   %s%d warnings%s   %d skipped\n' "$C_G" "$PASS" "$C_N" "$C_R" "$FAIL" "$C_N" "$C_Y" "$WARN" "$C_N" "$SKIP"
if [ -s "$TMPD/failed" ]; then
	printf '\n %sFailures:%s\n' "$C_R" "$C_N"
	sed 's/^/   - /' "$TMPD/failed"
fi
if [ -s "$TMPD/warned" ]; then
	printf '\n %sWarnings:%s\n' "$C_Y" "$C_N"
	sed 's/^/   - /' "$TMPD/warned"
fi
printf '%s============================================================%s\n' "$C_B" "$C_N"
[ "$FAIL" -eq 0 ] && exit 0
exit 1
