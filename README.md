**پارسی** | [English](README.en.md)




# راهنمای جامع نصب، راه‌اندازی و خودکارسازی Psiphon-Core به همراه پنل گرافیکی LuCI در OpenWrt 25

این پروژه یک راهنمای کاملاً بومی و عملیاتی برای کامپایل، کانفیگ و اتصال هسته لینوکسی سایفون (`psiphon-core`) به رابط کاربری گرافیکی لوسی (**LuCI JavaScript**) در سیستم‌عامل **OpenWrt 25** است. تمامی کلیدهای کنترل سرویس، فیلدهای تنظیمات (پورت‌ها، کشور، پروتکل) و بخش مانیتورینگ وضعیت آی‌پی کاملاً همگام‌سازی شده‌اند.

---

## 🛠️ ۱. آموزش کامپایل فایل باینری (روی کامپیوتر) - PowerShell

برای ساخت فایل اجرایی اختصاصی روتر خود، ابتدا مطمئن شوید زبان Go روی سیستم شما نصب است. سپس ترمینال را باز کرده و بر اساس معماری پردازنده روتر خود، دستورات زیر را اجرا کنید:

```powershell
# دریافت سورس کد رسمی هسته سایفون از مخزن گیت‌هاب
git clone https://github.com/Psiphon-Labs/psiphon-tunnel-core.git
cd psiphon-tunnel-core/ConsoleClient

# کامپایل برای روترهای ۶۴ بیتی (Aarch64 / ARM64 مانند GL.iNet MT3000 / MT2500)
$env:GOOS="linux"
$env:GOARCH="arm64"
go build -o psiphon-core main.go

# کامپایل برای روترهای ۳۲ بیتی (ARMv7 مانند Google Wifi AC-1304)
$env:GOOS="linux"
$env:GOARCH="arm"
$env:GOARM="7"
go build -o psiphon-core main.go


```

*پس از اتمام کامپایل، فایل خروجی `psiphon-core` را از طریق ابزارهایی مانند MobaXterm یا SCP به مسیر `/usr/bin/` روی روتر منتقل کنید.*

---

## 🚀 ۲. آماده‌سازی و نصب پیش‌نیازها در OpenWrt 25

در نسخه OpenWrt 25 ابزار قدیمی `opkg` حذف شده و سیستم از **`apk`** استفاده می‌کند. با اجرای دستور زیر، مجوزهای فایل باینری را صادر کرده و ابزارهای مانیتورینگ و شبکه را نصب کنید:

```bash
# صدور مجوز اجرا و ساخت پوشه دیتابیس سایفون
chmod +x /usr/bin/psiphon-core
mkdir -p /usr/bin/psiphon_data

# نصب پیش‌نیازهای شبکه و ابزار مانیتورینگ آی‌پی (مخصوص OpenWrt 25)
apk -U add socat curl wget-ssl coreutils-nohup


```

---

## 📁 ۳. استقرار زیرساخت و کدهای کامل پنل گرافیکی LuCI

بلوک کد زیر یک اسکریپت همه‌کاره است. آن را به طور کامل کپی کرده و در ترمینال روتر پیست کنید. این اسکریپت تمام فایل‌های ساختاری لوسی، تنظیمات UCI، کدهای جاوااسکریپت داشبورد (همراه با دکمه‌ها و فیلدهای کامل) و مجوزهای امنیتی ACL را به صورت یکجا ایجاد می‌کند:

```bash

# ۱. ساخت پوشه‌های مورد نیاز سیستم در صورت عدم وجود
mkdir -p /www/luci-static/resources/view/services
mkdir -p /usr/share/luci/menu.d
mkdir -p /usr/share/rpcd/acl.d
mkdir -p /etc/config

# ۲. ایجاد فایل تنظیمات پیش‌فرض سایفون
cat << 'EOF' > /etc/config/psiphon
config psiphon 'config'
	option enabled '0'
	option country ''
	option transport 'STANDARD'
	option socks_port '10808'
	option http_port '10809'
EOF

# ۳. ساخت فایل جاوااسکریپت اصلی پنل لوسی (بدون دکمه پاک کردن کش)
cat << 'EOF' > /www/luci-static/resources/view/services/psiphon.js
'use strict';
'require view';
'require form';
'require fs';
'require ui';
'require uci';
'require poll';

return L.view.extend({
	// متغیر کمکی برای ذخیره آی‌پی روتر
	router_ip: '192.168.8.1',

	load: function() {
		// واکشی خودکار آی‌پی محلی (LAN) روتر از uci قبل از رندر صفحه
		return L.uci.load('network').then(L.bind(function() {
			var ip = L.uci.get('network', 'lan', 'ipaddr');
			if (ip) {
				this.router_ip = ip;
			}
		}, this));
	},

	render: function() {
		const self = this;
		const m = new L.form.Map('psiphon', _('Psiphon VPN Configuration'), _('Unified Single-Page Control Panel for Psiphon Tunnel Core.'));
		const s = m.section(L.form.NamedSection, 'config', 'psiphon', _('Service Status & Configuration'));
		s.addremove = false;
		
		// ==========================================
		// بخش ۱: داشبورد مانیتورینگ آی‌پی
		// ==========================================
		let o = s.option(L.form.DummyValue, '_ip_box');
		o.rawhtml = true;
		o.render = function() {
			return E('div', { 'class': 'cbi-value', 'style': 'margin-bottom: 20px;' }, [
				E('div', { 'style': 'display: flex; flex-flow: row wrap; align-items: center; justify-content: space-between; background: #1a1c20; padding: 12px 20px; border-radius: 8px; border: 1px solid #333; box-shadow: 0 4px 6px rgba(0,0,0,0.3); width: 100%; gap: 15px;' }, [
					
					// بخش آی‌پی اصلی
					E('div', { 'style': 'display: flex; align-items: center; gap: 8px;' }, [
						E('span', { 'style': 'color: #88a; font-size: 13px; text-transform: uppercase; font-weight: bold;' }, _('🔴 Real IP:')),
						E('span', { 'id': 'real_ip_display', 'style': 'font-size: 14px; color: #ccc; font-family: monospace;' }, _('⏳ Checking...'))
					]),

					// خط جداکننده وسط
					E('div', { 'style': 'width: 1px; height: 24px; background-color: #444; display: inline-block;' }, ''),

					// بخش آی‌پی سایفون
					E('div', { 'style': 'display: flex; align-items: center; gap: 8px; flex: 1;' }, [
						E('span', { 'style': 'color: #88a; font-size: 13px; text-transform: uppercase; font-weight: bold;' }, _('🟢 Psiphon IP:')),
						E('span', { 'id': 'vpn_ip_display', 'style': 'font-size: 14px; color: #00ff66; font-family: monospace;' }, _('⏳ Checking...'))
					]),

					// دکمه رفرش
					E('div', {}, [
						E('button', {
							'class': 'btn cbi-button cbi-button-apply',
							'style': 'padding: 6px 15px; font-weight: bold; white-space: nowrap;',
							'click': function(ev) {
								ev.preventDefault();
								refreshIPs();
							}
						}, _('🔄 Refresh'))
					])
				])
			]);
		};

		function updateDisplayElement(el, data, fallbackText, successColor) {
			if (!el) return;
			if (data && data.status === 'success') {
				const flagUrl = 'https://flagcdn.com/w20/' + data.countryCode.toLowerCase() + '.png';
				el.innerHTML = '';
				el.appendChild(E('img', { 'src': flagUrl, 'style': 'vertical-align: middle; margin-right: 8px; border-radius: 2px;', 'alt': data.countryCode }));
				el.appendChild(E('b', { 'style': 'font-size: 15px; color: ' + (successColor || '#ccc') }, data.query));
				el.appendChild(E('span', { 'style': 'color: #888; font-size: 12px; margin-left: 5px;' }, '(' + data.country + ')'));
			} else {
				el.textContent = fallbackText;
			}
		}

		function refreshIPs() {
			const elReal = document.getElementById('real_ip_display');
			const elVpn = document.getElementById('vpn_ip_display');
			if (elReal) elReal.textContent = '⏳ ' + _('Checking...');
			if (elVpn) elVpn.textContent = '⏳ ' + _('Checking...');

			const cmdReal = 'curl -sL -m 5 http://ip-api.com/json/ || wget -qO- --timeout=5 http://ip-api.com/json/ || true';
			L.fs.exec('/bin/sh', ['-c', cmdReal]).then(function(res) {
				try {
					if (res.stdout && res.stdout.trim() !== '') {
						const d = JSON.parse(res.stdout);
						updateDisplayElement(elReal, d, '⚠️ ' + _('Failed'));
					} else {
						if (elReal) elReal.textContent = '⚠️ ' + _('Network Error');
					}
				} catch(e) { 
					if (elReal) elReal.textContent = '⚠️ ' + _('Parse Error'); 
				}
			}).catch(function() {
				if (elReal) elReal.textContent = '⚠️ ' + _('System Error');
			});

			const cmdVpn = 'export http_proxy="http://127.0.0.1:10809"; export all_proxy="socks5://127.0.0.1:10808"; curl -sL -m 6 http://ip-api.com/json/ || wget -qO- --timeout=6 http://ip-api.com/json/ || true';
			L.fs.exec('/bin/sh', ['-c', cmdVpn]).then(function(res) {
				try {
					if (res.stdout && res.stdout.trim() !== '') {
						const d = JSON.parse(res.stdout);
						updateDisplayElement(elVpn, d, '🔴 ' + _('Disconnected'), '#00ff66');
					} else {
						if (elVpn) elVpn.textContent = '🔴 ' + _('Disconnected');
					}
				} catch(e) { 
					if (elVpn) elVpn.textContent = '🔴 ' + _('Disconnected'); 
				}
			}).catch(function() {
				if (elVpn) elVpn.textContent = '🔴 ' + _('Disconnected');
			});
		}
		
		// ==========================================
		// بخش ۲: کنترل سرویس
		// ==========================================
		o = s.option(L.form.DummyValue, '_control_buttons');
		o.rawhtml = true;
		o.render = function() {
			return E('div', { 'class': 'cbi-value' }, [
				E('label', { 'class': 'cbi-value-title' }, _('Service Control')),
				E('div', { 'class': 'cbi-value-field' }, [
					E('button', { 
						'class': 'btn cbi-button cbi-button-remove', 
						'style': 'margin-right: 10px;', 
						'click': function(ev) { 
							ev.preventDefault(); 
							ui.showModal(_('Stopping service...'), [ E('p', { 'class': 'spinning' }, _('Please wait...')) ]);
							L.fs.exec('/etc/init.d/psiphon', ['stop']).then(function() { 
								L.fs.exec('/bin/sh', ['-c', 'killall -9 psiphon-core socat 2>/dev/null || true']).then(function() {
									ui.hideModal();
									ui.addNotification(null, E('p', _('Psiphon Service Stopped successfully.')), 'info');
									refreshIPs();
								});
							}).catch(function(err) { 
								ui.hideModal();
								ui.addNotification(null, E('p', _('Stop Error: ') + err), 'danger');
							}); 
						}
					}, _('Stop')),
					E('button', { 
						'class': 'btn cbi-button cbi-button-apply', 
						'click': function(ev) { 
							ev.preventDefault(); 
							ui.showModal(_('Starting service...'), [ E('p', { 'class': 'spinning' }, _('Initializing Psiphon Core...')) ]);
							L.fs.exec('/etc/init.d/psiphon', ['start']).then(function() { 
								ui.hideModal();
								ui.addNotification(null, E('p', _('Psiphon Service Started successfully.')), 'info');
								setTimeout(refreshIPs, 3000);
							}).catch(function(err) { 
								ui.hideModal();
								ui.addNotification(null, E('p', _('Start Error: ') + err), 'danger');
							}); 
						}
					}, _('Start'))
				])
			]);
		};

		// ==========================================
		// بخش ۳: تنظیمات عمومی و پورت‌ها
		// ==========================================
		o = s.option(L.form.Flag, 'enabled', _('Enable'));
		o.rmempty = false;

		o = s.option(L.form.ListValue, 'country', _('Region'));
		o.value('', _('Best Performance'));
		o.value('AT', _('Austria'));
		o.value('BE', _('Belgium'));
		o.value('CA', _('Canada'));
		o.value('CH', _('Switzerland'));
		o.value('DE', _('Germany'));
		o.value('DK', _('Denmark'));
		o.value('ES', _('Spain'));
		o.value('FI', _('Finland'));
		o.value('FR', _('France'));
		o.value('GB', _('United Kingdom'));
		o.value('IT', _('Italy'));
		o.value('JP', _('Japan'));
		o.value('NL', _('Netherlands'));
		o.value('NO', _('Norway'));
		o.value('PL', _('Poland'));
		o.value('SE', _('Sweden'));
		o.value('SG', _('Singapore'));
		o.value('US', _('United States'));
		o.default = '';

		o = s.option(L.form.ListValue, 'transport', _('Transport Mode'));
		o.value('STANDARD', _('Standard'));
		o.value('QUIC', _('QUIC'));
		o.value('SSH', _('SSH'));
		o.default = 'STANDARD';

		// پورت SOCKS با قابلیت تولید خودکار توضیحات بر اساس آی‌پی روتر
		const socksOpt = s.option(L.form.Value, 'socks_port', _('SOCKS Port'));
		socksOpt.datatype = 'port';
		socksOpt.default = '10808';
		socksOpt.description = _('Connect clients to: ') + '<b>' + self.router_ip + ':10808</b>';
		socksOpt.write = function(section_id, value) {
			this.description = _('Connect clients to: ') + '<b>' + self.router_ip + ':' + (value || '10808') + '</b>';
			return L.form.Value.prototype.write.call(this, section_id, value);
		};

		// پورت HTTP با قابلیت تولید خودکار توضیحات بر اساس آی‌پی روتر
		const httpOpt = s.option(L.form.Value, 'http_port', _('HTTP Port'));
		httpOpt.datatype = 'port';
		httpOpt.default = '10809';
		httpOpt.description = _('Connect clients to: ') + '<b>' + self.router_ip + ':10809</b>';
		httpOpt.write = function(section_id, value) {
			this.description = _('Connect clients to: ') + '<b>' + self.router_ip + ':' + (value || '10809') + '</b>';
			return L.form.Value.prototype.write.call(this, section_id, value);
		};

		// ==========================================
		// بخش ۴: مدیریت لاگ‌ها (دکمه کش حذف شد)
		// ==========================================
		o = s.option(L.form.Button, '_clear_log', _('Log Actions'));
		o.inputtitle = _('Clear Log Screen');
		o.inputstyle = 'reset';
		o.onclick = function(ev) {
			const box = document.getElementById('psiphon_live_log');
			if (box) box.value = _('Log monitor cleared...');
			return L.fs.exec('/bin/sh', ['-c', '> /tmp/psiphon.log || true']);
		};

		// ==========================================
		// بخش ۵: نمایشگر لاگ و ترمینال
		// ==========================================
		o = s.option(L.form.DummyValue, '_console_and_log');
		o.rawhtml = true;
		o.render = function() {
			return E('div', { 'class': 'cbi-value' }, [
				E('label', { 'class': 'cbi-value-title' }, _('Terminal / Logs')),
				E('div', { 'class': 'cbi-value-field', 'style': 'width: 100%; box-sizing: border-box;' }, [
					
					// کادر لاگ
					E('textarea', { 
						'id': 'psiphon_live_log', 
						'style': 'width: 100%; height: 260px; font-family: monospace; font-size: 12px; background: #111; color: #00ff66; padding: 10px; border-radius: 4px; border: 1px solid #222; resize: none; line-height: 1.6; box-sizing: border-box; margin-bottom: 15px;', 
						'readonly': 'readonly' 
					}, _('Waiting for log stream...')),

					// کادر ترمینال
					E('textarea', { 
						'id': 'cmd_input', 
						'placeholder': 'Enter shell command here...\nExample: ps -w | grep psiphon', 
						'style': 'width: 100%; height: 90px; padding: 10px; margin-bottom: 10px; background: #1a1c20; color: #fff; border: 1px solid #444; font-family: monospace; resize: none; box-sizing: border-box; border-radius: 4px;' 
					}),
					
					// دکمه اجرا
					E('div', { 'style': 'text-align: right;' }, [
						E('button', { 
							'class': 'btn cbi-button cbi-button-apply',
							'click': function(ev) {
								ev.preventDefault();
								const cmdInput = document.getElementById('cmd_input');
								const cmd = cmdInput ? cmdInput.value.trim() : '';
								if (!cmd) return;

								const logArea = document.getElementById('psiphon_live_log');
								if (logArea) {
									logArea.value += '\n$ ' + cmd + '\n';
									logArea.scrollTop = logArea.scrollHeight;
								}
								
								L.fs.exec('/bin/sh', ['-c', cmd]).then(function(res) {
									if (logArea) {
										logArea.value += (res.stdout || '') + (res.stderr || '');
										logArea.scrollTop = logArea.scrollHeight;
									}
									if (cmdInput) cmdInput.value = '';
								});
							}
						}, _('▶ Run Command'))
					])
				])
			]);
		};

		// تابع هوشمند فیلتر و رندر لاگ‌ها
		function fetchLog() {
			const logArea = document.getElementById('psiphon_live_log');
			if (!logArea) return; 
			
			L.resolveDefault(L.fs.read('/tmp/psiphon.log'), '').then(function(res) {
				if (res && res.trim() !== '') {
					const lines = res.split('\n');
					const filteredLog = [];

					for (let i = 0; i < lines.length; i++) {
						const line = lines[i].trim();
						if (line === '') continue;

						try {
							const logObj = JSON.parse(line);
							const time = logObj.timestamp ? logObj.timestamp.substring(11, 19) : "";
							
							if (logObj.noticeType === "ConnectedServerRegion") {
								filteredLog.push("[" + time + "] 🟢 CONNECTED TO SERVER REGION: " + logObj.data.serverRegion);
							} else if (logObj.noticeType === "Tunnels") {
								filteredLog.push("[" + time + "] ⚡ Active Tunnels Count: " + logObj.data.count);
							} else if (logObj.noticeType === "TrafficRateLimits") {
								const down = (logObj.data.downstreamBytesPerSecond / 1024).toFixed(1);
								const up = (logObj.data.upstreamBytesPerSecond / 1024).toFixed(1);
								filteredLog.push("[" + time + "] 📊 Speed -> Down: " + down + " KB/s | Up: " + up + " KB/s");
							} else if (logObj.noticeType === "ClientRegion") {
								filteredLog.push("[" + time + "] 🌍 Current Internet Uplink Location: " + logObj.data.region);
							} else if (logObj.noticeType === "SkipServerEntry") {
								filteredLog.push("[" + time + "] ⚠️ Skipping Blocked Server: " + (logObj.data.reason || "Timeout"));
							}
						} catch (e) {
							if (!line.includes(" Listening") && !line.includes("Parameters") && !line.includes("AvailableEgress") && !line.includes("ActiveAuthorizationIDs")) {
								filteredLog.push(line);
							}
						}
					}
					logArea.value = filteredLog.length > 0 ? filteredLog.join('\n') : _('Standby...');
					logArea.scrollTop = logArea.scrollHeight;
				} else {
					logArea.value = _('Service stopped or log empty.');
				}
			});
		}

		// راه‌اندازی تسک‌های خودکار و زمان‌بندی زنده LuCI Poll API
		L.Poll.add(function() {
			return Promise.all([
				fetchLog()
			]);
		}, 3);

		L.Poll.add(function() {
			return Promise.all([
				refreshIPs()
			]);
		}, 10);

		// اجرای اولیه پس از لود صفحه
		setTimeout(function() {
			refreshIPs();
			fetchLog();
		}, 1000);

		return m.render();
	}
});
EOF

# ۴. ایجاد فایل منو (Menu JSON) - ثبت در بخش Services لوسی
cat << 'EOF' > /usr/share/luci/menu.d/luci-app-psiphon.json
{
	"admin/services/psiphon": {
		"title": "Psiphon",
		"action": {
			"type": "view",
			"path": "services/psiphon"
		},
		"depends": {
			"acl": [ "luci-app-psiphon" ]
		}
	}
}
EOF

# ۵. ایجاد فایل دسترسی امنیتی سیستم (ACL JSON) - مجوز دسترسی به فرآیندها
cat << 'EOF' > /usr/share/rpcd/acl.d/luci-app-psiphon.json
{
	"luci-app-psiphon": {
		"description": "Grant access to Psiphon control and execution",
		"read": {
			"file": {
				"/tmp/psiphon.log": [ "read" ]
			},
			"uci": [ "psiphon", "network" ]
		},
		"write": {
			"file": {
				"/tmp/psiphon.log": [ "write" ],
				"/bin/sh": [ "exec" ],
				"/etc/init.d/psiphon": [ "exec" ]
			},
			"uci": [ "psiphon" ]
		}
	}
}
EOF

# ۶. تنظیم دقیق پرمیشن‌ها و سطوح دسترسی تمامی فایل‌ها
chmod 644 /etc/config/psiphon
chmod 644 /www/luci-static/resources/view/services/psiphon.js
chmod 644 /usr/share/luci/menu.d/luci-app-psiphon.json
chmod 644 /usr/share/rpcd/acl.d/luci-app-psiphon.json

# ۷. راه اندازی مجدد RPC سیستم و پاکسازی تمام کش‌های LuCI برای رندر مجدد
/etc/init.d/rpcd restart
rm -rf /tmp/luci-indexcache /tmp/luci-modulecache

echo "Psiphon panel updated successfully! Please hard refresh your browser (Ctrl+F5)."


```

## ⚙️ ۴. ایجاد اسکریپت سرویس هوشمند سیستم (`/etc/init.d/psiphon`)

این اسکریپت مغز متفکر اتصال بک‌اند است. هنگام استارت، تمامی فیلدهای تکمیل‌شده در پنل لوسی (مانند کشور انتخابی، پورت‌ها و نوع پروتکل) را دریافت کرده، فایل کانفیگ اصلی سایفون را در لحظه بازنویسی می‌کند و پروسه هدایت اتصالات به پورت‌های محلی شبکه LAN روتر را انجام می‌دهد:

```bash
cat << 'EOF' > /etc/init.d/psiphon
#!/bin/sh /etc/rc.common

START=99
USE_PROCD=1

start_service() {
    # ۱. خواندن پیکربندی‌های ذخیره شده از uci لوسی
    config_load psiphon
    local enabled country transport socks_port http_port
    
    config_get_bool enabled config enabled 0
    config_get country config country 'ALL'
    config_get transport config transport 'STANDARD'
    config_get socks_port config socks_port '10808'
    config_get http_port config http_port '10809'
    
    # اگر تیک گزینه Enable خاموش باشد، اجرای سرویس متوقف می‌شود
    if [ "$enabled" -eq 0 ]; then
        echo "Psiphon is disabled in LuCI configuration. Skipping start." >> /tmp/psiphon.log
        return 0
    fi

    # ۲. ساخت و بروزرسانی پویا و آنی فایل کانفیگ JSON سایفون بر اساس متغیرهای انتخابی لوسی
    cat << JSON > /usr/bin/psiphon.config
{
    "SocksProxyPort": $socks_port,
    "HttpProxyPort": $http_port,
    "DataRootDirectory": "/usr/bin/psiphon_data",
    "EgressRegion": "$country",
    "TransportProtocols": ["$transport"],
    "PropagationChannelId": "0000000000000000",
    "SponsorId": "0000000000000000",
    "ServerEntrySignaturePublicKey": "sHuUVTWaRyh5pZwy4UguSgkwmBe0EHtJJkoF5WrxmvA=",
    "UseIndistinguishableTLS": true
}
JSON

    # ۳. راه‌اندازی و مدیریت پروسه هوشمند هسته با سیستم پروکد
    procd_open_instance "psiphon"
    procd_set_param command /bin/sh -c "
        killall -9 psiphon-core socat 2>/dev/null
        
        # اجرای فایل باینری سایفون با کانفیگ بازنویسی شده
        /usr/bin/psiphon-core -config /usr/bin/psiphon.config > /tmp/psiphon.log 2>&1 &
        PSIPHON_PID=\$!
        
        # انتظار منطقی برای انجام موفق هندشیک‌ها و باز شدن پورت کلاینت
        echo 'Waiting for Psiphon to establish tunnels...' >> /tmp/psiphon.log
        while ! grep -q 'ListeningSocksProxyPort' /tmp/psiphon.log; do
            sleep 1
        done
        
        # استخراج اتوماتیک پورت‌های داینامیک داخلی ایجاد شده توسط هسته سایفون
        CORE_SOCKS=\$(grep 'ListeningSocksProxyPort' /tmp/psiphon.log | grep -o '\"port\":[0-9]*' | cut -d':' -f2)
        CORE_HTTP=\$(grep 'ListeningHttpProxyPort' /tmp/psiphon.log | grep -o '\"port\":[0-9]*' | cut -d':' -f2)
        
        # واکشی آی‌پی محلی فعلی روتر (LAN IP) برای پل زدن سراسری اتصالات
        ROUTER_IP=\$(ubus call network.interface.lan status | jsonfilter -e '@[\"ipv4-address\"][0].address')
        [ -z \"\$ROUTER_IP\" ] && ROUTER_IP='192.168.1.1'
        
        # اتصال پورت‌های لوکال هاست سایفون به پورت‌های ثابت تعریف شده در لوسی بر روی کل شبکه LAN
        socat TCP-LISTEN:\$socks_port,fork,bind=\$ROUTER_IP TCP:127.0.0.1:\$CORE_SOCKS &
        socat TCP-LISTEN:\$http_port,fork,bind=\$ROUTER_IP TCP:127.0.0.1:\$CORE_HTTP &
        
        echo \"Psiphon ports successfully bound to LAN IP \$ROUTER_IP on ports \$socks_port and \$http_port\" >> /tmp/psiphon.log
        
        wait \$PSIPHON_PID
    "
    procd_set_param respawn
    procd_close_instance
}

stop_service() {
    killall -9 psiphon-core socat 2>/dev/null || true
    echo "Psiphon core and socat tunnels stopped safely." > /tmp/psiphon.log
}
EOF

# اعطای دسترسی‌های اجرایی سرویس سیستم
chmod +x /etc/init.d/psiphon
/etc/init.d/psiphon enable


```

---

## 🔄 ۵. بارگذاری نهایی و اعمال تغییرات پنل گرافیکی

برای پاک کردن سیستم کش قدیمی رابط کاربری لوسی و بارگذاری کامل اسکریپت‌های امنیتی سیستم RPC، دستورات زیر را اجرا کنید:

```bash
chmod 644 /usr/share/rpcd/acl.d/luci-app-psiphon.json
chmod 644 /usr/share/luci/menu.d/luci-app-psiphon.json

# راه‌اندازی مجدد سرویس سیستم تبادل داده و وب‌سرور لوسی
/etc/init.d/rpcd restart
/etc/init.d/uhttpd restart


```

*حالا مرورگر خود را با کلیدهای ترکیبی `Ctrl + F5` در سیستم ریفرش کنید تا منوی سرویس با عملکرد کامل کلیدها بالا بیاید. (توصیه می‌شود یک بار از پنل Log Out کرده و مجدد وارد شوید).*

---

## 🛡️ ۶. تنظیمات فایروال (مبتنی بر Nftables در OpenWrt 25)

برای اینکه پورت‌های جدید پروکسی روتر اجازه تبادل اطلاعات با سایر دستگاه‌های متصل به وای‌فای یا شبکه LAN را داشته باشند، پورت‌ها را در لایه فایروال محلی باز کنید:

```bash
# باز کردن پورت‌های ورودی فایروال شبکه برای اتصالات کلاینت‌ها
nft add rule inet fw4 input iifname "br-lan" tcp dport 10808-10809 accept 2>/dev/null || true
/etc/init.d/firewall reload


```

اگر می‌خواهید بعد از ریبوت هم قوانین فایروال پاک نشود دستور زیر را بزنید
```bash

# اضافه کردن قانون فایروال با ساختار کاملاً منظم و ایجاد خط جدید
cat << 'EOF' >> /etc/config/firewall

config rule
	option name 'Allow-Psiphon-Proxy'
	option src 'lan'
	option dest_port '10808-10809'
	option proto 'tcp'
	option target 'ACCEPT'

EOF

/etc/init.d/firewall restart

```


---

## 🩺 ۷. تست و عیب‌یابی شبکه از طریق ترمینال

پس از زدن دکمه **Start Service** در پنل لوسی، با دستورات زیر می‌توانید عملکرد فیلترشکن را به طور مستقیم در لایه شبکه روتر ارزیابی کنید:

* **تست عبور موفق ترافیک از پورت HTTP Proxy:**

```bash
curl -x http://127.0.0.1:10809 https://api.ipify.org


```

* **تست عبور موفق ترافیک از پورت SOCKS5 Proxy:**

```bash
curl --socks5-hostname 127.0.0.1:10808 https://api.ipify.org


```

---

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
# ۱. متوقف کردن پردازش‌ها و غیرفعال‌سازی سرویس سیستم
/etc/init.d/psiphon disable 2>/dev/null
/etc/init.d/psiphon stop 2>/dev/null
killall -9 psiphon-core socat 2>/dev/null

# ۲. پاکسازی کامل فایل‌های سیستمی و پنل گرافیکی لوسی
rm -f /usr/bin/psiphon-core
rm -rf /usr/bin/psiphon_data
rm -f /usr/bin/psiphon.config
rm -f /etc/init.d/psiphon
rm -f /etc/config/psiphon
rm -f /www/luci-static/resources/view/services/psiphon.js
rm -f /usr/share/luci/menu.d/luci-app-psiphon.json
rm -f /usr/share/rpcd/acl.d/luci-app-psiphon.json
rm -f /tmp/psiphon.log

# ۳. راه‌اندازی مجدد بخش دسترسی‌ها و پاک کردن کامل سیستم کش لوسی
/etc/init.d/rpcd restart
/etc/init.d/uhttpd restart
rm -f /tmp/luci-indexcache*
rm -rf /tmp/luci-modulecache/*
rm -rf /tmp/luci-sessions/*

echo "Psiphon app and all associated LuCI components successfully uninstalled."


```
