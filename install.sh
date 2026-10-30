#!/bin/sh
# ==============================================================================
# Psiphon Core for OpenWrt 25 / LuCI — One-Click Installer
# Repo: https://github.com/MehArt44/Psiphon-core-Openwrt25-LuCI
#
# اجرا روی روتر:
#   wget -O /tmp/install.sh https://raw.githubusercontent.com/MehArt44/Psiphon-core-Openwrt25-LuCI/main/install.sh
#   sh /tmp/install.sh
# ==============================================================================

set -e

# ==============================================================================
# پردازش آرگومان‌ها و حالت حذف (--uninstall / --purge)
# ------------------------------------------------------------------------------
# این بخش عمداً قبل از دانلود قرار دارد تا حذف بدون دانلود مجدد باینری انجام شود.
# ==============================================================================
PSI_AUTO_INSTALL_DOH="${PSI_AUTO_INSTALL_DOH:-0}"
PSI_UNINSTALL=0; PSI_PURGE=0
for _a in "$@"; do
	case "$_a" in
		--auto-install-doh) PSI_AUTO_INSTALL_DOH=1 ;;
		--uninstall) PSI_UNINSTALL=1 ;;
		--purge) PSI_UNINSTALL=1; PSI_PURGE=1 ;;
		-h|--help) echo "Usage: sh $0 [--auto-install-doh] [--uninstall] [--purge]"; exit 0 ;;
		*) echo "WARNING: unknown option: $_a" >&2 ;;
	esac
done
if [ "$PSI_UNINSTALL" = 1 ]; then
	echo "Uninstalling luci-app-psiphon..."
	[ -x /etc/init.d/psiphon ] && { /etc/init.d/psiphon stop >/dev/null 2>&1 || true; /etc/init.d/psiphon disable >/dev/null 2>&1 || true; }
	[ -x /usr/bin/psiphon-helper ] && { PSI_INTERNAL=1 PSI_KS_RELEASE=1 /usr/bin/psiphon-helper cleanup >/dev/null 2>&1 || true; }
	rm -f /etc/init.d/psiphon /usr/bin/psiphon-helper /etc/hotplug.d/iface/90-psiphon \
		/usr/share/luci/menu.d/luci-app-psiphon.json /usr/share/rpcd/acl.d/luci-app-psiphon.json \
		/www/luci-static/resources/view/vpn/psiphon.js /etc/rc.d/S99psiphon
	rm -rf /tmp/psiphon /tmp/psiphon.log /tmp/dnsmasq.d/psiphon_dns.conf
	if uci -q get firewall.psiphon >/dev/null 2>&1; then
		uci -q delete firewall.psiphon_forwarding || true
		uci -q delete firewall.psiphon || true
		uci -q commit firewall || true
	fi
	if [ -f /etc/sysupgrade.conf ]; then
		for _f in /etc/config/psiphon /etc/init.d/psiphon /usr/bin/psiphon-helper /etc/hotplug.d/iface/90-psiphon \
			/usr/share/luci/menu.d/luci-app-psiphon.json /usr/share/rpcd/acl.d/luci-app-psiphon.json \
			/www/luci-static/resources/view/vpn/psiphon.js /usr/bin/psiphon-core /etc/psiphon /etc/rc.d/S99psiphon; do
			grep -vxF "$_f" /etc/sysupgrade.conf > /etc/sysupgrade.conf.psi.tmp 2>/dev/null && cat /etc/sysupgrade.conf.psi.tmp > /etc/sysupgrade.conf
			rm -f /etc/sysupgrade.conf.psi.tmp
		done
	fi
	if [ "$PSI_PURGE" = 1 ]; then
		rm -rf /etc/config/psiphon /etc/psiphon /usr/bin/psiphon-core
		echo "Purged config, datastore and core binary."
	else
		echo "Kept /etc/config/psiphon, /etc/psiphon and /usr/bin/psiphon-core (use --purge to remove them)."
	fi
	echo "Note: dhcp confdir (dnsmasq) was left untouched."
	rm -rf /tmp/luci-indexcache* /tmp/luci-modulecache/ /var/luci-indexcache* 2>/dev/null || true
	[ -x /etc/init.d/firewall ] && { /etc/init.d/firewall reload >/dev/null 2>&1 || true; }
	[ -x /etc/init.d/dnsmasq ] && { /etc/init.d/dnsmasq restart >/dev/null 2>&1 || true; }
	[ -x /etc/init.d/rpcd ] && { /etc/init.d/rpcd restart >/dev/null 2>&1 || true; }
	[ -x /etc/init.d/uhttpd ] && { /etc/init.d/uhttpd restart >/dev/null 2>&1 || true; }
	echo "Done."
	exit 0
fi


REPO_TAG="2.0.42"
BASE_URL="https://github.com/MehArt44/Psiphon-core-Openwrt25-LuCI/releases/download/${REPO_TAG}"
BIN_PATH="/usr/bin/psiphon-core"
TMP_BIN="/tmp/psiphon-core.download"

echo "=============================================="
echo " Psiphon Core Installer for OpenWrt / LuCI"
echo "=============================================="

# ==============================================================================
# مرحله ۰: بررسی پیش‌نیازها (باید یکی از wget یا curl موجود باشد)
# ------------------------------------------------------------------------------
# روی اکثر روترهای OpenWrt به‌صورت پیش‌فرض busybox wget نصب است؛ این بخش هر دو
# را چک می‌کند تا اسکریپت روی هر دستگاهی بدون خطا اجرا شود.
# ==============================================================================
if command -v wget >/dev/null 2>&1; then
    DOWNLOADER="wget"
elif command -v curl >/dev/null 2>&1; then
    DOWNLOADER="curl"
else
    echo "خطا: هیچ‌کدام از wget یا curl روی این روتر نصب نیست."
    echo "ابتدا با دستور: opkg update && opkg install wget-ssl   نصب کنید."
    exit 1
fi

download_file() {
    # $1 = URL   $2 = مسیر مقصد
    if [ "$DOWNLOADER" = "wget" ]; then
        wget -q --show-progress -O "$2" "$1" || wget -q -O "$2" "$1"
    else
        curl -fSL -o "$2" "$1"
    fi
}

# ==============================================================================
# مرحله ۱: شناسایی معماری CPU روتر
# ------------------------------------------------------------------------------
# خروجی uname -m به یکی از فرم‌های رایج ARM/MIPS/x86 ترجمه می‌شود تا نام درست
# فایل باینری منتشر شده در ریلیز گیت‌هاب انتخاب گردد.
# ==============================================================================
echo ""
echo "[1/5] شناسایی معماری پردازنده..."
RAW_ARCH=$(uname -m)
echo "      خروجی uname -m: ${RAW_ARCH}"

case "$RAW_ARCH" in
    x86_64|amd64)
        ARCH="amd64"
        ;;
    i386|i486|i586|i686)
        ARCH="386"
        ;;
    aarch64|aarch64_be|arm64)
        ARCH="arm64"
        ;;
    armv7*|armv6l)
        ARCH="armv7"
        ;;
    armv5*|armv4*|arm)
        ARCH="armv5"
        ;;
    mips)
        # تشخیص endianness برای مسیرهای MIPS خالص (بدون le/be در uname)
        if echo -n I | od -to2 | head -n1 | grep -qE '01[[:space:]]*$'; then
            ARCH="mipsle"
        else
            ARCH="mips"
        fi
        ;;
    mipsel|mipsle)
        ARCH="mipsle"
        ;;
    mips64|mips64el|mips64le)
        ARCH="mips64le"
        ;;
    *)
        echo "خطا: معماری '${RAW_ARCH}' پشتیبانی نمی‌شود."
        echo "معماری‌های پشتیبانی‌شده: 386, amd64, arm64, armv5, armv7, mips, mipsle, mips64le"
        exit 1
        ;;
esac
echo "      معماری انتخاب‌شده برای دانلود: ${ARCH}"

# ==============================================================================
# مرحله ۲: دانلود باینری متناظر از ریلیز گیت‌هاب
# ------------------------------------------------------------------------------
# فایل ابتدا در /tmp دانلود می‌شود تا در صورت قطع‌شدن دانلود یا خرابی فایل،
# نسخه‌ی قبلاً نصب‌شده (در صورت وجود) دست‌نخورده باقی بماند.
# ==============================================================================
echo ""
echo "[2/5] دانلود psiphon-core-${ARCH} ... (ممکن است تا ۱۰ دقیقه طول بکشد، لطفاً صبر کنید)"
DOWNLOAD_URL="${BASE_URL}/psiphon-core-${ARCH}"
download_file "$DOWNLOAD_URL" "$TMP_BIN"

if [ ! -s "$TMP_BIN" ]; then
    echo "خطا: دانلود ناموفق بود یا فایل خالی است. لینک را بررسی کنید:"
    echo "      $DOWNLOAD_URL"
    exit 1
fi
echo "      دانلود با موفقیت انجام شد."

# ==============================================================================
# مرحله ۳ و ۴: انتقال به /usr/bin/ و تغییر نام به psiphon-core
# ------------------------------------------------------------------------------
# اگر سرویس از قبل در حال اجرا باشد، ابتدا متوقف می‌شود تا فایل باینری در حال
# استفاده جایگزین نشود (جلوگیری از خطای "Text file busy").
# ==============================================================================
echo ""
echo "[3/5] نصب باینری در ${BIN_PATH} ..."
[ -x /etc/init.d/psiphon ] && /etc/init.d/psiphon stop >/dev/null 2>&1 || true

mv -f "$TMP_BIN" "$BIN_PATH"
chmod +x "$BIN_PATH"
echo "      باینری با موفقیت در ${BIN_PATH} قرار گرفت."
# ==============================================================================
set -e
PSI_AUTO_INSTALL_DOH="${PSI_AUTO_INSTALL_DOH:-0}"
PSI_UNINSTALL=0; PSI_PURGE=0
for _a in "$@"; do
	case "$_a" in
		--auto-install-doh) PSI_AUTO_INSTALL_DOH=1 ;;
		--uninstall) PSI_UNINSTALL=1 ;;
		--purge) PSI_UNINSTALL=1; PSI_PURGE=1 ;;
		-h|--help) echo "Usage: sh $0 [--auto-install-doh] [--uninstall] [--purge]"; exit 0 ;;
		*) echo "WARNING: unknown option: $_a" >&2 ;;
	esac
done
if [ "$PSI_UNINSTALL" = 1 ]; then
	echo "Uninstalling luci-app-psiphon..."
	[ -x /etc/init.d/psiphon ] && { /etc/init.d/psiphon stop >/dev/null 2>&1 || true; /etc/init.d/psiphon disable >/dev/null 2>&1 || true; }
	[ -x /usr/bin/psiphon-helper ] && { PSI_INTERNAL=1 PSI_KS_RELEASE=1 /usr/bin/psiphon-helper cleanup >/dev/null 2>&1 || true; }
	rm -f /etc/init.d/psiphon /usr/bin/psiphon-helper /etc/hotplug.d/iface/90-psiphon \
		/usr/share/luci/menu.d/luci-app-psiphon.json /usr/share/rpcd/acl.d/luci-app-psiphon.json \
		/www/luci-static/resources/view/vpn/psiphon.js /etc/rc.d/S99psiphon
	rm -rf /tmp/psiphon /tmp/psiphon.log /tmp/dnsmasq.d/psiphon_dns.conf
	if uci -q get firewall.psiphon >/dev/null 2>&1; then
		uci -q delete firewall.psiphon_forwarding || true
		uci -q delete firewall.psiphon || true
		uci -q commit firewall || true
	fi
	if [ -f /etc/sysupgrade.conf ]; then
		for _f in /etc/config/psiphon /etc/init.d/psiphon /usr/bin/psiphon-helper /etc/hotplug.d/iface/90-psiphon \
			/usr/share/luci/menu.d/luci-app-psiphon.json /usr/share/rpcd/acl.d/luci-app-psiphon.json \
			/www/luci-static/resources/view/vpn/psiphon.js /usr/bin/psiphon-core /etc/psiphon /etc/rc.d/S99psiphon; do
			grep -vxF "$_f" /etc/sysupgrade.conf > /etc/sysupgrade.conf.psi.tmp 2>/dev/null && cat /etc/sysupgrade.conf.psi.tmp > /etc/sysupgrade.conf
			rm -f /etc/sysupgrade.conf.psi.tmp
		done
	fi
	if [ "$PSI_PURGE" = 1 ]; then
		rm -rf /etc/config/psiphon /etc/psiphon /usr/bin/psiphon-core
		echo "Purged config, datastore and core binary."
	else
		echo "Kept /etc/config/psiphon, /etc/psiphon and /usr/bin/psiphon-core (use --purge to remove them)."
	fi
	echo "Note: dhcp confdir (dnsmasq) was left untouched."
	rm -rf /tmp/luci-indexcache* /tmp/luci-modulecache/ /var/luci-indexcache* 2>/dev/null || true
	[ -x /etc/init.d/firewall ] && { /etc/init.d/firewall reload >/dev/null 2>&1 || true; }
	[ -x /etc/init.d/dnsmasq ] && { /etc/init.d/dnsmasq restart >/dev/null 2>&1 || true; }
	[ -x /etc/init.d/rpcd ] && { /etc/init.d/rpcd restart >/dev/null 2>&1 || true; }
	[ -x /etc/init.d/uhttpd ] && { /etc/init.d/uhttpd restart >/dev/null 2>&1 || true; }
	echo "Done."
	exit 0
fi
if [ ! -x /usr/bin/psiphon-core ] && [ ! -f /usr/bin/psiphon-core ]; then
	echo "ERROR: /usr/bin/psiphon-core not found. Install the Psiphon core binary first (see README)."
	exit 1
fi
PSI_BACKUP_DIR=$(mktemp -d /tmp/psiphon-install-backup.XXXXXX) || { echo "ERROR: mktemp failed" >&2; exit 1; }
mkdir -p "$PSI_BACKUP_DIR/files"
: > "$PSI_BACKUP_DIR/manifest"
_PSI_TOUCHED=0
_PSI_WAS_RUNNING=0
pidof psiphon-core >/dev/null 2>&1 && _PSI_WAS_RUNNING=1
_psi_backup() {
	local _orig="$1" _safe
	if command -v md5sum >/dev/null 2>&1; then
		_safe=$(printf '%s' "$_orig" | md5sum | cut -d' ' -f1)
	else
		_safe=$(printf '%s' "$_orig" | tr '/' '_')
	fi
	if [ -f "$_orig" ]; then
		cp -p "$_orig" "$PSI_BACKUP_DIR/files/$_safe" 2>/dev/null
		echo "file=$_safe=$_orig" >> "$PSI_BACKUP_DIR/manifest"
	else
		echo "absent=$_safe=$_orig" >> "$PSI_BACKUP_DIR/manifest"
	fi
}
_psi_rollback() {
	local _rc="${1:-$?}" _kind _safe _orig
	set +e
	if [ "$_rc" -ne 0 ] && [ "${_PSI_TOUCHED:-0}" = 1 ] && [ -d "$PSI_BACKUP_DIR" ] && [ -s "$PSI_BACKUP_DIR/manifest" ]; then
		echo "[!] install FAILED (rc=$_rc) - restoring previous files..." >&2
		[ -x /etc/init.d/psiphon ] && /etc/init.d/psiphon stop >/dev/null 2>&1
		[ -x /usr/bin/psiphon-helper ] && PSI_INTERNAL=1 PSI_KS_RELEASE=1 /usr/bin/psiphon-helper cleanup >/dev/null 2>&1
		while IFS='=' read -r _kind _safe _orig; do
			[ -z "$_kind" ] && continue
			case "$_kind" in
				file)
					if [ -f "$PSI_BACKUP_DIR/files/$_safe" ]; then
						mkdir -p "$(dirname "$_orig")" 2>/dev/null
						cp -p "$PSI_BACKUP_DIR/files/$_safe" "$_orig" 2>/dev/null
						echo "    restored: $_orig" >&2
					fi
					;;
				absent)
					if [ -e "$_orig" ]; then
						rm -f "$_orig" 2>/dev/null
						echo "    removed:  $_orig" >&2
					fi
					;;
			esac
		done < "$PSI_BACKUP_DIR/manifest"
		command -v nft >/dev/null 2>&1 && nft delete table inet psiphon_dns 2>/dev/null
		command -v nft >/dev/null 2>&1 && nft delete table inet psiphon_ks 2>/dev/null
		command -v nft >/dev/null 2>&1 && nft delete table inet psiphon_mss 2>/dev/null
		if [ -f "$PSI_BACKUP_DIR/sysupgrade.conf" ]; then
			cp -f "$PSI_BACKUP_DIR/sysupgrade.conf" /etc/sysupgrade.conf 2>/dev/null && \
				echo "    restored: /etc/sysupgrade.conf" >&2
		fi
		for _cfg in firewall dhcp psiphon; do
			if [ -f "$PSI_BACKUP_DIR/uci_$_cfg" ]; then
				cp -f "$PSI_BACKUP_DIR/uci_$_cfg" "/etc/config/$_cfg" 2>/dev/null && \
					echo "    restored: /etc/config/$_cfg" >&2
			fi
		done
		/etc/init.d/firewall reload >/dev/null 2>&1 || true
		/etc/init.d/dnsmasq restart >/dev/null 2>&1 || true
		if [ "${_PSI_WAS_RUNNING:-0}" = 1 ] && [ -x /etc/init.d/psiphon ]; then
			echo "    restarting the previously running service..." >&2
			PSI_FORCE=1 /etc/init.d/psiphon start >/dev/null 2>&1 || true
		fi
	fi
	rm -rf "$PSI_BACKUP_DIR"
}
trap _psi_rollback EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP
for _cfg in firewall dhcp psiphon; do
	[ -f "/etc/config/$_cfg" ] && cp -p "/etc/config/$_cfg" "$PSI_BACKUP_DIR/uci_$_cfg" 2>/dev/null
done
for _f in \
	/etc/config/psiphon \
	/etc/init.d/psiphon \
	/usr/bin/psiphon-helper \
	/etc/hotplug.d/iface/90-psiphon \
	/usr/share/luci/menu.d/luci-app-psiphon.json \
	/usr/share/rpcd/acl.d/luci-app-psiphon.json \
	/www/luci-static/resources/view/vpn/psiphon.js ; do
	_psi_backup "$_f"
done
MISSING_CMD=""
for _c in ip nft uci ubus jsonfilter curl awk nslookup pidof sysctl; do
	command -v $_c >/dev/null 2>&1 || MISSING_CMD="$MISSING_CMD $_c"
done
for _c in nft ip uci jsonfilter; do
	if ! command -v "$_c" >/dev/null 2>&1; then
		echo "ERROR: required command '$_c' is missing - install it first (OpenWrt 25.x: apk add nftables ip-full jsonfilter; older: opkg install nftables ip-full jsonfilter; uci ships with the base system)." >&2
		exit 1
	fi
done
[ -n "$MISSING_CMD" ] && echo "WARNING: missing optional commands:$MISSING_CMD (some features may not work)"

if [ ! -e /dev/net/tun ]; then
	echo "WARNING: /dev/net/tun missing - install kmod-tun (apk add kmod-tun)"
fi
if ! ip rule show >/dev/null 2>&1; then
	echo "WARNING: ip rule broken - install ip-full (apk add ip-full)"
fi
if command -v curl >/dev/null 2>&1 && \
   ! curl -sI -m 5 https://api.github.com/zen 2>/dev/null | grep -q HTTP; then
	echo "WARNING: HTTPS/TLS not working - install ca-bundle (apk add ca-bundle)"
fi
PSI_INSTALL_DEPS="${PSI_INSTALL_DEPS:-1}"
if [ "$PSI_INSTALL_DEPS" = "1" ]; then
	_missing=""
	for _pkg in https-dns-proxy tcpdump ca-bundle; do
		if ! apk info -e "$_pkg" >/dev/null 2>&1 && ! opkg list-installed "$_pkg" >/dev/null 2>&1; then
			_missing="$_missing $_pkg"
		fi
	done
	if [ -n "$_missing" ]; then
		echo "INFO: installing required packages:$_missing" >&2
		if command -v apk >/dev/null 2>&1; then
			apk update >/dev/null 2>&1 || true
			apk add $_missing >/dev/null 2>&1 && \
				echo "  packages installed:$_missing" >&2 || \
				echo "  WARNING: apk add failed for:$_missing (install manually)" >&2
		elif command -v opkg >/dev/null 2>&1; then
			opkg update >/dev/null 2>&1 || true
			opkg install $_missing >/dev/null 2>&1 && \
				echo "  packages installed:$_missing" >&2 || \
				echo "  WARNING: opkg install failed for:$_missing (install manually)" >&2
		fi
	fi
fi
if ! apk info -e ca-bundle >/dev/null 2>&1 && ! opkg list-installed ca-bundle >/dev/null 2>&1; then
	echo "WARNING: ca-bundle is NOT installed - DoH will fail" >&2
	echo "         Fix: apk add ca-bundle" >&2
fi
_free_kb=$(df -k /overlay 2>/dev/null | awk 'NR==2{print $4}')
[ -n "$_free_kb" ] || _free_kb=$(df -k / 2>/dev/null | awk 'NR==2{print $4}')
if [ -n "$_free_kb" ] && [ "$_free_kb" -lt 1024 ] 2>/dev/null; then
	echo "ERROR: less than 1 MB free on flash ($_free_kb KB) - aborting." >&2
	exit 1
fi
if [ -n "$PSI_CORE_SHA256" ] && [ -f /usr/bin/psiphon-core ]; then
	_actual=$(sha256sum /usr/bin/psiphon-core 2>/dev/null | cut -d' ' -f1)
	if [ "$_actual" != "$PSI_CORE_SHA256" ]; then
		echo "ERROR: psiphon-core SHA256 mismatch." >&2
		echo "  expected: $PSI_CORE_SHA256" >&2
		echo "  actual:   $_actual" >&2
		exit 1
	fi
fi
chmod +x /usr/bin/psiphon-core
_PSI_TOUCHED=1
[ -x /etc/init.d/psiphon ] && /etc/init.d/psiphon stop >/dev/null 2>&1 || true
[ -x /usr/bin/psiphon-helper ] && PSI_INTERNAL=1 PSI_KS_RELEASE=1 /usr/bin/psiphon-helper cleanup >/dev/null 2>&1 || true
echo "Installing luci-app-psiphon files..."
mkdir -p "/etc/config"
[ -f "/etc/config/psiphon" ] || cat <<'__PSI_EOF__' > "/etc/config/psiphon"
config psiphon 'config'
	option enabled '0'
	option tun '0'
	option tun_addr '10.255.255.1'
	option tun_mtu 'auto'
	option kill_switch '0'
	option psiphon_dns '1'
	option dns_enabled '0'
	option force_router_dns '0'
	option transport 'STANDARD'
	option dns_preset 'cloudflare'
	option dns1 '1.1.1.1'
	option dns2 '1.0.0.1'
	option beast_mode '0'
	option cdn_fronting '0'
	option cdn_probe '0'
	option conn_mode 'auto'

__PSI_EOF__
mkdir -p "/etc/init.d"
cat <<'__PSI_EOF__' > "/etc/init.d/psiphon"
#!/bin/sh /etc/rc.common

START=99
STOP=10
USE_PROCD=1

PSI_INTERNAL=1
export PSI_INTERNAL

PROG="/usr/bin/psiphon-core"
HELPER="/usr/bin/psiphon-helper"
RUN_DIR="/tmp/psiphon"
LOG_FILE="/tmp/psiphon.log"

_core_flag() { "$PROG" -h 2>&1 | grep -Eq "^[[:space:]]+-$1([[:space:]]|\$)"; }

start_service() {
	local enabled tun tun_addr wan_if
	config_load psiphon
	tun_addr=$(uci -q get psiphon.config.tun_addr)
	echo "$tun_addr" | awk -F. 'NF==4 { for (i=1;i<=4;i++) if ($i !~ /^[0-9]+$/ || $i+0 > 255) exit 1; exit 0 } { exit 1 }' || tun_addr=10.255.255.1
	config_get_bool enabled "config" "enabled" 0
	config_get_bool tun "config" "tun" 0
	wan_if=$(ubus call network.interface.wan status 2>/dev/null | jsonfilter -e '@.l3_device' 2>/dev/null)
	[ -n "$wan_if" ] || wan_if=$(ip -4 route show default 2>/dev/null | awk '$0 !~ /tun0/ { for (i=1;i<=NF;i++) if ($i=="dev") { print $(i+1); exit } }')

	if [ "$enabled" -ne 1 ] && [ "${PSI_FORCE:-0}" != "1" ]; then
		if nft list table inet psiphon_ks >/dev/null 2>&1; then
			"$HELPER" cleanup
		else
			PSI_KS_RELEASE=1 "$HELPER" cleanup
		fi
		return 0
	fi

	[ -x "$PROG" ] || { echo "psiphon: $PROG not found or not executable" >&2; return 1; }

	"$HELPER" cleanup >/dev/null 2>&1
	"$HELPER" prepare || return 1
	echo "$wan_if" > "$RUN_DIR/core_wan" 2>/dev/null

	procd_open_instance "core"
	procd_set_param env PSI_INTERNAL=1
	procd_set_param command "$HELPER" run-core -config "$RUN_DIR/psiphon.config" -notices "$LOG_FILE"
	if [ "$tun" -eq 1 ]; then
		procd_append_param command -tunDevice tun0
		if [ -n "$wan_if" ] && _core_flag tunBindInterface; then
			procd_append_param command -tunBindInterface "$wan_if"
		fi
		if _core_flag tunAddress && _core_flag tunGateway; then
			procd_append_param command -tunAddress "$tun_addr" -tunGateway "$tun_addr"
		fi
	fi
	procd_set_param respawn 3600 5 5
	procd_set_param stdout 1
	procd_set_param stderr 1
	procd_close_instance

	procd_open_instance "watcher"
	procd_set_param command "$HELPER" watch
	procd_set_param env PSI_INTERNAL=1
	procd_set_param respawn 3600 5 0
	procd_close_instance

}

service_stopped() {
	"$HELPER" cleanup
}

stop_service() {
	local _pid _i
	_pid=$(pidof psiphon-core 2>/dev/null | awk '{print $1}')
	[ -n "$_pid" ] && kill -TERM "$_pid" 2>/dev/null
	_i=0
	while [ -n "$_pid" ] && [ "$_i" -lt 5 ] && kill -0 "$_pid" 2>/dev/null; do
		sleep 1; _i=$((_i+1))
	done
	[ -n "$_pid" ] && kill -0 "$_pid" 2>/dev/null && kill -KILL "$_pid" 2>/dev/null
	"$HELPER" persist_gated
	"$HELPER" cleanup
}

reload_service() {
	restart
}

service_triggers() {
	procd_add_reload_trigger "psiphon"
}
__PSI_EOF__

chmod 755 "/etc/init.d/psiphon"
mkdir -p "/usr/bin"
cat <<'__PSI_EOF__' > "/usr/bin/psiphon-helper"
#!/bin/sh

PROG=/usr/bin/psiphon-core
PERSIST=/etc/psiphon
OLD_DB_DIR=$PERSIST/ca.psiphon.PsiphonTunnel.tunnel-core/datastore
RUN=/tmp/psiphon
LOG=/tmp/psiphon.log
CONF=$RUN/psiphon.config
DB_DIR=$RUN/ca.psiphon.PsiphonTunnel.tunnel-core/datastore
DB=$DB_DIR/psiphon.boltdb
DB_BAK=$PERSIST/datastore.bak
_cd=$(uci -q get dhcp.@dnsmasq[0].confdir 2>/dev/null | awk '{print $1}')
case "$_cd" in /tmp/*|/var/*|/run/*) ;; *) _cd=/tmp/dnsmasq.d ;; esac
DNSCONF=$_cd/psiphon_dns.conf
TUN=tun0
RT=100
PREF=1000
PREF_RFC=990
TUN_MTU=1400
TUN_MSS=1360
NFT_TABLE=psiphon_dns
BUILTIN_DNS_HEX=9C75
DNS_ROUTES=$RUN/dns_routes
DOH_PORT_CANDIDATES="5454 8454 10054 15054 20054 25054"
DOH_PORT=5454
DOH_PORT_FILE=$RUN/doh.port
DOH_PID=$RUN/doh.pid
DOH_URL=https://1.1.1.1/dns-query
DOH_IPS="1.1.1.1 1.0.0.1"
PROBE_DOMAIN=example.com

say() { echo "[psiphon] $*" >> "$LOG"; }
U()   { uci -q get "psiphon.config.$1" 2>/dev/null; }
TUN_ADDR=$(U tun_addr)
echo "$TUN_ADDR" | awk -F. 'NF==4 { for (i=1;i<=4;i++) if ($i !~ /^[0-9]+$/ || $i+0 > 255) exit 1; exit 0 } { exit 1 }' || TUN_ADDR=10.255.255.1
TUN_MTU_FORCE=0
_m=$(U tun_mtu)
case "$_m" in
	''|auto) ;;
	*[!0-9]*) ;;
	*) if [ "$_m" -ge 1280 ] && [ "$_m" -le 1500 ]; then TUN_MTU=$_m; TUN_MTU_FORCE=1; fi ;;
esac
TUN_MSS=$((TUN_MTU - 40))

B() {
	local v
	v=$(U "$1"); [ -z "$v" ] && v="$2"
	case "$v" in 1|on|true|yes|enabled) return 0 ;; esac
	return 1
}

T() {
	local s="$1"; shift
	if command -v timeout >/dev/null 2>&1; then timeout "$s" "$@"; else "$@"; fi
}

is_ipv4() {
	echo "$1" | awk -F. 'NF==4 { for (i=1;i<=4;i++) if ($i !~ /^[0-9]+$/ || $i+0 > 255) exit 1; exit 0 } { exit 1 }'
}
is_host() {
	local h="$1"
	[ -n "$h" ] && [ ${#h} -le 253 ] || return 1
	echo "$h" | grep -Eq '^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}$'
}

json_escape() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }

lan_dev() {
	local d
	d=$(ubus call network.interface.lan status 2>/dev/null | jsonfilter -e '@.l3_device' 2>/dev/null)
	echo "${d:-br-lan}"
}
lan_ip() {
	local a
	a=$(ubus call network.interface.lan status 2>/dev/null | jsonfilter -e '@["ipv4-address"][0].address' 2>/dev/null)
	[ -z "$a" ] && a=$(uci -q get network.lan.ipaddr | cut -d/ -f1)
	echo "$a"
}
lan_subnet() {
	ip -4 -o addr show dev "$(lan_dev)" 2>/dev/null | awk '{print $4; exit}' | \
	awk -F'[./]' 'NF==5 { p=$5; o=""
		for (i=1;i<=4;i++) { b=p-(i-1)*8
			if (b>=8) n=$i; else if (b<=0) n=0; else { s=2^(8-b); n=int($i/s)*s }
			o=o (i>1?".":"") n }
		print o "/" p }'
}
wan_dev() {
	local d
	d=$(ubus call network.interface.wan status 2>/dev/null | jsonfilter -e '@.l3_device' 2>/dev/null)
	[ -z "$d" ] && d=$(ip -4 route show default 2>/dev/null | awk -v t="$TUN" '$0 !~ t { for (i=1;i<=NF;i++) if ($i=="dev") { print $(i+1); exit } }')
	echo "$d"
}

_log_since_restart() { [ -s "$LOG" ] || return 0; local n; n=$(grep -an '^\[psiphon\] core restarted' "$LOG" 2>/dev/null | tail -n1 | cut -d: -f1); if [ -n "$n" ]; then tail -n +"$n" "$LOG"; else cat "$LOG"; fi; }
core_pid()  { pidof psiphon-core 2>/dev/null | awk '{print $1}'; }
sock_port() { _log_since_restart | grep '"ListeningSocksProxyPort"' 2>/dev/null | tail -n1 | grep -oE '"port":[0-9]+' | grep -oE '[0-9]+'; }
tun_count() { _log_since_restart | grep '"noticeType":"Tunnels"' 2>/dev/null | tail -n1 | grep -oE '"count":[0-9]+' | grep -oE '[0-9]+'; }

latest_protocol() {
	local p nt
	[ -s "$LOG" ] || return 0
	for nt in ConnectedServer ConnectingServer; do
		p=$(_log_since_restart | grep -a "\"noticeType\":\"$nt\"" 2>/dev/null \
			| tail -n1 | sed -n 's/.*"protocol":"\([^"]*\)".*/\1/p')
		[ -n "$p" ] && { echo "$p"; return 0; }
	done
}

bt_sum() {
	local r s
	r=$(grep 'BytesTransferred' "$LOG" 2>/dev/null | sed -n 's/.*"received":\([0-9]*\).*/\1/p' | awk '{s+=$1} END{printf "%.0f", s}')
	s=$(grep 'BytesTransferred' "$LOG" 2>/dev/null | sed -n 's/.*"sent":\([0-9]*\).*/\1/p' | awk '{s+=$1} END{printf "%.0f", s}')
	echo "${r:-0} ${s:-0}"
}

cmd_status() {
	local pid port cnt brx=0 btx=0 r s proto=""
	pid=$(core_pid)
	if [ -n "$pid" ]; then
		port=$(sock_port)
		cnt=$(tun_count)
		proto=$(latest_protocol)
	fi
	[ -f "$RUN/bt_base" ] && read -r brx btx < "$RUN/bt_base"
	set -- $(bt_sum); r=$1; s=$2
	printf '{"running":%s,"port":%s,"tunnels":%s,"rx":%s,"tx":%s,"protocol":"%s"}\n' \
		"$([ -n "$pid" ] && echo 1 || echo 0)" "${port:-0}" "${cnt:-0}" \
		"$(echo "${brx:-0} $r" | awk '{printf "%.0f", $1+$2}')" \
		"$(echo "${btx:-0} $s" | awk '{printf "%.0f", $1+$2}')" "$proto"
}

geo_fetch() {
	local u out
	for u in "https://ipwho.is/$GEO_IP" "https://ipapi.co/${GEO_IP:+$GEO_IP/}json/" "https://ifconfig.co/json${GEO_IP:+?ip=$GEO_IP}"; do
		out=$(curl -sL -4 -m 5 --connect-timeout 4 "$@" "$u" 2>/dev/null)
		case "$out" in
			*'"success":false'*|*'"status":"fail"'*|*'"error"'*) continue ;;
			*'"ip"'*|*'"query"'*) echo "$out"; return 0 ;;
		esac
	done
	return 1
}

cmd_realip() {
	local w wip
	w=$(wan_dev)
	[ -z "$w" ] && return 1
	wip=$(ip -4 addr show dev "$w" 2>/dev/null | sed -n 's/.*inet \([0-9.]*\).*/\1/p' | head -n1)
	
	geo_fetch --interface "$w" && return 0
	[ -n "$wip" ] && echo "{\"ip\":\"$wip\",\"country\":\"Unknown\"}"
}

cmd_vpnip() {
	local p
	p=$(sock_port)
	[ -n "$p" ] || return 1
	geo_fetch --socks5-hostname "127.0.0.1:$p"
}

cmd_dnsleak() {
	local p r ups geo=""
	p=$(sock_port)
	r=$(T 8 nslookup whoami.akamai.net 127.0.0.1 2>/dev/null | awk '/^Name:/{f=1;next} f' \
		| grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n1)
	ups=$(grep -h '^server=[^/]' "$DNSCONF" 2>/dev/null | cut -d= -f2 | tr '\n' ' ')
	if [ -n "$r" ]; then
		if [ -n "$p" ]; then geo=$(GEO_IP="$r" geo_fetch --socks5-hostname "127.0.0.1:$p")
		else geo=$(GEO_IP="$r" geo_fetch); fi
	fi
	local dmode=none pinned=false flags="" _fu _port _f
	_port=$(doh_port)
	case "$ups" in
		*"127.0.0.1#$_port"*) doh_engine_ready && dmode=doh ;;
		*[0-9]*) dmode=udp ;;
	esac
	if [ "$dmode" = doh ]; then
		ip route get 1.1.1.1 2>/dev/null | grep -q "dev $TUN" && pinned=true
	elif [ "$dmode" = udp ]; then
		_f=$(echo "$ups" | awk '{print $1}')
		[ -n "$_f" ] && ip route get "$_f" 2>/dev/null | grep -q "dev $TUN" && pinned=true
	fi
	case "$(conn_mode)" in
		traffic_dns_https) [ "$dmode" = doh ] || flags="$flags doh_inactive" ;;
	esac
	_fu=$(dns_foreign_upstreams)
	[ -n "$_fu" ] && flags="$flags foreign_upstream"
	printf '{"resolver":"%s","upstreams":"%s","mode":"%s","pinned":%s,"flags":"%s","foreign":"%s","geo":%s}\n' "$r" "${ups% }" "$dmode" "$pinned" "${flags# }" "$_fu" "${geo:-null}"
}

cmd_diag() {
	local p sx=""
	p=$(sock_port); [ -n "$p" ] && sx="--socks5-hostname 127.0.0.1:$p"
	case "$1" in
		icmp) ping -c 1 -W 3 8.8.4.4 2>/dev/null | sed -n 's/.*time[=<]\([0-9.]*\).*/\1/p' | head -n1 ;;
		tcp)  curl -sL -4 -m 10 $sx -o /dev/null -w '%{time_appconnect}' 'https://cloudflare-dns.com/dns-query' 2>/dev/null | awk '{printf "%d", $1*1000}' ;;
		url)  _o=$(curl -sL -4 -m 10 $sx -o /dev/null -w '%{http_code} %{time_total}' 'https://api.github.com/zen' 2>/dev/null)
		      set -- $_o
		      [ "${1:-000}" != "000" ] && echo "${2:-0}" | awk '{printf "%d", $1*1000}' ;;
	esac
}

CDN_PROVIDERS_CORE="cloudflare fastly akamai cloudfront google github vercel imperva edgecast azure cdn77 sucuri"
CDN_PROVIDERS="$CDN_PROVIDERS_CORE gcore cdnvideo alibaba tencent bunny keycdn cachefly leaseweb baidu"

cdn_ranges() {
	case "$1" in
	cloudflare) echo "104.16.0.0/13 104.24.0.0/14 172.64.0.0/13 162.158.0.0/15 141.101.64.0/18 108.162.192.0/18 188.114.96.0/20 190.93.240.0/20 198.41.128.0/17 173.245.48.0/20 103.21.244.0/22 103.22.200.0/22 103.31.4.0/22 197.234.240.0/22 131.0.72.0/22" ;;
	fastly)     echo "151.101.0.0/16 199.232.0.0/16 146.75.0.0/16 140.248.0.0/16 167.82.0.0/17 167.82.128.0/20 167.82.160.0/20 167.82.224.0/20 157.52.64.0/18 172.111.64.0/18 185.31.16.0/22 199.27.72.0/21 104.156.80.0/20 23.235.32.0/20 43.249.72.0/22 103.244.50.0/24 103.245.222.0/23" ;;
	akamai)     echo "23.0.0.0/12 23.32.0.0/11 23.64.0.0/14 23.72.0.0/13 23.192.0.0/11 2.16.0.0/13 2.20.0.0/14 72.246.0.0/15 92.122.0.0/15 95.100.0.0/15 96.6.0.0/15 96.16.0.0/15 104.64.0.0/10 173.222.0.0/15 184.24.0.0/13 184.50.0.0/15 184.84.0.0/14 88.221.0.0/16" ;;
	cloudfront) echo "13.32.0.0/15 13.35.0.0/16 13.224.0.0/14 18.64.0.0/14 18.154.0.0/15 18.160.0.0/15 3.160.0.0/14 52.84.0.0/15 52.222.128.0/17 54.182.0.0/16 54.192.0.0/16 54.230.0.0/16 54.239.192.0/19 64.252.64.0/18 70.132.0.0/18 99.84.0.0/16 99.86.0.0/16 108.138.0.0/15 108.156.0.0/14 130.176.0.0/16 143.204.0.0/16 144.220.0.0/16 204.246.160.0/19 205.251.192.0/19" ;;
	google)     echo "142.250.0.0/15 172.217.0.0/16 216.58.192.0/19 64.233.160.0/19 74.125.0.0/16 108.177.0.0/17 173.194.0.0/16 209.85.128.0/17 216.239.32.0/19" ;;
	github)     echo "185.199.108.0/22 140.82.112.0/20 192.30.252.0/22" ;;
	vercel)     echo "76.76.21.0/24 76.76.19.0/24 66.33.60.0/24" ;;
	imperva)    echo "45.223.0.0/16 199.83.128.0/21 192.230.64.0/18 107.154.0.0/16 149.126.72.0/21" ;;
	edgecast)   echo "192.229.128.0/17 152.195.0.0/16 93.184.216.0/22 72.21.80.0/20 117.18.232.0/21" ;;
	azure)      echo "13.107.213.0/24 13.107.246.0/24 13.107.6.0/24 13.107.18.0/24 13.107.136.0/24 13.107.42.0/24" ;;
	cdn77)      echo "89.187.160.0/19 185.152.64.0/22 138.199.0.0/17" ;;
	sucuri)     echo "192.124.249.0/24 185.93.228.0/22 66.248.200.0/22" ;;
	gcore)      echo "92.223.64.0/18 92.38.128.0/17 185.156.176.0/22 185.178.208.0/22 185.187.240.0/22 185.228.168.0/22 188.116.12.0/22 195.201.200.0/22" ;;
	cdnvideo)   echo "89.111.160.0/19 91.226.136.0/22 94.198.52.0/22 185.45.192.0/22 185.129.100.0/22 194.85.80.0/21" ;;
	alibaba)    echo "47.74.0.0/15 47.88.0.0/14 47.246.0.0/16 106.11.0.0/16 140.205.0.0/16 163.181.0.0/16" ;;
	tencent)    echo "43.128.0.0/14 43.132.0.0/14 129.226.0.0/16 150.109.0.0/16 162.14.0.0/16 203.205.128.0/17" ;;
	bunny)      echo "38.92.173.0/24 91.200.176.0/24 103.180.114.0/24 103.180.115.0/24 107.150.176.0/24 109.104.146.0/24 109.224.228.0/23 185.190.83.0/24 194.156.156.0/24 212.104.158.0/24" ;;
	keycdn)     echo "68.70.192.0/24 68.70.193.0/24 68.70.194.0/24 68.70.205.0/24" ;;
	cachefly)   echo "45.88.132.0/22 204.93.142.0/24 204.93.143.0/24 205.234.175.0/24" ;;
	leaseweb)   echo "178.162.216.0/22 178.162.220.0/22 46.166.184.0/22 37.58.64.0/19" ;;
	baidu)      echo "180.76.0.0/16 106.12.0.0/15 182.61.0.0/16 220.181.0.0/16" ;;
	*) return 1 ;;
	esac
}

cdn_sample() {
	local n="$1"; shift
	echo "$@" | tr ' ,;' '\n\n\n' | \
		awk -v n="$n" -v seed="$(date +%s%N 2>/dev/null || date +%s)$$" '
		BEGIN { srand(seed); cnt = 0 }
		{
			if (index($1, "/") == 0) next
			split($1, p, "/")
			m = p[2] + 0
			if (m < 8 || m > 30) next
			split(p[1], o, ".")
			if (length(o) != 4) next
			_bad = 0
			for (k = 1; k <= 4; k++) {
				if (o[k] !~ /^[0-9]+$/) { _bad = 1; break }
				if (o[k] + 0 > 255) { _bad = 1; break }
			}
			if (_bad) next
			cnt++; r[cnt] = $1
		}
		END {
			if (cnt == 0) exit
			for (i = 0; i < n; i++) {
				split(r[int(rand()*cnt)+1], a, "/"); split(a[1], o, ".")
				m = a[2] + 0; if (m < 8 || m > 30) continue
				base = ((o[1]*256 + o[2])*256 + o[3])*256 + o[4]
				size = 2^(32-m); x = base - (base % size) + int(rand()*size)
				l = x % 256; if (l == 0 || l == 255) { i--; continue }
				printf "%d.%d.%d.%d\n", int(x/16777216), int(x/65536)%256, int(x/256)%256, l
			}
		}' | sort -u
}

cmd_scan() {
	local sni="$1" sel="$2" cidrs="$3" pool tmp ip pids=0 p
	[ -z "$sni" ] && { echo "no-sni"; return 1; }
	is_host "$sni" || { echo "invalid-sni"; return 1; }
	command -v curl >/dev/null 2>&1 || { echo "no-curl"; return 1; }

	case "$sel" in
		custom) pool=$(cdn_sample 40 $cidrs) ;;
		all|"") pool=$(for p in $CDN_PROVIDERS_CORE; do cdn_sample 6 $(cdn_ranges $p); done) ;;
		*)      cdn_ranges "$sel" >/dev/null 2>&1 || { echo "unknown-provider"; return 1; }
			pool=$(cdn_sample 36 $(cdn_ranges "$sel")) ;;
	esac

	mkdir -p "$RUN"
	tmp="$RUN/scan.$$"; : > "$tmp"
	for ip in $pool; do
		is_ipv4 "$ip" || continue
		( out=$(curl -s -4 -o /dev/null -m 3 --connect-timeout 3 \
			-w '%{time_appconnect} %{http_code}' \
			--resolve "$sni:443:$ip" "https://$sni/" 2>/dev/null)
		  set -- $out
		  case "${2:-0}" in
			2??|3??|4??) echo "$ip $(echo "${1:-0}" | awk '{v=int($1*1000); if (v<1) v=1; print v}')" >> "$tmp" ;;
		  esac ) &
		pids=$((pids+1))
		[ "$pids" -ge 8 ] && { wait; pids=0; }
	done
	wait
	sort -n -k2 "$tmp" 2>/dev/null | awk 'NF==2 && $2>0'
	rm -f "$tmp"
}

scan_pool() {
	local n p per
	case "$2" in quick) n=30 ;; deep) n=120 ;; *) n=60 ;; esac
	case "$1" in
		custom) cdn_sample "$n" $3 ;;
		all|"") per=$((n / $(echo $CDN_PROVIDERS_CORE | wc -w))); [ "$per" -lt 3 ] && per=3; for p in $CDN_PROVIDERS_CORE; do cdn_sample "$per" $(cdn_ranges "$p"); done ;;
		*)      cdn_ranges "$1" >/dev/null 2>&1 || return 1; cdn_sample "$n" $(cdn_ranges "$1") ;;
	esac
}
cmd_scan_inner() {
	local sni="$1" prov="$2" depth="$3" cidrs="$4" ip pids=0
	local out="$RUN/scan_result.tmp"
	mkdir -p "$RUN"; : > "$out"; : > "$RUN/scan_progress"
	scan_pool "$prov" "$depth" "$cidrs" > "$RUN/scan_pool"
	wc -l < "$RUN/scan_pool" > "$RUN/scan_total"
	for ip in $(cat "$RUN/scan_pool"); do
		( r=$(curl -s -4 -o /dev/null -m 3 --connect-timeout 3 \
			-w '%{time_appconnect} %{http_code}' \
			--resolve "$sni:443:$ip" "https://$sni/" 2>/dev/null)
		  set -- $r
		  case "${2:-0}" in
			2??|3??|4??) echo "$ip $(echo "${1:-0}" | awk '{v=int($1*1000); if (v<1) v=1; print v}')" >> "$out" ;;
		  esac
		  echo . >> "$RUN/scan_progress" ) &
		pids=$((pids+1))
		[ "$pids" -ge 6 ] && { wait; pids=0; }
	done
	wait
	sort -n -k2 "$out" > "$RUN/scan_result"; rm -f "$out"
	touch "$RUN/scan_done"
	rm -f "$RUN/scan_running" "$RUN/scan_pid"
	rm -rf "$RUN/scan.lock"
}

cmd_scan_run() {
	if command -v timeout >/dev/null 2>&1; then
		exec timeout 600 "$0" _scan_inner "$@"
	fi
	cmd_scan_inner "$@"
}
cmd_scan_start() {
	local sni="$1"
	[ -n "$sni" ] && is_host "$sni" || { echo "invalid-sni"; return 1; }
	command -v curl >/dev/null 2>&1 || { echo "no-curl"; return 1; }
	mkdir -p "$RUN"
	if ! mkdir "$RUN/scan.lock" 2>/dev/null; then
		local _sp
		_sp=$(cat "$RUN/scan.lock/pid" 2>/dev/null)
		[ -z "$_sp" ] && _sp=$(cat "$RUN/scan_pid" 2>/dev/null)
		if [ -n "$_sp" ] && [ -r "/proc/$_sp/cmdline" ] && \
		   grep -qa 'scan\|psiphon' "/proc/$_sp/cmdline" 2>/dev/null; then
			echo "scan-already-running"
			return 1
		fi
		rm -rf "$RUN/scan.lock"
		mkdir "$RUN/scan.lock" 2>/dev/null || { echo "scan-lock-failed"; return 1; }
	fi
	if [ -f "$RUN/scan_pid" ]; then
		local _lsp
		_lsp=$(cat "$RUN/scan_pid" 2>/dev/null)
		if [ -z "$_lsp" ] || [ ! -r "/proc/$_lsp/cmdline" ] || \
		   ! grep -qa 'scan\|psiphon' "/proc/$_lsp/cmdline" 2>/dev/null; then
			rm -f "$RUN/scan_pid" "$RUN/scan_running"
		fi
	fi
	touch "$RUN/scan_running"
	rm -f "$RUN/scan_done" "$RUN/scan_result"
	: > "$RUN/scan_progress"; : > "$RUN/scan_result.tmp"; echo 0 > "$RUN/scan_total"
	( cmd_scan_run "$1" "$2" "${3:-normal}" "$4" ) >/dev/null 2>&1 </dev/null &
	echo $! | tee "$RUN/scan_pid" "$RUN/scan.lock/pid" >/dev/null
	echo started
}
cmd_scan_result() {
	local st=running f="$RUN/scan_result.tmp"
	[ -f "$RUN/scan_done" ] && { st=done; f="$RUN/scan_result"; }
	echo "$st $(wc -l < "$RUN/scan_progress" 2>/dev/null || echo 0) $(cat "$RUN/scan_total" 2>/dev/null || echo 0)"
	sort -n -k2 "$f" 2>/dev/null | head -n 40
}

cmd_probe() {
	local sni="$1" tmp ip n=0 out ms code
	shift
	is_host "$sni" || { echo "invalid-sni 0"; return 1; }
	command -v curl >/dev/null 2>&1 || { echo "no-curl 0"; return 1; }
	mkdir -p "$RUN"; tmp="$RUN/probe.$$"; : > "$tmp"
	for ip in $(echo "$*" | tr ',;' '  '); do
		is_ipv4 "$ip" || { echo "$ip 0" >> "$tmp"; continue; }
		n=$((n+1)); [ "$n" -gt 60 ] && break
		( out=$(curl -s -4 -o /dev/null -m 5 -w '%{time_appconnect} %{http_code}' --resolve "$sni:443:$ip" "https://$sni/" 2>/dev/null)
		  set -- $out
		  ms=${1:-0}; code=${2:-0}
		  case "$code" in
			2??|3??|4??) echo "$ip $(echo "$ms" | awk '{v=int($1*1000); if (v<1) v=1; print v}')" >> "$tmp" ;;
			*)            echo "$ip 0"          >> "$tmp" ;;
		  esac ) &
	done
	wait
	cat "$tmp"; rm -f "$tmp"
}

cdn_filter_ips() {
	local sni="$1" out
	shift
	out=$(cmd_probe "$sni" "$@")
	echo "$out" | awk '$2+0 > 0 {print $1}' | tr '\n' ',' | sed 's/,$//'
}

core_has() {
	grep -qa "$1" "$PROG" 2>/dev/null
}
warn_key() { core_has "$1" || say "note: '$1' not found in psiphon-core strings (unsupported or packed binary) - setting may be ignored"; }

gen_config() {
	local EXTRA="" country transport protos="" cdn=0 sni ips good dl v pcid sid

	country=$(U country | tr 'a-z' 'A-Z')
	echo "$country" | grep -Eq '^[A-Z]{2}$' && EXTRA="$EXTRA,\"EgressRegion\":\"$country\""

	transport=$(U transport | tr 'a-z' 'A-Z')
	[ -z "$transport" ] && transport=STANDARD
	case "$transport" in
		QUIC) protos='"QUIC-OSSH"' ;;
		SSH)  protos='"SSH","OSSH"' ;;
		TLS)  protos='"FRONTED-MEEK-OSSH","TLS-OSSH"' ;;
		STANDARD) ;;
		*)    transport=STANDARD ;;
	esac
	EXTRA="$EXTRA,\"Transport\":\"$transport\""

	if B cdn_fronting 0; then
		cdn=1
		protos='"FRONTED-MEEK-OSSH","FRONTED-MEEK-HTTP-OSSH"'
		sni=$(U cdn_sni | tr -d ' ')
		ips=$(U cdn_edge_ips | tr ',;' '  ')
		if [ -n "$sni" ] && ! is_host "$sni"; then say "CDN: invalid SNI '$sni' ignored"; sni=""; fi
		good=""
		for v in $ips; do
			if is_ipv4 "$v"; then good="$good $v"; else say "CDN: invalid IP '$v' ignored"; fi
		done
		ips=$(echo $good)
		if [ -n "$sni" ] && [ -n "$ips" ]; then
			if ! core_has CdnFrontingCustomIpList || ! core_has CdnFrontingCustomSni; then
				say "CDN: psiphon-core does not advertise custom fronting options - pinning disabled"
				sni=""; ips=""
			fi
		fi
		if [ -n "$sni" ] && [ -n "$ips" ]; then
			if B cdn_probe 1 && command -v curl >/dev/null 2>&1; then
				good=$(cdn_filter_ips "$sni" $ips)
				if [ -n "$good" ]; then
					say "CDN: reachable edge IPs: $good (of: $(echo $ips | tr ' ' ','))"
					ips=$(echo "$good" | tr ',' ' ')
				else
					say "CDN: no edge IP completed a TLS handshake with SNI '$sni' - keeping the full list"
				fi
			fi
			warn_key CdnFrontingCustomIpList; warn_key CdnFrontingCustomSni
			EXTRA="$EXTRA,\"CdnFrontingCustomIpList\":\"$(echo $ips | tr ' ' ',')\",\"CdnFrontingCustomSni\":\"$(json_escape "$sni")\""
		elif [ -n "$sni" ] || [ -n "$ips" ]; then
			say "CDN: SNI and edge IPs must both be set - using Psiphon's built-in fronting providers"
		fi
	fi
	[ -n "$protos" ] && EXTRA="$EXTRA,\"LimitTunnelProtocols\":[$protos]"

	if B dns_enabled 0; then
		dl=""
		for v in $(U dns1) $(U dns2); do is_ipv4 "$v" && dl="${dl:+$dl,}$v"; done
		if [ -n "$dl" ] && core_has UpstreamDNSServer; then EXTRA="$EXTRA,\"UpstreamDNSServer\":\"$dl\""; fi
	fi

	if B beast_mode 0; then warn_key BeastMode; EXTRA="$EXTRA,\"BeastMode\":true"; else EXTRA="$EXTRA,\"BeastMode\":false"; fi

	pcid=$(U propagation_channel_id); echo "$pcid" | grep -Eq '^[0-9A-Fa-f]{16}$' || pcid=92AACC5BABE0944C
	sid=$(U sponsor_id); echo "$sid" | grep -Eq '^[0-9A-Fa-f]{16}$' || sid=1BC527D3D09985CF
	# --- Remote server list (online download) ---
	local RSL_URLS='[{"OnlyAfterAttempts":0,"SkipVerify":false,"URL":"aHR0cHM6Ly9zMy5hbWF6b25hd3MuY29tL3BzaXBob24vd2ViL21qcjQtcDIzci1wdXdsL3NlcnZlcl9saXN0X2NvbXByZXNzZWQ="},{"OnlyAfterAttempts":2,"SkipVerify":true,"URL":"aHR0cHM6Ly93d3cucmFjZWVnZ3V4ZGFzLmNvbS93ZWIvbWpyNC1wMjNyLXB1d2wvc2VydmVyX2xpc3RfY29tcHJlc3NlZA=="},{"OnlyAfterAttempts":2,"SkipVerify":true,"URL":"aHR0cHM6Ly93d3cuc3lzdGVtc2FmYXJpdW5pdmVyc2l0eWRlYnQuY29tL3dlYi9tanI0LXAyM3ItcHV3bC9zZXJ2ZXJfbGlzdF9jb21wcmVzc2Vk"},{"OnlyAfterAttempts":2,"SkipVerify":true,"URL":"aHR0cHM6Ly93d3cuYmxvZ3NmbWNhbmNlcmNpdGl6ZW4uY29tL3dlYi9tanI0LXAyM3ItcHV3bC9zZXJ2ZXJfbGlzdF9jb21wcmVzc2Vk"}]'
	local RSL_KEY='MIICIDANBgkqhkiG9w0BAQEFAAOCAg0AMIICCAKCAgEAt7Ls+/39r+T6zNW7GiVpJfzq/xvL9SBH5rIFnk0RXYEYavax3WS6HOD35eTAqn8AniOwiH+DOkvgSKF2caqk/y1dfq47Pdymtwzp9ikpB1C5OfAysXzBiwVJlCdajBKvBZDerV1cMvRzCKvKwRmvDmHgphQQ7WfXIGbRbmmk6opMBh3roE42KcotLFtqp0RRwLtcBRNtCdsrVsjiI1Lqz/lH+T61sGjSjQ3CHMuZYSQJZo/KrvzgQXpkaCTdbObxHqb6/+i1qaVOfEsvjoiyzTxJADvSytVtcTjijhPEV6XskJVHE1Zgl+7rATr/pDQkw6DPCNBS1+Y6fy7GstZALQXwEDN/qhQI9kWkHijT8ns+i1vGg00Mk/6J75arLhqcodWsdeG/M/moWgqQAnlZAGVtJI1OgeF5fsPpXu4kctOfuZlGjVZXQNW34aOzm8r8S0eVZitPlbhcPiR4gT/aSMz/wd8lZlzZYsje/Jr8u/YtlwjjreZrGRmG8KMOzukV3lLmMppXFMvl4bxv6YFEmIuTsOhbLTwFgh7KYNjodLj/LsqRVfwz31PgWQFTEPICV7GCvgVlPRxnofqKSjgTWI4mxDhBpVcATvaoBl1L/6WLbFvBsoAUBItWwctO2xalKxF5szhGm8lccoc5MZr8kfE0uxMgsxz4er68iCID+rsCAQM='
	if [ -n "$RSL_URLS" ] && [ -n "$RSL_KEY" ]; then
		EXTRA="$EXTRA,\"RemoteServerListDownloadFilename\":\"$RUN/server_list.dat\",\"RemoteServerListURLs\":$RSL_URLS,\"RemoteServerListSignaturePublicKey\":\"$RSL_KEY\""
	fi
	# --- end ---
	cat > "$CONF" <<JSON
{
  "DataRootDirectory": "$RUN",
  "DisableIPv6": true,
  "PropagationChannelId": "$pcid",
  "SponsorId": "$sid",
  "ServerEntrySignaturePublicKey": "sHuUVTWaRyh5pZwy4UguSgkwmBe0EHtJJkoF5WrxmvA=",
  "UseIndistinguishableTLS": true,
  "ProtocolMode": "auto",
  "EmitDiagnosticNotices": true,
  "EmitBytesTransferred": true$EXTRA
}
JSON
	if command -v jsonfilter >/dev/null 2>&1; then
		jsonfilter -i "$CONF" -e '@.DataRootDirectory' >/dev/null 2>&1 || {
			say "gen_config: generated JSON is INVALID - refusing to start"
			return 1
		}
	fi
}

restore_db() {
	local f
	[ -s "$DB" ] && return 0
	for f in "$DB_BAK" "$OLD_DB_DIR/psiphon.boltdb.backup" "$OLD_DB_DIR/psiphon.boltdb"; do
		if [ -s "$f" ] && [ "$(wc -c < "$f")" -ge 5000 ]; then
			cp -f "$f" "$DB" && say "datastore restored from $f"
			return 0
		fi
	done
}
persist_db() {
	[ -s "$DB" ] || return 0
	[ "$(wc -c < "$DB")" -ge 5000 ] || return 0
	if ! cmp -s "$DB" "$DB_BAK" 2>/dev/null; then
		mkdir -p "$PERSIST"
		_need=$(( $(wc -c < "$DB") / 1024 * 2 + 256 ))
		_have=$(df -k "$PERSIST" 2>/dev/null | awk 'NR==2{print $4}')
		if [ -n "$_have" ] && [ "$_have" -lt "$_need" ] 2>/dev/null; then
			say "persist_db: not enough free flash ($_have KB < $_need KB) - skipped"
			return 0
		fi
		cp -f "$DB" "$DB_BAK.tmp" && mv -f "$DB_BAK.tmp" "$DB_BAK" || rm -f "$DB_BAK.tmp"
	fi
}

# Gated backup: write /etc/psiphon/datastore.bak only if it is missing or older than
# PERSIST_MIN_GAP seconds (default 4 days = 345600). Used on tunnel (re)connect and on stop.
# A manual "psiphon-helper persist" is NOT gated (always forces a backup).
persist_db_gated() {
	local _now _bm
	if [ -s "$DB_BAK" ]; then
		_now=$(date +%s)
		_bm=$(stat -c %Y "$DB_BAK" 2>/dev/null || date -r "$DB_BAK" +%s 2>/dev/null || echo 0)
		[ $((_now - ${_bm:-0})) -lt "${PERSIST_MIN_GAP:-345600}" ] && return 0
	fi
	persist_db
}

_PSI_OWNED_RULES=$RUN/ip_rules_owned
_PSI_OWNED_ROUTES=$RUN/ip_routes_owned
_PSI_OWNED_RULES6=$RUN/ip6_rules_owned

_add_rule() {
	mkdir -p "$RUN"
	if ip rule add "$@" 2>/dev/null; then
		echo "$*" >> "$_PSI_OWNED_RULES"
		return 0
	fi
	return 1
}

_add_route() {
	mkdir -p "$RUN"
	if ip route add "$@" 2>/dev/null; then
		echo "$*" >> "$_PSI_OWNED_ROUTES"
		return 0
	fi
	return 1
}

_reap_owned_rules() {
	[ -f "$_PSI_OWNED_RULES" ] || return 0
	local _spec
	while IFS= read -r _spec; do
		[ -n "$_spec" ] && ip rule del $_spec 2>/dev/null
	done < "$_PSI_OWNED_RULES"
	rm -f "$_PSI_OWNED_RULES"
}

_reap_owned_rules6() {
	[ -f "$_PSI_OWNED_RULES6" ] || return 0
	local _spec
	while IFS= read -r _spec; do
		[ -n "$_spec" ] && ip -6 rule del $_spec 2>/dev/null
	done < "$_PSI_OWNED_RULES6"
	rm -f "$_PSI_OWNED_RULES6"
}

_reap_owned_routes() {
	[ -f "$_PSI_OWNED_ROUTES" ] || return 0
	local _spec
	while IFS= read -r _spec; do
		[ -n "$_spec" ] && ip route del $_spec 2>/dev/null
	done < "$_PSI_OWNED_ROUTES"
	rm -f "$_PSI_OWNED_ROUTES"
}

setup_policy() {
	local lan wan cur _net _lsn
	lan=$(lan_dev); wan=$(wan_dev)

	_reap_owned_rules
	for _net in 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 169.254.0.0/16 100.64.0.0/10 224.0.0.0/4; do
		_add_rule to $_net lookup main pref $PREF_RFC
	done
	_lsn=$(lan_subnet)
	if [ -n "$_lsn" ]; then
		_add_rule to "$_lsn" lookup main pref $PREF_RFC
		say "policy: LAN return route $_lsn via main"
	fi
	_add_rule iif "$lan" lookup $RT pref $PREF

	if B kill_switch 0; then
		_add_route blackhole default metric 4000 table $RT
	fi

	if true; then
		_reap_owned_rules6
		if ip -6 rule add iif "$lan" prohibit pref $PREF 2>/dev/null; then
			echo "iif $lan prohibit pref $PREF" >> "$_PSI_OWNED_RULES6"
		fi

		if B kill_switch 0 && [ -n "$wan" ]; then
			cur=$(cat /proc/sys/net/ipv6/conf/$wan/disable_ipv6 2>/dev/null)
			if [ "$cur" = "0" ]; then
				mkdir -p "$RUN" "$RUN/initial"
				echo "$wan" > "$RUN/ipv6_owned_wan"
				echo "$wan" > "$RUN/ipv6_disabled_wan"
				ip -6 addr show dev "$wan" scope global > "$RUN/initial/ipv6_addr.txt" 2>/dev/null
				echo 1 > /proc/sys/net/ipv6/conf/$wan/disable_ipv6 2>/dev/null
				ip -6 addr flush dev "$wan" scope global 2>/dev/null
				say "IPv6 disabled on WAN ($wan) to prevent leaks"
			fi
		fi
	fi
}
ensure_route() {
	local _lsn _lan
	[ -f "$RUN/stopping" ] && return 0
	ip rule show 2>/dev/null | grep -qw "lookup $RT" || setup_policy
	ks_apply
	apply_mss_clamp

	_lan=$(lan_dev); _lsn=$(lan_subnet)
	if [ -n "$_lsn" ] && ! ip -4 route show table main 2>/dev/null | grep -q "^$_lsn .*dev $_lan"; then
		ip route add "$_lsn" dev "$_lan" scope link 2>/dev/null && \
			say "main table: restored LAN route $_lsn"
	fi
	if ip link show "$TUN" >/dev/null 2>&1; then
		if ! ip route show table $RT 2>/dev/null | grep -q "dev $TUN"; then
			ip link set "$TUN" up 2>/dev/null
			if ! ip -4 addr show dev "$TUN" 2>/dev/null | grep -q "inet "; then
				ip addr add $TUN_ADDR/24 dev "$TUN" 2>/dev/null || true
				ip link set "$TUN" up 2>/dev/null || true
				say "tun0: re-assigned $TUN_ADDR/24 after reconnect"
			fi
			if ip route replace default dev "$TUN" metric 10 table $RT 2>/dev/null; then
				echo "default dev $TUN metric 10 table $RT" >> "$_PSI_OWNED_ROUTES"
				say "routing LAN via $TUN"
			fi
			ip -4 addr show dev "$TUN" 2>/dev/null | grep -q inet || say "warning: $TUN has no IPv4 address (masquerade may not work)"
		fi
	fi
}

conn_mode() {
	local m
	if B dns_enabled 0; then echo traffic_dns_udp; return; fi
	m=$(U conn_mode)
	case "$m" in
		traffic_dns_https|traffic_dns_udp) echo "$m" ;;
		*) echo auto ;;
	esac
}

dns_tunnel_wanted() {
	return 0
}

doh_available() { command -v https-dns-proxy >/dev/null 2>&1; }

doh_proc_net() { echo "${PSI_PROC_NET:-/proc/net}"; }

doh_port_busy() {
	local hp f d st files="udp udp6 tcp tcp6"
	case "$1" in ''|*[!0-9]*) return 0 ;; esac
	hp=$(printf '%04X' "$1" 2>/dev/null) || return 0
	[ "$2" = udp ] && files="udp udp6"
	d=$(doh_proc_net)
	for f in $files; do
		[ -r "$d/$f" ] || continue
		case "$f" in tcp*) st=0A ;; *) st="" ;; esac
		awk -v hp="$hp" -v st="$st" 'NR > 1 { n = split($2, a, ":"); if (toupper(a[n]) == hp && (st == "" || $4 == st)) { hit = 1; exit } } END { exit !hit }' "$d/$f" 2>/dev/null && return 0
	done
	return 1
}

doh_nap() { sleep 0.2 2>/dev/null || sleep 1; }

doh_engine_alive() {
	local p
	p=$(cat "$DOH_PID" 2>/dev/null)
	case "$p" in ''|*[!0-9]*) return 1 ;; esac
	kill -0 "$p" 2>/dev/null || return 1
	tr '\000' ' ' < "/proc/$p/cmdline" 2>/dev/null | grep -q 'https-dns-proxy'
}

doh_engine_ready() {
	doh_engine_alive && doh_port_busy "$(doh_port)" udp
}

doh_engine_stop() {
	local p n=0
	p=$(cat "$DOH_PID" 2>/dev/null)
	if doh_engine_alive; then
		kill "$p" 2>/dev/null
		while [ "$n" -lt 10 ] && doh_engine_alive; do doh_nap; n=$((n+1)); done
		doh_engine_alive && kill -9 "$p" 2>/dev/null
	fi
	rm -f "$DOH_PID" "$RUN/doh_in_tunnel"
}

doh_engine_start() {
	local c n tried=0
	doh_available || return 1
	doh_engine_ready && return 0
	doh_engine_alive && doh_engine_stop
	mkdir -p "$RUN"
	for c in $DOH_PORT_CANDIDATES; do
		if doh_port_busy "$c"; then
			say "DoH: local port $c is already in use by another process - trying the next one"
			continue
		fi
		tried=1
		_extra=""
		if command -v id >/dev/null 2>&1 && id nobody >/dev/null 2>&1; then
			_extra="-u nobody -g nogroup"
		fi
		( https-dns-proxy -a 127.0.0.1 -p "$c" -b "1.1.1.1,1.0.0.1" -r "$DOH_URL" -4 $_extra \
			>/dev/null 2>&1 </dev/null &
		  echo $! > "$DOH_PID" )
		n=0
		while [ "$n" -lt 10 ]; do
			doh_nap
			doh_engine_alive || break
			if doh_port_busy "$c" udp; then
				DOH_PORT=$c
				echo "$c" > "$DOH_PORT_FILE"
				say "DoH engine listening on 127.0.0.1:$c"
				return 0
			fi
			n=$((n+1))
		done
		say "DoH: engine did not come up on port $c"
		doh_engine_stop
	done
	[ "$tried" = 1 ] || say "ERROR: DoH: no free local port among: $DOH_PORT_CANDIDATES"
	return 1
}

dns_foreign_upstreams() {
	local v out=""
	for v in $(uci -q get 'dhcp.@dnsmasq[0].server' 2>/dev/null); do
		case "$v" in /*) continue ;; esac
		out="$out $v"
	done
	echo $out | tr -cd '0-9a-zA-Z.:#_ -'
}

FOREIGN_BAK=/etc/psiphon-dnsmasq-servers.bak
dns_foreign_isolate() {
	local v all="" keep="" has=0
	[ -f "$RUN/stopping" ] && return 0
	for v in $(uci -q get 'dhcp.@dnsmasq[0].server' 2>/dev/null); do
		all="$all $v"
		case "$v" in /*) keep="$keep $v" ;; *) has=1 ;; esac
	done
	[ "$has" = 1 ] || return 0
	for v in $all; do
		grep -qxF "$v" "$FOREIGN_BAK" 2>/dev/null || echo "$v" >> "$FOREIGN_BAK"
	done
	[ -s "$FOREIGN_BAK" ] || return 1
	uci -q delete 'dhcp.@dnsmasq[0].server'
	for v in $keep; do uci -q add_list "dhcp.@dnsmasq[0].server=$v"; done
	uci -q commit dhcp
	/etc/init.d/dnsmasq restart >/dev/null 2>&1
	say "DNS leak guard: removed non-tunnelled dnsmasq upstreams ($(echo $all | tr -cd '0-9a-zA-Z.:#_ /-')) - restored on stop"
	return 0
}

dns_foreign_restore() {
	local v
	[ -f "$FOREIGN_BAK" ] || return 1
	if [ -s "$FOREIGN_BAK" ]; then
		uci -q delete 'dhcp.@dnsmasq[0].server'
		while read -r v; do
			[ -n "$v" ] && uci -q add_list "dhcp.@dnsmasq[0].server=$v"
		done < "$FOREIGN_BAK"
		uci -q commit dhcp
	fi
	rm -f "$FOREIGN_BAK"
	return 0
}

doh_ensure() { doh_engine_start; }

doh_pre_apply() {
	mkdir -p "$RUN"
	if ! doh_ensure; then
		if [ ! -f "$RUN/doh_missing" ]; then
			say "conn_mode=$(conn_mode): DoH engine could not start (is https-dns-proxy installed? apk add https-dns-proxy ca-bundle) - DoH NOT applied"
			: > "$RUN/doh_missing"
		fi
		return 1
	fi
	rm -f "$RUN/doh_missing"
	write_dns_conf $(dns_list)
}

doh_rebind() {
	case "$(conn_mode)" in auto|traffic_dns_https) ;; *) [ -f "$RUN/udp_fallback_doh" ] || return 0 ;; esac
	doh_engine_alive || return 0
	[ -f "$RUN/doh_in_tunnel" ] && return 0
	doh_engine_stop
	doh_engine_start || return 1
	: > "$RUN/doh_in_tunnel"
	say "DoH engine re-bound through $TUN"
}

dns_list() {
	local l="" v
	if B dns_enabled 0; then
		for v in $(U dns1) $(U dns2); do is_ipv4 "$v" && l="$l $v"; done
	fi
	if [ -z "$l" ]; then
		for v in $(U dns1) $(U dns2); do is_ipv4 "$v" && l="$l $v"; done
	fi
	[ -z "$l" ] && l="1.1.1.1 1.0.0.1"
	echo $l
}

builtin_dns() { return 1; }

doh_port() {
	local p
	p=$(cat "$DOH_PORT_FILE" 2>/dev/null)
	case "$p" in ''|*[!0-9]*) p=$DOH_PORT ;; esac
	echo "$p"
}

write_dns_conf() {
	local s _new _m _p use_doh=0 need_doh=0
	_m=$(conn_mode)
	case "$_m" in traffic_dns_https) need_doh=1 ;; esac
	doh_engine_ready && use_doh=1
	[ "$_m" = traffic_dns_udp ] && [ ! -f "$RUN/udp_fallback_doh" ] && use_doh=0
	_p=$(doh_port)
	mkdir -p "$(dirname "$DNSCONF")"
	_new=$(mktemp /tmp/psiphon-dns.XXXXXX) || return 1
	{
		echo "no-resolv"
		if [ "$use_doh" = 1 ]; then
			echo "server=127.0.0.1#$_p"
			echo "server=/$PROBE_DOMAIN/127.0.0.1#$_p"
		else
			for s in "$@"; do echo "server=$s"; done
		fi
	} > "$_new"
	if [ -f "$DNSCONF" ] && cmp -s "$_new" "$DNSCONF"; then
		rm -f "$_new"
		return 0
	fi
	mv -f "$_new" "$DNSCONF"
	/etc/init.d/dnsmasq restart >/dev/null 2>&1
	say "DNS conf written (DoH=$use_doh port=$_p)"
	if [ "$need_doh" = 1 ] && [ "$use_doh" = 0 ]; then
		say "ERROR: conn_mode=$_m requires the DoH engine but it is NOT running - plain resolvers are in use (check: https-dns-proxy + ca-bundle installed, free local port)"
	fi
}

dns_route_add() {
	local s
	[ -f "$DNS_ROUTES" ] || : > "$DNS_ROUTES"
	if doh_available; then
		set -- "$@" $DOH_IPS
	fi
	for s in "$@"; do
		if grep -qx "${s} keep" "$DNS_ROUTES" 2>/dev/null; then
			continue
		fi
		if grep -qx "${s} added" "$DNS_ROUTES" 2>/dev/null; then
			ip route show "$s/32" 2>/dev/null | grep -q "dev $TUN" || \
				ip route replace "$s/32" dev "$TUN" 2>/dev/null
			continue
		fi
		if ip route show "$s/32" 2>/dev/null | grep -q .; then
			ip route show "$s/32" > "$RUN/dns_route_saved_$s.txt" 2>/dev/null
			echo "$s replace" >> "$DNS_ROUTES"
			ip route replace "$s/32" dev "$TUN" 2>/dev/null
		else
			echo "$s added" >> "$DNS_ROUTES"
			ip route replace "$s/32" dev "$TUN" 2>/dev/null
		fi
	done
}

dns_route_del() {
	local ip state _line
	[ -f "$DNS_ROUTES" ] || return 0
	while read -r ip state; do
		[ -z "$ip" ] && continue
		case "$state" in
			added)
				ip route del "$ip/32" dev "$TUN" 2>/dev/null
				;;
			replace)
				ip route del "$ip/32" 2>/dev/null
				if [ -f "$RUN/dns_route_saved_$ip.txt" ]; then
					while IFS= read -r _line; do
						[ -n "$_line" ] && ip route add $_line 2>/dev/null
					done < "$RUN/dns_route_saved_$ip.txt"
					rm -f "$RUN/dns_route_saved_$ip.txt"
				fi
				;;
			keep)
				;;
		esac
	done < "$DNS_ROUTES"
	rm -f "$DNS_ROUTES"
}

dns_check() {
	local n=0 out resolver
	sleep 1
	while [ "$n" -lt 6 ]; do
		out=$(T 4 nslookup -type=A example.com 127.0.0.1 2>/dev/null)
		if echo "$out" | grep -q '^Name:' && \
		   echo "$out" | awk '
			/^Name:/ { in_answer = 1; next }
			in_answer && /[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/ {
				s = $0
				while (match(s, /[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/)) {
					ip = substr(s, RSTART, RLENGTH)
					if (ip !~ /^(127|10|0)\./ && ip !~ /^192\.168\./ && ip !~ /^172\.(1[6-9]|2[0-9]|3[01])\./ && ip !~ /^169\.254\./) { found = 1; exit }
					s = substr(s, RSTART + RLENGTH)
				}
			}
			END { exit !found }
		   '; then
			resolver=$(grep -h '^server=[^/]' "$DNSCONF" 2>/dev/null | cut -d= -f2 | tr '\n' ' ')
			say "dns_check: OK (upstream: ${resolver% })"
			return 0
		fi
		n=$((n+1)); sleep 2
	done
	say "dns_check: FAILED after 6 attempts"
	return 1
}

dns_diag() {
	local r u t first
	first=$(echo $(dns_list) | awk '{print $1}')
	[ -n "$first" ] || return 0
	r=$(ip route get "$first" 2>/dev/null | head -n1)
	u=$(T 5 nslookup -type=A example.com "$first" 2>&1 | grep -E '^(Address|\*\*\*|;;|nslookup:)' | tail -n2 | tr '\n' ' ')
	t=n/a
	if command -v curl >/dev/null 2>&1; then
		t=$(curl -s -m 6 -o /dev/null -w '%{http_code}' -H 'accept: application/dns-json' "https://$first/dns-query?name=example.com&type=A" 2>/dev/null)
	fi
	local e=off _fu
	doh_engine_alive && e=alive
	doh_engine_ready && e=ready
	say "dns_diag: route[$r] udp53[${u:-no answer}] tcp-https[${t:-fail}] doh_engine[$e] doh_port[$(doh_port)] doh_route[$(ip route get 1.1.1.1 2>/dev/null | head -n1)]"
	_fu=$(dns_foreign_upstreams)
	if [ -n "$_fu" ]; then
		say "dns_diag: WARNING extra dnsmasq upstreams outside this service ($_fu) - dnsmasq also queries them and they are NOT tunnelled"
	fi
	if ! doh_available; then
		say "hint: Psiphon's tunnel does not carry UDP reliably - install https-dns-proxy (apk add https-dns-proxy ca-bundle) so DNS runs as DoH over TCP through the tunnel"
	fi
}

dns_fallback_check() {
	# After Stop: if the router's own DNS cannot resolve (system DoH proxy blocked on the WAN), fall back to plain WAN DNS
	local _i=0 _ok=0
	while [ "$_i" -lt 3 ]; do
		sleep 3
		if timeout 4 nslookup openwrt.org 127.0.0.1 2>/dev/null | grep -q "^Name:" ; then _ok=1; break; fi
		_i=$((_i+1))
	done
	[ "$_ok" = 1 ] && return 0
	pidof psiphon-core >/dev/null 2>&1 && return 0
	# Only conclude DoH is blocked when the WAN itself is reachable (otherwise a temporary outage would disable it for good)
	ping -c1 -W3 1.1.1.1 >/dev/null 2>&1 || ping -c1 -W3 8.8.8.8 >/dev/null 2>&1 || return 0
	say "DNS check failed after stop (system DoH likely blocked) - switching dnsmasq to plain WAN DNS"
	if [ -x /etc/init.d/https-dns-proxy ]; then
		/etc/init.d/https-dns-proxy stop >/dev/null 2>&1
		/etc/init.d/https-dns-proxy disable >/dev/null 2>&1   # keep it off after reboot (it would restore noresolv=1)
		say "system https-dns-proxy disabled (re-enable: /etc/init.d/https-dns-proxy enable && start)"
	fi
	uci -q set 'dhcp.@dnsmasq[0].noresolv=0'
	uci -q commit dhcp
	/etc/init.d/dnsmasq restart >/dev/null 2>&1
}

dns_restore() {
	doh_engine_stop 2>/dev/null
	dns_route_del
	local _re=0
	dns_foreign_restore && _re=1
	[ -f "$DNSCONF" ] && { rm -f "$DNSCONF"; _re=1; }
	if [ "$_re" = 1 ]; then
		/etc/init.d/dnsmasq restart >/dev/null 2>&1
		dns_fallback_check &
		say "router DNS restored to default (not tunnelled)"
	fi
}

ks_apply() {
	local _w _s _d _sd _dr1 _dr2 _v6
	B kill_switch 0 || return 0
	[ -f "$RUN/stopping" ] && return 0
	command -v nft >/dev/null 2>&1 || return 0
	_w=$(wan_dev); [ -n "$_w" ] || return 0
	_s=$(cat "$RUN/ks_wan" 2>/dev/null)
	_d=$(grep -h '^server=' "$DNSCONF" 2>/dev/null | cut -d= -f2 | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | tr '\n' ',' | sed 's/,$//; s/,/, /g')
	_sd=$(cat "$RUN/ks_dns" 2>/dev/null)
	_dr1=""; _dr2=""
	if [ -f "$DNSCONF" ]; then
		_d="ALL:$_d"
		_dr1="oifname \"$_w\" udp dport 53 reject"
		_dr2="oifname \"$_w\" tcp dport { 53, 853 } reject"
	elif [ -n "$_d" ]; then
		_dr1="oifname \"$_w\" ip daddr { $_d } udp dport 53 reject"
		_dr2="oifname \"$_w\" ip daddr { $_d } tcp dport 53 reject"
	fi
	_v6=""
	if true; then
		_v6="  chain ks_fwd6 { type filter hook forward priority 0; policy accept;
    oifname \"$_w\" meta nfproto ipv6 reject
  }
  chain ks_out6 { type filter hook output priority 0; policy accept;
    oifname \"$_w\" meta l4proto icmpv6 accept
    oifname \"$_w\" udp dport 547 accept
    oifname \"$_w\" meta nfproto ipv6 reject
  }"
	fi
	if [ "$_s" = "$_w" ] && [ "$_sd" = "$_d" ] && nft list table inet psiphon_ks >/dev/null 2>&1; then
		return 0
	fi
	mkdir -p "$RUN"
	nft -f - 2>/dev/null <<NFT && { echo "$_w" > "$RUN/ks_wan"; echo "$_d" > "$RUN/ks_dns"; }
add table inet psiphon_ks
delete table inet psiphon_ks
table inet psiphon_ks {
  chain ks_fwd { type filter hook forward priority 0; policy accept;
    oifname "$_w" ip daddr != 127.0.0.0/8 reject
  }
$_v6
  chain ks_out4 { type filter hook output priority 0; policy accept;
    $_dr1
    $_dr2
  }
}
NFT
}

fw_strict_on() {
	[ -f "$RUN/stopping" ] && return 0
	local _stored _current
	_stored=$(cat "$RUN/strict_wan" 2>/dev/null)
	_current=$(wan_dev)
	if command -v nft >/dev/null 2>&1 \
	   && nft list table inet $NFT_TABLE >/dev/null 2>&1; then
		[ -n "$_stored" ] && [ "$_stored" = "$_current" ] && return 0
		if [ -n "$_stored" ] && [ -n "$_current" ] && [ "$_stored" != "$_current" ]; then
			local lan2 lip2
			lan2=$(lan_dev); lip2=$(lan_ip)
			if [ -n "$lan2" ] && [ -n "$lip2" ] && [ -n "$_current" ]; then
				{
					echo "delete table inet $NFT_TABLE"
					echo "table inet $NFT_TABLE {"
					echo "  chain dns_redir { type nat hook prerouting priority dstnat; policy accept;"
					echo "    iifname \"$lan2\" ip daddr != $lip2 udp dport 53 redirect to :53"
					echo "    iifname \"$lan2\" ip daddr != $lip2 tcp dport 53 redirect to :53"
					echo "  }"
					echo "  chain dns_out { type filter hook output priority filter; policy accept;"
					echo "    oifname \"$_current\" udp dport 53 reject"
					echo "    oifname \"$_current\" tcp dport 53 reject"
					echo "  }"
					echo "  chain dns_fwd { type filter hook forward priority filter; policy accept;"
					echo "    oifname \"$_current\" udp dport 53 reject"
					echo "    oifname \"$_current\" tcp dport 53 reject"
					echo "  }"
					echo "}"
				} | if nft -f - 2>/dev/null; then
					echo "$_current" > "$RUN/strict_wan"
					say "strict DNS table atomically rebuilt for $_current"
					return 0
				fi
			fi
		fi
	fi
	if command -v iptables >/dev/null 2>&1 \
	   && iptables -t nat -C PREROUTING -j psiphon_dns_nat >/dev/null 2>&1; then
		[ -n "$_stored" ] && [ "$_stored" = "$_current" ] && return 0
	fi

	local lan wan lip
	lan=$(lan_dev); wan=$(wan_dev); lip=$(lan_ip)
	mkdir -p "$RUN"
	[ -n "$wan" ] && echo "$wan" > "$RUN/strict_wan"
	fw_strict_off
	if command -v nft >/dev/null 2>&1; then
		{
			echo "table inet $NFT_TABLE {"
			echo "  chain dns_redir { type nat hook prerouting priority dstnat; policy accept;"
			if [ -n "$lip" ]; then
				echo "    iifname \"$lan\" ip daddr != $lip udp dport 53 redirect to :53"
				echo "    iifname \"$lan\" ip daddr != $lip tcp dport 53 redirect to :53"
			fi
			echo "  }"
			if [ -n "$wan" ]; then
				echo "  chain dns_out { type filter hook output priority filter; policy accept;"
				echo "    oifname \"$wan\" udp dport 53 reject"
				echo "    oifname \"$wan\" tcp dport 53 reject"
				echo "  }"
				echo "  chain dns_fwd { type filter hook forward priority filter; policy accept;"
				echo "    oifname \"$wan\" udp dport 53 reject"
				echo "    oifname \"$wan\" tcp dport 53 reject"
				echo "  }"
			fi
			echo "}"
		} | nft -f - 2>/dev/null && { say "strict DNS enforcement on (nftables)"; return 0; }
	fi
	if command -v iptables >/dev/null 2>&1; then
		iptables -t nat -N psiphon_dns_nat 2>/dev/null; iptables -t nat -F psiphon_dns_nat 2>/dev/null
		iptables -t nat -C PREROUTING -j psiphon_dns_nat 2>/dev/null || iptables -t nat -I PREROUTING -j psiphon_dns_nat 2>/dev/null
		iptables -N psiphon_dns_block 2>/dev/null; iptables -F psiphon_dns_block 2>/dev/null
		for ch in OUTPUT FORWARD; do
			iptables -C $ch -j psiphon_dns_block 2>/dev/null || iptables -I $ch -j psiphon_dns_block 2>/dev/null
		done
		for p in udp tcp; do
			[ -n "$lip" ] && iptables -t nat -A psiphon_dns_nat -i "$lan" ! -d "$lip" -p $p --dport 53 -j REDIRECT --to-ports 53 2>/dev/null
			[ -n "$wan" ] && iptables -A psiphon_dns_block -o "$wan" -p $p --dport 53 -j REJECT 2>/dev/null
		done
		say "strict DNS enforcement on (iptables)"
		return 0
	fi
	say "warning: neither nft nor iptables found - strict DNS enforcement unavailable"
	return 1
}
fw_strict_off() {
	command -v nft >/dev/null 2>&1 && nft delete table inet $NFT_TABLE 2>/dev/null

	if command -v iptables >/dev/null 2>&1; then
		iptables -t nat -D PREROUTING -j psiphon_dns_nat 2>/dev/null
		iptables -t nat -F psiphon_dns_nat 2>/dev/null; iptables -t nat -X psiphon_dns_nat 2>/dev/null
		for ch in OUTPUT FORWARD; do iptables -D $ch -j psiphon_dns_block 2>/dev/null; done
		iptables -F psiphon_dns_block 2>/dev/null; iptables -X psiphon_dns_block 2>/dev/null
	fi
	return 0
}

apply_mss_clamp() {
	local _err
	command -v nft >/dev/null 2>&1 || return 0
	nft list chain inet psiphon_mss mss_fwd >/dev/null 2>&1 && return 0
	_err=$(nft -f - 2>&1 <<NFT
add table inet psiphon_mss
delete table inet psiphon_mss
table inet psiphon_mss {
  chain mss_fwd { type filter hook forward priority -150; policy accept;
    oifname "$TUN" meta nfproto ipv4 tcp flags syn tcp option maxseg size > $TUN_MSS tcp option maxseg size set $TUN_MSS
    iifname "$TUN" meta nfproto ipv4 tcp flags syn tcp option maxseg size > $TUN_MSS tcp option maxseg size set $TUN_MSS
  }
}
NFT
	) && { say "MSS clamping applied on $TUN (mss $TUN_MSS)"; return 0; }
	nft delete table inet psiphon_mss 2>/dev/null
	say "warning: MSS clamp not applied (fw4 zone mtu_fix still clamps): $(echo "$_err" | head -n1)"
	return 0
}
cleanup_mss() {
	command -v nft >/dev/null 2>&1 && nft delete table inet psiphon_mss 2>/dev/null
	return 0
}

ks_keep() {
	[ "${PSI_KS_RELEASE:-0}" = 1 ] && return 1
	B kill_switch 0 || return 1
	B tun 0 || return 1
	return 0
}
ks_hold() {
	local _w
	command -v nft >/dev/null 2>&1 || return 1
	_w=$(wan_dev); [ -n "$_w" ] || return 1
	nft -f - 2>/dev/null <<NFT
add table inet psiphon_ks
delete table inet psiphon_ks
table inet psiphon_ks {
  chain ks_fwd { type filter hook forward priority 0; policy accept;
    oifname "$_w" ip daddr != 127.0.0.0/8 reject
    oifname "$_w" meta nfproto ipv6 reject
  }
  chain ks_out { type filter hook output priority 0; policy accept;
    oifname "$_w" meta l4proto icmpv6 accept
    oifname "$_w" udp dport 547 accept
    oifname "$_w" meta nfproto ipv6 reject
    oifname "$_w" udp dport 53 reject
    oifname "$_w" tcp dport { 53, 853 } reject
  }
}
NFT
}
cleanup_nft_ks() {
	rm -f "$RUN/ks_wan" "$RUN/ks_dns" "$RUN/ks_hold" 2>/dev/null
	if ks_keep && ks_hold; then
		: > "$RUN/ks_hold"
		return 0
	fi
	command -v nft >/dev/null 2>&1 && nft delete table inet psiphon_ks 2>/dev/null
	return 0
}

dns_apply() {
	local mode="" s list _fu
	local _now _last _delay _fail _cm
	case "$(conn_mode)" in
		traffic_dns_https)
			doh_available || say "warning: https-dns-proxy unavailable - falling back to UDP resolvers through the tunnel" ;;
	esac
	_now=$(date +%s)
	_last=$(cat "$RUN/dns_last_try" 2>/dev/null || echo 0)
	_fail=$(cat "$RUN/dns_fail_count" 2>/dev/null || echo 0)
	case "$_fail" in
		0) _delay=10 ;;
		1) _delay=30 ;;
		2) _delay=60 ;;
		*) _delay=120 ;;
	esac

	if dns_tunnel_wanted; then
		list=$(dns_list)
		dns_route_add $list
	fi

	if [ $((_now - _last)) -lt "$_delay" ]; then
		if [ "$(cat "$RUN/dns_bo_logged" 2>/dev/null)" != "$_last" ]; then
			say "dns_apply: backoff (${_delay}s, fail=$_fail) - route kept, skipping check"
			echo "$_last" > "$RUN/dns_bo_logged"
		fi
		return 2
	fi
	echo "$_now" > "$RUN/dns_last_try"
	if ! dns_tunnel_wanted; then
		if B tun 0; then
			say "warning: DNS tunnelling disabled - queries go to the ISP resolver and may leak/be hijacked."
		else
			say "DNS tunnelling disabled in settings"
		fi
		return 0
	fi

	list=$(dns_list)

	dns_route_add $list
	_cm=$(conn_mode)
	[ "$_cm" = traffic_dns_udp ] && [ -f "$RUN/udp_fallback_doh" ] && _cm=auto
	case "$_cm" in
		auto|traffic_dns_https)
			if doh_engine_ready; then
				doh_rebind
			else
				doh_engine_stop
				doh_engine_start && : > "$RUN/doh_in_tunnel"
			fi
			if ! doh_engine_ready; then
				if [ "$(conn_mode)" = traffic_dns_https ]; then
					say "ERROR: conn_mode=traffic_dns_https needs the DoH engine but it is not running - falling back to plain resolvers THROUGH the tunnel (check: https-dns-proxy + ca-bundle installed, free local port)"
				else
					say "DoH engine not running - using plain UDP resolvers through the tunnel (may fail: install https-dns-proxy)"
				fi
			fi ;;
	esac
	dns_foreign_isolate
	write_dns_conf $list

	if dns_check; then
		mode="$list via $TUN"
		say "router DNS now uses: $mode"
		_fu=$(dns_foreign_upstreams)
		if [ -n "$_fu" ] && [ ! -f "$RUN/foreign_warned" ]; then
			say "WARNING: dnsmasq also has upstreams outside this service ($_fu) - they are NOT tunnelled and can leak DNS (e.g. the system https-dns-proxy). Disable them or their dnsmasq integration."
			: > "$RUN/foreign_warned"
		fi
		echo 0 > "$RUN/dns_fail_count"
		B force_router_dns 1 && fw_strict_on
		return 0
	fi
	if [ "$(conn_mode)" = traffic_dns_udp ] && [ ! -f "$RUN/udp_fallback_doh" ] && doh_available; then
		dns_diag
		say "Custom DNS (UDP): the tunnel does not carry UDP - switching to DoH (Cloudflare 1.1.1.1 through the tunnel) automatically"
		: > "$RUN/udp_fallback_doh"
		rm -f "$RUN/dns_last_try"
		dns_apply
		return $?
	fi
	dns_diag
	echo $((_fail + 1)) > "$RUN/dns_fail_count"

	if B kill_switch 0; then
		say "DNS health check FAILED - kill_switch ON, DNS stays closed (will retry)"
		B force_router_dns 1 && fw_strict_on
		return 2
	fi

	say "DNS check failed (fail-open: config kept, will retry)"
	return 2
}

log_fd_is_append() {
	local pid fd fl
	pid=$(core_pid); [ -n "$pid" ] || return 0
	for fd in /proc/$pid/fd/*; do
		[ "$(readlink "$fd" 2>/dev/null)" = "$LOG" ] || continue
		fl=$(sed -n 's/^flags:[[:space:]]*//p' "/proc/$pid/fdinfo/${fd##*/}" 2>/dev/null)
		[ -n "$fl" ] || return 0
		[ $(( 0$fl & 02000 )) -ne 0 ] && return 0
		return 1
	done
	return 0
}
trim_log() {
	local sz n drop r s br=0 bs=0 tmp="$RUN/log.tmp"
	[ -f "$LOG" ] || return 0
	sz=$(wc -c < "$LOG" 2>/dev/null); [ "${sz:-0}" -gt 262144 ] || return 0
	log_fd_is_append || return 0
	n=$(wc -l < "$LOG"); drop=$((n - 500)); [ "$drop" -gt 0 ] || return 0
	head -n "$drop" "$LOG" > "$tmp.old"
	r=$(grep 'BytesTransferred' "$tmp.old" | sed -n 's/.*"received":\([0-9]*\).*/\1/p' | awk '{s+=$1} END{printf "%.0f", s}')
	s=$(grep 'BytesTransferred' "$tmp.old" | sed -n 's/.*"sent":\([0-9]*\).*/\1/p' | awk '{s+=$1} END{printf "%.0f", s}')
	[ -f "$RUN/bt_base" ] && read -r br bs < "$RUN/bt_base"
	echo "$br $r $bs $s" | awk '{printf "%.0f %.0f\n", $1+$2, $3+$4}' > "$RUN/bt_base"
	{
		grep -a '^\[psiphon\] core restarted' "$tmp.old" | tail -n 1
		grep -aE '"noticeType":"(ListeningSocksProxyPort|ListeningHttpProxyPort)"' "$tmp.old" | tail -n 2
		grep -E '"noticeType":"(ConnectedServerRegion|ClientRegion|ConnectedServer|ConnectingServer)"' "$tmp.old" | tail -n 6
		grep '"noticeType":"Tunnels"' "$tmp.old" | tail -n 1
		tail -n +$((drop + 1)) "$LOG" | awk '
			/^\[psiphon\]/ {
				if ($0 == prev) { dup++; next }
				if (dup > 0) { print prev" (x"(dup+1)")"; dup = 0 }
				prev = $0; print; next
			}
			{ if (dup > 0) { print prev" (x"(dup+1)")"; dup = 0 } print }
			END { if (dup > 0) print prev" (x"(dup+1)")" }
		'
	} > "$tmp"
	cat "$tmp" > "$LOG"
	rm -f "$tmp" "$tmp.old"
}

cmd_health() {
	local p ok_running=0 ok_tun=0 ok_socks=0 ok_dns=0 ip4="" socks_ms=0 dns_ms=0
	p=$(sock_port)

	pidof psiphon-core >/dev/null 2>&1 && ok_running=1

	if ip link show "$TUN" >/dev/null 2>&1; then
		ip4=$(ip -4 addr show dev "$TUN" 2>/dev/null | sed -n 's/.*inet \([0-9.]*\).*/\1/p' | head -n1)
		[ -n "$ip4" ] && ok_tun=1
	fi

	if [ -n "$p" ]; then
		_o=$(curl -sL -m 6 --socks5-hostname "127.0.0.1:$p" -o /dev/null \
			-w '%{http_code} %{time_total}' 'https://api.github.com/zen' 2>/dev/null)
		set -- $_o
		if [ "${1:-000}" != "000" ]; then
			ok_socks=1
			socks_ms=$(echo "${2:-0}" | awk '{printf "%d", $1*1000}')
		fi
	fi

	if T 4 nslookup example.com 127.0.0.1 >/dev/null 2>&1; then
		ok_dns=1
		dns_ms=1
	fi

	printf '{"running":%s,"tun":%s,"ip4":"%s","socks":%s,"socks_ms":%s,"dns":%s}\n' \
		"$ok_running" "$ok_tun" "$ip4" "$ok_socks" "$socks_ms" "$ok_dns"
}

cmd_prepare() {
	mkdir -p "$RUN" "$DB_DIR" "$PERSIST"
	echo "[System] Starting Psiphon..." > "$LOG"
	echo "0 0" > "$RUN/bt_base"
	if [ ! -s "$RUN/bootstrap_dns" ]; then
		grep -h '^server=' /tmp/dnsmasq.d/*.conf 2>/dev/null | \
			cut -d= -f2 | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' > "$RUN/bootstrap_dns" || true
		if [ ! -s "$RUN/bootstrap_dns" ]; then
		_bootstrap=$(uci -q get dhcp.@dnsmasq[0].server 2>/dev/null)
		echo "$_bootstrap" | tr ' ' '
' | \
			grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' > "$RUN/bootstrap_dns" || true
		fi
		[ -s "$RUN/bootstrap_dns" ] || echo "1.1.1.1" > "$RUN/bootstrap_dns"
	fi
	restore_db
	gen_config || return 1

	if B tun 0; then
		if ip link show "$TUN" >/dev/null 2>&1; then
			[ -f "$RUN/tun_owned" ] || say "WARNING: $TUN already exists and is not owned by Psiphon - the core may fail to start (OpenVPN?)"
		else
			: > "$RUN/tun_owned"
		fi
		setup_policy
		apply_mss_clamp
		rm -f "$RUN/stopping" "$RUN/ks_hold"
		ks_apply
		say "Full Tunnel mode: policy routing prepared$(B kill_switch 0 && echo ', kill switch armed')"
	else
		say "Proxy mode (no tun0): DNS/kill switch/IPv6 options are inactive"
	fi
}

_psi_is_stopping() { [ -f "$RUN/stopping" ]; }

cmd_watch() {
	local tun=0 i=0 dns_on=0 cnt pid last_pid _cur_mtu
	B tun 0 && tun=1
	rm -f "$RUN/stopping" 2>/dev/null
	if ! B kill_switch 0; then
		dns_restore >/dev/null 2>&1
	fi
	last_pid=$(cat "$RUN/core_pid" 2>/dev/null)
	while :; do
		if _psi_is_stopping; then
			say "watcher: stopping marker detected - waiting for kill"
			while _psi_is_stopping; do sleep 1; done
			return 0
		fi
		pid=$(core_pid)
		if [ "$pid" != "$last_pid" ]; then
			echo "$pid" > "$RUN/core_pid"
			say "watcher: core pid ${last_pid:-0} -> ${pid:-0}"
			if [ "$dns_on" -ne 0 ]; then
				if B kill_switch 0; then
					say "DNS: core PID changed, kill_switch ON - keeping fail-closed resolver"
					dns_on=3
				else
					dns_restore
					dns_on=0
				fi
			fi
			last_pid="$pid"
		fi
		cnt=$(tun_count)
		if [ "$dns_on" -eq 0 ]; then
			case "$(conn_mode)" in
				traffic_dns_https) [ "$tun" -eq 1 ] && [ "${cnt:-0}" -lt 1 ] && doh_pre_apply ;;
			esac
		fi
		if [ "$tun" -eq 1 ]; then
			ensure_route

			if ip link show "$TUN" >/dev/null 2>&1; then
				if ! ip -4 addr show dev "$TUN" 2>/dev/null | grep -q "inet "; then
					ip addr add $TUN_ADDR/24 dev "$TUN" 2>/dev/null || true
					ip link set "$TUN" up 2>/dev/null || true
					say "tun0: re-assigned $TUN_ADDR/24 after reconnect"
				fi
				_cur_mtu=$(cat /sys/class/net/$TUN/mtu 2>/dev/null)
				if [ "${_cur_mtu:-0}" -gt "$TUN_MTU" ] || \
				   { [ "$TUN_MTU_FORCE" = "1" ] && [ "${_cur_mtu:-0}" -ne "$TUN_MTU" ]; }; then
					ip link set "$TUN" mtu "$TUN_MTU" 2>/dev/null && say "tun0: MTU set to $TUN_MTU"
				fi
			fi
			if [ -n "$pid" ] && [ "${cnt:-0}" -ge 1 ]; then
				if [ "$dns_on" -ne 0 ] && [ $((i % 10)) -eq 0 ] && [ -f "$DNSCONF" ] && [ -n "$(dns_foreign_upstreams)" ]; then dns_foreign_isolate; fi
				if [ "$dns_on" -eq 0 ] || [ "$dns_on" -eq 2 ] || \
				   { [ "$dns_on" -eq 3 ] && [ $((i % 3)) -eq 0 ]; }; then
					dns_apply
					case $? in
						0) dns_on=1 ;;
						2) dns_on=3 ;;
						*) dns_on=2 ;;
					esac
				elif [ "$dns_on" -eq 1 ] && B force_router_dns 1 && [ -f "$DNSCONF" ]; then
					fw_strict_on
				fi
			elif [ "$dns_on" -ne 0 ]; then
				if B kill_switch 0; then
					[ "$dns_on" -ne 3 ] && say "DNS: tunnel dropped - kill switch ON, staying fail-closed"
					dns_on=3
				else
					dns_restore; dns_on=0
					ip route del default dev "$TUN" table "$RT" 2>/dev/null
				fi
			fi
		fi
		i=$((i + 1))
		[ $((i % 20))  -eq 0 ] && trim_log
		# After each tunnel (re)connect, wait ~90s (DSL has refreshed server entries) and back up the
		# datastore to $DB_BAK - but only if that backup is older than PERSIST_MIN_GAP (4 days).
		if [ -n "$pid" ] && [ "${cnt:-0}" -ge 1 ]; then
			if [ "${_pconn:-0}" -eq 0 ]; then _pconn=1; _pconn_i=$i; fi
			if [ "$_pconn" -eq 1 ] && [ $((i - _pconn_i)) -ge 30 ]; then
				_pconn=2
				! _psi_is_stopping && persist_db_gated
			fi
		else
			_pconn=0
		fi
		sleep 3
	done
}

cmd_cleanup() {
	local wan sp
	mkdir -p "$RUN"
	: > "$RUN/stopping"
	if [ -f "$RUN/scan_pid" ] || [ -f "$RUN/scan_running" ]; then
		sp=$(cat "$RUN/scan_pid" 2>/dev/null)
		if [ -n "$sp" ]; then
			pkill -P "$sp" 2>/dev/null
			kill  "$sp" 2>/dev/null
		fi
		rm -f "$RUN/scan_pid" "$RUN/scan_running"
		rm -rf "$RUN/scan.lock"
	fi
	
	nft delete table inet psiphon_dns 2>/dev/null
	nft delete table inet psiphon_mss 2>/dev/null
	
	dns_restore
	doh_engine_stop
	rm -f "$RUN/doh_started_by_us" "$RUN/dns_bo_logged" "$DOH_PORT_FILE" "$RUN/foreign_warned" "$RUN/udp_fallback_doh"
	rm -f "$RUN/doh_missing"
	fw_strict_off

	_reap_owned_rules
	_reap_owned_routes
	cleanup_nft_ks
	cleanup_mss
	_reap_owned_rules6
	ip route show table $RT 2>/dev/null | grep "dev $TUN" | while IFS= read -r _r; do
		[ -n "$_r" ] && ip route del $_r table $RT 2>/dev/null
	done
	if [ -f "$RUN/tun_owned" ]; then
		ip -4 addr flush dev "$TUN" 2>/dev/null || true
		ip link delete "$TUN" 2>/dev/null
		rm -f "$RUN/tun_owned"
	fi

	if [ -f "$RUN/ipv6_disabled_wan" ] && [ -f "$RUN/ipv6_owned_wan" ]; then
		read -r wan < "$RUN/ipv6_disabled_wan"
		_owned=$(cat "$RUN/ipv6_owned_wan" 2>/dev/null)
		if [ -n "$wan" ] && [ "$wan" = "$_owned" ]; then
			echo 0 > /proc/sys/net/ipv6/conf/$wan/disable_ipv6 2>/dev/null
			if [ -f "$RUN/initial/ipv6_addr.txt" ]; then
				local _now _then
				_now=$(ip -6 addr show dev "$wan" scope global 2>/dev/null | grep -c inet6)
				_then=$(grep -c inet6 "$RUN/initial/ipv6_addr.txt" 2>/dev/null)
				[ "$_now" -lt "$_then" ] && \
					say "note: IPv6 not fully restored (had $_then, now $_now)"
			fi
			say "IPv6 re-enabled on WAN ($wan); will return on next RA/DHCPv6 renewal"
			sleep 2
			_now6=$(ip -6 addr show dev "$wan" scope global 2>/dev/null | grep -c inet6)
			_then6=$(grep -c inet6 "$RUN/initial/ipv6_addr.txt" 2>/dev/null)
			if [ "${_now6:-0}" -lt "${_then6:-0}" ]; then
				say "IPv6: $((_then6 - _now6)) address(es) not yet back - ifup $wan (controlled)"
				say "IPv6: not redialing $wan (RA/DHCPv6 will restore the addresses)"
			else
				say "IPv6 fully restored on $wan"
			fi
		fi
		rm -f "$RUN/ipv6_disabled_wan" "$RUN/ipv6_owned_wan"
	fi

	echo "[System] Stopping Psiphon..." > "$LOG"
	[ -f "$RUN/ks_hold" ] && say "Kill Switch: Psiphon stopped - LAN internet stays BLOCKED (turn Kill Switch off and press Stop, or press Start, to release)"
	if ! pidof psiphon-core >/dev/null 2>&1; then
		persist_db_gated
	fi
}

cmd_restart() {
	( PSI_FORCE=1 /etc/init.d/psiphon restart ) >/dev/null 2>&1 </dev/null &
	echo started
}
cmd_stop()    { /etc/init.d/psiphon stop >/dev/null 2>&1; }
cmd_clearlog() {
	[ -f "$LOG" ] || return 0
	log_fd_is_append || return 0
	local tmp="$RUN/log.keep" br=0 bs=0 r=0 s=0
	mkdir -p "$RUN"
	if [ -s "$RUN/bt_base" ]; then
		read -r br bs < "$RUN/bt_base" 2>/dev/null || { br=0; bs=0; }
	fi
	[ -z "$br" ] && br=0
	[ -z "$bs" ] && bs=0
	set -- $(bt_sum); r=${1:-0}; s=${2:-0}
	[ -z "$r" ] && r=0
	[ -z "$s" ] && s=0
	echo "$br $r $bs $s" | awk '{printf "%.0f %.0f\n", $1+$2, $3+$4}' > "$RUN/bt_base.tmp"
	mv -f "$RUN/bt_base.tmp" "$RUN/bt_base"
	{
		grep -a '^\[psiphon\] core restarted' "$LOG" 2>/dev/null | tail -n 1
		grep -aE '"noticeType":"(ListeningSocksProxyPort|ListeningHttpProxyPort)"' "$LOG" 2>/dev/null | tail -n 2
		grep -aE '"noticeType":"(ConnectedServerRegion|ClientRegion|ConnectedServer|ConnectingServer|Tunnels)"' "$LOG" 2>/dev/null | tail -n 6
	} > "$tmp"
	cat "$tmp" > "$LOG"
	rm -f "$tmp"
}
cmd_fw_refresh() {
	local _bw _cw _now _last
	if B tun 0 && pidof psiphon-core >/dev/null 2>&1; then
		_bw=$(cat "$RUN/core_wan" 2>/dev/null); _cw=$(wan_dev)
		if [ -n "$_cw" ] && [ "$_bw" != "$_cw" ]; then
			_now=$(date +%s); _last=$(cat "$RUN/wan_restart_ts" 2>/dev/null || echo 0)
			if [ $((_now - _last)) -ge 60 ]; then
				echo "$_now" > "$RUN/wan_restart_ts"
				say "WAN device changed (${_bw:-none} -> $_cw): restarting service to re-bind the core"
				( PSI_FORCE=1 /etc/init.d/psiphon restart >/dev/null 2>&1 ) >/dev/null 2>&1 </dev/null &
				return 0
			fi
		fi
	fi
	local _stored _current
	_stored=$(cat "$RUN/strict_wan" 2>/dev/null)
	_current=$(wan_dev)
	[ -n "$_stored" ] && [ "$_stored" = "$_current" ] && return 0
	[ -z "$_current" ] && return 0
	if B force_router_dns 1; then
		fw_strict_on
	fi
}
cmd_run_core() {
	say "core restarted"
	exec "$PROG" "$@"
}

# ---- maintenance: update / uninstall from the LuCI page ---------------------
MAINT_LOG=/tmp/psimaint.log
MAINT_ST=/tmp/psimaint.state
MAINT_RUN=/tmp/psimaint-run.sh

cmd_maint_start() { # update | uninstall [purge=1]
	local act="$1" purge="$2" port="" pid
	case "$act" in update|uninstall) ;; *) echo "bad-action"; return 1 ;; esac
	command -v curl >/dev/null 2>&1 || { echo "no-curl"; return 1; }
	if [ -f "$MAINT_ST" ] && grep -q '^running' "$MAINT_ST" 2>/dev/null; then
		pid=$(awk '{print $3}' "$MAINT_ST" 2>/dev/null)
		case "$pid" in ''|*[!0-9]*) pid=0 ;; esac
		[ "$pid" -gt 1 ] && kill -0 "$pid" 2>/dev/null && { echo "busy"; return 1; }
	fi
	# when the tunnel is up, GitHub can be reached through its local SOCKS proxy if the direct path is blocked
	pidof psiphon-core >/dev/null 2>&1 && port=$(sock_port)
	# the runner lives in /tmp (not in this file): the installer rewrites this helper while it runs
	cat > "$MAINT_RUN" <<'__PSI_RUN__'
#!/bin/sh
trap '' HUP
ACTION="$1"
ST=/tmp/psimaint.state
BASE="https://raw.githubusercontent.com/MehArt44/Psiphon-core-Openwrt25-LuCI/main"
fin() { echo "$1 $ACTION $$ $2" > "$ST"; }
case "$ACTION" in
	update)    URL="$BASE/install.sh";   F=/tmp/psimaint-install.sh ;;
	uninstall) URL="$BASE/Uninstall.sh"; F=/tmp/psimaint-uninstall.sh ;;
	*) echo "bad action"; fin failed 2; exit 2 ;;
esac
echo "[1/3] Downloading $URL"
rm -f "$F"
if curl -fsSL -m 45 -o "$F" "$URL" 2>/dev/null; then
	echo "      direct download OK"
elif [ -n "$PSI_SOCKS" ] && curl -fsSL -m 60 --socks5-hostname "127.0.0.1:$PSI_SOCKS" -o "$F" "$URL" 2>/dev/null; then
	echo "      downloaded through the Psiphon tunnel"
else
	echo "ERROR: download failed (GitHub is unreachable). Connect Psiphon first, then try again."
	rm -f "$F"; fin failed 3; exit 3
fi
echo "[2/3] Checking the downloaded script"
SZ=$(wc -c < "$F" 2>/dev/null); SZ=${SZ:-0}
if [ "$SZ" -lt 3000 ] || ! head -n1 "$F" | grep -q '^#!/bin/sh' || ! grep -qi psiphon "$F" || ! sh -n "$F" 2>/dev/null; then
	echo "ERROR: the downloaded file is not a valid installer script (size $SZ) - nothing was changed."
	rm -f "$F"; fin failed 4; exit 4
fi
echo "      OK ($SZ bytes)"
echo "[3/3] Running it"
case "$ACTION" in
	update)    sh "$F" install ;;
	uninstall) if [ "$PSI_PURGE" = "1" ]; then sh "$F" -y --purge; else sh "$F" -y; fi ;;
esac
rc=$?
rm -f "$F"
if [ "$rc" = 0 ]; then echo "FINISHED OK"; fin done 0; else echo "FINISHED WITH ERRORS (exit $rc)"; fin failed "$rc"; fi
exit "$rc"
__PSI_RUN__
	chmod 700 "$MAINT_RUN"
	: > "$MAINT_LOG"
	if command -v setsid >/dev/null 2>&1; then
		PSI_SOCKS="$port" PSI_PURGE="$purge" setsid sh "$MAINT_RUN" "$act" >"$MAINT_LOG" 2>&1 </dev/null &
	else
		PSI_SOCKS="$port" PSI_PURGE="$purge" nohup sh "$MAINT_RUN" "$act" >"$MAINT_LOG" 2>&1 </dev/null &
	fi
	echo "running $act $!" > "$MAINT_ST"
	echo started
}

cmd_maint_status() {
	local st act pid rc
	[ -f "$MAINT_ST" ] || { echo '{"state":"idle","action":"","rc":0}'; return 0; }
	read -r st act pid rc < "$MAINT_ST"
	case "$act" in update|uninstall) ;; *) act="" ;; esac
	case "$pid" in ''|*[!0-9]*) pid=0 ;; esac
	case "$rc" in ''|*[!0-9]*) rc=0 ;; esac
	if [ "$st" = running ] && { [ "$pid" -le 1 ] || ! kill -0 "$pid" 2>/dev/null; }; then st=failed; rc=1; fi
	case "$st" in running|done|failed) ;; *) st=idle ;; esac
	printf '{"state":"%s","action":"%s","rc":%s}\n' "$st" "$act" "$rc"
}

cmd_maint_log() { tail -n 150 "$MAINT_LOG" 2>/dev/null; }

case "$1" in
	status)   cmd_status ;;
	health)   cmd_health ;;
	realip)   cmd_realip ;;
	vpnip)    cmd_vpnip ;;
	dnsleak)  cmd_dnsleak ;;
	diag)     shift; cmd_diag "$@" ;;
	probe)    shift; cmd_probe "$@" ;;
	scan)     shift; cmd_scan "$@" ;;
	taillog)  tail -n 400 "$LOG" 2>/dev/null ;;
	restart)  cmd_restart ;;
	persist)  persist_db ;;
	persist_gated) persist_db_gated ;;
	stop)     cmd_stop ;;
	clearlog) cmd_clearlog ;;
	fw-refresh) cmd_fw_refresh ;;
	run-core)
		[ "${PSI_INTERNAL:-0}" = "1" ] || { echo "forbidden" >&2; exit 1; }
		shift; cmd_run_core "$@" ;;
	prepare)
		[ "${PSI_INTERNAL:-0}" = "1" ] || { echo "forbidden" >&2; exit 1; }
		cmd_prepare ;;
	watch)
		[ "${PSI_INTERNAL:-0}" = "1" ] || { echo "forbidden" >&2; exit 1; }
		cmd_watch ;;
	cleanup)
		[ "${PSI_INTERNAL:-0}" = "1" ] || { echo "forbidden" >&2; exit 1; }
		cmd_cleanup ;;
	_scan_inner)  shift; cmd_scan_inner "$@" ;;
	scan-start)  shift; cmd_scan_start "$@" ;;
	scan-result) cmd_scan_result ;;
	maint-start)  shift; cmd_maint_start "$@" ;;
	maint-status) cmd_maint_status ;;
	maint-log)    cmd_maint_log ;;
	*) echo "usage: $0 {status|health|realip|vpnip|dnsleak|diag|probe|scan|taillog|restart|stop|clearlog|prepare|watch|cleanup}" >&2; exit 1 ;;
esac
__PSI_EOF__

chmod 755 "/usr/bin/psiphon-helper"
mkdir -p "/etc/hotplug.d/iface"
cat <<'__PSI_EOF__' > "/etc/hotplug.d/iface/90-psiphon"
#!/bin/sh
[ "$ACTION" = "ifup" ] || exit 0
pidof psiphon-core >/dev/null 2>&1 || exit 0
[ -x /usr/bin/psiphon-helper ] || exit 0
/usr/bin/psiphon-helper fw-refresh >/dev/null 2>&1
exit 0
__PSI_EOF__
chmod 755 "/etc/hotplug.d/iface/90-psiphon"
mkdir -p "/usr/share/luci/menu.d"
cat <<'__PSI_EOF__' > "/usr/share/luci/menu.d/luci-app-psiphon.json"
{
    "admin/vpn": {
        "title": "VPN",
        "order": 60,
        "action": {
            "type": "alias",
            "path": "admin/vpn/psiphon"
        }
    },
    "admin/vpn/psiphon": {
        "title": "Psiphon VPN",
        "order": 1,
        "action": {
            "type": "view",
            "path": "vpn/psiphon"
        },
        "depends": {
            "uci": {
                "psiphon": true
            }
        }
    }
}
__PSI_EOF__
mkdir -p "/usr/share/rpcd/acl.d"
cat <<'__PSI_EOF__' > "/usr/share/rpcd/acl.d/luci-app-psiphon.json"
{
	"luci-app-psiphon": {
		"description": "Grant execution rights for Psiphon service controls",
		"read": {
			"uci": [ "psiphon" ],
			"file": {
				"/tmp/psiphon.log": [ "read" ],
				"/tmp/psiphon/psiphon.config": [ "read" ],
				"/usr/bin/psiphon-helper": [ "exec" ]
			},
			"ubus": {
				"file": [ "exec", "read" ]
			}
		},
		"write": {
			"uci": [ "psiphon" ],
			"file": {
				"/usr/bin/psiphon-helper": [ "exec" ]
			}
		}
	}
}
__PSI_EOF__
mkdir -p "/www/luci-static/resources/view/vpn"
cat <<'__PSI_EOF__' > "/www/luci-static/resources/view/vpn/psiphon.js"
'use strict';
'require view';
'require form';
'require fs';
'require ui';
'require uci';
'require poll';

return view.extend({
	country_names: {
		AT: 'Austria', BE: 'Belgium', BG: 'Bulgaria', CA: 'Canada', CH: 'Switzerland', 
		CZ: 'Czech Republic', DE: 'Germany', DK: 'Denmark', EE: 'Estonia', 
		ES: 'Spain', FI: 'Finland', FR: 'France', GB: 'United Kingdom', 
		HU: 'Hungary', IE: 'Ireland', IN: 'India', IT: 'Italy', JP: 'Japan', 
		LV: 'Latvia', NL: 'Netherlands', NO: 'Norway', PL: 'Poland', 
		RO: 'Romania', RS: 'Serbia', SE: 'Sweden', SG: 'Singapore', 
		SK: 'Slovakia', US: 'United States'
	},
	flags: {
		AT: '🇦🇹', BE: '🇧🇪', BG: '🇧🇬', CA: '🇨🇦', CH: '🇨🇭', CZ: '🇨🇿', 
		DE: '🇩🇪', DK: '🇩🇰', EE: '🇪🇪', ES: '🇪🇸', FI: '🇫🇮', FR: '🇫🇷', 
		GB: '🇬🇧', HU: '🇭🇺', IE: '🇮🇪', IN: '🇮🇳', IT: '🇮🇹', JP: '🇯🇵', 
		LV: '🇱🇻', NL: '🇳🇱', NO: '🇳🇴', PL: '🇵🇱', RO: '🇷🇴', RS: '🇷🇸', 
		SE: '🇸🇪', SG: '🇸🇬', SK: '🇸🇰', US: '🇺🇸'
	},
	socksPort: null,

	load: function() {
		return Promise.resolve().then(L.bind(function() {
			if (!document.getElementById('nvl-emoji-font')) {
				var fl = document.createElement('link');
				fl.id = 'nvl-emoji-font';
				fl.rel = 'stylesheet';
				fl.href = 'https://fonts.googleapis.com/css2?family=Noto+Color+Emoji&display=swap';
				document.head.appendChild(fl);
			}
			if (!document.getElementById('noto-emoji-font')) {
				var style = document.createElement('style');
				style.id = 'noto-emoji-font';
				style.innerHTML = `
					.win-flag { font-family: "Noto Color Emoji", "Segoe UI Emoji", sans-serif !important; }
					:root {
						--psi-bg: #1B2227;
						--psi-bg-2: #1a1d22;
						--psi-bg-3: #232830;
						--psi-border: #383d45;
						--psi-border-2: #343b46;
						--psi-text: #b8bfc7;
						--psi-text-dim: #92a0b0;
						--psi-text-mute: #46505A;
						--psi-accent-green: #4fd88a;
						--psi-accent-blue: #5b9bd9;
						--psi-accent-yellow: #e0b34d;
						--psi-accent-red: #e2645c;
					}
					.cbi-section-node { display: flex; flex-direction: column; gap: 8px; width: 100% !important; background: transparent !important; border: none !important; padding: 0 !important; }
					.psiphon-top-row { width: 100%; order: 1; margin-bottom: 0px; }
					.psiphon-bottom-grid { display: flex; flex-direction: row; gap: 12px; width: 100%; align-items: stretch; order: 2; }
					.psiphon-col-left { flex: 1.1; min-width: 320px; display: flex; flex-direction: column; background: var(--background-card, #1B2227); padding: 6px 14px; border-radius: 10px; border: 1px solid rgba(255,255,255,0.08); box-shadow: 0 4px 10px rgba(0,0,0,0.2); justify-content: flex-start; }
					.psiphon-col-right { flex: 0.9; min-width: 320px; display: flex; flex-direction: column; gap: 8px; background: #1B2227; padding: 10px 14px; border-radius: 10px; border: 1px solid #383d45; box-shadow: 0 4px 10px rgba(0,0,0,0.3); justify-content: flex-start; }
					.psiphon-col-left > .cbi-value { width: 100% !important; padding: 5px 6px !important; margin-bottom: 0 !important; border-bottom: 1px solid rgba(255,255,255,0.04) !important; display: flex !important; flex-direction: row !important; align-items: center !important; min-height: 36px; box-sizing: border-box; border-radius: 6px; transition: background 0.15s ease; }
					.psiphon-col-left > .cbi-value:hover { background: rgba(255,255,255,0.025); }
					.psiphon-col-left > .cbi-value:last-child { border-bottom: none !important; }
					.psiphon-col-left .cbi-value-title { width: 38% !important; min-width: 140px !important; text-align: left !important; padding: 0 10px 0 0 !important; font-size: 13px; color: #b8bfc7; }
					.psiphon-col-left .cbi-value-field { width: 62% !important; padding: 0 !important; font-size: 13px; }
					.psiphon-col-left .cbi-value-description { margin-top: 2px !important; font-size: 11px !important; color: #46505A; line-height: 1.25; }
					.psiphon-col-left input[type="text"], .psiphon-col-left select { height: 26px !important; padding: 3px 8px !important; font-size: 13px !important; background-color: #262b33 !important; color: #c7ccd1 !important; width: 100% !important; box-sizing: border-box; border: 1px solid #383d45 !important; border-radius: 6px !important; transition: border-color 0.15s ease, box-shadow 0.15s ease; }
					.psiphon-col-left input[type="text"]:hover, .psiphon-col-left select:hover { border-color: #4a5568 !important; }
					.psiphon-col-left input[type="text"]:focus, .psiphon-col-left select:focus { border-color: #4fd88a !important; box-shadow: 0 0 0 3px rgba(79,216,138,0.15) !important; outline: none !important; }
					.psiphon-col-left input[readonly] { opacity: 0.7; cursor: not-allowed; }

					.psiphon-col-left input[type="checkbox"], .cbi-value-field > input[type="checkbox"] {
						appearance: none; -webkit-appearance: none; -moz-appearance: none;
						width: 32px; height: 18px; min-width: 32px;
						border-radius: 999px; background: #2a2f38; border: 1px solid #3a4049;
						position: relative; cursor: pointer; outline: none;
						transition: background 0.2s ease, border-color 0.2s ease;
						vertical-align: middle;
					}
					.psiphon-col-left input[type="checkbox"]::before, .cbi-value-field > input[type="checkbox"]::before {
						content: ''; position: absolute; top: 2px; left: 2px;
						width: 12px; height: 12px; border-radius: 50%;
						background: #9aa5b1; box-shadow: 0 1px 3px rgba(0,0,0,0.4);
						transition: transform 0.2s ease, background 0.2s ease;
					}
					.psiphon-col-left input[type="checkbox"]:checked, .cbi-value-field > input[type="checkbox"]:checked {
						background: linear-gradient(135deg, #4fd88a, #3cb375); border-color: #4fd88a;
					}
					.psiphon-col-left input[type="checkbox"]:checked::before, .cbi-value-field > input[type="checkbox"]:checked::before {
						transform: translateX(14px); background: #fff;
					}
					.psiphon-col-left input[type="checkbox"]:hover, .cbi-value-field > input[type="checkbox"]:hover { border-color: #5a6572; }
					.psiphon-col-left input[type="checkbox"]:focus-visible, .cbi-value-field > input[type="checkbox"]:focus-visible {
						box-shadow: 0 0 0 3px rgba(79,216,138,0.25);
					}

					.psiphon-col-left .cbi-button, .cbi-button { border-radius: 6px !important; transition: transform 0.12s ease, box-shadow 0.12s ease, filter 0.12s ease !important; }
					.psiphon-col-left .cbi-button { padding: 4px 12px !important; font-size: 12px !important; height: auto !important; min-height: 26px !important; }
					.cbi-button:hover, button.btn:hover { filter: brightness(1.15); transform: translateY(-1px); }
					.cbi-button:active, button.btn:active { transform: translateY(0); filter: brightness(0.95); }

					.psi-btn{ border-radius:6px; padding:5px 14px; font-size:12px; font-weight:700;
						cursor:pointer; border:1px solid transparent; background:transparent; }
					.psi-btn:disabled{ opacity:.5; cursor:not-allowed; }
					.psi-btn-start{ color:#4fd88a; border-color:#4fd88a; }
					.psi-btn-start:hover:not(:disabled){ background:#4fd88a; color:#12241b; }
					.psi-btn-stop{ color:#e2645c; border-color:#e2645c; }
					.psi-btn-stop:hover:not(:disabled){ background:#e2645c; color:#fff; }
					.psi-btn-refresh{ background:transparent; color:#b8bfc7; border-color:#3a3f47; }
					.psi-btn-check{ background:linear-gradient(135deg,#2b5876,#4e4376); color:#fff; border-color:transparent; }
					.cbi-value[data-name="dns1"] input.cbi-input-invalid, .cbi-value[data-name="dns2"] input.cbi-input-invalid, div[data-name="dns1"] input.cbi-input-invalid, div[data-name="dns2"] input.cbi-input-invalid{ border:1px solid #e2645c !important; box-shadow:0 0 0 1px #e2645c; }
					.psi-btn-ghost{ border-radius:4px; padding:3px 10px; font-size:11px; font-weight:700;
						cursor:pointer; background:transparent; color:#e2645c; border:1px solid #e2645c; }
					.psi-bar { position:relative; height:2.5px; margin:6px 0 2px; border-radius:3px; background:#3b3b43; box-shadow:inset 0 0 0 1px rgba(0,0,0,.35); }
					.psi-bar-fill { position:absolute; left:0; top:0; height:100%; width:0; border-radius:3px; opacity:0; background-image:linear-gradient(90deg,#00e5ff,#ff00ff); transition:width .9s cubic-bezier(.22,.61,.36,1), opacity .4s ease; }
					.psi-bar-fill.up { opacity:1; }
					.psi-bar-fill.down { opacity:1; background-image:linear-gradient(90deg,#ff00ff,#00e5ff); transition:width 1.2s ease-in, opacity 1.2s ease-in; }
					.psi-bar-fill::after { content:''; position:absolute; left:0; right:0; top:100%; height:16px; background:inherit; filter:blur(12px); opacity:.35; -webkit-mask-image:linear-gradient(#000,transparent); mask-image:linear-gradient(#000,transparent); pointer-events:none; }
					.psi-bar-fill::before { content:''; position:absolute; top:0; left:0; right:0; bottom:0; border-radius:inherit; opacity:0; background-image:linear-gradient(90deg,transparent,rgba(255,255,255,.6),transparent); background-size:40% 100%; background-repeat:no-repeat; background-position:-60% 0; }
					.psi-bar-fill.busy::before { opacity:1; animation:psi-shine 1.6s linear infinite; }
					@keyframes psi-shine { from { background-position:-60% 0; } to { background-position:160% 0; } }
					@keyframes psi-glow { 0%,100% { filter:brightness(1); } 50% { filter:brightness(1.3); } }
					@media (prefers-reduced-motion: reduce) { .psi-bar-fill, .psi-bar-fill::before { animation:none !important; transition:none !important; } }
					.psi-log { font-family:monospace; font-size:12px; line-height:1.5; background:#181b1f; color:#c0c8d2; padding:8px; border-radius:4px; border:1px solid #2b2f35; box-sizing:border-box; }
					.psi-ll { white-space:pre-wrap; word-break:break-word; padding-left:15ch; text-indent:-15ch; }
					.psi-ll .t { color:#5d6878; display:inline-block; width:9ch; text-indent:0; }
					.psi-ll .g { font-weight:700; display:inline-block; width:6ch; text-indent:0; }
					.psi-ll .ip { color:#f0a35e; }
					.psi-ll .x { color:#46505A; margin-left:6px; }
					.psi-acc { width:100% !important; margin:2px 0 !important; padding:0 !important; border:1px solid #2f343b !important; border-radius:8px !important; background:#1a1f25 !important; overflow:hidden; transition:border-color .15s ease; }
					.psi-acc.psi-open { border-color:#3f4752 !important; }
					.psi-acc-hdr { display:flex; align-items:center; gap:10px; padding:9px 12px; cursor:pointer; user-select:none; width:100%; box-sizing:border-box; background:linear-gradient(135deg,#1e2329,#232830); transition:background .15s ease; }
					.psi-acc-hdr:hover { background:linear-gradient(135deg,#232830,#2a3038); }
					.psi-acc-hdr .psi-acc-arrow { width:12px; text-align:center; color:#46505A; font-size:10px; flex-shrink:0; transition:transform .2s ease; }
					.psi-acc.psi-open .psi-acc-arrow { transform:rotate(90deg); }
					.psi-acc-hdr .psi-acc-title { flex:1; font-weight:700; font-size:13px; color:#d5dae0; text-align:left; }
					.psi-acc-hdr .psi-acc-sub { font-size:11px; color:#46505A; font-weight:400; margin-left:6px; }
					.psi-acc-hdr .psi-acc-badge { font-size:10px; font-weight:700; padding:2px 8px; border-radius:4px; letter-spacing:.3px; background:rgba(146,160,176,0.15); color:#92a0b0; flex-shrink:0; }
					.psi-acc-hdr .psi-acc-badge.on { background:rgba(79,216,138,0.15); color:#4fd88a; box-shadow:0 0 0 1px rgba(79,216,138,0.25) inset; }
					.psi-acc-body { display:none; padding:4px 10px 10px 10px; border-top:1px solid #2b3038; }
					.psi-acc.psi-open .psi-acc-body { display:block; }
					.psi-acc-body > .cbi-value { width:100% !important; padding:5px 4px !important; margin-bottom:0 !important; border-bottom:1px solid rgba(255,255,255,0.04) !important; display:flex !important; flex-direction:row !important; align-items:center !important; min-height:34px; box-sizing:border-box; border-radius:5px; }
					.psi-acc-body > .cbi-value:last-child { border-bottom:none !important; }
					.psi-acc-body .cbi-value-title { width:40% !important; min-width:140px !important; text-align:left !important; padding:0 10px 0 0 !important; font-size:13px; color:#b8bfc7; }
					.psi-acc-body .cbi-value-field { width:60% !important; padding:0 !important; font-size:13px; }
					.psi-acc-body .cbi-value-description { margin-top:2px !important; font-size:11px !important; color:#46505A; line-height:1.25; }
					.psi-acc-body input[type="text"], .psi-acc-body select { height:26px !important; padding:3px 8px !important; font-size:13px !important; background-color:#262b33 !important; color:#c7ccd1 !important; width:100% !important; box-sizing:border-box; border:1px solid #383d45 !important; border-radius:6px !important; }
					.psi-maint-row { display:flex; align-items:center; gap:10px; padding:9px 4px; border-bottom:1px solid rgba(255,255,255,0.04); flex-wrap:wrap; }
					.psi-maint-row:last-of-type { border-bottom:none; }
					.psi-maint-info { flex:1; min-width:200px; font-size:13px; color:#b8bfc7; }
					.psi-maint-info small { display:block; margin-top:2px; font-size:11px; color:#6b7683; line-height:1.3; }
					.psi-maint-check { display:flex; align-items:center; gap:6px; font-size:12px; color:#e0b34d; cursor:pointer; }
					#psi-maint-status { margin-top:8px; font-size:12px; color:#92a0b0; }
					#psi-maint-log { display:none; margin-top:6px; max-height:220px; overflow:auto; padding:8px; background:#12161b; border:1px solid #2b3038; border-radius:6px; font-family:monospace; font-size:11px; line-height:1.45; color:#b8bfc7; white-space:pre-wrap; word-break:break-all; }
					@media (max-width: 940px) { 
						.psiphon-bottom-grid { flex-direction: column; align-items: fill; } 
						.psiphon-col-right, .psiphon-col-left { width: 100%; box-sizing: border-box; } 
					}
				`;
				document.head.appendChild(style);
			}
		}, this));
	},

	render: function() {
		var self = this;
		var poll_counter = 0;

        var dnsMap = {
            'custom': ['', ''],
            'google': ['8.8.8.8', '8.8.4.4'],
            'opendns': ['208.67.222.222', '208.67.220.220'],
            'cloudflare': ['1.1.1.1', '1.0.0.1'],
            'norton': ['199.85.126.10', '199.85.127.10'],
            'comodo_sec': ['8.26.56.26', '8.20.247.20'],
            'comodo': ['156.154.70.22', '156.154.71.22'],
            'dns_watch': ['84.200.69.80', '84.200.70.40'],
            'adguard_noblock': ['94.140.14.140', '94.140.15.150'],
            'adguard_block': ['94.140.14.14', '94.140.15.15'],
            'adguard_family': ['94.140.14.16', '94.140.14.17'],
            'quad9_sec': ['9.9.9.9', '149.112.112.112'],
            'quad9_nosec': ['9.9.9.10', '149.112.112.10']
        };

		var logoContainer = E('div', { 'id': 'psiphon-dynamic-logo', 'style': 'height: 52px; width: 52px; flex-shrink: 0; display: flex; align-items: center; justify-content: center;' });
		function getLogoSvg(c1, c2) {
			return '<svg width="100%" height="100%" viewBox="0 0 48.00 48.00" xmlns="http://www.w3.org/2000/svg">' +
				'<path d="M 12 0 H 36 A 12 12 0 0 1 48 12 V 36 A 12 12 0 0 1 36 48 H 12 A 12 12 0 0 1 0 36 V 12 A 12 12 0 0 1 12 0 Z" fill="' + c1 + '"/>' +
				'<path d="M 20.593 32.889 L 34.273 32.824 L 37.97 29.341 L 40.491 9.289 L 37.302 5.922 L 10.97 5.601 C 9.476 6.667 8.285 8.104 7.514 9.77 L 17.57 9.868 L 13.607 40.876 C 15.408 41.841 17.408 42.377 19.45 42.444 Z" fill="#fff"/>' +
				'<path d="M 23.797 11.765 L 21.624 26.41 L 31.601 26.303 L 33.739 11.765 Z" fill="' + c2 + '"/>' +
				'</svg>';
		}
		logoContainer.innerHTML = getLogoSvg('#ff4800', '#ff4800');

		var titleHtml = E('div', { 'style': 'display: flex; align-items: center; gap: 12px; margin-bottom: 14px; padding: 2px 0;' }, [
			logoContainer,
			E('div', { 'style': 'display: flex; flex-direction: column; justify-content: center;' }, [
				E('h2', { 'style': 'margin: 0; font-weight: bold; color: inherit; font-size: 20px; line-height: 1.2;' }, _('Psiphon VPN Configuration')),
				E('span', { 'style': 'font-size: 11px; color: #92a0b0; display: block; margin-top: 2px;' }, _('Unified control panel for Psiphon tunnel-core (OpenWrt 25 / 2.0.40 ).'))
			])
		]);

		var m = new form.Map('psiphon', titleHtml);
		var s = m.section(form.NamedSection, 'config', 'psiphon');
		s.addremove = false;

		var o = s.option(form.DummyValue, '_ip_box');
		o.rawhtml = true;
		o.render = function() {
			return E('div', { 'class': 'psiphon-top-row' }, [
				E('div', { 'style': 'display: flex; flex-flow: row wrap; align-items: center; justify-content: space-between; background: var(--psi-bg, #1B2227); padding: 8px 16px; border-radius: 8px; border: 1px solid var(--psi-border, #383d45); box-shadow: 0 4px 6px rgba(0,0,0,0.3); width: 100%; gap: 12px;' }, [
					E('div', { 'style': 'display: flex; align-items: center; gap: 6px; flex: 0.8; min-width: 110px;' }, [
						E('span', { 'style': 'color: #92a0b0; font-size: 12px; text-transform: uppercase; font-weight: bold; flex-shrink: 0;' }, _('State')),
						E('span', { 'id': 'state_display', 'style': 'font-size: 13px; font-weight: bold; color: #92a0b0;' }, _('Checking')),
						E('span', { 'id': 'protocol_display', 'style': 'font-size: 10px; font-weight: 600; color: #4fd88a; background: rgba(79,216,138,0.1); padding: 1px 6px; border-radius: 4px; display: none; font-family: monospace; letter-spacing: 0.3px;' }, '')
					]),
					E('div', { 'style': 'width: 1px; height: 18px; background-color: #3a3f47; display: inline-block;' }, ''),
					E('div', { 'style': 'display: flex; align-items: center; gap: 6px; flex: 1 1 0%; min-width: 180px;' }, [
						E('span', { 'style': 'color: #92a0b0; font-size: 12px; text-transform: uppercase; font-weight: bold; width: 60px; flex-shrink: 0;' }, _('Real IP')),
						E('span', { 'id': 'real_ip_display', 'style': 'font-size: 13px; color: #b8bfc7; font-family: monospace; display: flex; align-items: center; gap: 5px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;' }, _('Checking'))
					]),
					E('div', { 'style': 'width: 1px; height: 18px; background-color: #3a3f47; display: inline-block;' }, ''),
					E('div', { 'style': 'display: flex; align-items: center; gap: 6px; flex: 1 1 0%; min-width: 180px;' }, [
						E('span', { 'style': 'color: #92a0b0; font-size: 12px; text-transform: uppercase; font-weight: bold; width: 80px; flex-shrink: 0;' }, _('Psiphon IP')),
						E('span', { 'id': 'vpn_ip_display', 'style': 'font-size: 13px; color: #b8bfc7; font-family: monospace; display: flex; align-items: center; gap: 5px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;' }, _('Checking'))
					]),
					E('div', { 'style': 'display: flex; gap: 6px; flex-shrink: 0;' }, [
						E('button', { 'class': 'psi-btn psi-btn-refresh', 'style': 'white-space: nowrap;', 'click': function(ev) { ev.preventDefault(); refreshIPs(true); } }, _('Refresh')),
						E('button', { 'class': 'psi-btn psi-btn-check', 'style': 'white-space: nowrap;', 'click': function(ev) { 
							ev.preventDefault(); 
							runClientSideDiagnostics(); 
						}}, _('Test Latency'))
					])
				]),
				E('div', { 'class': 'psi-bar', 'id': 'psi-bar' }, [ E('div', { 'class': 'psi-bar-fill', 'id': 'psi-bar-fill' }) ])
			]);
		};

        var optControl = s.option(form.DummyValue, '_control_buttons');
        optControl.rawhtml = true;
        optControl.render = function() {
            var uiObj = (typeof ui !== 'undefined') ? ui : (L.ui || null);
            var startBtn, stopBtn, busyNote = null;

            function note(text, cls, ms) {
                if (!uiObj) return null;
                var n = E('p', text);
                if (ms && uiObj.addTimeLimitedNotification)
                    return uiObj.addTimeLimitedNotification(null, n, ms, cls);
                return uiObj.addNotification(null, n, cls);
            }
            function dropBusy() {
                if (busyNote && busyNote.parentNode) busyNote.parentNode.removeChild(busyNote);
                busyNote = null;
            }

            function setButtonsBusy(busy) {
                if (startBtn) startBtn.disabled = busy;
                if (stopBtn) stopBtn.disabled = busy;
            }

            return E('div', { 'class': 'cbi-value' }, [
                E('label', { 'class': 'cbi-value-title' }, _('Service Control')),
                E('div', { 'class': 'cbi-value-field', 'style': 'display: flex; gap: 8px;' }, [
                    startBtn = E('button', {
                        'class': 'psi-btn psi-btn-start',
                        'click': function(ev) {
                            ev.preventDefault();
                            setButtonsBusy(true);
                            dropBusy(); busyNote = note(_('Restarting Psiphon service...'), 'info', 15000);

                            fs.exec('/usr/bin/psiphon-helper', ['restart'])
                            .then(function(r) {
                                if (r && r.code !== 0) {
                                    dropBusy(); if (uiObj) uiObj.addNotification(null, E('p', _('Restart failed: ') + (r.stderr || r.code)), 'error');
                                } else {
                                    dropBusy(); note(_('Restart command accepted.'), 'info', 4000);
                                }
                                setTimeout(function() { refreshIPs(true); }, 2500);
                                setTimeout(function() { refreshIPs(true); }, 9000);
                                setTimeout(function() { refreshIPs(true); }, 20000);
                            })
                            .catch(function(e) {
                                if (/timed out/i.test(String(e))) {
                                    dropBusy(); note(_('Restart is still running in the background...'), 'info', 6000);
                                    setTimeout(function() { refreshIPs(true); }, 9000);
                                    setTimeout(function() { refreshIPs(true); }, 20000);
                                } else if (uiObj) {
                                    dropBusy(); uiObj.addNotification(null, E('p', _('Restart error: ') + e), 'error');
                                }
                            })
                            .finally(function() { setButtonsBusy(false); });
                        }
                    }, _('Start / Restart')),

                    stopBtn = E('button', {
                        'class': 'psi-btn psi-btn-stop',
                        'click': function(ev) {
                            ev.preventDefault();
                            setButtonsBusy(true);
                            dropBusy(); busyNote = note(_('Stopping Psiphon service...'), 'info', 15000);

                            fs.exec('/usr/bin/psiphon-helper', ['stop'])
                            .then(function(r) {
                                if (r && r.code !== 0) {
                                    dropBusy(); if (uiObj) uiObj.addNotification(null, E('p', _('Stop failed: ') + (r.stderr || r.code)), 'error');
                                } else {
                                    dropBusy(); note(_('Stop command accepted.'), 'info', 4000);
                                }
                                setTimeout(function() { refreshIPs(true); }, 1500);
                            })
                            .catch(function(e) {
                                dropBusy(); if (uiObj) uiObj.addNotification(null, E('p', _('Stop error: ') + e), 'error');
                            })
                            .finally(function() { setButtonsBusy(false); });
                        }
                    }, _('Stop'))
                ])
            ]);
        };

		var optEnabled = s.option(form.Flag, 'enabled', _('Auto Connect + Full Tunnel'), _('Start on boot and route all LAN traffic through tun0. Required for the DNS and Kill Switch options. Off = local proxy only.'));
		optEnabled.rmempty = false;
		optEnabled.default = '0';
		optEnabled.write = function(section_id, value) {
			this.map.data.set(this.map.config, section_id, 'tun', value);
			return form.Flag.prototype.write.apply(this, arguments);
		};
		optEnabled.remove = function(section_id) {
			this.map.data.set(this.map.config, section_id, 'tun', '0');
			return form.Flag.prototype.remove.apply(this, arguments);
		};

		var optKill = s.option(form.Flag, 'kill_switch', _('Kill Switch'), _('⚠️ ON: blocks LAN internet while the tunnel is down or Psiphon is stopped, and blocks all IPv6 (no leaks). To get internet back: turn it off, then press Stop. OFF: LAN falls back to WAN if the tunnel drops.'));
		optKill.rmempty = false;
		optKill.default = '0';
		optKill.depends('enabled', '1');

		var optCountry = s.option(form.ListValue, 'country', _('Region'));
		optCountry.rmempty = true; optCountry.optional = true;
		optCountry.value('', '⚡ ' + _('Best Performance'));
		var countries = ['AT','BE','BG','CA','CH','CZ','DE','DK','EE','ES','FI','FR','GB','HU','IE','IN','IT','JP','LV','NL','NO','PL','RO','RS','SE','SG','SK','US'];
		countries.forEach(function(c) {
			var fullName = self.country_names[c] || c;
			optCountry.value(c, (self.flags[c] || '') + ' [' + c + '] ' + fullName);
		});

		var optTransport = s.option(form.ListValue, 'transport', _('Transport Mode'), _('Tunnel protocol family. Ignored while CDN Fronting is on.'));
		optTransport.value('STANDARD', _('Standard (auto)'));
		optTransport.value('TLS', _('TLS / Fronted'));
		optTransport.value('QUIC', _('QUIC'));
		optTransport.value('SSH', _('SSH'));
		optTransport.default = 'STANDARD';

		var optMtu = s.option(form.ListValue, 'tun_mtu', _('Tunnel MTU'),
			_('MTU of tun0 (MSS is clamped automatically). Lower it only if pages hang or uploads stall.'));
		optMtu.value('auto', _('Auto (1400, recommended)'));
		optMtu.value('1280', '1280 \u2014 ' + _('safest'));
		optMtu.value('1360', '1360 \u2014 ' + _('PPPoE + overhead'));
		optMtu.value('1380', '1380 \u2014 ' + _('PPPoE / DSL'));
		optMtu.value('1400', '1400 \u2014 ' + _('conservative'));
		optMtu.value('1420', '1420 \u2014 ' + _('higher throughput'));
		optMtu.value('1440', '1440 \u2014 ' + _('IPv4, no overhead'));
		optMtu.value('1500', '1500 \u2014 ' + _('only without overhead'));
		optMtu.default = 'auto';
		optMtu.rmempty = false;
		optMtu.depends('enabled', '1');

        var optConnMode = s.option(form.ListValue, 'conn_mode', _('Connection Mode'),
            _('How traffic and DNS are handled (DNS always uses the tunnel). Hidden while Custom DNS is on (forces UDP). DoH needs https-dns-proxy + ca-bundle. Automatic = DoH if installed, else UDP.'));
        optConnMode.value('auto', _('Automatic (use the options below)'));
        optConnMode.value('traffic_dns_https', _('Traffic and DNS (HTTPS / DoH)'));
        optConnMode.value('traffic_dns_udp', _('Custom DNS / Traffic Mode(UDP)'));
        optConnMode.default = 'auto';
        optConnMode.rmempty = false;
        optConnMode.retain = true;
        optConnMode.depends({ dns_enabled: '0' });
        optConnMode.depends({ enabled: '0' });
        optConnMode.cfgvalue = function(section_id) {
            if (uci.get('psiphon', section_id, 'dns_enabled') === '1')
                return 'traffic_dns_udp';
            return form.ListValue.prototype.cfgvalue.apply(this, arguments);
        };

        var optForceDns = s.option(form.Flag, 'force_router_dns', _('Strict DNS Enforcement'), _('While connected: redirect LAN DNS to the router and block plain DNS on the WAN.'));
        optForceDns.rmempty = false;
        optForceDns.default = '0';
        optForceDns.depends('enabled', '1');

        var dnsEnable = s.option(form.Flag, 'dns_enabled', _('Custom DNS Mode(UDP)'), _('Use your own IPv4 DNS over UDP through the tunnel (sets Connection Mode to UDP). Psiphon usually cannot carry UDP: then DoH (Cloudflare) is used automatically (needs https-dns-proxy). Keep Kill Switch ON.'));
        dnsEnable.rmempty = false;
        dnsEnable.default = '0';
        dnsEnable.depends('enabled', '1');
        var psiPrevConnMode = null;
        dnsEnable.onchange = function(ev, section_id, value) {
            var on = (String(value) === '1');
            var cm = optConnMode.getUIElement(section_id);
            if (cm) {
                if (on) {
                    var cur = cm.getValue();
                    if (cur !== 'traffic_dns_udp') psiPrevConnMode = cur;
                    cm.setValue('traffic_dns_udp');
                } else if (psiPrevConnMode) {
                    cm.setValue(psiPrevConnMode);
                    psiPrevConnMode = null;
                }
            }
            [dns1, dns2].forEach(function(o) {
                var u = o.getUIElement(section_id);
                if (u && typeof u.triggerValidation === 'function') u.triggerValidation();
            });
        };

        var dnsPreset = s.option(form.ListValue, 'dns_preset', _('DNS Server Preset'));
        dnsPreset.depends({ enabled: '1', dns_enabled: '1' });
        dnsPreset.value('custom', _('Custom (edit manually)'));
        dnsPreset.value('google', 'Google Public DNS');
        dnsPreset.value('opendns', 'OpenDNS');
        dnsPreset.value('cloudflare', 'Cloudflare');
        dnsPreset.value('comodo_sec', 'Comodo Secure');
        dnsPreset.value('comodo', 'Comodo');
        dnsPreset.value('dns_watch', 'DNS WATCH');
        dnsPreset.value('adguard_noblock', 'AdGuard (No Block)');
        dnsPreset.value('adguard_block', 'AdGuard (Block)');
        dnsPreset.value('adguard_family', 'AdGuard (Family)');
        dnsPreset.value('quad9_sec', 'Quad9 Security');
        dnsPreset.value('quad9_nosec', 'Quad9 No Security');

        var dns1 = s.option(form.Value, 'dns1', _('DNS 1'));
        dns1.depends({ enabled: '1', dns_enabled: '1' });
        dns1.placeholder = '156.154.70.22';
        dns1.rmempty = true;

        var dns2 = s.option(form.Value, 'dns2', _('DNS 2'));
        dns2.depends({ enabled: '1', dns_enabled: '1' });
        dns2.placeholder = '156.154.71.22';
        dns2.rmempty = true;

        var psiDnsRequired = function(section_id, value) {
            if (dnsEnable.formvalue(section_id) === '1' && (!value || !String(value).trim()))
                return _('Required: enter a DNS server IPv4 address');
            return true;
        };
        dns1.validate = psiDnsRequired;
        dns2.validate = psiDnsRequired;
        [dns1, dns2].forEach(function(o) {
            var origRender = o.render;
            o.render = function(option_index, section_id, in_table) {
                var self = this;
                return Promise.resolve(origRender.apply(self, arguments)).then(function(node) {
                    setTimeout(function() {
                        var u = o.getUIElement(section_id);
                        if (u && typeof u.triggerValidation === 'function') u.triggerValidation();
                    }, 0);
                    return node;
                });
            };
        });

        dnsPreset.onchange = function(ev, section_id, value) {
            if (dnsMap[value]) {
                var fields = ['dns1', 'dns2'];
                for (var i = 0; i < 2; i++) {
                    var el = document.querySelector('div[data-name="' + fields[i] + '"] input') || 
                             document.querySelector('input[id$=".' + fields[i] + '"]') ||
                             document.querySelector('input[name$=".' + fields[i] + '"]');
                    if (el) {
                        el.value = dnsMap[value][i] || '';
                        el.dispatchEvent(new Event('input', { bubbles: true }));
                        el.dispatchEvent(new Event('change', { bubbles: true }));
                    }
                }
            }
        };

        var optBeast = s.option(form.Flag, 'beast_mode', _('Beast Mode'), _('Aggressive connection establishment.'));
        optBeast.rmempty = true;
        optBeast.default = '0';

        var optCdnHdr = s.option(form.DummyValue, '_cdn_hdr', '');
        optCdnHdr.rawhtml = true;
        optCdnHdr.render = function() {
            return E('div', { 'class': 'psi-acc', 'id': 'psi-acc-cdn', 'data-key': 'cdn' }, [
                E('div', { 'class': 'psi-acc-hdr' }, [
                    E('span', { 'class': 'psi-acc-arrow' }, '\u25B6'),
                    E('span', { 'class': 'psi-acc-title' }, _('CDN Fronting')),
                    E('span', { 'class': 'psi-acc-sub' }, _('FRONTED-MEEK / edge IP pinning')),
                    E('span', { 'class': 'psi-acc-badge', 'id': 'psi-badge-cdn' }, '\u2014')
                ]),
                E('div', { 'class': 'psi-acc-body', 'id': 'psi-body-cdn' })
            ]);
        };
        var optCdn = s.option(form.Flag, 'cdn_fronting', _('CDN Fronting'), _('Force CDN-fronted protocols (FRONTED-MEEK). Optionally pin edge IPs and SNI below; empty = built-in providers.'));
        optCdn.rmempty = false;
        optCdn.default = '0';

        var optCdnSni = s.option(form.Value, 'cdn_sni', _('CDN SNI hostname'),
            _('⚠️ Stored only: core 2.0.40 does not pin it (used by the test/scan tools). TLS server name for the edge IPs.'));
        optCdnSni.depends('cdn_fronting', '1');
        optCdnSni.placeholder = 'vercel.com';
        optCdnSni.rmempty = true;
        optCdnSni.validate = function(section_id, value) {
            if (!value) return true;
            return /^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}$/.test(value) ||
                   _('Invalid hostname (e.g. vercel.com)');
        };

        var optCdnIp = s.option(form.Value, 'cdn_edge_ips', _('CDN edge IPs'),
            _('⚠️ Stored only: core 2.0.40 does not pin it (used by the test/scan tools). Comma-separated IPv4 edge addresses.'));
        optCdnIp.depends('cdn_fronting', '1');
        optCdnIp.placeholder = '2.18.79.83, 2.19.30.248';
        optCdnIp.rmempty = true;
        optCdnIp.validate = function(section_id, value) {
            if (!value) return true;
            var parts = value.split(/[\s,;]+/).filter(Boolean);
            for (var i = 0; i < parts.length; i++) {
                var p = parts[i];
                if (!/^\d{1,3}(\.\d{1,3}){3}$/.test(p)) return _('Invalid IPv4: ') + p;
                var o = p.split('.');
                for (var j = 0; j < 4; j++) if (+o[j] > 255) return _('Invalid IPv4: ') + p;
            }
            return true;
        };

        var optCdnProbe = s.option(form.Flag, 'cdn_probe', _('Pre-check edge IPs'),
            _('⚠️ Stored only; used only if the core supports custom fronting. Keeps edge IPs that pass a TLS handshake at start.'));
        optCdnProbe.depends('cdn_fronting', '1');
        optCdnProbe.default = '0';
        optCdnProbe.rmempty = false;
        var optCdnTest = s.option(form.DummyValue, '_cdn_test', _('CDN edge check'));
        optCdnTest.renderWidget = function() {
            return E('div', {}, [
                E('button', { 'class': 'psi-btn psi-btn-check', 'click': function(ev) { ev.preventDefault(); runCdnProbe(ev.currentTarget); } }, _('Test edge IPs')),
                E('div', { 'id': 'cdn_probe_result', 'style': 'font-family: monospace; font-size: 12px; color: #92a0b0; margin-top: 6px; line-height: 1.5;' },
                    _('Direct TLS check of each edge IP with the SNI above (not via the tunnel). Success = handshake only.'))
            ]);
        };

        var CDN_SNI_MAP = {
            akamai: 'a248.e.akamai.net',
            fastly: 'www.python.org',
            cloudflare: 'cdnjs.cloudflare.com',
            cloudfront: 'd1.awsstatic.com',
            google: 'www.google.com',
            github: 'pages.github.com',
            vercel: 'vercel.com',
            imperva: 'www.imperva.com',
            edgecast: 'www.edgio.com',
            azure: 'ajax.aspnetcdn.com',
            cdn77: 'www.cdn77.com',
            sucuri: 'cdn.sucuri.net',
            gcore: 'gcore.com',
            cdnvideo: 'www.cdnvideo.ru',
            alibaba: 'www.alicdn.com',
            tencent: 'cloud.tencent.com',
            bunny: 'bunnycdn.com',
            keycdn: 'www.keycdn.com',
            cachefly: 'www.cachefly.com',
            leaseweb: 'www.leaseweb.com',
            baidu: 'www.bdstatic.com'
        };
        var CDN_PROVIDERS = [
            ['akamai', 'Akamai'], ['fastly', 'Fastly'], ['cloudflare', 'Cloudflare'],
            ['cloudfront', 'Amazon CloudFront'], ['google', 'Google (GFE/Cloud)'], ['github', 'GitHub Pages'],
            ['vercel', 'Vercel'], ['imperva', 'Imperva'], ['edgecast', 'Edgecast / Edgio'],
            ['azure', 'Microsoft Azure CDN'], ['cdn77', 'CDN77'], ['sucuri', 'Sucuri'],
            ['gcore', 'Gcore (small - CDN edge only)'],
            ['cdnvideo', 'CDNvideo (RU, low value)'],
            ['alibaba', 'Alibaba Cloud (China cloud - low value)'],
            ['tencent', 'Tencent Cloud (China cloud - low value)'],
            ['bunny', 'Bunny CDN (small)'], ['keycdn', 'KeyCDN (small)'],
            ['cachefly', 'CacheFly (small)'],
            ['leaseweb', 'Leaseweb CDN (small)'],
            ['baidu', 'Baidu AI Cloud (China cloud - low value)'],
            ['all', 'All (mixed sample of 12 core CDNs)'],
            ['custom', 'Custom CIDR ranges...']
        ];
        var SEL_STYLE = 'font-family:inherit !important; height:28px; background:#262b33; color:#c7ccd1; border:1px solid #383d45; border-radius:6px; padding:3px 8px; font-size:13px;';

        function setSniField(val) {
            var f = document.querySelector('input[id$=".cdn_sni"]') || document.querySelector('div[data-name="cdn_sni"] input');
            if (!f || !val) return false;
            f.value = val;
            f.dispatchEvent(new Event('input', { bubbles: true }));
            f.dispatchEvent(new Event('change', { bubbles: true }));
            return true;
        }

        var optCdnScan = s.option(form.DummyValue, '_cdn_scan', _('CDN IP scanner'));
        optCdnScan.renderWidget = function() {
            return E('div', {}, [
                E('div', { 'style': 'display:flex; gap:8px; flex-wrap:wrap; align-items:center;' }, [
                    E('select', { 'id': 'cdn_scan_provider', 'change': function(ev) { var v = CDN_SNI_MAP[ev.target.value]; if (v) setSniField(v); }, 'style': SEL_STYLE + 'min-width:200px;' },
                        CDN_PROVIDERS.map(function(p) { return E('option', { 'value': p[0] }, p[1]); })),
                    E('select', { 'id': 'cdn_scan_depth', 'style': SEL_STYLE },
                        [E('option', { 'value': 'quick' }, _('Quick (~30 IPs)')), E('option', { 'value': 'normal', 'selected': 'selected' }, _('Normal (~60 IPs)')), E('option', { 'value': 'deep' }, _('Deep (~120 IPs)'))]),
                    E('input', { 'id': 'cdn_scan_cidr', 'type': 'text', 'placeholder': 'custom: 1.2.3.0/24, 5.6.0.0/16', 'style': SEL_STYLE + 'min-width:220px;' }),
                    E('button', { 'class': 'psi-btn psi-btn-check', 'click': function(ev) { ev.preventDefault(); runCdnScan(ev.currentTarget); } }, _('Scan and fill'))
                ]),
                E('div', { 'id': 'cdn_scan_result', 'style': 'font-family: monospace; font-size: 12px; color: #92a0b0; margin-top: 6px; line-height: 1.5;' },
                    _('Samples random IPs from the provider ranges. Green = TLS handshake only, not proof of a working tunnel.'))
            ]);
        };

        var optMaintHdr = s.option(form.DummyValue, '_maint_hdr', '');
        optMaintHdr.rawhtml = true;
        optMaintHdr.render = function() {
            return E('div', { 'class': 'psi-acc', 'id': 'psi-acc-maint', 'data-key': 'maint' }, [
                E('div', { 'class': 'psi-acc-hdr' }, [
                    E('span', { 'class': 'psi-acc-arrow' }, '\u25B6'),
                    E('span', { 'class': 'psi-acc-title' }, _('Update / Uninstall')),
                    E('span', { 'class': 'psi-acc-sub' }, _('install from GitHub / remove Psiphon'))
                ]),
                E('div', { 'class': 'psi-acc-body', 'id': 'psi-body-maint' }, [
                    E('div', { 'class': 'psi-maint-row' }, [
                        E('div', { 'class': 'psi-maint-info' }, [
                            E('strong', {}, _('Update')),
                            E('small', {}, _('Downloads the latest installer from GitHub and runs it. Settings are kept; the service restarts and this page may need a reload (Ctrl+F5). Uses the Psiphon tunnel automatically if GitHub is blocked.'))
                        ]),
                        E('button', { 'class': 'psi-btn psi-btn-check', 'id': 'psi-maint-update', 'click': function(ev) { ev.preventDefault(); maintConfirm('update'); } }, _('Update now'))
                    ]),
                    E('div', { 'class': 'psi-maint-row' }, [
                        E('div', { 'class': 'psi-maint-info' }, [
                            E('strong', {}, _('Uninstall')),
                            E('small', {}, _('Stops Psiphon, restores network/DNS and removes the app. By default your settings and the core are kept for a later reinstall.')),
                            E('label', { 'class': 'psi-maint-check' }, [
                                E('input', { 'type': 'checkbox', 'id': 'psi-maint-purge' }),
                                _('Also delete the Psiphon core, settings and every file named *psiphon* (full removal)')
                            ])
                        ]),
                        E('button', { 'class': 'psi-btn psi-btn-stop', 'id': 'psi-maint-uninstall', 'click': function(ev) { ev.preventDefault(); maintConfirm('uninstall'); } }, _('Uninstall'))
                    ]),
                    E('div', { 'id': 'psi-maint-status' }, ''),
                    E('pre', { 'id': 'psi-maint-log' }, '')
                ])
            ]);
        };

        var MAINT_HELPER = '/usr/bin/psiphon-helper';
        var maintTimer = null, maintFails = 0, maintAction = '', maintSeenLog = false;

        function maintEl(id) { return document.getElementById(id); }
        function maintSay(msg, color) {
            var el = maintEl('psi-maint-status');
            if (el) { el.textContent = msg; el.style.color = color || '#92a0b0'; }
        }
        function maintButtons(disabled) {
            ['psi-maint-update', 'psi-maint-uninstall', 'psi-maint-purge'].forEach(function(id) {
                var b = maintEl(id); if (b) b.disabled = disabled;
            });
        }
        function maintStopPoll() { if (maintTimer) { clearInterval(maintTimer); maintTimer = null; } }

        function maintConfirm(action) {
            var purge = !!(maintEl('psi-maint-purge') || {}).checked;
            var msg, title, label, cls;
            if (action === 'update') {
                title = _('Update Psiphon');
                msg = _('The latest installer will be downloaded from GitHub and run. The VPN service restarts, so the connection drops briefly.');
                label = _('Update'); cls = 'cbi-button cbi-button-positive';
            } else {
                title = _('Uninstall Psiphon');
                msg = purge
                    ? _('FULL REMOVAL: Psiphon, its core, all settings and every file named *psiphon* will be deleted. This cannot be undone.')
                    : _('Psiphon will be stopped and removed. Settings and the core are kept so a later reinstall can reuse them.');
                label = _('Uninstall'); cls = 'cbi-button cbi-button-negative';
            }
            ui.showModal(title, [
                E('p', {}, msg),
                E('div', { 'class': 'right' }, [
                    E('button', { 'class': 'btn', 'click': ui.hideModal }, _('Cancel')), ' ',
                    E('button', { 'class': cls, 'click': function() { ui.hideModal(); maintStart(action, purge); } }, label)
                ])
            ]);
        }

        function maintStart(action, purge) {
            var args = ['maint-start', action];
            if (action === 'uninstall' && purge) args.push('1');
            maintButtons(true);
            maintSay(_('Starting…'));
            L.resolveDefault(fs.exec(MAINT_HELPER, args), null).then(function(r) {
                var out = (r && r.stdout) ? r.stdout.trim() : '';
                if (out !== 'started') {
                    maintButtons(false);
                    var why = { busy: _('Another update/uninstall is already running.'), 'no-curl': _('curl is not installed on the router.') }[out] || _('Could not start (helper not available).');
                    maintSay(why, '#e2645c');
                    return;
                }
                maintAction = action; maintFails = 0; maintSeenLog = false;
                var box = maintEl('psi-maint-log');
                if (box) { box.style.display = 'block'; box.textContent = ''; }
                maintSay(action === 'update' ? _('Updating… please wait (up to a few minutes).') : _('Uninstalling… this page stops working when the removal finishes.'), '#e0b34d');
                maintStopPoll();
                maintTimer = setInterval(maintPoll, 2000);
            });
        }

        function maintPoll() {
            L.resolveDefault(fs.exec(MAINT_HELPER, ['maint-status']), null).then(function(r) {
                var st = null;
                try { st = (r && r.stdout) ? JSON.parse(r.stdout.trim()) : null; } catch (e) { st = null; }
                if (!st) {
                    maintFails++;
                    if (maintFails >= 3) {
                        maintStopPoll();
                        if (maintAction === 'uninstall') {
                            maintSay(_('The helper is gone: the removal has finished. Reload the page (Ctrl+F5); the VPN menu entry disappears.'), '#4fd88a');
                        } else {
                            maintSay(_('Lost contact with the router (services are restarting). Wait a few seconds and reload the page (Ctrl+F5).'), '#e0b34d');
                            maintButtons(false);
                        }
                    }
                    return;
                }
                maintFails = 0;
                L.resolveDefault(fs.exec(MAINT_HELPER, ['maint-log']), null).then(function(l) {
                    var box = maintEl('psi-maint-log');
                    if (box && l && typeof l.stdout === 'string') {
                        box.textContent = l.stdout;
                        box.scrollTop = box.scrollHeight;
                    }
                });
                if (st.state === 'done') {
                    maintStopPoll();
                    maintSay(maintAction === 'uninstall'
                        ? _('Uninstall finished. Reload the page (Ctrl+F5).')
                        : _('Update finished. Reload the page (Ctrl+F5) to load the new interface.'), '#4fd88a');
                    if (maintAction !== 'uninstall') maintButtons(false);
                } else if (st.state === 'failed') {
                    maintStopPoll();
                    maintSay(_('Failed (exit code %d). See the log below; nothing else was changed if the download failed.').format(st.rc), '#e2645c');
                    maintButtons(false);
                }
            });
        }

        function runCdnScan(btn) {
            var box = document.getElementById('cdn_scan_result');
            if (!box) return;
            var prov = (document.getElementById('cdn_scan_provider') || {}).value || 'akamai';
            var depth = (document.getElementById('cdn_scan_depth') || {}).value || 'normal';
            var cidr = String((document.getElementById('cdn_scan_cidr') || {}).value || '').trim();
            var sni = String(optCdnSni.formvalue('config') || '').trim();
            if (!sni) { sni = CDN_SNI_MAP[prov] || ''; if (sni) setSniField(sni); }
            if (!sni) { box.style.color = '#e2645c'; box.textContent = _('Fill the CDN SNI hostname first (no default is known for this provider).'); return; }
            if (prov === 'custom' && !cidr) { box.style.color = '#e2645c'; box.textContent = _('Enter at least one CIDR range for the custom option.'); return; }
            btn.disabled = true;
            box.style.color = '#92a0b0';
            box.textContent = _('Starting...');
            runHelper(['scan-start', sni, prov, depth, cidr]).then(function(r) {
                if (r !== 'started') { btn.disabled = false; box.style.color = '#e2645c'; box.textContent = _('Scanner could not start') + ': ' + r; return; }
                var tries = 0;
                (function poll() {
                    runHelper(['scan-result']).then(function(out) {
                        var lines = String(out || '').split('\n').filter(Boolean);
                        var head = (lines.shift() || '').split(' ');
                        var done = head[0] === 'done';
                        var rows = lines.map(function(l) { var p = l.trim().split(/\s+/); return { ip: p[0], ms: parseInt(p[1], 10) || 0 }; })
                            .filter(function(r) { return r.ip && r.ms > 0; });
                        rows.sort(function(a, b) { return a.ms - b.ms; });
                        box.innerHTML = '';
                        box.style.color = '#92a0b0';
                        box.appendChild(E('div', { 'style': 'margin-bottom:4px;' }, (done ? _('Finished') : _('Scanning')) + ' ' + (head[1] || 0) + '/' + (head[2] || '?') + ' - ' + rows.length + ' ' + _('reachable')));
                        rows.slice(0, 12).forEach(function(r) { box.appendChild(E('div', { 'style': 'color:#4fd88a;' }, '+ ' + r.ip + ' - ' + r.ms + ' ms')); });
                        if (done) {
                            btn.disabled = false;
                            if (!rows.length) { box.style.color = '#e2645c'; box.textContent = _('No reachable edge IP found. Try Deep, another provider, or a custom CIDR range.'); return; }
                            var csv = rows.slice(0, 20).map(function(r) { return r.ip; }).join(',');
                            var field = document.querySelector('input[id$=".cdn_edge_ips"]') || document.querySelector('div[data-name="cdn_edge_ips"] input');
                            if (field) {
                                field.value = csv;
                                field.dispatchEvent(new Event('input', { bubbles: true }));
                                field.dispatchEvent(new Event('change', { bubbles: true }));
                                box.appendChild(E('div', { 'style': 'margin-top:6px; font-size:11px;' }, _('Filled CDN edge IPs with the fastest ') + Math.min(rows.length, 20) + _(' IP(s). Click Save & Apply.')));
                            } else {
                                box.appendChild(E('div', { 'style': 'margin-top:6px; color:#e0b34d; font-size:11px;' }, _('Could not auto-fill the field - copy the IPs manually.')));
                            }
                        } else if (++tries < 300) {
                            setTimeout(poll, 2000);
                        } else {
                            btn.disabled = false;
                        }
                    });
                })();
            });
        }

        function runCdnProbe(btn) {
            var box = document.getElementById('cdn_probe_result');
            if (!box) return;
            var sni = String(optCdnSni.formvalue('config') || '').trim();
            var ips = String(optCdnIp.formvalue('config') || '').trim();
            if (!sni || !ips) { box.textContent = _('Enter both the SNI hostname and the edge IPs first.'); return; }
            btn.disabled = true;
            box.textContent = _('Testing…');
            runHelper(['probe', sni].concat(ips.split(/[\s,;]+/).filter(Boolean))).then(function(out) {
                btn.disabled = false;
                var rows = out.split('\n').map(function(l) {
                    var p = l.trim().split(/\s+/);
                    return { ip: p[0], ms: parseInt(p[1], 10) || 0 };
                }).filter(function(r) { return r.ip; });
                rows.sort(function(a, b) { return (a.ms > 0 ? a.ms : 1e9) - (b.ms > 0 ? b.ms : 1e9); });
                box.innerHTML = '';
                if (!rows.length) { box.textContent = _('No result.'); return; }
                rows.forEach(function(r) {
                    box.appendChild(E('div', { 'style': 'color:' + (r.ms > 0 ? '#4fd88a' : '#e2645c') },
                        (r.ms > 0 ? '✅ ' : '❌ ') + r.ip + ' — ' + (r.ms > 0 ? r.ms + ' ms' : _('no TLS handshake'))));
                });
            });
        }

		var optClearLog = E('button', { 'class': 'psi-btn-ghost', 'click': function(ev) {
			ev.preventDefault();
			var box = document.getElementById('psiphon_live_log');
			if (box) { box.textContent = ''; box.appendChild(E('div', { 'style': 'color:#46505A;' }, _('Log monitor cleared'))); }
			if (self) self.logKey = null;
			fs.exec('/usr/bin/psiphon-helper', ['clearlog']);
		}}, _('Clear Log Screen'));

		var optLayoutFixer = s.option(form.DummyValue, '_layout_fixer');
		optLayoutFixer.rawhtml = true;
		optLayoutFixer.render = function() {
			setTimeout(function() {
				var node = document.querySelector('.cbi-section-node');
				if (!node) return;

				if (!document.getElementById('psiphon-js-grid')) {
					var topRow = node.querySelector('.psiphon-top-row');
					var leftColElements = [];
					var allChildren = Array.from(node.children);
					
					allChildren.forEach(function(child) {
						if (child !== topRow && child.id !== 'psiphon_right_panel_container') {
							leftColElements.push(child);
						}
					});

					var colLeftDiv = E('div', { 'class': 'psiphon-col-left' });
					leftColElements.forEach(function(el) { colLeftDiv.appendChild(el); });

					var trafficStatsWidget = E('div', { 'class': 'psiphon-card', 'style': 'background: linear-gradient(135deg, #1a1d22 0%, #232830 100%); padding: 10px 14px; border-radius: 8px; border: 1px solid #343b46; box-shadow: inset 0 1px 0 rgba(255,255,255,0.05);' }, [
						E('div', { 'style': 'font-weight: bold; color: #96a5ba; font-size: 13px; margin-bottom: 10px; display: flex; align-items: center; gap: 6px;' }, [
							E('span', { 'style': 'width: 8px; height: 8px; background: #4fd88a; border-radius: 50%; display: inline-block; box-shadow: 0 0 8px #4fd88a;' }),
							_('Tunnel Performance & Health Stats')
						]),
						E('div', { 'style': 'display: grid; grid-template-columns: repeat(4, 1fr); gap: 8px; font-family: monospace;' }, [
							E('div', { 'style': 'background: rgba(0,0,0,0.25); padding: 8px; border-radius: 6px; border: 1px solid rgba(255,255,255,0.03); text-align: center;' }, [
								E('div', { 'style': 'font-size: 10px; color: #92a0b0; text-transform: uppercase; margin-bottom: 2px;' }, _('ACTIVE TUNNELS')),
								E('span', { 'id': 'stat_tunnels_count', 'style': 'font-size: 14px; font-weight: bold; color: #fff;' }, '0')
							]),
							E('div', { 'style': 'background: rgba(79,216,138,0.05); padding: 8px; border-radius: 6px; border: 1px solid rgba(79,216,138,0.1); text-align: center;' }, [
								E('div', { 'style': 'font-size: 10px; color: #4fd88a; text-transform: uppercase; margin-bottom: 2px;' }, _('DOWNLOAD')),
								E('span', { 'id': 'stat_down_speed', 'style': 'font-size: 13px; font-weight: bold; color: #4fd88a;' }, '0.0 KB/s')
							]),
							E('div', { 'style': 'background: rgba(51,153,255,0.05); padding: 8px; border-radius: 6px; border: 1px solid rgba(51,153,255,0.1); text-align: center;' }, [
								E('div', { 'style': 'font-size: 10px; color: #5b9bd9; text-transform: uppercase; margin-bottom: 2px;' }, _('UPLOAD')),
								E('span', { 'id': 'stat_up_speed', 'style': 'font-size: 13px; font-weight: bold; color: #5b9bd9;' }, '0.0 KB/s')
							]),
							E('div', { 'style': 'background: rgba(255,204,0,0.05); padding: 8px; border-radius: 6px; border: 1px solid rgba(255,204,0,0.1); text-align: center;' }, [
								E('div', { 'style': 'font-size: 10px; color: #e0b34d; text-transform: uppercase; margin-bottom: 2px;' }, _('TOTAL TRAFFIC')),
								E('span', { 'id': 'stat_total_traffic', 'style': 'font-size: 13px; font-weight: bold; color: #e0b34d;' }, '0 B')
							])
						])
					]);

					var diagnosticsWidget = E('div', { 'class': 'psiphon-card', 'style': 'background: linear-gradient(135deg, #1a1d22 0%, #232830 100%); padding: 10px 14px; border-radius: 8px; border: 1px solid #343b46;' }, [
						E('div', { 'style': 'display: flex; justify-content: space-between; align-items: center; margin-bottom: 8px;' }, [
							E('div', { 'style': 'font-weight: bold; color: #96a5ba; font-size: 13px;' }, _('Router Network Latency')),
							E('span', { 'style': 'font-size: 10px; color: #46505A; background: rgba(0,0,0,0.3); padding: 2px 6px; border-radius: 4px;' }, _('Router-Side Diagnostics'))
						]),
						E('div', { 'style': 'display: grid; grid-template-columns: repeat(3, 1fr); gap: 6px; text-align: center;' }, [
							E('div', { 'style': 'background: rgba(0,0,0,0.3); padding: 8px; border-radius: 6px; border: 1px solid rgba(255,255,255,0.03);' }, [
								E('div', { 'style': 'font-size: 11px; color: #92a0b0; margin-bottom: 4px; font-weight: bold;' }, _('ICMP Ping')),
								E('div', { 'id': 'diag_icmp', 'style': 'font-family: monospace; font-size: 13px; color: #e0b34d;' }, '-')
							]),
							E('div', { 'style': 'background: rgba(0,0,0,0.3); padding: 8px; border-radius: 6px; border: 1px solid rgba(255,255,255,0.03);' }, [
								E('div', { 'style': 'font-size: 11px; color: #92a0b0; margin-bottom: 4px; font-weight: bold;' }, _('TLS Ping')),
								E('div', { 'id': 'diag_tcp', 'style': 'font-family: monospace; font-size: 13px; color: #4fd88a;' }, '-')
							]),
							E('div', { 'style': 'background: rgba(0,0,0,0.3); padding: 8px; border-radius: 6px; border: 1px solid rgba(255,255,255,0.03);' }, [
								E('div', { 'style': 'font-size: 11px; color: #92a0b0; margin-bottom: 4px; font-weight: bold;' }, _('URL Test')),
								E('div', { 'id': 'diag_url', 'style': 'font-family: monospace; font-size: 13px; color: #5b9bd9;' }, '-')
							])
						])
					]);

					var dnsLeakWidget = E('div', { 'class': 'psiphon-card', 'style': 'background: linear-gradient(135deg, #1a1d22 0%, #232830 100%); padding: 10px 14px; border-radius: 8px; border: 1px solid #343b46;' }, [
						E('div', { 'style': 'display: flex; justify-content: space-between; align-items: center; margin-bottom: 6px;' }, [
							E('div', { 'style': 'font-weight: bold; color: #e0b34d; font-size: 13px;' }, _('DNS Leak Test')),
							E('button', { 'class': 'btn', 'id': 'dns_leak_run_btn', 'style': 'padding: 3px 12px !important; font-size: 11px !important; height: auto !important; background: transparent !important; border: 1px solid #e0b34d !important; color: #e0b34d !important; border-radius: 4px; cursor: pointer;', 'click': function(ev) { ev.preventDefault(); runDnsLeakTest(); } }, _('Run'))
						]),
						E('div', { 'id': 'dns_leak_results', 'style': 'font-family: monospace; font-size: 12px; color: #92a0b0; line-height: 1.6; min-height: 20px;' }, _('Not tested yet — click Run, or it runs automatically after the first successful connection.'))
					]);

					var colRightDiv = E('div', { 'id': 'psiphon_right_panel_container', 'class': 'psiphon-col-right' }, [
						E('div', { 'style': 'display: flex; flex-direction: column; gap: 5px; flex: 1;' }, [
							E('div', { 'style': 'display: flex; justify-content: space-between; align-items: center;' }, [
								E('label', { 'style': 'font-weight: bold; color: #92a0b0; font-size: 13px;' }, _('Logs')),
								optClearLog
							]),
							E('div', { 'style': 'position: relative; flex: 1; min-height: 170px;' }, [
								E('div', { 'id': 'psiphon_live_log', 'class': 'psi-log', 'style': 'position: absolute; top: 0; left: 0; right: 0; bottom: 0; overflow: auto;' }, _('Waiting for log stream'))
							])
						]),
						dnsLeakWidget,
						trafficStatsWidget,
						diagnosticsWidget
					]);

					var bottomGridDiv = E('div', { 'id': 'psiphon-js-grid', 'class': 'psiphon-bottom-grid' }, [colLeftDiv, colRightDiv]);
					node.appendChild(bottomGridDiv);

					(function() {
						var cdnAcc = document.getElementById('psi-acc-cdn');
						if (!cdnAcc) return;

						var colLeft = node.querySelector('.psiphon-col-left');
						if (!colLeft) return;

						function findOpt(name) {
							var el = colLeft.querySelector('.cbi-value[data-name="' + name + '"]');
							if (el) return el;
							el = colLeft.querySelector('[data-name="' + name + '"]');
							if (el) {
								var w = el.closest ? el.closest('.cbi-value') : null;
								return w || el;
							}
							var inp = colLeft.querySelector('input[id$=".' + name + '"]');
							if (!inp) inp = colLeft.querySelector('select[id$=".' + name + '"]');
							if (inp) {
								var w2 = inp.closest ? inp.closest('.cbi-value') : null;
								return w2 || inp;
							}
							return null;
						}

						function group(accEl, bodyId, names) {
							var body = document.getElementById(bodyId);
							if (!body) return;
							names.forEach(function(n) {
								var el = findOpt(n);
								if (el && el.parentNode !== body && !accEl.contains(el)) {
									body.appendChild(el);
								}
							});
						}

						group(cdnAcc, 'psi-body-cdn', [
							'cdn_fronting', 'cdn_sni', 'cdn_edge_ips', 'cdn_probe',
							'_cdn_test', '_cdn_scan'
						]);

						function wireAccordion(acc, storageKey, badgeId, uciKey) {
							var hdr = acc.querySelector('.psi-acc-hdr');
							var badge = document.getElementById(badgeId);
							if (!hdr) return;

							function updateBadge() {
								if (!badge) return;
								var v = uci.get('psiphon', 'config', uciKey);
								var on = (v === '1' || v === 'on' || v === 'true' || v === 'yes');
								if (on) {
									badge.textContent = _('ON');
									badge.classList.add('on');
								} else {
									badge.textContent = _('OFF');
									badge.classList.remove('on');
								}
							}

							var saved = null;
							try { saved = localStorage.getItem(storageKey); } catch (e) {}
							if (saved === 'open') acc.classList.add('psi-open');

							hdr.addEventListener('click', function() {
								var open = acc.classList.toggle('psi-open');
								try { localStorage.setItem(storageKey, open ? 'open' : 'closed'); } catch (e) {}
							});

							var cb = acc.querySelector('input[id$=".' + uciKey + '"]')
								|| acc.querySelector('input[data-name="' + uciKey + '"]');
							if (cb) {
								cb.addEventListener('change', function() {
									if (!badge) return;
									if (cb.checked) {
										badge.textContent = _('ON');
										badge.classList.add('on');
									} else {
										badge.textContent = _('OFF');
										badge.classList.remove('on');
									}
								});
							}
							updateBadge();
						}

						wireAccordion(cdnAcc, 'psi-acc-cdn-state', 'psi-badge-cdn', 'cdn_fronting');

						(function() {
							var macc = document.getElementById('psi-acc-maint');
							if (!macc) return;
							var mh = macc.querySelector('.psi-acc-hdr');
							if (!mh) return;
							var ms = null;
							try { ms = localStorage.getItem('psi-acc-maint-state'); } catch (e) {}
							if (ms === 'open') macc.classList.add('psi-open');
							mh.addEventListener('click', function() {
								var o = macc.classList.toggle('psi-open');
								try { localStorage.setItem('psi-acc-maint-state', o ? 'open' : 'closed'); } catch (e) {}
							});
						})();
					})();

				}
			}, 50);
			return E('div', { 'style': 'display:none;' }, '');
		};

		function formatBytes(bytes) {
			if (!bytes || bytes < 0) return '0 B';
			var units = ['B', 'KB', 'MB', 'GB', 'TB'];
			var i = 0;
			var val = bytes;
			while (val >= 1024 && i < units.length - 1) { val /= 1024; i++; }
			return val.toFixed(i === 0 ? 0 : 1) + ' ' + units[i];
		}

		function updateDisplayElement(el, data, fallbackText, successColor) {
			if (!el) return;
			var addr = data && (data.query || data.ip);
			var okFlag = !data || data.success !== false;
			if (data && addr && okFlag) {
				var countryName = data.country || data.country_name || '';
				var cc = (data.countryCode || data.country_code || data.country_iso || '').toUpperCase();
				if (cc.length !== 2) {
					var _fb = (countryName || '').toUpperCase();
					cc = _fb.length === 2 ? _fb : '';
				}
				el.innerHTML = '';
				if (cc) {
					el.appendChild(E('span', {
						'style': 'font-size: 10px; font-weight: 700; color: #92a0b0; background: rgba(146,160,176,0.15); padding: 1px 5px; border-radius: 3px; margin-right: 4px; vertical-align: middle; letter-spacing: 0.3px;'
					}, cc));
				}
				var flagEmoji = self.flags[cc] || '';
				if (flagEmoji) el.appendChild(E('span', { 'class': 'win-flag', 'style': 'font-size: 16px; line-height: 1; vertical-align: middle;' }, flagEmoji));
				el.appendChild(E('b', { 'style': 'font-size: 14px; margin-left: 5px; vertical-align: middle; color: ' + (successColor || '#b8bfc7') }, ' ' + addr));
				if (countryName) el.appendChild(E('span', { 'style': 'color: #92a0b0; font-size: 11px; margin-left: 4px; vertical-align: middle;' }, '(' + countryName + ')'));
			} else {
				el.textContent = fallbackText;
			}
		}

		var HELPER = '/usr/bin/psiphon-helper';
		var STATE_STYLE = {
			connected:  { text: _('Connected'),   color: '#4fd88a', logo: '#02D16C' },
			connecting: { text: _('Connecting…'), color: '#e0b34d', logo: '#ffb020' },
			stopped:    { text: _('Stopped'),     color: '#92a0b0', logo: '#ff4800' },
			unknown:    { text: _('Checking'),    color: '#92a0b0', logo: '#ff4800' }
		};

		function runHelper(args) {
			return L.resolveDefault(fs.exec(HELPER, args), null).then(function(r) {
				return (r && r.stdout) ? r.stdout.trim() : '';
			});
		}

		function helperJSON(args) {
			return runHelper(args).then(function(t) {
				try { return t ? JSON.parse(t) : null; } catch (e) { return null; }
			});
		}

		function psiBarSet(kind) {
			var fill = document.getElementById('psi-bar-fill');
			if (!fill) return;
			var prev = self.barKind;
			if (kind === 'connecting') {
				self.barW = (prev === 'connecting') ? Math.min(92, (self.barW || 6) + (92 - (self.barW || 6)) * 0.18) : 6;
				fill.className = 'psi-bar-fill up busy';
				fill.style.width = self.barW + '%';
			} else if (kind === 'connected') {
				self.barW = 100;
				fill.className = 'psi-bar-fill up done';
				fill.style.width = '100%';
			} else {
				self.barW = 0;
				fill.className = (prev === 'connected' || prev === 'connecting') ? 'psi-bar-fill down' : 'psi-bar-fill';
				fill.style.width = '0%';
			}
			self.barKind = kind;
		}

		function setState(kind) {
			psiBarSet(kind);
			var st = STATE_STYLE[kind] || STATE_STYLE.unknown;
			var elState = document.getElementById('state_display');
			var elLogo = document.getElementById('psiphon-dynamic-logo');
			if (elState) { elState.textContent = st.text; elState.style.color = st.color; }
			if (elLogo && self.logoColor !== st.logo) { elLogo.innerHTML = getLogoSvg(st.logo, st.logo); self.logoColor = st.logo; }
		}

		function refreshStatus() {
			return helperJSON(['status']).then(function(st) {
				if (!st) return null;
				self.socksPort = (st.port > 0) ? st.port : null;
				st.connected = !!(st.running && st.tunnels > 0 && st.port > 0);
				setState(st.connected ? 'connected' : (st.running ? 'connecting' : 'stopped'));

				var protoEl = document.getElementById('protocol_display');
				if (protoEl) {
				    if (st.connected && st.protocol) {
				        protoEl.textContent = st.protocol;
				        protoEl.style.display = 'inline-block';
				    } else {
				        protoEl.style.display = 'none';
				    }
				}
				var tc = document.getElementById('stat_tunnels_count');
				if (tc) tc.textContent = st.tunnels || 0;
				var tt = document.getElementById('stat_total_traffic');
				if (tt) tt.textContent = formatBytes((st.rx || 0) + (st.tx || 0));
				return st;
			});
		}

		function refreshIPs(force) {
			if (self.ipBusy && !force) return;
			self.ipBusy = true;

			var elReal = document.getElementById('real_ip_display');
			var elVpn = document.getElementById('vpn_ip_display');

			refreshStatus().then(function(st) {
				if (!st) return;
				var now = Date.now();
				var jobs = [];

				var needReal = force || !self.lastRealGeo || (now - (self.realAt || 0) > (st.connected ? 600000 : 60000));
				if (needReal && (force || now - (self.realTry || 0) > 15000)) {
					self.realTry = now;
					jobs.push(helperJSON(['realip']).then(function(geo) {
						if (geo) { self.lastRealGeo = geo; self.realAt = Date.now(); }
					}));
				}

				if (!st.connected) {
					self.lastVpnGeo = null;
					self.vpnTry = 0;
					self.dnsLeakTestDone = false;
					self.wasConnected = false;
				} else {
					var needVpn = force || !self.wasConnected || !self.lastVpnGeo || (now - (self.vpnAt || 0) > 300000);
					if (needVpn && (force || now - (self.vpnTry || 0) > 15000)) {
						self.vpnTry = now;
						jobs.push(helperJSON(['vpnip']).then(function(geo) {
							if (geo) { self.lastVpnGeo = geo; self.vpnAt = Date.now(); }
						}));
					}
					self.wasConnected = true;
				}

				return Promise.all(jobs).then(function() {
					if (self.lastRealGeo) updateDisplayElement(elReal, self.lastRealGeo, _('Unknown'));
					else if (elReal) elReal.textContent = _('Unknown');

					if (!elVpn) return;
					if (!st.running) {
						elVpn.textContent = _('Disconnected');
					} else if (!st.connected) {
						elVpn.textContent = _('Connecting…');
					} else if (self.lastVpnGeo) {
						updateDisplayElement(elVpn, self.lastVpnGeo, _('Disconnected'), '#4fd88a');
						if (!self.dnsLeakTestDone) {
							self.dnsLeakTestDone = true;
							setTimeout(runDnsLeakTest, 15000);
						}
					} else {
						elVpn.textContent = _('Tunnel is up - IP lookup failed');
					}
				});
			}).then(function() { self.ipBusy = false; }, function() { self.ipBusy = false; });
		}

		function runDnsLeakTest() {
			var box = document.getElementById('dns_leak_results');
			var btn = document.getElementById('dns_leak_run_btn');
			if (!box) return;
			box.textContent = _('Testing…');
			box.style.color = '#92a0b0';
			if (btn) btn.disabled = true;

			helperJSON(['dnsleak']).then(function(r) {
				if (btn) btn.disabled = false;
				if (!r) { box.textContent = _('Test failed to run.'); box.style.color = '#e2645c'; return; }

				var geo = r.geo || null;
				var rCC = geo ? String(geo.country_code || geo.countryCode || '').toUpperCase() : '';
				var rCountry = geo ? (geo.country || geo.country_name || '') : '';
				var realCC = self.lastRealGeo ? String(self.lastRealGeo.country_code || self.lastRealGeo.countryCode || '').toUpperCase() : '';
				var color = '#e0b34d';
				var lines = [];

				var dMode = r.mode || (r.upstreams ? 'udp' : 'none');
				var dPinned = (r.pinned === true || r.pinned === 'true');
				lines.push(_('Router DNS upstream') + ': ' + (r.upstreams ? r.upstreams : _('ISP default (not tunnelled)')) + (dMode === 'doh' ? ' [DoH]' : ''));
				var dFlags = String(r.flags || '');
				if (dFlags.indexOf('doh_inactive') >= 0)
					lines.push('⚠️ ' + _('DoH was requested but the DoH engine is not running - plain DNS resolvers are in use.'));
				if (dFlags.indexOf('foreign_upstream') >= 0)
					lines.push('⚠️ ' + _('Other DNS upstreams are active in dnsmasq') + ' (' + (r.foreign || '') + ') ' + _('- they are NOT tunnelled and may leak. Disable them (for example the system https-dns-proxy dnsmasq integration).'));
				if (r.resolver) {
					lines.push(_('Resolver seen by the internet') + ': ' + (self.flags[rCC] || '') + ' ' + r.resolver + (rCountry ? ' (' + rCountry + ')' : ''));
					if (dMode !== 'none' && dPinned && realCC && rCC && rCC === realCC) {
						lines.push('ℹ️ ' + _('DNS is routed through the tunnel, but the resolver is in the same country as your real IP (the tunnel exit may be in that country). Verify at browserleaks.com/dns.'));
						color = '#e0b34d';
					} else if (dMode !== 'none' && !dPinned) {
						lines.push('⚠️ ' + _('LEAK: the resolver route is NOT pinned to the tunnel - DNS leaves through your real WAN.'));
						color = '#e2645c';
					} else if (realCC && rCC && rCC === realCC) {
						lines.push('⚠️ ' + _('POSSIBLE leak (same country as your real IP) — verify from a LAN client at browserleaks.com/dns.'));
						color = '#e2645c';
					} else if (!r.upstreams) {
						lines.push('⚠️ ' + _('DNS is not routed through the tunnel (Full Tunnel + Psiphon/Custom DNS must be on).'));
						color = '#e2645c';
					} else {
						lines.push('ℹ️ ' + _('Resolver is in a different country and upstreams are tunnelled. Verify from a LAN client (browserleaks.com/dns) for confirmation.'));
						color = '#4fd88a';
					}
				} else {
					lines.push(_('Could not determine the active resolver.'));
				}

				if (dFlags && color === '#4fd88a') color = '#e0b34d';
				box.style.color = color;
				box.innerHTML = '';
				lines.forEach(function(l) { box.appendChild(E('div', {}, l)); });
				box.appendChild(E('div', { 'style': 'margin-top: 6px;' }, [
					E('a', { 'href': 'https://browserleaks.com/dns', 'target': '_blank', 'rel': 'noopener', 'style': 'color: #5b9bd9; font-size: 11px;' },
						_('Open full multi-resolver test in your browser') + ' →')
				]));
			});
		}

		function runClientSideDiagnostics() {
			['icmp', 'tcp', 'url'].forEach(function(k) {
				var el = document.getElementById('diag_' + k);
				if (el) el.textContent = '...';
				runHelper(['diag', k]).then(function(v) {
					var ms = parseFloat(v);
					if (el) el.textContent = (v && !isNaN(ms) && ms > 0) ? (Math.round(ms) + ' ms') : (k === 'url' ? 'Timeout' : 'Error');
				});
			});
		}

		var LOG_MAX = 250;
		var TAG_COLOR = { INFO:'#5b9bd9', CONN:'#3ed6d6', DNS:'#b78cff', SEC:'#6ea8fe', CDN:'#ff7ad9', OK:'#4fd88a', WARN:'#e0b34d', ERR:'#e2645c', SYS:'#46505A', CMD:'#46505A' };
		var MSG_COLOR = { err:'#ff7b72', warn:'#e0b34d', ok:'#4fd88a', info:'#c0c8d2', dim:'#46505A' };

		function logClassify(msg) {
			var lv = 'info', tag = 'INFO';
			if (/\bERROR\b|\bFAILED\b|\bINVALID\b|refusing|failed|not running|\u274C/.test(msg)) { lv = 'err'; tag = 'ERR'; }
			else if (/warning|Skipping|Retrying|Timeout|backoff|fail-open|fail-closed|hint:|stays closed/i.test(msg)) { lv = 'warn'; tag = 'WARN'; }
			else {
				if (/\bdns\b|dns_|\bdoh\b|resolver/i.test(msg)) tag = 'DNS';
				else if (/\bcdn\b/i.test(msg)) tag = 'CDN';
				else if (/kill.?switch|ipv6|strict|\bmss\b|\bmtu\b|policy/i.test(msg)) tag = 'SEC';
				else if (/tunnel|socks|http proxy|region|trying|connected|tun0|routing|core pid/i.test(msg)) tag = 'CONN';
				if (/\u2705|\bConnected\b|\bOK\b|listening|restored|enabled|applied|written/.test(msg) && !/Tunnels Count 0/.test(msg)) lv = 'ok';
			}
			return { lv: lv, tag: tag };
		}

		function logParse(line) {
			var m = /^\[(\d\d:\d\d:\d\d)\]\s?(.*)$/.exec(line);
			if (m) { var c = logClassify(m[2]); return { time: m[1], tag: c.tag, lv: c.lv, msg: m[2] }; }
			m = /^\[(System|psiphon)\]\s?(.*)$/.exec(line);
			if (m) {
				var c2 = logClassify(m[2]);
				if (m[1] === 'System' && c2.lv === 'info') c2.tag = 'SYS';
				return { time: '', tag: c2.tag, lv: c2.lv, msg: m[2] };
			}
			if (line.charAt(0) === '$') return { time: '', tag: 'CMD', lv: 'dim', msg: line };
			var c3 = logClassify(line);
			return { time: '', tag: c3.tag, lv: c3.lv, msg: line };
		}

		function logMsgNodes(msg, color) {
			var out = [], parts = msg.split(/(\b\d{1,3}(?:\.\d{1,3}){3}(?::\d+)?\b)/);
			for (var i = 0; i < parts.length; i++) {
				if (!parts[i]) continue;
				if (i % 2) out.push(E('span', { 'class': 'ip' }, parts[i]));
				else out.push(E('span', { 'style': 'color:' + color + ';' }, parts[i]));
			}
			return out;
		}

		function renderLog(lines) {
			var box = document.getElementById('psiphon_live_log');
			if (!box) return;
			if (lines.length > LOG_MAX) lines = lines.slice(lines.length - LOG_MAX);
			var key = lines.join('\n');
			if (self.logKey === key) return;
			var first = (self.logKey === undefined);
			self.logKey = key;
			var atBottom = first || (box.scrollHeight - box.scrollTop <= box.clientHeight + 24);

			var entries = [];
			lines.forEach(function(l) {
				var e = logParse(l), last = entries[entries.length - 1];
				if (last && last.tag === e.tag && last.msg === e.msg) { last.n++; if (e.time) last.time = e.time; }
				else { e.n = 1; entries.push(e); }
			});

			var frag = document.createDocumentFragment();
			entries.forEach(function(e) {
				var kids = [
					E('span', { 'class': 't' }, e.time ? e.time : ''),
					E('span', { 'class': 'g', 'style': 'color:' + (TAG_COLOR[e.tag] || '#5b9bd9') + ';' }, e.tag)
				].concat(logMsgNodes(e.msg, MSG_COLOR[e.lv] || MSG_COLOR.info));
				if (e.n > 1) kids.push(E('span', { 'class': 'x' }, '\u00d7' + e.n));
				frag.appendChild(E('div', { 'class': 'psi-ll' }, kids));
			});
			box.textContent = '';
			box.appendChild(frag);
			if (atBottom) box.scrollTop = box.scrollHeight;
		}

		function renderLogMsg(text) {
			var box = document.getElementById('psiphon_live_log');
			if (!box) return;
			self.logKey = '\u0000' + text;
			box.textContent = '';
			box.appendChild(E('div', { 'style': 'color:#46505A;' }, text));
		}

		function fetchLog() {
			var logArea = document.getElementById('psiphon_live_log');
			if (!logArea || document.hidden) return Promise.resolve();

			return runHelper(['taillog']).then(function(res) {
				if (!res) { renderLogMsg(_('Service stopped or log empty')); return; }

				var lines = res.split('\n');
				var filteredLog = [];
				var prevBT = null;
				var latestRateDown = null, latestRateUp = null;

				for (var i = 0; i < lines.length; i++) {
					var line = lines[i].trim();
					if (line === '') continue;

					if (line.startsWith('[System]') || line.startsWith('[psiphon]') || line.startsWith('$')) {
						if (line.indexOf('Stopping Psiphon') !== -1) { prevBT = null; latestRateDown = latestRateUp = '0.0'; }
						filteredLog.push(line);
						continue;
					}

					try {
						var logObj = JSON.parse(line);
						var time = logObj.timestamp ? logObj.timestamp.substring(11, 19) : '';
						var timePrefix = time ? '[' + time + '] ' : '';

						if (logObj.noticeType === 'ListeningSocksProxyPort') {
							filteredLog.push(timePrefix + 'SOCKS proxy listening on random port ' + logObj.data.port);
						} else if (logObj.noticeType === 'ListeningHttpProxyPort') {
							filteredLog.push(timePrefix + 'HTTP proxy listening on random port ' + logObj.data.port);
						} else if (logObj.noticeType === 'ConnectedServerRegion') {
							filteredLog.push(timePrefix + 'Connected to server region ' + logObj.data.serverRegion);
						} else if (logObj.noticeType === 'Tunnels') {
							filteredLog.push(timePrefix + 'Tunnels Count ' + logObj.data.count);
						} else if (logObj.noticeType === 'BytesTransferred') {
							var btTime = logObj.timestamp ? Date.parse(logObj.timestamp) : NaN;
							if (prevBT && !isNaN(btTime) && btTime > prevBT.time) {
								var dt = (btTime - prevBT.time) / 1000;
								latestRateDown = (logObj.data.received / 1024 / dt).toFixed(1);
								latestRateUp = (logObj.data.sent / 1024 / dt).toFixed(1);
							}
							prevBT = { time: btTime };
						} else if (logObj.noticeType === 'ClientRegion') {
							filteredLog.push(timePrefix + 'Current Internet Location ' + logObj.data.region);
						} else if (logObj.noticeType === 'SkipServerEntry') {
							filteredLog.push(timePrefix + 'Skipping Blocked Server IP');
						} else if (logObj.noticeType === 'EstablishTunnelTimeout') {
							filteredLog.push(timePrefix + 'Connection Timeout. Retrying...');
						} else if (logObj.noticeType === 'ConnectingServer') {
						    var d = logObj.data || {};
						    var proto = d.protocol || '?';
						    var se = d.serverEntry ? String(d.serverEntry) : '';
						    var sip = se.split(' ')[0] || '?';
						    filteredLog.push(timePrefix + '\u2192 trying ' + sip + ' via ' + proto);
						} else if (logObj.noticeType === 'ConnectedServer') {
						    var d = logObj.data || {};
						    var proto = d.protocol || '?';
						    var se = d.serverEntry ? String(d.serverEntry) : '';
						    var sip = se.split(' ')[0] || '?';
						    filteredLog.push(timePrefix + '\u2705 Connected: ' + sip + ' via ' + proto);
						}
					} catch (e) {
					}
				}

				var downEl = document.getElementById('stat_down_speed');
				var upEl = document.getElementById('stat_up_speed');
				if (downEl && latestRateDown !== null) downEl.textContent = latestRateDown + ' KB/s';
				if (upEl && latestRateUp !== null) upEl.textContent = latestRateUp + ' KB/s';

				if (filteredLog.length > 0) renderLog(filteredLog); else renderLogMsg(_('Standby'));
			});
		}

		setTimeout(function() {
			document.querySelectorAll('.psiphon-col-left select, .psiphon-col-left option').forEach(function(el) { el.classList.add('win-flag'); });
		}, 500);

		poll.add(L.bind(function() {
			refreshIPs(false);
			return fetchLog();
		}, this), 3);

		setTimeout(L.bind(function() { refreshIPs(true); fetchLog(); runClientSideDiagnostics(); }, this), 1000);

		return m.render();
	}
});
__PSI_EOF__
PSI_SETUP_TMP=$(mktemp /tmp/psiphon-setup.XXXXXX) || { echo "ERROR: mktemp failed" >&2; exit 1; }
_psi_exit_trap() {
	local _rc=$?
	rm -f "$PSI_SETUP_TMP"
	[ "$_rc" -ne 0 ] && { _psi_rollback "$_rc"; exit "$_rc"; }
	return "$_rc"
}
trap _psi_exit_trap EXIT
cat <<'__PSI_EOF__' > "$PSI_SETUP_TMP"
#!/bin/sh
set -e

if ! uci -q get firewall.psiphon >/dev/null 2>&1; then
	uci -q batch <<-EOF
		set firewall.psiphon=zone
		set firewall.psiphon.name='psiphon'
		set firewall.psiphon.input='REJECT'
		set firewall.psiphon.output='ACCEPT'
		set firewall.psiphon.forward='REJECT'
		set firewall.psiphon.masq='1'
		set firewall.psiphon.mtu_fix='1'
		set firewall.psiphon.device='tun0'
		set firewall.psiphon_forwarding=forwarding
		set firewall.psiphon_forwarding.src='lan'
		set firewall.psiphon_forwarding.dest='psiphon'
		commit firewall
	EOF
fi

_existing_cd=$(uci -q get dhcp.@dnsmasq[0].confdir 2>/dev/null) || true
if [ -z "$_existing_cd" ]; then
	uci -q set dhcp.@dnsmasq[0].confdir='/tmp/dnsmasq.d'
	uci -q commit dhcp || echo "WARN: dhcp commit failed (continuing)" >&2
else
	case "$_existing_cd" in
		/tmp/*|/var/*|/run/*) echo "INFO: dnsmasq confdir is $_existing_cd - the Psiphon DNS override will be written there" >&2 ;;
		*) echo "WARNING: dnsmasq confdir ($_existing_cd) is not on tmpfs - Psiphon will use /tmp/dnsmasq.d which dnsmasq will NOT read. Tunnelled DNS needs a tmpfs confdir." >&2 ;;
	esac
fi

if [ -f /usr/share/rpcd/acl.d/luci-app-psiphon.json ]; then
	rm -f /usr/share/rpcd/acl.d/luci-app-psiphon.json.old 2>/dev/null || true
fi
uci -q delete psiphon.config.route_dns || true
uci -q commit psiphon || echo "WARN: psiphon commit failed (continuing)" >&2

SUCONF=/etc/sysupgrade.conf
touch "$SUCONF" 2>/dev/null
[ -f "$SUCONF" ] && cp -p "$SUCONF" "$PSI_BACKUP_DIR/sysupgrade.conf" 2>/dev/null
for _f in /etc/config/psiphon /etc/init.d/psiphon /usr/bin/psiphon-helper \
          /etc/hotplug.d/iface/90-psiphon \
          /usr/share/luci/menu.d/luci-app-psiphon.json \
          /usr/share/rpcd/acl.d/luci-app-psiphon.json \
          /www/luci-static/resources/view/vpn/psiphon.js \
          /usr/bin/psiphon-core \
          /etc/psiphon \
          /etc/rc.d/S99psiphon; do
	grep -qxF "$_f" "$SUCONF" 2>/dev/null || echo "$_f" >> "$SUCONF"
done

chmod 755 /etc/init.d/psiphon /usr/bin/psiphon-helper 2>/dev/null
mkdir -p /tmp/dnsmasq.d /etc/psiphon
/etc/init.d/psiphon enable 2>/dev/null

if [ -z "$IPKG_INSTROOT" ]; then
	/etc/init.d/firewall reload >/dev/null 2>&1 || \
		echo "WARN: firewall reload returned non-zero (continuing)" >&2
	/etc/init.d/dnsmasq restart >/dev/null 2>&1 || \
		echo "WARN: dnsmasq restart returned non-zero (continuing)" >&2
	[ -x /usr/bin/psiphon-core ] || echo "luci-app-psiphon: /usr/bin/psiphon-core not found - install the Psiphon core binary (see README)." >&2
fi
exit 0
__PSI_EOF__
export PSI_BACKUP_DIR
echo "Applying setup (firewall zone, dnsmasq conf-dir, service)..."
export PSI_BACKUP_DIR
if ! sh "$PSI_SETUP_TMP"; then
	echo "ERROR: setup phase failed - rolling back." >&2
	exit 1
fi
rm -f "$PSI_SETUP_TMP"
rm -rf /tmp/luci-indexcache* /tmp/luci-modulecache/ /var/luci-indexcache*
/etc/init.d/rpcd restart >/dev/null 2>&1 || true
/etc/init.d/uhttpd restart >/dev/null 2>&1 || true
/etc/init.d/firewall reload >/dev/null 2>&1 || true
chmod +x /etc/init.d/psiphon
if /etc/init.d/psiphon restart >/dev/null 2>&1; then
	sleep 4
	if [ "$(uci -q get psiphon.config.enabled)" = "1" ]; then
		if /usr/bin/psiphon-helper status 2>/dev/null | grep -q '"running":1'; then
			echo "Post-install: psiphon-core is running."
		else
			echo "WARNING: psiphon-core is NOT running - see: logread | grep psiphon ; cat /tmp/psiphon.log" >&2
		fi
	else
		echo "Post-install: installed; service is disabled (enable it from LuCI)."
	fi
else
	echo "WARNING: /etc/init.d/psiphon restart returned non-zero - check logs." >&2
fi
trap - EXIT
rm -rf "$PSI_BACKUP_DIR"
echo "Done. Open LuCI > VPN > Psiphon VPN."
