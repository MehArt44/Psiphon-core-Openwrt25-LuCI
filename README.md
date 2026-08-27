**پارسی** | [English](README.en.md)

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

فایل Psiphon VPN 2.0.40.sh به پوشه زیر
 منتقل کنید و دستور زیر اجرا کنید
"/tmp/Psiphon VPN 2.0.40.sh"

```bash
sh "/tmp/Psiphon VPN 2.0.40.sh"
```


# 🗑️ حذف کامل و بی‌بازگشت سایفون از سیستم (Uninstall)

انتقال فایل به داخل روتر / و اجرای دستور زیر
```bash
sh "/tmp/Uninstall.sh"
```

## محیط Luci برای سایفون

<img width="1616" height="1602" alt="image" src="https://github.com/user-attachments/assets/a3460d87-24bc-4907-afa6-a63d4523b88f" />


```bash
https://browserleaks.com/dns
https://browserleaks.com/ip

```
<img width="1578" height="1589" alt="image" src="https://github.com/user-attachments/assets/a96214aa-08a6-407f-823a-779e26be24d6" />




