**پارسی** | [English](README.en.md) | [Chinese](README.zh.md)

راهنمای نصب، راه‌اندازی و خودکارسازی Psiphon-Core به همراه پنل گرافیکی LuCI در OpenWrt 25
این پروژه یک راهنمای کاملاً عملیاتی برای اتصال هسته لینوکسی سایفون (psiphon-core) به رابط کاربری گرافیکی لوسی (LuCI JavaScript) در سیستم‌عامل OpenWrt 25 است. تمامی کلیدهای کنترل سرویس، فیلدهای تنظیمات (پورت‌ها، کشور، پروتکل) و بخش مانیتورینگ وضعیت آی‌پی و جلوگیری از نشت  DNSکاملاً همگام‌سازی شده‌اند. 

## 🚀 آموزش نصب آسان (Installation)

برای نصب سریع، کافیست از طریق نرم‌افزارهای SSH (مانند PuTTY یا Terminal) به روتر خود متصل شوید و دستور زیر را اجرا کنید:
```bash

wget -O /tmp/install.sh https://raw.githubusercontent.com/MehArt44/Psiphon-core-Openwrt25-LuCI/main/install.sh

sh /tmp/install.sh

```

## 🚀 آموزش نصب دستی (Installation)

 🛠️ ۱. دانلود فایل مناسب روتر از بخش Releases 
شناسایی معماری CPU روتر دستور زیر در روتر بزنید

```bash
uname -m
```

 🚀 ۲. انتقال فایل‌ها به روتر

1.	پس از اتمام دانلود ، نام فایل را به `psiphon-core` تغییر دهید 
2.	از طریق ابزارهایی مانند MobaXterm یا SCP به مسیر زیر داخل روتر منتقل کنید 
3.	 به پوشه ` `/usr/bin` در روتر منتقل کنید
```bash
 `/usr/bin/psiphon-core`
```

 📁 ۳. استقرار زیرساخت و کدهای کامل پنل گرافیکی

فایل Psiphon VPN 2.0.40_manual.setup.sh به پوشه زیر
 منتقل کنید و دستور زیر اجرا کنید
"/tmp/Psiphon VPN 2.0.40_manual.setup.sh"

```bash
sh "/tmp/Psiphon VPN 2.0.40_manual.setup.sh"
```
 ✅ . شروع به کار
 Auto Connect (Enable) , Full Tunnel Mode  فعال کنید
2. با هر تغییر برای ذخیره در تنظیمات Save & Apply را باید بزنید
3. کلید Start را بزنید تا این دوتا فایل و پوشه ساخته شود
```bash
 "/etc/psiphon/ca.psiphon.PsiphonTunnel.tunnel-core/datastore/psiphon.boltdb"
 "/etc/psiphon/psiphon.config"
```


# 🗑️ حذف کامل و بی‌بازگشت سایفون از سیستم (Uninstall)

انتقال فایل به داخل روتر / و اجرای دستور زیر
```bash
sh "/tmp/Uninstall.sh"
```

##محیط Luci برای سایفون

توجه داشته باشید بعد از هر تغییر Save & Apply بزنید ، بعد Start را بزنید

<img width="1992" height="1912" alt="Psiphon VPN" src="https://github.com/user-attachments/assets/71b58768-c9d6-455a-a47a-9973182afa96" />

 Save & Apply 
<img width="734" height="1274" alt="image" src="https://github.com/user-attachments/assets/298ec61e-ed5c-4a87-a59a-da9ee662972e" />




```bash
https://browserleaks.com/dns
https://browserleaks.com/ip

```
<img width="1572" height="1472" alt="image" src="https://github.com/user-attachments/assets/a9f5d3bf-5246-4025-aa10-36f1231e04d8" />





