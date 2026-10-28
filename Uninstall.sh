#!/bin/sh
# ---------------------------------------------------------------------------
# Uninstall.sh - complete removal of luci-app-psiphon (Psiphon VPN for OpenWrt)
# Companion of Psiphon_VPN_2_0_42_manual_setup.sh
#
# What it does (in this order, every step is idempotent and non-fatal):
#   1. stops + disables the service, releases the Kill Switch, kills leftovers
#   2. runs the helper's own cleanup, then repeats it manually as a fallback:
#        nft tables (psiphon_dns / psiphon_ks / psiphon_mss), ip rules (pref 990 /
#        1000), routing table 100, tun0, IPv6 sysctl, dnsmasq override, DoH engine,
#        dnsmasq upstreams that the service had isolated
#   3. removes the installed files + the firewall zone/forwarding
#   4. removes the entries the installer added to /etc/sysupgrade.conf
#   5. (optional) purges config / datastore / core binary / extra packages
#   6. reloads firewall, dnsmasq, rpcd, uhttpd and verifies nothing is left over
#
# Usage: sh Uninstall.sh [options]
#   -y, --yes          do not ask for confirmation
#   --purge            also delete /etc/config/psiphon, /etc/psiphon (datastore)
#                      and /usr/bin/psiphon-core
#   --remove-deps      also remove https-dns-proxy and tcpdump (installed by the
#                      installer; do NOT use if other services need them)
#   --reset-confdir    unset dnsmasq 'confdir' if it is still /tmp/dnsmasq.d
#                      (the installer sets it when it was empty)
#   -h, --help         show this help
# ---------------------------------------------------------------------------

PSI_YES=0; PSI_PURGE=0; PSI_RMDEPS=0; PSI_RESET_CD=0

usage() {
	cat <<'USAGE'
Usage: sh Uninstall.sh [options]
  -y, --yes          do not ask for confirmation
  --purge            also delete /etc/config/psiphon, /etc/psiphon (datastore)
                     and /usr/bin/psiphon-core
  --remove-deps      also remove https-dns-proxy and tcpdump (installed by the
                     installer; do NOT use if other services need them)
  --reset-confdir    unset dnsmasq 'confdir' if it is still /tmp/dnsmasq.d
                     (the installer sets it when it was empty)
  -h, --help         show this help
USAGE
}

for _a in "$@"; do
	case "$_a" in
		-y|--yes) PSI_YES=1 ;;
		--purge) PSI_PURGE=1 ;;
		--remove-deps) PSI_RMDEPS=1 ;;
		--reset-confdir) PSI_RESET_CD=1 ;;
		-h|--help) usage; exit 0 ;;
		*) echo "WARNING: unknown option: $_a" >&2; usage; exit 2 ;;
	esac
done

if [ -t 1 ]; then
	C_R=$(printf '\033[31m'); C_G=$(printf '\033[32m'); C_Y=$(printf '\033[33m'); C_B=$(printf '\033[36m'); C_N=$(printf '\033[0m')
else
	C_R=""; C_G=""; C_Y=""; C_B=""; C_N=""
fi
step() { printf '\n%s==> %s%s\n' "$C_B" "$*" "$C_N"; }
ok()   { printf '  %s[ok]%s %s\n' "$C_G" "$C_N" "$*"; }
note() { printf '  %s[..]%s %s\n' "$C_B" "$C_N" "$*"; }
warn() { printf '  %s[!!]%s %s\n' "$C_Y" "$C_N" "$*" >&2; }
err()  { printf '  %s[XX]%s %s\n' "$C_R" "$C_N" "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }

[ "$(id -u 2>/dev/null)" = "0" ] || { err "must be run as root"; exit 1; }

RUN=/tmp/psiphon
TUN=tun0
RT=100
HELPER=/usr/bin/psiphon-helper
CORE=/usr/bin/psiphon-core
FOREIGN_BAK=/etc/psiphon-dnsmasq-servers.bak
SUCONF=/etc/sysupgrade.conf

APP_FILES="/etc/init.d/psiphon /usr/bin/psiphon-helper /etc/hotplug.d/iface/90-psiphon \
/usr/share/luci/menu.d/luci-app-psiphon.json /usr/share/rpcd/acl.d/luci-app-psiphon.json \
/www/luci-static/resources/view/vpn/psiphon.js /etc/rc.d/S99psiphon"

# every path the installer put into sysupgrade.conf
SU_ENTRIES="/etc/config/psiphon /etc/init.d/psiphon /usr/bin/psiphon-helper /etc/hotplug.d/iface/90-psiphon \
/usr/share/luci/menu.d/luci-app-psiphon.json /usr/share/rpcd/acl.d/luci-app-psiphon.json \
/www/luci-static/resources/view/vpn/psiphon.js /usr/bin/psiphon-core /etc/psiphon /etc/rc.d/S99psiphon"

# dnsmasq conf-dir (same logic as the helper: must be on tmpfs)
_cd=$(uci -q get 'dhcp.@dnsmasq[0].confdir' 2>/dev/null | awk '{print $1}')
case "$_cd" in /tmp/*|/var/*|/run/*) ;; *) _cd=/tmp/dnsmasq.d ;; esac
DNSCONF="$_cd/psiphon_dns.conf"

# ---- is anything installed? -------------------------------------------------
FOUND=0
for _f in $APP_FILES /etc/config/psiphon $CORE /etc/psiphon; do
	[ -e "$_f" ] && FOUND=1
done
uci -q get firewall.psiphon >/dev/null 2>&1 && FOUND=1
[ -d "$RUN" ] && FOUND=1

echo "Psiphon VPN (luci-app-psiphon) uninstaller"
if [ "$FOUND" = 0 ]; then
	echo "Nothing to uninstall: no Psiphon files, firewall zone or runtime state found."
	echo "(Still checking for leftover network state below.)"
fi
echo
echo "Plan:"
echo "  - stop the service, release Kill Switch, restore DNS / IPv6 / routing"
echo "  - remove LuCI app, init script, helper, hotplug, ACL, menu, firewall zone"
if [ "$PSI_PURGE" = 1 ]; then
	echo "  - PURGE: delete /etc/config/psiphon, /etc/psiphon (datastore) and $CORE"
else
	echo "  - keep /etc/config/psiphon, /etc/psiphon and $CORE (use --purge to remove)"
fi
[ "$PSI_RMDEPS" = 1 ]   && echo "  - remove packages: https-dns-proxy tcpdump"
[ "$PSI_RESET_CD" = 1 ] && echo "  - reset dnsmasq confdir if it is /tmp/dnsmasq.d"
echo

if [ "$PSI_YES" != 1 ]; then
	if [ -r /dev/tty ]; then
		printf 'Continue? [y/N] ' > /dev/tty
		read -r _ans < /dev/tty
		case "$_ans" in y|Y|yes|YES) ;; *) echo "Aborted."; exit 1 ;; esac
	else
		err "no terminal available for confirmation - re-run with --yes"
		exit 1
	fi
fi

# ---- helpers ----------------------------------------------------------------
# kill every process whose command line matches an ERE (never ourselves)
kill_matching() {
	local _p _c _sig="${2:-TERM}"
	for _p in /proc/[0-9]*; do
		_p=${_p#/proc/}
		[ "$_p" = "$$" ] && continue
		_c=$(tr '\000' ' ' < "/proc/$_p/cmdline" 2>/dev/null) || continue
		[ -n "$_c" ] || continue
		echo "$_c" | grep -Eq "$1" && kill -"$_sig" "$_p" 2>/dev/null
	done
	return 0
}

# ---- 1. stop the service ----------------------------------------------------
step "Stopping the service"
if [ -x /etc/init.d/psiphon ]; then
	/etc/init.d/psiphon disable >/dev/null 2>&1 && note "autostart disabled"
	# PSI_KS_RELEASE makes the helper drop the kill-switch hold instead of keeping LAN blocked
	PSI_KS_RELEASE=1 /etc/init.d/psiphon stop >/dev/null 2>&1 && note "init script stop done"
else
	note "init script not present"
fi

# the watcher, a running scan, and the core itself (if procd did not take them down)
kill_matching 'psiphon-helper[[:space:]]+(watch|_scan_inner|scan-start|run-core)'
if pidof psiphon-core >/dev/null 2>&1; then
	_pids=$(pidof psiphon-core)
	kill -TERM $_pids 2>/dev/null
	_i=0
	while [ "$_i" -lt 8 ] && pidof psiphon-core >/dev/null 2>&1; do sleep 1; _i=$((_i+1)); done
	if pidof psiphon-core >/dev/null 2>&1; then
		kill -KILL $(pidof psiphon-core) 2>/dev/null
		sleep 1
	fi
fi
if pidof psiphon-core >/dev/null 2>&1; then
	warn "psiphon-core is still running"
else
	ok "psiphon-core is not running"
fi

# ---- 2. network / DNS cleanup ----------------------------------------------
step "Restoring network state"

# 2a. the helper knows best what it created
if [ -x "$HELPER" ]; then
	PSI_INTERNAL=1 PSI_KS_RELEASE=1 "$HELPER" cleanup >/dev/null 2>&1 && ok "helper cleanup finished" || warn "helper cleanup returned an error - doing manual cleanup"
else
	note "helper not present - doing manual cleanup only"
fi

# 2b. manual, idempotent fallback (covers a missing/broken helper or a crash)

# DoH engine we started (verify the pid really is https-dns-proxy: the system may run its own)
if [ -f "$RUN/doh.pid" ]; then
	_dp=$(cat "$RUN/doh.pid" 2>/dev/null)
	case "$_dp" in
		''|*[!0-9]*) ;;
		*)
			if tr '\000' ' ' < "/proc/$_dp/cmdline" 2>/dev/null | grep -q 'https-dns-proxy'; then
				kill "$_dp" 2>/dev/null && ok "stopped DoH engine (pid $_dp)"
			fi
			;;
	esac
fi

# nftables tables
if have nft; then
	for _t in psiphon_dns psiphon_ks psiphon_mss; do
		if nft list table inet "$_t" >/dev/null 2>&1; then
			nft delete table inet "$_t" 2>/dev/null && ok "removed nft table inet $_t"
		fi
	done
fi
# iptables fallback chains (only used when nft was unavailable at install/run time)
if have iptables; then
	iptables -t nat -D PREROUTING -j psiphon_dns_nat >/dev/null 2>&1
	iptables -t nat -F psiphon_dns_nat >/dev/null 2>&1; iptables -t nat -X psiphon_dns_nat >/dev/null 2>&1
	for _ch in OUTPUT FORWARD; do iptables -D "$_ch" -j psiphon_dns_block >/dev/null 2>&1; done
	iptables -F psiphon_dns_block >/dev/null 2>&1; iptables -X psiphon_dns_block >/dev/null 2>&1
fi

# policy routing: rules that point to table 100, then the RFC1918/LAN return rules (pref 990)
if have ip; then
	_had_rules=0
	ip rule show 2>/dev/null | grep -Eq "lookup $RT([[:space:]]|\$)" && _had_rules=1
	[ -f "$RUN/ip_rules_owned" ] && _had_rules=1
	if [ "$_had_rules" = 1 ]; then
		for _n in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
			_pref=$(ip rule show 2>/dev/null | awk -v rt="$RT" '$0 ~ ("lookup " rt "([ ]|$)") {sub(":","",$1); print $1; exit}')
			[ -n "$_pref" ] || break
			ip rule del pref "$_pref" 2>/dev/null || break
		done
		for _n in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
			ip rule show 2>/dev/null | awk '$1=="990:" && /lookup main/ {f=1} END{exit !f}' || break
			ip rule del pref 990 2>/dev/null || break
		done
		ok "removed Psiphon ip rules"
	fi
	# IPv6 'prohibit' rule for the LAN device (pref 1000)
	for _n in 1 2 3 4 5; do
		ip -6 rule show 2>/dev/null | awk '$1=="1000:" && /iif .*prohibit/ {f=1} END{exit !f}' || break
		ip -6 rule del pref 1000 2>/dev/null || break
	done
	# routing table 100
	if [ -n "$(ip route show table $RT 2>/dev/null)" ]; then
		ip route flush table "$RT" 2>/dev/null && ok "flushed routing table $RT"
	fi
	# tun0: only delete it when Psiphon created it (an OpenVPN/WireGuard tun0 must survive)
	if ip link show "$TUN" >/dev/null 2>&1; then
		if [ -f "$RUN/tun_owned" ]; then
			ip -4 addr flush dev "$TUN" 2>/dev/null
			ip link delete "$TUN" 2>/dev/null && ok "removed $TUN"
		else
			note "$TUN exists but was not created by Psiphon - left untouched"
		fi
	fi
fi

# IPv6 on the WAN device (the Kill Switch may have disabled it)
if [ -f "$RUN/ipv6_disabled_wan" ]; then
	_w6=$(cat "$RUN/ipv6_disabled_wan" 2>/dev/null)
	if [ -n "$_w6" ] && [ -w "/proc/sys/net/ipv6/conf/$_w6/disable_ipv6" ]; then
		echo 0 > "/proc/sys/net/ipv6/conf/$_w6/disable_ipv6" 2>/dev/null && ok "IPv6 re-enabled on $_w6 (addresses return with the next RA/DHCPv6 renewal)"
	fi
fi

# dnsmasq: put back the upstream servers that the service had isolated
if [ -f "$FOREIGN_BAK" ]; then
	if [ -s "$FOREIGN_BAK" ]; then
		uci -q delete 'dhcp.@dnsmasq[0].server'
		while read -r _v; do
			[ -n "$_v" ] && uci -q add_list "dhcp.@dnsmasq[0].server=$_v"
		done < "$FOREIGN_BAK"
		uci -q commit dhcp && ok "restored dnsmasq upstream servers"
	fi
	rm -f "$FOREIGN_BAK"
fi
# dnsmasq: the Psiphon DNS override (check both the detected and the default location)
for _f in "$DNSCONF" /tmp/dnsmasq.d/psiphon_dns.conf; do
	[ -f "$_f" ] && rm -f "$_f" && ok "removed $_f"
done

# ---- 3. remove files + firewall --------------------------------------------
step "Removing files"
for _f in $APP_FILES; do
	if [ -e "$_f" ] || [ -L "$_f" ]; then
		rm -f "$_f" && note "removed $_f"
	fi
done
rm -f /usr/share/rpcd/acl.d/luci-app-psiphon.json.old 2>/dev/null
# the "vpn" view directory is only removed when it is empty (other apps may use it)
rmdir /www/luci-static/resources/view/vpn 2>/dev/null

step "Removing the firewall zone"
_fw_changed=0
# remove by name as well as by the fixed section names, in case the sections were renamed
for _s in $(uci -q show firewall 2>/dev/null | sed -n "s/^firewall\.\([^.=]*\)\.name='psiphon'\$/\1/p") psiphon; do
	if uci -q get "firewall.$_s" >/dev/null 2>&1; then
		uci -q delete "firewall.$_s" && _fw_changed=1
	fi
done
for _s in $(uci -q show firewall 2>/dev/null | sed -n "s/^firewall\.\([^.=]*\)\.dest='psiphon'\$/\1/p") psiphon_forwarding; do
	if uci -q get "firewall.$_s" >/dev/null 2>&1; then
		uci -q delete "firewall.$_s" && _fw_changed=1
	fi
done
if [ "$_fw_changed" = 1 ]; then
	uci -q commit firewall && ok "firewall zone 'psiphon' and its forwarding removed"
else
	note "no Psiphon firewall zone found"
fi

# ---- 4. sysupgrade.conf -----------------------------------------------------
step "Cleaning $SUCONF"
if [ -f "$SUCONF" ]; then
	_su_tmp=$(mktemp /tmp/psiphon-su.XXXXXX 2>/dev/null) || _su_tmp=/tmp/psiphon-su.$$
	cp -p "$SUCONF" "$_su_tmp" 2>/dev/null
	for _f in $SU_ENTRIES; do
		grep -vxF -e "$_f" "$_su_tmp" > "$_su_tmp.n"; _rc=$?
		# grep exits 1 when no line is left - that is fine (empty file); >1 means a real error
		[ "$_rc" -le 1 ] && cat "$_su_tmp.n" > "$_su_tmp"
		rm -f "$_su_tmp.n"
	done
	if ! cmp -s "$_su_tmp" "$SUCONF"; then
		cat "$_su_tmp" > "$SUCONF" && ok "removed Psiphon entries from $SUCONF"
	else
		note "no Psiphon entries in $SUCONF"
	fi
	rm -f "$_su_tmp"
else
	note "$SUCONF not present"
fi

# ---- 5. optional purge / packages / confdir ---------------------------------
if [ "$PSI_PURGE" = 1 ]; then
	step "Purging data"
	rm -rf /etc/config/psiphon /etc/psiphon "$CORE"
	ok "removed /etc/config/psiphon, /etc/psiphon and $CORE"
fi

if [ "$PSI_RMDEPS" = 1 ]; then
	step "Removing packages"
	if have apk; then
		apk del https-dns-proxy tcpdump >/dev/null 2>&1 && ok "apk del https-dns-proxy tcpdump" || warn "apk del failed or packages not installed"
	elif have opkg; then
		opkg remove https-dns-proxy tcpdump >/dev/null 2>&1 && ok "opkg remove https-dns-proxy tcpdump" || warn "opkg remove failed or packages not installed"
	else
		warn "no package manager found"
	fi
fi

if [ "$PSI_RESET_CD" = 1 ]; then
	step "dnsmasq confdir"
	if [ "$(uci -q get 'dhcp.@dnsmasq[0].confdir' 2>/dev/null)" = "/tmp/dnsmasq.d" ]; then
		uci -q delete 'dhcp.@dnsmasq[0].confdir' && uci -q commit dhcp && ok "confdir reset"
	else
		note "confdir is not /tmp/dnsmasq.d - left untouched"
	fi
else
	note "dnsmasq confdir was left untouched (use --reset-confdir to unset /tmp/dnsmasq.d)"
fi

# ---- 6. temp files, caches, service reloads --------------------------------
step "Cleaning temporary files and reloading services"
rm -rf "$RUN" /tmp/psiphon.log /tmp/psiphon-install-backup.* /tmp/psiphon-setup.* /tmp/psiphon-dns.* 2>/dev/null
rm -rf /tmp/luci-indexcache* /tmp/luci-modulecache/ /var/luci-indexcache* 2>/dev/null
[ -x /etc/init.d/firewall ] && { /etc/init.d/firewall reload >/dev/null 2>&1 && note "firewall reloaded" || warn "firewall reload failed"; }
[ -x /etc/init.d/dnsmasq ]  && { /etc/init.d/dnsmasq restart  >/dev/null 2>&1 && note "dnsmasq restarted" || warn "dnsmasq restart failed"; }
[ -x /etc/init.d/rpcd ]     && { /etc/init.d/rpcd restart     >/dev/null 2>&1 && note "rpcd restarted"; }
[ -x /etc/init.d/uhttpd ]   && { /etc/init.d/uhttpd restart   >/dev/null 2>&1 && note "uhttpd restarted"; }

# ---- 7. verification --------------------------------------------------------
step "Verifying"
LEFT=0
chk() { # description, condition command...  -> prints a warning when the condition is TRUE (= leftover)
	local _d="$1"; shift
	if "$@" >/dev/null 2>&1; then warn "leftover: $_d"; LEFT=$((LEFT+1)); fi
}
for _f in $APP_FILES; do chk "$_f exists" test -e "$_f"; done
chk "psiphon-core process running"      pidof psiphon-core
chk "firewall zone 'psiphon' present"   uci -q get firewall.psiphon
chk "$RUN still exists"                 test -e "$RUN"
chk "$DNSCONF still exists"             test -e "$DNSCONF"
if have nft; then
	for _t in psiphon_dns psiphon_ks psiphon_mss; do chk "nft table inet $_t" nft list table inet "$_t"; done
fi
if have ip; then
	chk "ip rules pointing to table $RT"  sh -c "ip rule show | grep -Eq 'lookup $RT([[:space:]]|\$)'"
	chk "routes in table $RT"             sh -c "[ -n \"\$(ip route show table $RT)\" ]"
	ip link show "$TUN" >/dev/null 2>&1 && note "$TUN still exists (not created by Psiphon, or belongs to another VPN)"
fi
if [ "$PSI_PURGE" = 1 ]; then
	chk "/etc/config/psiphon exists" test -e /etc/config/psiphon
	chk "/etc/psiphon exists"        test -e /etc/psiphon
	chk "$CORE exists"               test -e "$CORE"
fi

# connectivity sanity check (router -> internet over the normal WAN path)
if have curl; then
	if curl -s -m 8 -o /dev/null -w '%{http_code}' https://api.github.com/zen 2>/dev/null | grep -q '^[23]'; then
		ok "router internet access works"
	else
		warn "router could not reach https://api.github.com (check WAN / DNS - ca-bundle installed?)"
	fi
fi
if have nslookup; then
	if nslookup example.com 127.0.0.1 2>/dev/null | grep -q '^Name:'; then
		ok "local DNS resolver (dnsmasq) answers"
	else
		warn "local DNS resolver did not answer - try: /etc/init.d/dnsmasq restart"
	fi
fi

echo
if [ "$LEFT" = 0 ]; then
	printf '%sDone. Psiphon VPN has been removed.%s\n' "$C_G" "$C_N"
else
	printf '%sDone with %s leftover(s) - see the warnings above.%s\n' "$C_Y" "$LEFT" "$C_N"
fi
[ "$PSI_PURGE" = 1 ] || echo "Kept: /etc/config/psiphon, /etc/psiphon, $CORE (reinstall will reuse them; add --purge to delete)."
echo "If the LuCI menu still shows 'VPN > Psiphon VPN', reload the page with Ctrl+F5."
[ "$LEFT" = 0 ] || exit 1
exit 0
