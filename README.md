**پارسی** | [English](README.en.md) | [Chinese](README.zh.md)

# Psiphon VPN + CDN Fronting

راهنمای نصب، راه‌اندازی و خودکارسازی Psiphon-Core به همراه پنل گرافیکی LuCI در OpenWrt 25

این پروژه یک راهنمای کاملاً عملیاتی برای اتصال هسته لینوکسی سایفون (psiphon-core) به رابط کاربری گرافیکی لوسی (LuCI JavaScript) در سیستم‌عامل OpenWrt 25 است. تمامی کلیدهای کنترل سرویس، فیلدهای تنظیمات (پورت‌ها، کشور، پروتکل) و بخش مانیتورینگ وضعیت آی‌پی و جلوگیری از نشت DNS کاملاً همگام‌سازی شده‌اند.

## 🚀 آموزش نصب آسان (Installation)

برای نصب سریع، کافیست از طریق نرم‌افزارهای SSH (مانند PuTTY یا Terminal) به روتر خود متصل شوید و دستور زیر را اجرا کنید:

```bash
wget -O /tmp/install.sh https://raw.githubusercontent.com/MehArt44/Psiphon-core-Openwrt25-LuCI/main/install.sh
sh /tmp/install.sh
```

> ⏳ دانلود و نصب ممکن است تا ۱۰ دقیقه طول بکشد؛ لطفاً صبر کنید.

## 🛠️ آموزش نصب دستی (Manual Installation)

### ۱. دانلود فایل مناسب روتر از بخش Releases

برای شناسایی معماری CPU روتر، دستور زیر را در روتر اجرا کنید:

```bash
uname -m
```

### ۲. انتقال فایل به روتر

1. پس از اتمام دانلود، نام فایل را به `psiphon-core` تغییر دهید.
2. با ابزارهایی مانند MobaXterm یا SCP فایل را به روتر منتقل کنید.
3. فایل را در پوشه `/usr/bin` روتر قرار دهید:

```bash
/usr/bin/psiphon-core
```

### ۳. استقرار زیرساخت و کدهای کامل پنل گرافیکی

فایل `Psiphon VPN 2.0.42_manual.setup.sh` را به پوشه `/tmp` منتقل کنید و دستور زیر را اجرا کنید:

```bash
sh "/tmp/Psiphon VPN 2.0.42_manual.setup.sh"
```

### ✅ ۴. شروع به کار

1. گزینه‌های **Auto Connect (Enable)** و **Full Tunnel Mode** را فعال کنید.
2. با هر تغییر، برای ذخیره‌شدن تنظیمات باید **Save & Apply** را بزنید.
3. کلید **Start** را بزنید تا این دو فایل و پوشه ساخته شوند:

```bash
/tmp/psiphon/ca.psiphon.PsiphonTunnel.tunnel-core/datastore/psiphon.boltdb
/tmp/psiphon/psiphon.config
```

## 🗑️ حذف کامل سایفون از سیستم (Uninstall) — تست‌شده در حالت TEST

فایل `Uninstall.sh` را به روتر منتقل کنید و یکی از دستورهای زیر را اجرا کنید:

```bash
sh Uninstall.sh            # با تأیید
sh Uninstall.sh -y         # بدون پرسش
sh Uninstall.sh -y --purge # حذف کامل
```

نصب‌کننده (`install.sh`) هم این گزینه‌ها را پشتیبانی می‌کند و در حالت حذف، چیزی دانلود نمی‌کند:

```bash
sh /tmp/install.sh --uninstall
sh /tmp/install.sh --purge
```

**مراحل حذف:**

- **توقف و آزادسازی:** سرویس را متوقف و غیرفعال می‌کند و kill switch را آزاد می‌کند تا اینترنت LAN بسته نماند. اگر psiphon-core یا watcher هنوز زنده باشند، آن‌ها را هم می‌بندد.
- **پاکسازی شبکه:** ابتدا cleanup خود helper اجرا می‌شود و بعد یک پاکسازی دستی جداگانه به‌عنوان پشتیبان. این پشتیبان جدول‌های nft، ip ruleهای 990 و 1000، جدول route شماره 100، tun0 (فقط اگر خود Psiphon ساخته باشد)، IPv6 روی WAN، فایل DNS در dnsmasq، موتور DoH و upstreamهای dnsmasq را برمی‌گرداند.
- **حذف فایل‌ها:** فایل‌های برنامه، zone و forwarding فایروال و ورودی‌های `/etc/sysupgrade.conf` پاک می‌شوند.
- **تأیید پایانی:** در آخر باقی‌مانده‌ها را بررسی می‌کند و دسترسی روتر به اینترنت و DNS محلی را هم تست می‌کند.

**گزینه‌ها:**

- `--purge`: علاوه بر بقیه، config، datastore و فایل core را هم پاک می‌کند.
- `--remove-deps`: بسته‌های https-dns-proxy و tcpdump را حذف می‌کند.
- `--reset-confdir`: مقدار confdir در dnsmasq را برمی‌گرداند.

## 🧪 تست کامل (Test_Full.sh)

```bash
sh Test_Full.sh            # تست‌های غیرمزاحم
sh Test_Full.sh --quick    # فقط بررسی ایستا
sh Test_Full.sh --full     # با تست راه‌اندازی/توقف و اسکنر CDN
sh Test_Full.sh --only helper,live
```

- **env:** پیش‌نیازها، kmod-tun، ca-bundle، TLS، فضای flash و nftables.
- **files:** فایل‌های نصب‌شده، دسترسی‌ها، syntax، JSONهای menu و ACL، و flagهای باینری core.
- **config:** مقادیر UCI و تناقض بین گزینه‌ها، zone فایروال، confdir در dnsmasq و ورودی‌های sysupgrade.
- **helper:** تست آفلاین خود helper؛ config تولیدشده برای core، parserهای لاگ، محاسبه subnet، MTU و MSS، و رنج‌ها و نمونه‌گیری CDN بررسی می‌شوند.

## 🖥️ محیط LuCI برای سایفون

توجه: بعد از هر تغییر **Save & Apply** را بزنید، سپس **Start** را بزنید.

<img width="1992" height="1912" alt="Psiphon VPN" src="https://github.com/user-attachments/assets/71b58768-c9d6-455a-a47a-9973182afa96" />

**Save & Apply**

<img width="734" height="1274" alt="image" src="https://github.com/user-attachments/assets/298ec61e-ed5c-4a87-a59a-da9ee662972e" />

برای بررسی IP و نشت DNS:

```bash
https://browserleaks.com/dns
https://browserleaks.com/ip
```

<img width="1572" height="1472" alt="image" src="https://github.com/user-attachments/assets/a9f5d3bf-5246-4025-aa10-36f1231e04d8" />
