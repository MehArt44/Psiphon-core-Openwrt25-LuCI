**پارسی** | [English](README.en.md)



# راهنمای جامع نصب، راه‌اندازی و خودکارسازی Psiphon-Core به همراه پنل گرافیکی LuCI در OpenWrt 25

این پروژه یک راهنمای کاملاً بومی و عملیاتی برای کامپایل، کانفیگ و اتصال هسته لینوکسی سایفون (`psiphon-core`) به رابط کاربری گرافیکی لوسی (**LuCI JavaScript**) در سیستم‌عامل **OpenWrt 25** است. تمامی کلیدهای کنترل سرویس، فیلدهای تنظیمات (پورت‌ها، کشور، پروتکل) و بخش مانیتورینگ وضعیت آی‌پی کاملاً همگام‌سازی شده‌اند. بدون سربار روی روم و سی پی یو روتر

---

## 🛠️ ۱. آموزش کامپایل فایل باینری (روی کامپیوتر) – PowerShell/ کامپایل شده برای چند معماری CPU در Rel

برای ساخت فایل اجرایی اختصاصی روتر خود، ابتدا مطمئن شوید زبان Go روی سیستم شما نصب است. سپس ترمینال را باز کرده و بر اساس معماری پردازنده روتر خود، دستورات زیر را اجرا کنید:

```powershell
# دریافت سورس کد رسمی هسته سایفون از مخزن گیت‌هاب
git clone https://github.com/Psiphon-Labs/psiphon-tunnel-core.git
cd psiphon-tunnel-core/ConsoleClient

# کامپایل برای روترهای ۶۴ بیتی (Aarch64 / ARM64 مانند GL.iNet MT3000 / MT2500)
$env:GOOS="linux"
$env:GOARCH="arm64"
go build -o psiphon-core .

# کامپایل برای روترهای ۳۲ بیتی (ARMv7 مانند Google Wifi AC-1304)
$env:GOOS="linux"
$env:GOARCH="arm"
$env:GOARM="7"
go build -o psiphon-core .

```

*پس از اتمام کامپایل،  فایل خروجی `psiphon-core`  و پوشه psiphon_data را از طریق ابزارهایی مانند MobaXterm یا SCP به مسیر `/usr/bin/` روی روتر منتقل کنید.*

---

## 🚀 ۲. آماده‌سازی در OpenWrt 
⚠️ بعد از اجرای دستور زیر محتوای پوشه psiphon_data.zip به آدرس /usr/bin/psiphon_data/ منتقل کنید  ⚠️

```bash
# صدور مجوز اجرا و ساخت پوشه دیتابیس سایفون
chmod +x /usr/bin/psiphon-core
mkdir -p /usr/bin/psiphon_data
```
---

## 📁 ۳. استقرار زیرساخت و کدهای کامل پنل گرافیکی     1 – 7 
بلوک کد زیر یک اسکریپت همه‌کاره است. آن را به طور کامل کپی کرده و در ترمینال روتر پیست کنید. این اسکریپت تمام فایل‌های ساختاری لوسی، تنظیمات UCI، کدهای جاوااسکریپت داشبورد (همراه با دکمه‌ها و فیلدهای کامل) و مجوزهای امنیتی را به صورت یکجا ایجاد می‌کند:

===================================================================
# GROUP 1 (Priority 1): Core Permissions & RPCD ACL
# GROUP 2 (Priority 2): Base UCI Configuration
# GROUP 3 (Priority 3): LuCI Menu Registration
# GROUP 4 (Priority 4): Init.d Service Script Generation
# GROUP 5 (Priority 5): Firewall and Routing Configurations
# GROUP 6 (Priority 6): LuCI Frontend (View Script)
# GROUP 7 (Priority 7): Service Restart & Cache Cleanup
===================================================================

```bash
#!/bin/sh

# ==============================================================================
# GROUP 1 (Priority 1): Core Permissions & RPCD ACL
# ==============================================================================
echo "Creating LuCI RPCD Access Permissions..."

chmod +x /usr/bin/psiphon-core
mkdir -p /usr/bin/psiphon_data
mkdir -p /usr/share/rpcd/acl.d/

cat << 'EOF' > /usr/share/rpcd/acl.d/luci-app-psiphon.json
{
	"luci-app-psiphon": {
		"description": "Grant execution rights for Psiphon service controls",
		"read": {
			"cgi-io": [ "exec" ],
			"file": {
				"/tmp/psiphon.log": [ "read" ],
				"/usr/bin/psiphon_data/psiphon.config": [ "read" ],
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
# GROUP 2 (Priority 2): Base UCI Configuration
# ==============================================================================
echo "Creating base config file..."

touch /etc/config/psiphon
uci set psiphon.config=psiphon
uci set psiphon.config.enabled='0'
uci set psiphon.config.tun='0'
uci set psiphon.config.transport='STANDARD'
uci set psiphon.config.beast_mode='0'
uci set psiphon.config.cdn_edge_ips=''
uci set psiphon.config.cdn_sni=''
uci commit psiphon

# ==============================================================================
# GROUP 3 (Priority 3): LuCI Menu Registration
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
# GROUP 4 (Priority 4): Init.d Service Script Generation
# ==============================================================================
echo "Generating Init.d script with custom Transport and advanced leak protection..."

cat << 'EOF' > /etc/init.d/psiphon
#!/bin/sh /etc/rc.common

START=99
STOP=10
USE_PROCD=1

PROG="/usr/bin/psiphon-core"
DATA_DIR="/usr/bin/psiphon_data"
CONFIG_FILE="$DATA_DIR/psiphon.config"
LOG_FILE="/tmp/psiphon.log"

stop_service() {
    echo "[System] Stopping Psiphon..." > "$LOG_FILE"
    
    ip rule del iif br-lan lookup 100 2>/dev/null
    ip route flush table 100 2>/dev/null
    killall -9 psiphon-core 2>/dev/null
    ip link delete tun0 2>/dev/null
    ip route del default dev tun0 metric 1 2>/dev/null

    WAN_IF=$(ip route show default | grep -v tun0 | awk '{print $5}' | head -n 1)
    if [ -n "$WAN_IF" ]; then
        iptables -D OUTPUT -o "$WAN_IF" -p udp --dport 53 -j REJECT 2>/dev/null
        iptables -D OUTPUT -o "$WAN_IF" -p tcp --dport 53 -j REJECT 2>/dev/null
        iptables -D FORWARD -o "$WAN_IF" -p udp --dport 53 -j REJECT 2>/dev/null
    fi
}

start_service() {
    stop_service

    config_load psiphon

    local enabled tun country transport
    local beast_mode cdn_edge_ips cdn_sni
    config_get_bool enabled "config" "enabled" 0
    config_get_bool tun "config" "tun" 0
    config_get country "config" "country" ""
    config_get transport "config" "transport" "STANDARD"
    config_get_bool beast_mode "config" "beast_mode" 0
    config_get cdn_edge_ips "config" "cdn_edge_ips" ""
    config_get cdn_sni "config" "cdn_sni" ""

    [ "$enabled" -eq 1 ] || return 0

    mkdir -p "$DATA_DIR"

    cat << JSON > "$CONFIG_FILE"
{
  "DataRootDirectory": "/usr/bin/psiphon_data",
  "DisableIPv6": true,
  "PropagationChannelId": "0000000000000000",
  "SponsorId": "0000000000000000",
  "ServerEntrySignaturePublicKey": "",
  "UseIndistinguishableTLS": true,
  "ProtocolMode": "auto"
}
JSON

    if [ -n "$country" ]; then
        sed -i '$ s/}/,\n  "EgressRegion": "'"$country"'"\n}/' "$CONFIG_FILE"
    fi

    if [ -n "$transport" ]; then
        upper_transport=$(echo "$transport" | tr '[:lower:]' '[:upper:]')
        sed -i '$ s/}/,\n  "Transport": "'"$upper_transport"'"\n}/' "$CONFIG_FILE"
    fi

    if [ "$beast_mode" -eq 1 ]; then
        sed -i '$ s/}/,\n  "BeastMode": true\n}/' "$CONFIG_FILE"
    else
        sed -i '$ s/}/,\n  "BeastMode": false\n}/' "$CONFIG_FILE"
    fi

    [ -n "$cdn_edge_ips" ] && sed -i '$ s/}/,\n  "CdnFrontingCustomIpList": "'"$cdn_edge_ips"'"\n}/' "$CONFIG_FILE"
    [ -n "$cdn_sni" ] && sed -i '$ s/}/,\n  "CdnFrontingCustomSni": "'"$cdn_sni"'"\n}/' "$CONFIG_FILE"

    procd_open_instance
    procd_set_param command $PROG -config "$CONFIG_FILE" -notices "$LOG_FILE"
    if [ "$tun" -eq 1 ]; then
        procd_append_param command -tunDevice tun0
    fi
    procd_set_param respawn 3600 5 5
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_close_instance

    if [ "$tun" -eq 1 ]; then
        (
            sleep 4
            ip link set tun0 up 2>/dev/null
            ip rule add iif br-lan lookup 100 2>/dev/null
            ip route replace default dev tun0 table 100 2>/dev/null
        ) &
    fi
}

reload_service() {
    start_service
}
EOF

# ==============================================================================
# GROUP 5 (Priority 5): Firewall and Routing Configurations
# ==============================================================================
echo "Configuring Firewall Zones..."

for sec in $(uci show firewall | grep -E "name='psiphon'|dest='psiphon'|src='psiphon'" | cut -d. -f1,2); do
    uci delete "$sec" 2>/dev/null
done
uci commit firewall

uci set firewall.psiphon=zone
uci set firewall.psiphon.name='psiphon'
uci set firewall.psiphon.input='REJECT'
uci set firewall.psiphon.output='ACCEPT'
uci set firewall.psiphon.forward='REJECT'
uci set firewall.psiphon.masq='1'
uci set firewall.psiphon.mtu_fix='1'
uci set firewall.psiphon.device='tun0'

uci set firewall.psiphon_forwarding=forwarding
uci set firewall.psiphon_forwarding.src='lan'
uci set firewall.psiphon_forwarding.dest='psiphon'

uci commit firewall

# ==============================================================================
# GROUP 6 (Priority 6): LuCI Frontend (View Script)
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
	hasConnected: false,
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
					/* استایل دکمه‌ها همراه با کادر رنگی استارتاپ/استاپ */
					.psiphon-btn { padding: 0 10px !important; font-size: 12px !important; height: 26px !important; min-height: 26px !important; line-height: 24px !important; border-radius: 4px; cursor: pointer; transition: all 0.2s ease-in-out; }
					.btn-group { display: flex; gap: 8px; align-items: center; }

					/* ساختار شبکه و کانتینرها */
					.win-flag { font-family: "Noto Color Emoji", "Segoe UI Emoji", sans-serif !important; }
					.cbi-section-node { display: flex; flex-direction: column; gap: 12px; width: 100% !important; background: transparent !important; border: none !important; padding: 0 !important; }
					.psiphon-top-row { width: 100%; order: 1; margin-bottom: 2px; }
					.psiphon-bottom-grid { display: flex; flex-direction: row; gap: 16px; width: 100%; align-items: stretch; order: 2; }
					.psiphon-col-left { flex: 1.1; min-width: 320px; display: flex; flex-direction: column; background: var(--background-card, #1a1c20); padding: 12px 16px; border-radius: 8px; border: 1px solid rgba(255,255,255,0.05); box-shadow: 0 4px 6px rgba(0,0,0,0.15); justify-content: flex-start; }
					.psiphon-col-right { flex: 0.9; min-width: 320px; display: flex; flex-direction: column; gap: 8px; background: #1a1c20; padding: 14px 16px; border-radius: 8px; border: 1px solid #333; box-shadow: 0 4px 6px rgba(0,0,0,0.3); justify-content: space-between; }
					
					/* فیلدهای فرم */
					.psiphon-col-left > .cbi-value { width: 100% !important; padding: 5px 0 !important; margin-bottom: 0 !important; border-bottom: 1px solid rgba(255,255,255,0.03) !important; display: flex !important; flex-direction: row !important; align-items: center !important; min-height: 38px; box-sizing: border-box; }
					.psiphon-col-left > .cbi-value:last-child { border-bottom: none !important; }
					.psiphon-col-left .cbi-value-title { width: 35% !important; min-width: 130px !important; text-align: left !important; padding: 0 !important; font-size: 13px; }
					.psiphon-col-left .cbi-value-field { width: 65% !important; padding: 0 !important; font-size: 13px; }
					.psiphon-col-left .cbi-value-description { margin-top: 2px !important; font-size: 11px !important; opacity: 0.8; line-height: 1.3; }
					.psiphon-col-left input[type="text"], .psiphon-col-left select { height: 26px !important; padding: 2px 6px !important; font-size: 13px !important; background-color: #222 !important; color: #ddd !important; width: 100% !important; box-sizing: border-box; }
					
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

		var logoContainer = E('div', { 'id': 'psiphon-dynamic-logo', 'style': 'width: 48px; height: 48px; flex-shrink: 0; display: flex; align-items: center; justify-content: center;' });
		function getLogoSvg(c1, c2) {
			return '<svg width="48" height="48" viewBox="0 0 48.00 48.00" xmlns="http://www.w3.org/2000/svg">' +
				'<path d="M 12 0 H 36 A 12 12 0 0 1 48 12 V 36 A 12 12 0 0 1 36 48 H 12 A 12 12 0 0 1 0 36 V 12 A 12 12 0 0 1 12 0 Z" fill="' + c1 + '"/>' +
				'<path d="M 20.593 32.889 L 34.273 32.824 L 37.97 29.341 L 40.491 9.289 L 37.302 5.922 L 10.97 5.601 C 9.476 6.667 8.285 8.104 7.514 9.77 L 17.57 9.868 L 13.607 40.876 C 15.408 41.841 17.408 42.377 19.45 42.444 Z" fill="#fff"/>' +
				'<path d="M 23.797 11.765 L 21.624 26.41 L 31.601 26.303 L 33.739 11.765 Z" fill="' + c2 + '"/>' +
				'</svg>';
		}
		logoContainer.innerHTML = getLogoSvg('#fb510c', '#f45825');

		var titleHtml = E('div', { 'style': 'display: flex; align-items: center; gap: 12px; margin-bottom: 10px; padding: 4px 0;' }, [
			logoContainer,
			E('div', { 'style': 'display: flex; flex-direction: column; justify-content: center;' }, [
				E('h2', { 'style': 'margin: 0; font-weight: bold; color: #fff; font-size: 22px; line-height: 1.2;' }, _('Psiphon VPN Configuration')),
				E('span', { 'style': 'font-size: 11px; color: #aaa; display: block; margin-top: 2px;' }, _('Unified Single-Page Control Panel for Psiphon Tunnel Core.'))
			])
		]);

		var m = new form.Map('psiphon', titleHtml);
		var s = m.section(form.NamedSection, 'config', 'psiphon');
		s.addremove = false;

		var o = s.option(form.DummyValue, '_ip_box');
		o.rawhtml = true;
		o.render = function() {
			return E('div', { 'class': 'psiphon-top-row' }, [
				E('div', { 'style': 'display: flex; flex-flow: row wrap; align-items: center; justify-content: space-between; background: #1a1c20; padding: 10px 16px; border-radius: 8px; border: 1px solid #333; box-shadow: 0 4px 6px rgba(0,0,0,0.3); width: 100%; gap: 12px;' }, [
					E('div', { 'style': 'display: flex; align-items: center; gap: 6px; flex: 1 1 0%; min-width: 180px;' }, [
						E('span', { 'style': 'color: #88a; font-size: 12px; text-transform: uppercase; font-weight: bold; width: 60px; flex-shrink: 0;' }, _('Real IP')),
						E('span', { 'id': 'real_ip_display', 'style': 'font-size: 13px; color: #ccc; font-family: monospace; display: flex; align-items: center; gap: 5px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;' }, _('Checking'))
					]),
					E('div', { 'style': 'width: 1px; height: 18px; background-color: #444; display: inline-block;' }, ''),
					E('div', { 'style': 'display: flex; align-items: center; gap: 6px; flex: 1 1 0%; min-width: 180px;' }, [
						E('span', { 'style': 'color: #88a; font-size: 12px; text-transform: uppercase; font-weight: bold; width: 80px; flex-shrink: 0;' }, _('Psiphon IP')),
						E('span', { 'id': 'vpn_ip_display', 'style': 'font-size: 13px; color: #00ff66; font-family: monospace; display: flex; align-items: center; gap: 5px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;' }, _('Checking'))
					]),
					E('div', { 'class': 'btn-group flex-shrink-0' }, [
						E('button', { 'class': 'btn cbi-button cbi-button-apply psiphon-btn', 'click': function(ev) { ev.preventDefault(); refreshIPs(); } }, _('Refresh')),
						E('button', { 'class': 'btn cbi-button cbi-button-action psiphon-btn', 'style': 'background: linear-gradient(135deg, #2b5876, #4e4376); color: #fff;', 'click': function(ev) { 
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
            return E('div', { 'class': 'cbi-value' }, [
                E('label', { 'class': 'cbi-value-title' }, _('Service Control')),
                E('div', { 'class': 'cbi-value-field btn-group' }, [
                    E('button', { 
                        'class': 'btn cbi-button cbi-button-remove psiphon-btn', 
                        'style': 'border: 1px solid #ff4d4d; background-color: rgba(255, 77, 77, 0.1); color: #ff4d4d;',
                        'click': function(ev) { 
                            ev.preventDefault(); 
                            self.hasConnected = false;
                            if (uiObj) uiObj.addNotification(null, E('p', _('Stopping Psiphon service...')), 'info');
                            fs.exec('/bin/sh', ['-c', '/etc/init.d/psiphon stop >/dev/null 2>&1 &']).then(function() { 
                                setTimeout(function() {
                                    refreshIPs();
                                    var elLogo = document.getElementById('psiphon-dynamic-logo');
                                    if (elLogo) elLogo.innerHTML = getLogoSvg('#fb510c', '#f45825');
                                    var elVpn = document.getElementById('vpn_ip_display');
                                    if (elVpn) elVpn.textContent = _('Disconnected');
                                }, 1000); 
                            });
                        }
                    }, _('Stop')),

                    E('button', { 
                        'class': 'btn cbi-button cbi-button-apply psiphon-btn', 
                        'style': 'border: 1px solid #00ff66; background-color: rgba(0, 255, 102, 0.1); color: #00ff66;',
                        'click': function(ev) { 
                            ev.preventDefault();
                            self.hasConnected = false;
                            if (uiObj) uiObj.addNotification(null, E('p', _('Restarting Psiphon service...')), 'info');
                            fs.exec('/bin/sh', ['-c', '/etc/init.d/psiphon restart >/dev/null 2>&1 &']).then(function() { setTimeout(refreshIPs, 2000); });
                        }
                    }, _('Start'))
                ])
            ]);
        };

		var optEnabled = s.option(form.Flag, 'enabled', _('Enable'));
		optEnabled.rmempty = false;
		
		var optTun = s.option(form.Flag, 'tun', _('Enable TUN Mode'), _('Route all device traffic through Psiphon TUN interface'));
		optTun.rmempty = false;

		var optCountry = s.option(form.ListValue, 'country', _('Region'));
		optCountry.rmempty = true; optCountry.optional = true;
		optCountry.value('', '⚡ ' + _('Best Performance'));
		var countries = ['AT','BE','BG','CA','CH','CZ','DE','DK','EE','ES','FI','FR','GB','HU','IE','IN','IT','JP','LV','NL','NO','PL','RO','RS','SE','SG','SK','US'];
		countries.forEach(function(c) {
			var fullName = self.country_names[c] || c;
			optCountry.value(c, (self.flags[c] || '') + ' ' + fullName + ' [' + c + ']');
		});

		var optTransport = s.option(form.ListValue, 'transport', _('Transport Mode'));
		optTransport.value('STANDARD', _('Standard')); optTransport.value('QUIC', _('QUIC')); optTransport.value('SSH', _('SSH'));

        var optBeast = s.option(form.Flag, 'beast_mode', _('Beast Mode')); 
        optBeast.rmempty = true; 
        optBeast.default = '0';
        
        var optCdnIp = s.option(form.Value, 'cdn_edge_ips', _('CDN edge IPs')); 
        optCdnIp.rmempty = true;
        optCdnIp.placeholder = 'e.g., 1.1.1.1,1.0.0.1';

        var optCdnSni = s.option(form.Value, 'cdn_sni', _('CDN SNI hostname')); 
        optCdnSni.rmempty = true;
        optCdnSni.placeholder = 'e.g., cdn.example.com';

		var optClearLog = E('button', { 'class': 'btn cbi-button cbi-button-reset psiphon-btn', 'click': function(ev) {
			ev.preventDefault();
			var box = document.getElementById('psiphon_live_log');
			if (box) box.value = _('Log monitor cleared');
			fs.exec('/bin/sh', ['-c', '> /tmp/psiphon.log || true']);
		}}, _('Clear Log Screen'));

		// ==========================================
		// GROUP 5: Layout Fixer (Optimized Cards & Standardized Grids)
		// ==========================================
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

					// ویجت مانیتورینگ
					var trafficStatsWidget = E('div', { 'class': 'psiphon-card', 'style': 'margin-top: 8px; background: linear-gradient(135deg, #16191d 0%, #1f242d 100%); padding: 10px 12px; border-radius: 6px; border: 1px solid #2a323d; box-shadow: inset 0 1px 0 rgba(255,255,255,0.05);' }, [
						E('div', { 'style': 'font-weight: bold; color: #a1b0c9; font-size: 12px; margin-bottom: 8px; display: flex; align-items: center; gap: 6px;' }, [
							E('span', { 'style': 'width: 8px; height: 8px; background: #00ff66; border-radius: 50%; display: inline-block; box-shadow: 0 0 6px #00ff66;' }),
							_('Tunnel Performance & Health Stats')
						]),
						E('div', { 'style': 'display: grid; grid-template-columns: repeat(3, 1fr); gap: 6px; font-family: monospace;' }, [
							E('div', { 'style': 'background: rgba(0,0,0,0.25); padding: 6px; border-radius: 4px; border: 1px solid rgba(255,255,255,0.03); text-align: center; display: flex; flex-direction: column; justify-content: center; min-height: 45px;' }, [
								E('div', { 'style': 'font-size: 10px; color: #8899aa; text-transform: uppercase; margin-bottom: 2px;' }, _('Active Tunnels')),
								E('span', { 'id': 'stat_tunnels_count', 'style': 'font-size: 13px; font-weight: bold; color: #fff;' }, '0')
							]),
							E('div', { 'style': 'background: rgba(0,255,102,0.05); padding: 6px; border-radius: 4px; border: 1px solid rgba(0,255,102,0.1); text-align: center; display: flex; flex-direction: column; justify-content: center; min-height: 45px;' }, [
								E('div', { 'style': 'font-size: 10px; color: #00ff66; text-transform: uppercase; margin-bottom: 2px;' }, _('Download')),
								E('span', { 'id': 'stat_down_speed', 'style': 'font-size: 12px; font-weight: bold; color: #00ff66;' }, '0 KB/s')
							]),
							E('div', { 'style': 'background: rgba(51,153,255,0.05); padding: 6px; border-radius: 4px; border: 1px solid rgba(51,153,255,0.1); text-align: center; display: flex; flex-direction: column; justify-content: center; min-height: 45px;' }, [
								E('div', { 'style': 'font-size: 10px; color: #3399ff; text-transform: uppercase; margin-bottom: 2px;' }, _('Upload')),
								E('span', { 'id': 'stat_up_speed', 'style': 'font-size: 12px; font-weight: bold; color: #3399ff;' }, '0 KB/s')
							])
						])
					]);

					// ویجت دیباگ مرورگر
					var diagnosticsWidget = E('div', { 'class': 'psiphon-card', 'style': 'margin-top: 8px; background: linear-gradient(135deg, #16191d 0%, #1f242d 100%); padding: 10px 12px; border-radius: 6px; border: 1px solid #2a323d;' }, [
						E('div', { 'style': 'display: flex; justify-content: space-between; align-items: center; margin-bottom: 8px;' }, [
							E('div', { 'style': 'font-weight: bold; color: #a1b0c9; font-size: 12px;' }, _('Browser-Side Connection Diagnostics')),
							E('span', { 'style': 'font-size: 9px; color: #667788; background: rgba(0,0,0,0.3); padding: 2px 5px; border-radius: 4px;' }, _('Zero Router Overhead'))
						]),
						E('div', { 'style': 'display: grid; grid-template-columns: repeat(3, 1fr); gap: 6px; text-align: center;' }, [
							E('div', { 'style': 'background: rgba(0,0,0,0.3); padding: 6px; border-radius: 4px; border: 1px solid rgba(255,255,255,0.03); display: flex; flex-direction: column; justify-content: center; min-height: 45px;' }, [
								E('div', { 'style': 'font-size: 10px; color: #8899aa; margin-bottom: 2px; font-weight: bold;' }, _('ICMP Sim')),
								E('div', { 'id': 'diag_icmp', 'style': 'font-family: monospace; font-size: 12px; color: #ffcc00;' }, '-')
							]),
							E('div', { 'style': 'background: rgba(0,0,0,0.3); padding: 6px; border-radius: 4px; border: 1px solid rgba(255,255,255,0.03); display: flex; flex-direction: column; justify-content: center; min-height: 45px;' }, [
								E('div', { 'style': 'font-size: 10px; color: #8899aa; margin-bottom: 2px; font-weight: bold;' }, _('TCP Ping')),
								E('div', { 'id': 'diag_tcp', 'style': 'font-family: monospace; font-size: 12px; color: #00ff66;' }, '-')
							]),
							E('div', { 'style': 'background: rgba(0,0,0,0.3); padding: 6px; border-radius: 4px; border: 1px solid rgba(255,255,255,0.03); display: flex; flex-direction: column; justify-content: center; min-height: 45px;' }, [
								E('div', { 'style': 'font-size: 10px; color: #8899aa; margin-bottom: 2px; font-weight: bold;' }, _('URL Test')),
								E('div', { 'id': 'diag_url', 'style': 'font-family: monospace; font-size: 12px; color: #3399ff;' }, '-')
							])
						])
					]);

					colLeftDiv.appendChild(trafficStatsWidget);
					colLeftDiv.appendChild(diagnosticsWidget);

					var colRightDiv = E('div', { 'id': 'psiphon_right_panel_container', 'class': 'psiphon-col-right' }, [
						E('div', { 'style': 'display: flex; flex-direction: column; gap: 6px; flex: 1;' }, [
							E('div', { 'style': 'display: flex; justify-content: space-between; align-items: center;' }, [
								E('label', { 'style': 'font-weight: bold; color: #88a; font-size: 13px;' }, _('Logs')),
								optClearLog
							]),
							E('textarea', { 'id': 'psiphon_live_log', 'style': 'width: 100%; flex: 1; min-height: 200px; font-family: monospace; font-size: 12px; background: #111; color: #00ff66; padding: 10px; border-radius: 4px; border: 1px solid #222; resize: none; line-height: 1.6; box-sizing: border-box;' }, _('Waiting for log stream'))
						]),
						E('div', { 'style': 'display: flex; flex-direction: column; gap: 4px; margin-top: 2px;' }, [
							E('label', { 'style': 'font-weight: bold; color: #88a; font-size: 13px;' }, _('Terminal')),
							E('textarea', { 'id': 'cmd_input', 'placeholder': 'Enter shell command here...', 'style': 'width: 100%; height: 100px; padding: 8px 10px; background: #111; color: #fff; border: 1px solid #222; font-family: monospace; resize: none; box-sizing: border-box; border-radius: 4px; line-height: 1.4;' }),
							E('div', { 'style': 'text-align: right; margin-top: 2px;' }, [
								E('button', { 'class': 'btn cbi-button cbi-button-apply psiphon-btn', 'click': function(ev) {
									ev.preventDefault();
									var cmdInput = document.getElementById('cmd_input');
									var cmd = cmdInput ? cmdInput.value.trim() : '';
									if (cmd === '') return;
									var logArea = document.getElementById('psiphon_live_log');
									if (logArea) { logArea.value += '\n$ ' + cmd + '\n'; logArea.scrollTop = logArea.scrollHeight; }
									fs.exec('/bin/sh', ['-c', cmd]).then(function(res) {
										if (logArea) { logArea.value += (res.stdout || '') + (res.stderr || ''); logArea.scrollTop = logArea.scrollHeight; }
										if (cmdInput) cmdInput.value = '';
									});
								}}, _('Run Command'))
							])
						])
					]);

					var bottomGridDiv = E('div', { 'id': 'psiphon-js-grid', 'class': 'psiphon-bottom-grid' }, [colLeftDiv, colRightDiv]);
					node.appendChild(bottomGridDiv);
				}
			}, 50);
			return E('div', { 'style': 'display:none;' }, '');
		};

		function updateDisplayElement(el, data, fallbackText, successColor) {
			if (!el) return;
			if (data && data.query) {
				var cc = (data.countryCode || data.country || '').toUpperCase();
				el.innerHTML = '';
				var flagEmoji = self.flags[cc] || '';
				if (flagEmoji) el.appendChild(E('span', { 'class': 'win-flag', 'style': 'font-size: 16px; line-height: 1; vertical-align: middle;' }, flagEmoji));
				el.appendChild(E('b', { 'style': 'font-size: 14px; margin-left: 5px; vertical-align: middle; color: ' + (successColor || '#ccc') }, ' ' + data.query));
				if (data.country) el.appendChild(E('span', { 'style': 'color: #888; font-size: 11px; margin-left: 4px; vertical-align: middle;' }, '(' + data.country + ')'));
			} else {
				el.textContent = fallbackText;
			}
		}

		function refreshIPs() {
			var elReal = document.getElementById('real_ip_display');
			var elVpn = document.getElementById('vpn_ip_display');
			var elLogo = document.getElementById('psiphon-dynamic-logo');

			var cmdReal = 'curl -sL -m 3 --interface wan http://ip-api.com/json/ 2>/dev/null || curl -sL -m 3 http://ip-api.com/json/ 2>/dev/null';
			fs.exec('/bin/sh', ['-c', cmdReal]).then(function(res) {
				try {
					if (res.stdout && res.stdout.trim() !== '') {
						var parsed = JSON.parse(res.stdout);
						updateDisplayElement(elReal, parsed, _('Failed'));
					} else { elReal.textContent = _('Failed'); }
				} catch(e) { elReal.textContent = _('Failed'); }
			});
			
			// استفاده از پورت 10109 یا 10809 (پورت پروکسی HTTP) به جای 8080
			var cmdVpn = 'curl -sL -m 3 --interface tun0 http://ip-api.com/json/ 2>/dev/null || curl -sL -m 3 -x http://127.0.0.1:10809 http://ip-api.com/json/ 2>/dev/null';
			fs.exec('/bin/sh', ['-c', cmdVpn]).then(function(res) {
				try {
					if (res.stdout && res.stdout.trim() !== '') {
						var parsed = JSON.parse(res.stdout);
						if (parsed && parsed.query) {
							updateDisplayElement(elVpn, parsed, _('Disconnected'), '#00ff66');
							if (elLogo) elLogo.innerHTML = getLogoSvg('#00e873', '#00e873');
							return;
						}
					}
					if (elVpn) elVpn.textContent = _('Disconnected');
					if (elLogo) elLogo.innerHTML = getLogoSvg('#fb510c', '#f45825');
				} catch(e) { 
					if (elVpn) elVpn.textContent = _('Disconnected'); 
					if (elLogo) elLogo.innerHTML = getLogoSvg('#fb510c', '#f45825');
				}
			});
		}

		function runClientSideDiagnostics() {
			var icmpEl = document.getElementById('diag_icmp');
			var tcpEl = document.getElementById('diag_tcp');
			var urlEl = document.getElementById('diag_url');

			if (icmpEl) icmpEl.textContent = 'Testing...';
			if (tcpEl) tcpEl.textContent = 'Testing...';
			if (urlEl) urlEl.textContent = 'Testing...';

			var t0 = performance.now();
			var img = new Image();
			img.onload = img.onerror = function() {
				var latency = Math.round(performance.now() - t0);
				if (icmpEl) icmpEl.textContent = latency + ' ms';
			};
			img.src = 'https://www.google.com/images/branding/googlelogo/1x/googlelogo_color_272x92dp.png?_=' + Date.now();

			var t2 = performance.now();
			fetch('https://www.gstatic.com/generate_204?_=' + Date.now(), { mode: 'no-cors', cache: 'no-store' }).then(function() {
				var tcpLatency = Math.round(performance.now() - t2);
				if (tcpEl) tcpEl.textContent = tcpLatency + ' ms';
			}).catch(function() {
				var t3 = performance.now();
				fetch('https://cp.cloudflare.com/generate_204?_=' + Date.now(), { mode: 'no-cors', cache: 'no-store' }).then(function() {
					var tcpLatency2 = Math.round(performance.now() - t3);
					if (tcpEl) tcpEl.textContent = tcpLatency2 + ' ms';
				}).catch(function() {
					if (tcpEl) tcpEl.textContent = 'Error';
				});
			});

			var t4 = performance.now();
			fetch('https://ipapi.co/json/', { mode: 'cors', cache: 'no-store' }).then(function(res) {
				var urlLatency = Math.round(performance.now() - t4);
				if (urlEl) urlEl.textContent = urlLatency + ' ms';
			}).catch(function() {
				if (urlEl) urlEl.textContent = 'Timeout';
			});
		}

		function fetchLog() {
			var logArea = document.getElementById('psiphon_live_log');
			if (!logArea) return;
			L.resolveDefault(fs.read('/tmp/psiphon.log'), '').then(function(res) {
				if (res && res.trim() !== '') {
					var lines = res.split('\n');
					var filteredLog = [];

					for (var i = 0; i < lines.length; i++) {
						var line = lines[i].trim();
						if (line === '') continue;

						if (line.startsWith('[System]') || line.startsWith('$')) {
							filteredLog.push(line);
							continue;
						}

						try {
							var logObj = JSON.parse(line);
							var time = logObj.timestamp ? logObj.timestamp.substring(11, 19) : '';
							var timePrefix = time ? '[' + time + '] ' : '';
							
							if (logObj.noticeType === 'ListeningSocksProxyPort') {
								filteredLog.push(timePrefix + 'SOCKS proxy listening on port ' + logObj.data.port);
							} else if (logObj.noticeType === 'ListeningHttpProxyPort') {
								filteredLog.push(timePrefix + 'HTTP proxy listening on port ' + logObj.data.port);
							} else if (logObj.noticeType === 'ConnectedServerRegion') {
								filteredLog.push(timePrefix + 'Connected to server region ' + logObj.data.serverRegion);
							} else if (logObj.noticeType === 'Tunnels') {
								filteredLog.push(timePrefix + 'Tunnels Count ' + logObj.data.count);
								var tunCountEl = document.getElementById('stat_tunnels_count');
								if (tunCountEl) tunCountEl.textContent = logObj.data.count;
								
								// بررسی هوشمند: به محض برقراری اولین تونل، دقیقاً یک‌بار ریفرش IP انجام شود تا لوگو سبز شود
								if (logObj.data.count > 0 && !self.hasConnected) {
									self.hasConnected = true;
									refreshIPs();
								} else if (logObj.data.count === 0) {
									self.hasConnected = false;
								}
							} else if (logObj.noticeType === 'TrafficRateLimits') {
								var down = (logObj.data.downstreamBytesPerSecond / 1024).toFixed(1);
								var up = (logObj.data.upstreamBytesPerSecond / 1024).toFixed(1);
								filteredLog.push(timePrefix + 'Speed Down ' + down + ' KB/s Up ' + up + ' KB/s');
								var downEl = document.getElementById('stat_down_speed');
								var upEl = document.getElementById('stat_up_speed');
								if (downEl) downEl.textContent = down + ' KB/s';
								if (upEl) upEl.textContent = up + ' KB/s';
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

					var isBottom = (logArea.scrollHeight - logArea.scrollTop <= logArea.clientHeight + 20);
					logArea.value = filteredLog.length > 0 ? filteredLog.join('\n') : _('Standby');
					if (isBottom) logArea.scrollTop = logArea.scrollHeight;
				} else {
					logArea.value = _('Service stopped or log empty');
				}
			});
		}

		setTimeout(function() {
			document.querySelectorAll('.cbi-input-select, select, option, .control-group').forEach(function(el) { el.classList.add('win-flag'); });
		}, 500);

		poll.add(L.bind(function() {
			return fetchLog();
		}, this), 3);

		setTimeout(L.bind(function() { refreshIPs(); fetchLog(); runClientSideDiagnostics(); }, this), 1000);

		return m.render();
	}
});
EOF

# ==============================================================================
# GROUP 7 (Priority 7): Service Restart & Cache Cleanup
# ==============================================================================
echo "Clearing cache and restarting UI..."

rm -rf /tmp/luci-indexcache* /tmp/luci-modulecache/ /var/luci-indexcache*
/etc/init.d/rpcd restart
/etc/init.d/uhttpd restart
/etc/init.d/firewall restart
chmod +x /etc/init.d/psiphon

/etc/init.d/psiphon restart

echo "Setup Completed Successfully! All updates applied."



```



*تست اجرای و متوقف کردن با دستور*

* **روشن کردن تانل سایفون:**
```bash
/etc/init.d/psiphon start
```
* **خاموش کردن کامل سیستم:**
```bash
/etc/init.d/psiphon stop
```
* **فعال‌سازی اجرای خودکار پس از روشن شدن روتر:**
```bash
/etc/init.d/psiphon enable
```

## 🗑️ ۸. حذف کامل و بی‌بازگشت سایفون از سیستم (Uninstall)

اگر به هر دلیلی تمایل داشتید تمامی تنظیمات، فایل‌های باینری، دیتابیس‌ها و منوهای پنل لوسی سایفون را بدون به جا ماندن هیچ ردپایی حذف کنید، اسکریپت یکپارچه زیر را در ترمینال روتر اجرا کنید:

```bash
# متوقف کردن سرویس و غیرفعال‌سازی آن
/etc/init.d/psiphon stop 2>/dev/null
/etc/init.d/psiphon disable 2>/dev/null

# پاکسازی قوانین فایروال مربوط به سایفون
for sec in $(uci show firewall | grep -E "name='psiphon'|dest='psiphon'|src='psiphon'" | cut -d. -f1,2); do
    uci delete "$sec" 2>/dev/null
done
uci commit firewall

# حذف کامل فایل‌ها، باینری‌ها و دایرکتوری‌ها
rm -f /usr/bin/psiphon-core
rm -rf /usr/bin/psiphon_data
rm -f /usr/share/rpcd/acl.d/luci-app-psiphon.json
rm -f /etc/config/psiphon
rm -f /usr/share/luci/menu.d/luci-app-psiphon.json
rm -f /etc/init.d/psiphon
rm -rf /www/luci-static/resources/view/vpn/psiphon.js
rm -f /tmp/psiphon.log

# پاک‌سازی کش LuCI و راه‌اندازی مجدد سرویس‌های سیستمی
rm -rf /tmp/luci-indexcache* /tmp/luci-modulecache/ /var/luci-indexcache*
/etc/init.d/rpcd restart
/etc/init.d/uhttpd restart
/etc/init.d/firewall restart

echo "Psiphon has been completely uninstalled from the system."
```

## محیط Luci برای سایفون 

<img width="1746" height="1640" alt="Psiphon-Core Openwrt25" src="https://github.com/user-attachments/assets/66af9842-4eca-4622-acc5-7a8be2000192" />

 


