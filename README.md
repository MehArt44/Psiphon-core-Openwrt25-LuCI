**پارسی** | [English](README.en.md)

راهنمای جامع نصب، راه‌اندازی و خودکارسازی Psiphon-Core به همراه پنل گرافیکی LuCI در OpenWrt 25
این پروژه یک راهنمای کاملاً بومی و عملیاتی برای کامپایل، کانفیگ و اتصال هسته لینوکسی سایفون (psiphon-core) به رابط کاربری گرافیکی لوسی (LuCI JavaScript) در سیستم‌عامل OpenWrt 25 است. تمامی کلیدهای کنترل سرویس، فیلدهای تنظیمات (پورت‌ها، کشور، پروتکل) و بخش مانیتورینگ وضعیت آی‌پی کاملاً همگام‌سازی شده‌اند. بدون سربار روی رم و سی پی یو روتر


## 🚀 آموزش نصب آسان (Installation)

برای نصب سریع، کافیست از طریق نرم‌افزارهای SSH (مانند PuTTY یا Terminal) به روتر خود متصل شوید و دستور زیر را اجرا کنید:
:

```bash

wget -O /tmp/install.sh https://raw.githubusercontent.com/MehArt44/Psiphon-core-Openwrt25-LuCI/main/install.sh

sh /tmp/install.sh



```



## 🚀 آموزش نصب دستی (Installation)


# 🛠️ ۱. دانلود فایل مناسب روتر از بخش Releases
شناسایی معماری روتر دستور زیر در روتر بزنید

```bash

uname -m

```


# 🚀 ۲. انتقال فایل‌ها به روتر

پس از اتمام کامپایل، فایل خروجی `psiphon-core` و پوشه `psiphon_data` را از طریق ابزارهایی مانند MobaXterm یا SCP به مسیرهای زیر روی روتر منتقل کنید 
اگر کام
```bash
 `/usr/bin/psiphon-core`
```

# 📁 ۳. استقرار زیرساخت و کدهای کامل پنل گرافیکی

فایل Psiphon VPN 2.0.40.sh به پوشه زیر
 منتقل کنید و دستور زیر بدید
"/tmp/Psiphon VPN 2.0.40.sh"

```bash

sh "/tmp/Psiphon VPN 2.0.40.sh"

```

GROUP 1-7

GROUP 1: Core Permissions & RPCD ACL
GROUP 2: Base UCI Configuration (Optimized with Batch)
GROUP 3: LuCI Menu Registration
GROUP 4: Init.d Script with Boltdb Logic (Procd Managed & Random Ports)
GROUP 5: Firewall and Routing Configurations
GROUP 6: LuCI Frontend (View Script) - Updated UI & Fixes
GROUP 7: Service Restart & Cache Cleanup

```bash
#!/bin/sh

# ==============================================================================
# GROUP 1: Core Permissions & RPCD ACL
# ==============================================================================
echo "Creating LuCI RPCD Access Permissions..."

chmod +x /usr/bin/psiphon-core
mkdir -p /etc/psiphon
mkdir -p /usr/share/rpcd/acl.d/

cat << 'EOF' > /usr/share/rpcd/acl.d/luci-app-psiphon.json
{
	"luci-app-psiphon": {
		"description": "Grant execution rights for Psiphon service controls",
		"read": {
			"cgi-io": [ "exec" ],
			"file": {
				"/tmp/psiphon.log": [ "read" ],
				"/etc/psiphon/psiphon.config": [ "read" ],
				"/etc/init.d/psiphon": [ "exec" ]
			},
			"ubus": {
				"file": [ "exec", "read" ]
			}
		},
		"write": {
			"file": {
				"/tmp/psiphon.log": [ "write" ],
				"/etc/init.d/psiphon": [ "exec" ],
				"/bin/sh": [ "exec" ]
			}
		}
	}
}
EOF

# ==============================================================================
# GROUP 2: Base UCI Configuration (Optimized with Batch)
# ==============================================================================
echo "Creating base config file..."

touch /etc/config/psiphon
uci -q batch <<-EOF
	set psiphon.config=psiphon
	set psiphon.config.enabled='0'
	set psiphon.config.tun='0'
	set psiphon.config.kill_switch='0'
	set psiphon.config.route_ipv6='0'
	set psiphon.config.route_dns='0'
	set psiphon.config.dns_enabled='0'
	set psiphon.config.psiphon_dns='1'
	set psiphon.config.force_router_dns='1'
	set psiphon.config.transport='STANDARD'
	set psiphon.config.dns_preset='comodo'
	set psiphon.config.beast_mode='0'
	set psiphon.config.cdn_edge_ips=''
	set psiphon.config.cdn_sni=''
	commit psiphon
EOF

# ==============================================================================
# GROUP 3: LuCI Menu Registration
# ==============================================================================
echo "Creating LuCI menu entry under VPN..."

mkdir -p /usr/share/luci/menu.d/
cat << 'EOF' > /usr/share/luci/menu.d/luci-app-psiphon.json
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
EOF

# ==============================================================================
# GROUP 4: Init.d Script with Boltdb Logic (Procd Managed & Random Ports)
# ==============================================================================
echo "Generating Init.d script with smart procd management..."

cat << 'EOF' > /etc/init.d/psiphon
#!/bin/sh /etc/rc.common

START=99
STOP=10
USE_PROCD=1

PROG="/usr/bin/psiphon-core"
DATA_DIR="/etc/psiphon"
CONFIG_FILE="$DATA_DIR/psiphon.config"
LOG_FILE="/tmp/psiphon.log"
DNSMASQ_PSIPHON_CONF="/tmp/dnsmasq.d/psiphon_dns.conf"

NAT_CHAIN="psiphon_dns_nat"
BLOCK_CHAIN="psiphon_dns_block"

get_wan_if() {
    ip route show default 2>/dev/null | grep -v tun0 | awk '{print $5}' | head -n 1
}

ensure_chains() {
    iptables -t nat -N "$NAT_CHAIN" 2>/dev/null
    iptables -t nat -C PREROUTING -j "$NAT_CHAIN" 2>/dev/null || iptables -t nat -I PREROUTING -j "$NAT_CHAIN"
    iptables -t nat -C OUTPUT -j "$NAT_CHAIN" 2>/dev/null || iptables -t nat -I OUTPUT -j "$NAT_CHAIN"

    iptables -N "$BLOCK_CHAIN" 2>/dev/null
    iptables -C OUTPUT -j "$BLOCK_CHAIN" 2>/dev/null || iptables -I OUTPUT -j "$BLOCK_CHAIN"
    iptables -C FORWARD -j "$BLOCK_CHAIN" 2>/dev/null || iptables -I FORWARD -j "$BLOCK_CHAIN"
}

flush_chains() {
    iptables -t nat -F "$NAT_CHAIN" 2>/dev/null
    iptables -F "$BLOCK_CHAIN" 2>/dev/null
}


apply_psiphon_dns() {
    mkdir -p "$(dirname "$DNSMASQ_PSIPHON_CONF")"
    cat > "$DNSMASQ_PSIPHON_CONF" << 'DNSCONF'
no-resolv
server=1.1.1.1
server=8.8.8.8
DNSCONF
    kill -HUP "$(pgrep dnsmasq)" 2>/dev/null
    echo "[psiphon] dnsmasq redirected through tunnel (1.1.1.1, 8.8.8.8 via tun0)" >> "$LOG_FILE"
}

restore_dnsmasq() {
    rm -f "$DNSMASQ_PSIPHON_CONF"
    kill -HUP "$(pgrep dnsmasq)" 2>/dev/null
    echo "[psiphon] dnsmasq DNS restored to default" >> "$LOG_FILE"
}

stop_service() {
    echo "[System] Stopping Psiphon..." > "$LOG_FILE"

    restore_dnsmasq

    ip rule del iif br-lan lookup 100 2>/dev/null
    ip route flush table 100 2>/dev/null
    ip link delete tun0 2>/dev/null
    ip route del default dev tun0 metric 1 2>/dev/null

    flush_chains
}

apply_dns_rules() {
    dns_enabled="$1" dns1="$2" psiphon_dns="$3" force_router_dns="$4"

    ensure_chains
    flush_chains

    if [ "$force_router_dns" -eq 1 ] && { { [ "$dns_enabled" -eq 1 ] && [ -n "$dns1" ]; } || [ "$psiphon_dns" -eq 1 ]; }; then
        WAN_IF=$(get_wan_if)
        if [ -n "$WAN_IF" ]; then
            if [ "$dns_enabled" -eq 1 ] && [ -n "$dns1" ]; then
                iptables -A "$BLOCK_CHAIN" -o "$WAN_IF" ! -d "$dns1" -p udp --dport 53 -j REJECT 2>/dev/null
                iptables -A "$BLOCK_CHAIN" -o "$WAN_IF" ! -d "$dns1" -p tcp --dport 53 -j REJECT 2>/dev/null
            else
                iptables -A "$BLOCK_CHAIN" -o "$WAN_IF" -p udp --dport 53 -j REJECT 2>/dev/null
                iptables -A "$BLOCK_CHAIN" -o "$WAN_IF" -p tcp --dport 53 -j REJECT 2>/dev/null
            fi
        fi
    fi

    if [ "$dns_enabled" -eq 1 ] && [ -n "$dns1" ]; then
        iptables -t nat -A "$NAT_CHAIN" -i br-lan -p udp --dport 53 -j DNAT --to-destination "$dns1" 2>/dev/null
        iptables -t nat -A "$NAT_CHAIN" -i br-lan -p tcp --dport 53 -j DNAT --to-destination "$dns1" 2>/dev/null
        iptables -t nat -A "$NAT_CHAIN" ! -d 127.0.0.0/8 -p udp --dport 53 -j DNAT --to-destination "$dns1" 2>/dev/null
        iptables -t nat -A "$NAT_CHAIN" ! -d 127.0.0.0/8 -p tcp --dport 53 -j DNAT --to-destination "$dns1" 2>/dev/null
    fi
}

json_escape() {
    printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

start_service() {
    stop_service

    config_load psiphon

    local enabled tun dns_enabled psiphon_dns dns1 dns2 dns3 dns4 country transport
    local beast_mode cdn_edge_ips cdn_sni force_router_dns
    config_get_bool enabled "config" "enabled" 0
    config_get_bool tun "config" "tun" 0
    config_get_bool dns_enabled "config" "dns_enabled" 0
    config_get_bool psiphon_dns "config" "psiphon_dns" 1
    config_get_bool force_router_dns "config" "force_router_dns" 1
    config_get country "config" "country" ""
    config_get transport "config" "transport" "STANDARD"
    config_get dns1 "config" "dns1" ""
    config_get dns2 "config" "dns2" ""
    config_get dns3 "config" "dns3" ""
    config_get dns4 "config" "dns4" ""
    config_get_bool beast_mode "config" "beast_mode" 0
    config_get cdn_edge_ips "config" "cdn_edge_ips" ""
    config_get cdn_sni "config" "cdn_sni" ""

    [ "$enabled" -eq 1 ] || return 0

    mkdir -p "$DATA_DIR"

    DB_DIR="$DATA_DIR/ca.psiphon.PsiphonTunnel.tunnel-core/datastore"
    DB_FILE="$DB_DIR/psiphon.boltdb"
    BK_FILE="$DB_DIR/psiphon.boltdb.backup"

    mkdir -p "$DB_DIR"

    if [ -f "$BK_FILE" ]; then
        if [ ! -f "$DB_FILE" ]; then
            cp -f "$BK_FILE" "$DB_FILE"
        else
            DB_SIZE=$(wc -c < "$DB_FILE" 2>/dev/null || echo 0)
            [ "$DB_SIZE" -lt 5000 ] && cp -f "$BK_FILE" "$DB_FILE"
        fi
    fi

    EXTRA=""
    [ -n "$country" ] && EXTRA="$EXTRA,\"EgressRegion\":\"$(json_escape "$country")\""

    if [ -n "$transport" ]; then
        upper_transport=$(echo "$transport" | tr '[:lower:]' '[:upper:]')
        EXTRA="$EXTRA,\"Transport\":\"$upper_transport\""
        case "$upper_transport" in
            QUIC) protos='["QUIC-OSSH"]' ;;
            SSH)  protos='["SSH","OSSH"]' ;;
            TLS)  protos='["FRONTED-MEEK-OSSH","TLS-OSSH"]' ;;
            *)    protos="" ;;
        esac
        [ -n "$protos" ] && EXTRA="$EXTRA,\"LimitTunnelProtocols\":$protos"
    fi

    if [ "$dns_enabled" -eq 1 ]; then
        dns_list=""
        [ -n "$dns1" ] && dns_list="$dns1"
        [ -n "$dns2" ] && dns_list="${dns_list:+$dns_list,}$dns2"
        [ -n "$dns3" ] && dns_list="${dns_list:+$dns_list,}$dns3"
        [ -n "$dns4" ] && dns_list="${dns_list:+$dns_list,}$dns4"
        [ -n "$dns_list" ] && EXTRA="$EXTRA,\"UpstreamDNSServer\":\"$(json_escape "$dns_list")\""
    elif [ "$psiphon_dns" -eq 1 ]; then
        :
    fi

    if [ "$beast_mode" -eq 1 ]; then
        EXTRA="$EXTRA,\"BeastMode\":true"
    else
        EXTRA="$EXTRA,\"BeastMode\":false"
    fi

    [ -n "$cdn_edge_ips" ] && EXTRA="$EXTRA,\"CdnFrontingCustomIpList\":\"$(json_escape "$cdn_edge_ips")\""
    [ -n "$cdn_sni" ] && EXTRA="$EXTRA,\"CdnFrontingCustomSni\":\"$(json_escape "$cdn_sni")\""

    cat << JSON > "$CONFIG_FILE"
{
  "DataRootDirectory": "$DATA_DIR",
  "DisableIPv6": true,
  "PropagationChannelId": "0000000000000000",
  "SponsorId": "0000000000000000",
  "ServerEntrySignaturePublicKey": "",
  "UseIndistinguishableTLS": true,
  "ProtocolMode": "auto",
  "EmitDiagnosticNotices": true,
  "EmitBytesTransferred": true$EXTRA
}
JSON

    procd_open_instance "core"
    procd_set_param command $PROG -config "$CONFIG_FILE" -notices "$LOG_FILE"
    if [ "$tun" -eq 1 ]; then
        procd_append_param command -tunDevice tun0
    fi
    procd_set_param respawn 3600 5 5
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_close_instance

    procd_open_instance "watcher"
    procd_set_param command /bin/sh -c "
        while sleep 60; do
            if [ -f \"$DB_FILE\" ]; then
                DB_SIZE=\$(wc -c < \"$DB_FILE\" 2>/dev/null || echo 0)
                if [ \"\$DB_SIZE\" -gt 1048576 ]; then
                    cp -f \"$DB_FILE\" \"$BK_FILE.tmp\" && mv -f \"$BK_FILE.tmp\" \"$BK_FILE\"
                fi
            fi
        done
    "
    procd_close_instance

    if [ "$tun" -eq 1 ]; then
        (
            for _ in $(seq 1 20); do
                if ip link show tun0 >/dev/null 2>&1; then
                    ip link set tun0 up 2>/dev/null
                    ip rule add iif br-lan lookup 100 2>/dev/null
                    ip route replace default dev tun0 table 100 2>/dev/null

                    [ "$dns_enabled" -eq 1 ] && [ -n "$dns1" ] && ip route add "$dns1" dev tun0 2>/dev/null
                    [ "$dns_enabled" -eq 1 ] && [ -n "$dns2" ] && ip route add "$dns2" dev tun0 2>/dev/null

                    apply_dns_rules "$dns_enabled" "$dns1" "$psiphon_dns" "$force_router_dns"

                    if [ "$psiphon_dns" -eq 1 ] && [ "$dns_enabled" -eq 0 ]; then
                        ip route add 1.1.1.1/32 dev tun0 2>/dev/null
                        ip route add 8.8.8.8/32 dev tun0 2>/dev/null
                        apply_psiphon_dns
                    fi
                    break
                fi
                sleep 1
            done
        ) &
    else
        apply_dns_rules "$dns_enabled" "$dns1" "$psiphon_dns" "$force_router_dns"
    fi
}

reload_service() {
    start_service
}
EOF

# ==============================================================================
# GROUP 5: Firewall and Routing Configurations
# ==============================================================================
echo "Configuring Firewall Zones..."

for sec in $(uci show firewall | grep -E "name='psiphon'|dest='psiphon'|src='psiphon'" | cut -d. -f1,2); do
    uci -q delete "$sec"
done

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

# ==============================================================================
# GROUP 6: LuCI Frontend (View Script) - Updated UI & Fixes
# ==============================================================================
echo "Updating Psiphon View Script..."

mkdir -p /www/luci-static/resources/view/vpn/
cat << 'EOF' > /www/luci-static/resources/view/vpn/psiphon.js
'use strict';
'require view';
'require form';
'require fs';
'require ui';
'require uci';
'require poll';

return view.extend({
	router_ip: '192.168.18.1',
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
		return Promise.all([
			uci.load('network'),
			L.resolveDefault(fs.read('/tmp/psiphon.log'), '')
		]).then(L.bind(function(data) {
			var ip = uci.get('network', 'lan', 'ipaddr');
			if (ip) { this.router_ip = ip; }
			
			if (!document.getElementById('noto-emoji-font')) {
				var link = document.createElement('link');
				link.id = 'noto-emoji-font';
				link.rel = 'stylesheet';
				link.href = 'https://fonts.googleapis.com/css2?family=Noto+Color+Emoji&display=swap';
				document.head.appendChild(link);
				
				var style = document.createElement('style');
				style.innerHTML = `
					.win-flag { font-family: "Noto Color Emoji", "Segoe UI Emoji", sans-serif !important; }
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
					.psiphon-col-left .cbi-value-description { margin-top: 2px !important; font-size: 11px !important; color: #7c8ba0; line-height: 1.25; }
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
					.psi-btn-ghost{ border-radius:4px; padding:3px 10px; font-size:11px; font-weight:700;
						cursor:pointer; background:transparent; color:#e2645c; border:1px solid #e2645c; }
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
            'custom': ['', '', '', ''],
            'google': ['8.8.8.8', '8.8.4.4', '2001:4860:4860::8888', '2001:4860:4860::8844'],
            'opendns': ['208.67.222.222', '208.67.220.220', '2620:119:35::35', '2620:119:53::53'],
            'cloudflare': ['1.1.1.1', '1.0.0.1', '2606:4700:4700::1111', '2606:4700:4700::1001'],
            'norton': ['199.85.126.10', '199.85.127.10', '', ''],
            'comodo_sec': ['8.26.56.26', '8.20.247.20', '', ''],
            'comodo': ['156.154.70.22', '156.154.71.22', '', ''],
            'dns_watch': ['84.200.69.80', '84.200.70.40', '2001:1608:10:25::1c04:b12f', '2001:1608:10:25::9249:d69b'],
            'adguard_noblock': ['94.140.14.140', '94.140.15.150', '2a00:5a60::ad1:0ff', '2a00:5a60::ad2:0ff'],
            'adguard_block': ['94.140.14.14', '94.140.15.15', '2a00:5a60::bad1:0ff', '2a00:5a60::bad2:0ff'],
            'adguard_family': ['94.140.14.16', '94.140.14.17', '2a10:50c0::bad1:ff', '2a10:50c0::bad2:ff'],
            'quad9_sec': ['9.9.9.9', '149.112.112.112', '2620:fe::fe', '2620:fe::9'],
            'quad9_nosec': ['9.9.9.10', '149.112.112.10', '2620:fe::10', '2620:fe::fe:10']
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
				E('h2', { 'style': 'margin: 0; font-weight: bold; color: #fff; font-size: 20px; line-height: 1.2;' }, _('Psiphon VPN Configuration')),
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
				E('div', { 'style': 'display: flex; flex-flow: row wrap; align-items: center; justify-content: space-between; background: #1B2227; padding: 8px 16px; border-radius: 8px; border: 1px solid #383d45; box-shadow: 0 4px 6px rgba(0,0,0,0.3); width: 100%; gap: 12px;' }, [
					E('div', { 'style': 'display: flex; align-items: center; gap: 6px; flex: 0.8; min-width: 110px;' }, [
						E('span', { 'style': 'color: #92a0b0; font-size: 12px; text-transform: uppercase; font-weight: bold; flex-shrink: 0;' }, _('State')),
						E('span', { 'id': 'state_display', 'style': 'font-size: 13px; font-weight: bold; color: #92a0b0;' }, _('Checking'))
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
						E('button', { 'class': 'psi-btn psi-btn-refresh', 'style': 'white-space: nowrap;', 'click': function(ev) { ev.preventDefault(); refreshIPs(); } }, _('Refresh')),
						E('button', { 'class': 'psi-btn psi-btn-check', 'style': 'white-space: nowrap;', 'click': function(ev) { 
							ev.preventDefault(); 
							runClientSideDiagnostics(); 
						}}, _('Test Latency'))
					])
				])
			]);
		};

        var optControl = s.option(form.DummyValue, '_control_buttons');
        optControl.rawhtml = true;
        optControl.render = function() {
            var uiObj = (typeof ui !== 'undefined') ? ui : (L.ui || null);
            var startBtn, stopBtn;

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
                            if (uiObj) uiObj.addNotification(null, E('p', _('Restarting Psiphon service...')), 'info');

                            fs.exec('/bin/sh', ['-c', '/etc/init.d/psiphon restart >/dev/null 2>&1 &'])
                            .then(function() {
                                setTimeout(refreshIPs, 2000);
                            })
                            .finally(function() { setButtonsBusy(false); });
                        }
                    }, _('Start / Restart')),

                    stopBtn = E('button', {
                        'class': 'psi-btn psi-btn-stop',
                        'click': function(ev) {
                            ev.preventDefault();
                            setButtonsBusy(true);
                            if (uiObj) uiObj.addNotification(null, E('p', _('Stopping Psiphon service...')), 'info');

                            fs.exec('/bin/sh', ['-c', '/etc/init.d/psiphon stop >/dev/null 2>&1 &'])
                            .then(function() {
                                setTimeout(refreshIPs, 1000);
                            })
                            .finally(function() { setButtonsBusy(false); });
                        }
                    }, _('Stop'))
                ])
            ]);
        };

		var optEnabled = s.option(form.Flag, 'enabled', _('Auto Connect (Enable)'), _('Start Psiphon VPN automatically on boot.'));
		optEnabled.rmempty = false;
		
		var optTun = s.option(form.Flag, 'tun', _('Full Tunnel Mode'), _('Route all LAN traffic through Psiphon via tun2socks.'));
		optTun.rmempty = false;

        var optKill = s.option(form.Flag, 'kill_switch', _('Kill Switch'), _('Block LAN traffic when tunnel is down.'));
        optKill.rmempty = false;

        var optRoute6 = s.option(form.Flag, 'route_ipv6', _('Route IPv6'), _('Keep IPv6 inside policy route.'));
        optRoute6.rmempty = false;

        var optRouteDns = s.option(form.Flag, 'route_dns', _('Route DNS through tunnel'), _('Pin DNS servers to tunnel device.'));
        optRouteDns.rmempty = false;

		var optCountry = s.option(form.ListValue, 'country', _('Region'));
		optCountry.rmempty = true; optCountry.optional = true;
		optCountry.value('', '⚡ ' + _('Best Performance'));
		var countries = ['AT','BE','BG','CA','CH','CZ','DE','DK','EE','ES','FI','FR','GB','HU','IE','IN','IT','JP','LV','NL','NO','PL','RO','RS','SE','SG','SK','US'];
		countries.forEach(function(c) {
			var fullName = self.country_names[c] || c;
			optCountry.value(c, (self.flags[c] || '') + ' [' + c + '] ' + fullName);
		});

		var optTransport = s.option(form.ListValue, 'transport', _('Transport Mode'), _('Restricts tunnel protocol family.'));
		optTransport.value('STANDARD', _('Standard (auto)')); optTransport.value('QUIC', _('QUIC')); optTransport.value('SSH', _('SSH'));

        var optPsiphonDns = s.option(form.Flag, 'psiphon_dns', _('Use Psiphon DNS'), _('Route DNS queries through Psiphon\'s built-in resolver (port 40053), tunneled and censorship-resistant. Ignored if Custom DNS is enabled below.'));
        optPsiphonDns.rmempty = false;
        optPsiphonDns.default = '1';

        var dnsEnable = s.option(form.Flag, 'dns_enabled', _('Enable Custom DNS'), _('Override Psiphon DNS with your own upstream servers.'));
        dnsEnable.rmempty = false;

        var optForceDns = s.option(form.Flag, 'force_router_dns', _('Strict DNS Enforcement'), _('Extra hardening: block raw port-53 traffic that tries to bypass the router\'s DNS entirely. DNS routing itself (Psiphon/Custom) is always active regardless of this option.'));
        optForceDns.rmempty = false;

        var dnsPreset = s.option(form.ListValue, 'dns_preset', _('DNS Server Preset'));
        dnsPreset.depends('dns_enabled', '1');
        dnsPreset.value('custom', _('Custom (edit manually)'));
        dnsPreset.value('google', 'Google Public DNS');
        dnsPreset.value('opendns', 'OpenDNS');
        dnsPreset.value('cloudflare', 'Cloudflare');
        dnsPreset.value('norton', 'Norton ConnectSafe Basic');
        dnsPreset.value('comodo_sec', 'Comodo Secure');
        dnsPreset.value('comodo', 'Comodo');
        dnsPreset.value('dns_watch', 'DNS WATCH');
        dnsPreset.value('adguard_noblock', 'AdGuard (No Block)');
        dnsPreset.value('adguard_block', 'AdGuard (Block)');
        dnsPreset.value('adguard_family', 'AdGuard (Family)');
        dnsPreset.value('quad9_sec', 'Quad9 Security');
        dnsPreset.value('quad9_nosec', 'Quad9 No Security');

        var dns1 = s.option(form.Value, 'dns1', _('DNS 1'));
        dns1.depends('dns_enabled', '1');
        dns1.placeholder = '156.154.70.22';
        dns1.rmempty = true;

        var dns2 = s.option(form.Value, 'dns2', _('DNS 2'));
        dns2.depends('dns_enabled', '1');
        dns2.placeholder = '156.154.71.22';
        dns2.rmempty = true;

        var dns3 = s.option(form.Value, 'dns3', _('DNS 3'));
        dns3.depends('dns_enabled', '1');
        dns3.placeholder = 'Optional IPv4 or IPv6';
        dns3.rmempty = true;

        var dns4 = s.option(form.Value, 'dns4', _('DNS 4'));
        dns4.depends('dns_enabled', '1');
        dns4.placeholder = 'Optional IPv4 or IPv6';
        dns4.rmempty = true;

        dnsPreset.onchange = function(ev, section_id, value) {
            if (dnsMap[value]) {
                var fields = ['dns1', 'dns2', 'dns3', 'dns4'];
                for (var i = 0; i < 4; i++) {
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

        var optCdnSni = s.option(form.Value, 'cdn_sni', _('CDN SNI hostname'), _('Hostname pinned to edge IPs.')); 
        optCdnSni.rmempty = true;
        optCdnSni.placeholder = 'e.g., cdn.example.com';
        
        var optCdnIp = s.option(form.Value, 'cdn_edge_ips', _('CDN edge IPs'), _('Comma separated edge IPs.')); 
        optCdnIp.rmempty = true;
        optCdnIp.placeholder = 'e.g., 1.1.1.1,1.0.0.1';

		var optClearLog = E('button', { 'class': 'psi-btn-ghost', 'click': function(ev) {
			ev.preventDefault();
			var box = document.getElementById('psiphon_live_log');
			if (box) box.value = _('Log monitor cleared');
			fs.exec('/bin/sh', ['-c', '> /tmp/psiphon.log || true']);
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
							E('span', { 'style': 'font-size: 10px; color: #7c8ba0; background: rgba(0,0,0,0.3); padding: 2px 6px; border-radius: 4px;' }, _('Router-Side Diagnostics'))
						]),
						E('div', { 'style': 'display: grid; grid-template-columns: repeat(3, 1fr); gap: 6px; text-align: center;' }, [
							E('div', { 'style': 'background: rgba(0,0,0,0.3); padding: 8px; border-radius: 6px; border: 1px solid rgba(255,255,255,0.03);' }, [
								E('div', { 'style': 'font-size: 11px; color: #92a0b0; margin-bottom: 4px; font-weight: bold;' }, _('ICMP Ping')),
								E('div', { 'id': 'diag_icmp', 'style': 'font-family: monospace; font-size: 13px; color: #e0b34d;' }, '-')
							]),
							E('div', { 'style': 'background: rgba(0,0,0,0.3); padding: 8px; border-radius: 6px; border: 1px solid rgba(255,255,255,0.03);' }, [
								E('div', { 'style': 'font-size: 11px; color: #92a0b0; margin-bottom: 4px; font-weight: bold;' }, _('TCP Ping')),
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
							E('textarea', { 'id': 'psiphon_live_log', 'style': 'width: 100%; flex: 1; min-height: 170px; font-family: monospace; font-size: 12px; background: #181b1f; color: #6b6b82; padding: 8px; border-radius: 4px; border: 1px solid #2b2f35; resize: none; line-height: 1.5; box-sizing: border-box;' }, _('Waiting for log stream'))
						]),
						dnsLeakWidget,
						trafficStatsWidget,
						diagnosticsWidget
					]);

					var bottomGridDiv = E('div', { 'id': 'psiphon-js-grid', 'class': 'psiphon-bottom-grid' }, [colLeftDiv, colRightDiv]);
					node.appendChild(bottomGridDiv);
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
				var cc = (data.countryCode || data.country_code || countryName || '').toUpperCase();
				el.innerHTML = '';
				var flagEmoji = self.flags[cc] || '';
				if (flagEmoji) el.appendChild(E('span', { 'class': 'win-flag', 'style': 'font-size: 16px; line-height: 1; vertical-align: middle;' }, flagEmoji));
				el.appendChild(E('b', { 'style': 'font-size: 14px; margin-left: 5px; vertical-align: middle; color: ' + (successColor || '#b8bfc7') }, ' ' + addr));
				if (countryName) el.appendChild(E('span', { 'style': 'color: #92a0b0; font-size: 11px; margin-left: 4px; vertical-align: middle;' }, '(' + countryName + ')'));
			} else {
				el.textContent = fallbackText;
			}
		}

		var GEO_URL = 'https://ipwho.is/';

		function refreshIPs() {
			var elState = document.getElementById('state_display');
			var elReal = document.getElementById('real_ip_display');
			var elVpn = document.getElementById('vpn_ip_display');
			var elLogo = document.getElementById('psiphon-dynamic-logo');

			var isPrivate = "case \"$ip\" in 10.*|192.168.*|172.1[6-9].*|172.2[0-9].*|172.3[0-1].*|100.6[4-9].*|100.[7-9][0-9].*|100.1[0-1][0-9].*|100.12[0-7].*|127.*|\"\") continue ;; esac;";
			var wanLookup =
				"WAN_DEV=$(uci -q get network.wan.device 2>/dev/null); " +
				"[ -z \"$WAN_DEV\" ] && WAN_DEV=$(ubus call network.interface.wan status 2>/dev/null | jsonfilter -e '@.l3_device' 2>/dev/null); " +
				"WAN_IP=''; " +
				"if [ -n \"$WAN_DEV\" ]; then WAN_IP=$(ip -4 -o addr show dev \"$WAN_DEV\" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1); fi; " +
				"[ -z \"$WAN_IP\" ] && WAN_IP=$(ubus call network.interface.wan status 2>/dev/null | jsonfilter -e '@[\"ipv4-address\"][0].address' 2>/dev/null); " +
				"if [ -z \"$WAN_IP\" ]; then WAN_IP=$(ip -4 -o addr show 2>/dev/null | awk '{print $2, $4}' | while read -r dev cidr; do " +
				"case \"$dev\" in lo|br-lan|tun0) continue ;; esac; ip=\"${cidr%%/*}\"; " + isPrivate + " echo \"$ip\"; break; done); fi; " +
				"case \"$WAN_IP\" in 10.*|192.168.*|172.1[6-9].*|172.2[0-9].*|172.3[0-1].*|100.6[4-9].*|100.[7-9][0-9].*|100.1[0-1][0-9].*|100.12[0-7].*|\"\") WAN_IP='' ;; esac; ";

			var cmdReal = wanLookup +
				"WAN_IF=\"$WAN_DEV\"; " +
				"[ -z \"$WAN_IF\" ] && WAN_IF=$(ip route show default 2>/dev/null | grep -v tun0 | awk '{print $5}' | head -n 1); " +
				"RIP=$(nslookup ipwho.is 2>/dev/null | awk '/^Address/{a=$2} END{print a}' | sed 's/:53$//'); " +
				"if [ -n \"$RIP\" ]; then " +
				"  if [ -n \"$WAN_IF\" ]; then curl -sL -4 -m 10 --interface \"$WAN_IF\" --resolve ipwho.is:443:\"$RIP\" '" + GEO_URL + "'\"$WAN_IP\" 2>/dev/null; " +
				"  else curl -sL -4 -m 10 --resolve ipwho.is:443:\"$RIP\" '" + GEO_URL + "'\"$WAN_IP\" 2>/dev/null; fi; " +
				"else " +
				"  if [ -n \"$WAN_IF\" ]; then curl -sL -4 -m 10 --interface \"$WAN_IF\" '" + GEO_URL + "'\"$WAN_IP\" 2>/dev/null; " +
				"  else curl -sL -4 -m 10 '" + GEO_URL + "'\"$WAN_IP\" 2>/dev/null; fi; " +
				"fi";


			if (self.lastRealGeo && self.socksPort) {
				updateDisplayElement(elReal, self.lastRealGeo, _('Failed'));
			} else {
				fs.exec('/bin/sh', ['-c', cmdReal]).then(function(res) {
					try {
						if (res.stdout && res.stdout.trim() !== '') {
							var parsed = JSON.parse(res.stdout);
							updateDisplayElement(elReal, parsed, _('Failed'));
							self.lastRealGeo = parsed;
						} else if (self.lastRealGeo) {
							updateDisplayElement(elReal, self.lastRealGeo, _('Failed'));
						} else {
							elReal.textContent = _('Failed');
						}
					} catch(e) {
						if (self.lastRealGeo) {
							updateDisplayElement(elReal, self.lastRealGeo, _('Failed'));
						} else {
							elReal.textContent = _('Failed');
						}
					}
				});
			}

			var socksCheckCmd = "grep '\"noticeType\":\"ListeningSocksProxyPort\"' /tmp/psiphon.log 2>/dev/null | tail -n1 | grep -o '\"port\":[0-9]*' | head -n1 | cut -d: -f2";

			fs.exec('/bin/sh', ['-c', socksCheckCmd]).then(function(res) {
				var livePort = (res && res.stdout) ? res.stdout.trim() : '';
				if (livePort) { self.socksPort = livePort; }

				if (!self.socksPort) {
					self.dnsLeakTestDone = false;
					if (elVpn) elVpn.textContent = _('Disconnected');
					if (elState) { elState.textContent = _('Stopped'); elState.style.color = '#92a0b0'; }
					if (elLogo) elLogo.innerHTML = getLogoSvg('#ff4800', '#ff4800');
					return;
				}

				var cmdVpn = 'curl -sL -4 -m 6 --socks5-hostname 127.0.0.1:' + self.socksPort + " '" + GEO_URL + "' 2>/dev/null";

				fs.exec('/bin/sh', ['-c', cmdVpn]).then(function(res) {
					try {
						if (res.stdout && res.stdout.trim() !== '') {
							var parsed = JSON.parse(res.stdout);
							if (parsed && (parsed.query || parsed.ip) && parsed.success !== false) {
								updateDisplayElement(elVpn, parsed, _('Disconnected'), '#4fd88a');
								self.lastVpnGeo = parsed;
								if (elState) { elState.textContent = _('Connected'); elState.style.color = '#4fd88a'; }
								if (elLogo) elLogo.innerHTML = getLogoSvg('#02D16C', '#02D16C');
								if (!self.dnsLeakTestDone) {
									self.dnsLeakTestDone = true;
									runDnsLeakTest();
								}
								return;
							}
						}
						self.socksPort = null;
						self.dnsLeakTestDone = false;
						if (elVpn) elVpn.textContent = _('Disconnected');
						if (elState) { elState.textContent = _('Disconnected'); elState.style.color = '#e2645c'; }
						if (elLogo) elLogo.innerHTML = getLogoSvg('#ff4800', '#ff4800');
					} catch(e) {
						self.socksPort = null;
						self.dnsLeakTestDone = false;
						if (elVpn) elVpn.textContent = _('Disconnected');
						if (elState) { elState.textContent = _('Disconnected'); elState.style.color = '#e2645c'; }
						if (elLogo) elLogo.innerHTML = getLogoSvg('#ff4800', '#ff4800');
					}
				});
			});
		}

		function runDnsLeakTest() {
			var box = document.getElementById('dns_leak_results');
			var btn = document.getElementById('dns_leak_run_btn');
			if (!box) return;
			box.textContent = _('Testing…');
			box.style.color = '#92a0b0';
			if (btn) btn.disabled = true;

			var socksArg = self.socksPort ? ('--socks5-hostname 127.0.0.1:' + self.socksPort) : '';

			var blFetchCmd;
			var UA = "-A 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36'";
			if (socksArg) {
				blFetchCmd = "BL_TEXT=$(curl -sL -4 -m 10 " + socksArg + " " + UA + " 'https://browserleaks.com/ip' 2>/dev/null | sed -e 's/<[^>]*>/ /g' -e 's/&nbsp;/ /g' | tr -s ' \\t\\r\\n' ' '); ";
			} else {
				blFetchCmd =
					"BLIP=$(nslookup browserleaks.com 2>/dev/null | awk '/^Address/{a=$2} END{print a}' | sed 's/:53$//'); " +
					"RESOLVE_OPT=''; [ -n \"$BLIP\" ] && RESOLVE_OPT=\"--resolve browserleaks.com:443:$BLIP\"; " +
					"BL_TEXT=$(curl -sL -4 -m 10 $RESOLVE_OPT " + UA + " 'https://browserleaks.com/ip' 2>/dev/null | sed -e 's/<[^>]*>/ /g' -e 's/&nbsp;/ /g' | tr -s ' \\t\\r\\n' ' '); ";
			}

			var cmd =
				blFetchCmd +
				"echo \"BL_MATCH=$(echo \"$BL_TEXT\" | grep -oE 'IP Address[[:space:]]*[A-Z]{2}([0-9]{1,3}\\.){3}[0-9]{1,3}' | head -n1 | grep -oE '[A-Z]{2}([0-9]{1,3}\\.){3}[0-9]{1,3}$')\"; " +
				"echo '---SEP---'; " +
				"RESOLVER_IP=$(nslookup myip.opendns.com resolver1.opendns.com 2>/dev/null | grep 'Address' | tail -n1 | awk '{print $NF}'); " +
				"echo \"RESOLVER_IP=$RESOLVER_IP\"; " +
				"if [ -n \"$RESOLVER_IP\" ]; then curl -sL -4 -m 10 \"https://ipwho.is/$RESOLVER_IP\" 2>/dev/null; fi";

			fs.exec('/bin/sh', ['-c', cmd]).then(function(res) {
				if (btn) btn.disabled = false;
				var out = (res && res.stdout) ? res.stdout : '';
				var parts = out.split('---SEP---');
				var blBlock = parts[0] || '';
				var resolverBlock = parts[1] || '';

				var blM = blBlock.match(/BL_MATCH=([A-Z]{2})((?:\d{1,3}\.){3}\d{1,3})/);
				var blCC = blM ? blM[1] : '';
				var blIp = blM ? blM[2] : '';

				var m = resolverBlock.match(/RESOLVER_IP=(\S*)/);
				var resolverIp = m ? m[1] : '';
				var resolverGeo = null;
				var jsonStart = resolverBlock.indexOf('{');
				if (jsonStart !== -1) {
					try { resolverGeo = JSON.parse(resolverBlock.slice(jsonStart)); } catch (e) {}
				}

				var realCC = self.lastRealGeo ? (self.lastRealGeo.country_code || self.lastRealGeo.countryCode || '').toUpperCase() : '';
				var vpnCC = self.lastVpnGeo ? (self.lastVpnGeo.country_code || self.lastVpnGeo.countryCode || '').toUpperCase() : '';

				var lines = [];

				if (blIp) {
					var blFlag = self.flags[blCC] || '';
					lines.push(_('browserleaks.com/ip') + ': ' + blFlag + ' ' + blIp + (blCC ? ' (' + blCC + ')' : ''));
				} else {
					lines.push(_('browserleaks.com/ip: no readable response.'));
				}

				if (resolverIp && resolverGeo && resolverGeo.success !== false) {
					var rCC = (resolverGeo.country_code || resolverGeo.countryCode || '').toUpperCase();
					var rFlag = self.flags[rCC] || '';
					var rCountry = resolverGeo.country || resolverGeo.country_name || '';
					lines.push(_('Actual DNS resolver (OpenDNS check)') + ': ' + rFlag + ' ' + resolverIp + (rCountry ? ' (' + rCountry + ')' : ''));

					if (vpnCC && rCC === vpnCC) {
						lines.push('✅ ' + _('No leak — DNS resolves through the tunnel exit.'));
						box.style.color = '#4fd88a';
					} else if (realCC && rCC === realCC) {
						lines.push('⚠️ ' + _('Possible DNS leak — resolver matches your real ISP, not the tunnel.'));
						box.style.color = '#e2645c';
					} else {
						lines.push('ℹ️ ' + _('Inconclusive — treat as approximate.'));
						box.style.color = '#e0b34d';
					}
				} else {
					lines.push(_('Could not determine the active resolver.'));
					if (!blIp) box.style.color = '#92a0b0';
				}

				box.innerHTML = '';
				lines.forEach(function(l) { box.appendChild(E('div', {}, l)); });
				box.appendChild(E('div', { 'style': 'margin-top: 6px;' }, [
					E('a', { 'href': 'https://browserleaks.com/dns', 'target': '_blank', 'rel': 'noopener', 'style': 'color: #5b9bd9; font-size: 11px;' },
						_('Open full multi-resolver test in your browser') + ' →')
				]));
			}).catch(function() {
				if (btn) btn.disabled = false;
				box.textContent = _('Test failed to run.');
				box.style.color = '#e2645c';
			});
		}

		function runClientSideDiagnostics() {
			var icmpEl = document.getElementById('diag_icmp');
			var tcpEl = document.getElementById('diag_tcp');
			var urlEl = document.getElementById('diag_url');

			if (icmpEl) icmpEl.textContent = '...';
			if (tcpEl) tcpEl.textContent = '...';
			if (urlEl) urlEl.textContent = '...';

			var cmdIcmp = "ping -c 1 1.1.1.1 2>&1 | grep -oE 'time[=<][0-9.]+' | head -n1 | grep -oE '[0-9.]+'";
			fs.exec('/bin/sh', ['-c', cmdIcmp]).then(function(res) {
				var v = (res && res.stdout) ? res.stdout.trim() : '';
				if (icmpEl) icmpEl.textContent = v ? (Math.round(parseFloat(v)) + ' ms') : 'Error';
			}).catch(function() { if (icmpEl) icmpEl.textContent = 'Error'; });

			var socksArg = self.socksPort ? ('--socks5-hostname 127.0.0.1:' + self.socksPort) : '';

			var cmdTcp = "curl -sL -4 -m 12 " + socksArg + " -o /dev/null -w '%{time_connect}' 'https://cloudflare-dns.com/dns-query' 2>/dev/null";
			fs.exec('/bin/sh', ['-c', cmdTcp]).then(function(res) {
				var v = (res && res.stdout) ? res.stdout.trim() : '';
				var ms = parseFloat(v) * 1000;
				if (tcpEl) tcpEl.textContent = (v && !isNaN(ms) && ms > 0) ? (Math.round(ms) + ' ms') : 'Error';
			}).catch(function() { if (tcpEl) tcpEl.textContent = 'Error'; });

			var cmdUrl = "curl -sL -4 -m 12 " + socksArg + " -o /dev/null -w '%{time_total}' 'https://api.github.com/zen' 2>/dev/null";
			fs.exec('/bin/sh', ['-c', cmdUrl]).then(function(res) {
				var v = (res && res.stdout) ? res.stdout.trim() : '';
				var ms = parseFloat(v) * 1000;
				if (urlEl) urlEl.textContent = (v && !isNaN(ms) && ms > 0) ? (Math.round(ms) + ' ms') : 'Timeout';
			}).catch(function() { if (urlEl) urlEl.textContent = 'Timeout'; });
		}

		function fetchLog() {
			var logArea = document.getElementById('psiphon_live_log');
			if (!logArea) return;
			L.resolveDefault(fs.read('/tmp/psiphon.log'), '').then(function(res) {
				if (res && res.trim() !== '') {
					var lines = res.split('\n');
					var filteredLog = [];
					var prevBT = null;
					var latestRateDown = null, latestRateUp = null;
					var totalSent = 0, totalReceived = 0, sawBT = false;

					for (var i = 0; i < lines.length; i++) {
						var line = lines[i].trim();
						if (line === '') continue;

						if (line.startsWith('[System]') || line.startsWith('$')) {
							if (line.indexOf('Stopping Psiphon') !== -1) { self.socksPort = null; prevBT = null; latestRateDown = latestRateUp = '0.0'; totalSent = totalReceived = 0; sawBT = true; }
							filteredLog.push(line);
							continue;
						}

						try {
							var logObj = JSON.parse(line);
							var time = logObj.timestamp ? logObj.timestamp.substring(11, 19) : '';
							var timePrefix = time ? '[' + time + '] ' : '';
							
							if (logObj.noticeType === 'ListeningSocksProxyPort') {
								filteredLog.push(timePrefix + 'SOCKS proxy listening on random port ' + logObj.data.port);
								self.socksPort = logObj.data.port;
							} else if (logObj.noticeType === 'ListeningHttpProxyPort') {
								filteredLog.push(timePrefix + 'HTTP proxy listening on random port ' + logObj.data.port);
							} else if (logObj.noticeType === 'ConnectedServerRegion') {
								filteredLog.push(timePrefix + 'Connected to server region ' + logObj.data.serverRegion);
							} else if (logObj.noticeType === 'Tunnels') {
								filteredLog.push(timePrefix + 'Tunnels Count ' + logObj.data.count);
								var tunCountEl = document.getElementById('stat_tunnels_count');
								if (tunCountEl) tunCountEl.textContent = logObj.data.count;
							} else if (logObj.noticeType === 'BytesTransferred') {
								var btTime = logObj.timestamp ? Date.parse(logObj.timestamp) : NaN;
								if (prevBT && !isNaN(btTime) && btTime > prevBT.time) {
									var dt = (btTime - prevBT.time) / 1000;
									latestRateDown = (logObj.data.received / 1024 / dt).toFixed(1);
									latestRateUp = (logObj.data.sent / 1024 / dt).toFixed(1);
								}
								prevBT = { time: btTime };
								totalSent += (logObj.data.sent || 0);
								totalReceived += (logObj.data.received || 0);
								sawBT = true;
							} else if (logObj.noticeType === 'ClientRegion') {
								filteredLog.push(timePrefix + 'Current Internet Location ' + logObj.data.region);
							} else if (logObj.noticeType === 'SkipServerEntry') {
								filteredLog.push(timePrefix + 'Skipping Blocked Server IP');
							} else if (logObj.noticeType === 'EstablishTunnelTimeout') {
								filteredLog.push(timePrefix + 'Connection Timeout. Retrying...');
							}
						} catch (e) {
						}
					}

					if (latestRateDown !== null || latestRateUp !== null) {
						var downEl = document.getElementById('stat_down_speed');
						var upEl = document.getElementById('stat_up_speed');
						if (downEl && latestRateDown !== null) downEl.textContent = latestRateDown + ' KB/s';
						if (upEl && latestRateUp !== null) upEl.textContent = latestRateUp + ' KB/s';
					}
					if (sawBT) {
						var totalEl = document.getElementById('stat_total_traffic');
						if (totalEl) totalEl.textContent = formatBytes(totalSent + totalReceived);
					}

					var isBottom = (logArea.scrollHeight - logArea.scrollTop <= logArea.clientHeight + 20);
					logArea.value = filteredLog.length > 0 ? filteredLog.join('\n') : _('Standby');
					if (isBottom) logArea.scrollTop = logArea.scrollHeight;
				} else {
					logArea.value = _('Service stopped or log empty');
					self.socksPort = null;
				}
			});
		}

		setTimeout(function() {
			document.querySelectorAll('.cbi-input-select, select, option, .control-group').forEach(function(el) { el.classList.add('win-flag'); });
		}, 500);

		poll.add(L.bind(function() {
			poll_counter++;
			if (poll_counter % 3 === 0) refreshIPs();
			return fetchLog();
		}, this), 3);

		setTimeout(L.bind(function() { refreshIPs(); fetchLog(); runClientSideDiagnostics(); }, this), 1000);

		return m.render();
	}
});
EOF

# ==============================================================================
# GROUP 7: Service Restart & Cache Cleanup
# ==============================================================================
echo "Clearing cache and restarting UI..."

rm -rf /tmp/luci-indexcache* /tmp/luci-modulecache/ /var/luci-indexcache*
/etc/init.d/rpcd restart
/etc/init.d/uhttpd restart
/etc/init.d/firewall restart
chmod +x /etc/init.d/psiphon

ln -sf /etc/init.d/psiphon /etc/rc.d/S99psiphon
ln -sf /etc/init.d/psiphon /etc/rc.d/K10psiphon

mkdir -p /tmp/dnsmasq.d

if ! grep -q 'conf-dir=/tmp/dnsmasq.d' /etc/dnsmasq.conf 2>/dev/null && \
   ! uci -q get dhcp.@dnsmasq[0].confdir | grep -q '/tmp/dnsmasq.d'; then
    uci -q set dhcp.@dnsmasq[0].confdir='/tmp/dnsmasq.d'
    uci commit dhcp
    /etc/init.d/dnsmasq reload 2>/dev/null
fi

/etc/init.d/psiphon restart

echo "Setup Completed Successfully! All optimizations applied /   Psiphon VPN 2.0.40  ."


.

```

## 💡 دستورات تست، اجرا و مدیریت سرویس

*   **روشن کردن تانل سایفون:**
    ```bash
    /etc/init.d/psiphon start
    ```
*   **خاموش کردن کامل سیستم:**
    ```bash
    /etc/init.d/psiphon stop
    ```
*   **فعال‌سازی اجرای خودکار پس از روشن شدن روتر:**
    ```bash
    /etc/init.d/psiphon enable
    ```


## 🗑️ ۸. حذف کامل و بی‌بازگشت سایفون از سیستم (Uninstall)

اگر به هر دلیلی تمایل داشتید تمامی تنظیمات، فایل‌های باینری، دیتابیس‌ها و منوهای پنل لوسی سایفون را بدون به جا ماندن هیچ ردپایی حذف کنید، اسکریپت یکپارچه زیر را در ترمینال روتر اجرا کنید:

```bash
#!/bin/sh
echo "Stopping Psiphon service and cleaning up..."

# ۱. متوقف کردن سرویس و غیرفعال کردن از سیستم Init
if [ -x /etc/init.d/psiphon ]; then
    /etc/init.d/psiphon stop 2>/dev/null
    /etc/init.d/psiphon disable 2>/dev/null
fi

# متوقف کردن اجباری تمام پردازنده‌های فعال در صورت باقی ماندن
killall -9 psiphon-core 2>/dev/null
for pid in $(pgrep -f "psiphon-core"); do
    kill -9 "$pid" 2>/dev/null
done

# ۲. پاکسازی کامل قوانین مسیریابی و اینترفیس TUN
ip rule del iif br-lan lookup 100 2>/dev/null
ip route flush table 100 2>/dev/null
ip link delete tun0 2>/dev/null

# ۳. پاکسازی قوانین IPTables (اضافه شده بر اساس اسکریپت نصب)
iptables -t nat -D PREROUTING -j psiphon_dns_nat 2>/dev/null
iptables -t nat -D OUTPUT -j psiphon_dns_nat 2>/dev/null
iptables -t nat -F psiphon_dns_nat 2>/dev/null
iptables -t nat -X psiphon_dns_nat 2>/dev/null

iptables -D OUTPUT -j psiphon_dns_block 2>/dev/null
iptables -D FORWARD -j psiphon_dns_block 2>/dev/null
iptables -F psiphon_dns_block 2>/dev/null
iptables -X psiphon_dns_block 2>/dev/null

# ۴. بازنشانی تنظیمات DNS به حالت پیش‌فرض روتر
rm -f /tmp/dnsmasq.d/psiphon_dns.conf
/etc/init.d/dnsmasq restart >/dev/null 2>&1

# ۵. پاکسازی تنظیمات UCI (فایروال و کانفیگ خود سایفون)
for sec in $(uci show firewall | grep -E "name='psiphon'|dest='psiphon'|src='psiphon'" | cut -d. -f1,2); do
    uci -q delete "$sec"
done
uci commit firewall

uci -q delete psiphon
uci commit psiphon

# ۶. حذف کامل فایل‌ها، باینری‌ها، دایرکتوری‌ها و اسکریپت‌های پنل
rm -f /usr/bin/psiphon-core
rm -rf /etc/psiphon
rm -f /etc/config/psiphon
rm -f /usr/share/rpcd/acl.d/luci-app-psiphon.json
rm -f /usr/share/luci/menu.d/luci-app-psiphon.json
rm -f /etc/init.d/psiphon
rm -rf /www/luci-static/resources/view/vpn/psiphon.js
rm -f /tmp/psiphon.log
rm -f /tmp/psiphon-watchdog.pid
rm -f /etc/rc.d/S99psiphon
rm -f /etc/rc.d/K10psiphon
# جستجوی محتاطانه برای جلوگیری از خطای سیستم‌فایل‌های مجازی
find / -name "*psiphon*" -not -path "/proc/*" -not -path "/sys/*" 2>/dev/null | xargs rm -rf 2>/dev/null

# ۷. پاکسازی کش LuCI و راه‌اندازی مجدد سرویس‌های سیستمی
rm -rf /tmp/luci-indexcache* /tmp/luci-modulecache/ /var/luci-indexcache*
/etc/init.d/rpcd restart
/etc/init.d/uhttpd restart
/etc/init.d/firewall restart

echo "Psiphon has been completely uninstalled from the system.  Psiphon VPN 2.0.40    "


```

## محیط Luci برای سایفون

