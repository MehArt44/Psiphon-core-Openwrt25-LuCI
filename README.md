**پارسی** | [English](README.en.md)



# OpenWrt 24.10 & 25 Psiphon-Core Setup & Automation Guide

🛑فایل کامپایل شده در Releases برای هر دو معماری پردازنده وجود دارد
 برای اطمینان مراحل کامپایل شرح داده شده است؛ فقط دستورات را باید اجرا کنید🛑

این پروژه یک راهنمای جامع و اسکریپت هوشمند برای راه‌اندازی، مدیریت و جفت‌کردن هسته لینوکسی سایفون (`psiphon-core`) با روترهای مبتنی بر **OpenWrt** معماری `aarch64_cortex-a53` و `arm_Cortex-A7 (Google Wifi AC-1304)`

---

## 🛠️ ۱. آموزش کامپایل فایل باینری (روی کامپیوتر)  PowerShell
برای کامپایل صحیح هسته سایفون، باید خط فرمان خود را به سمت پوشه کلاینت متنی (ConsoleClient) هدایت کنید. کد اصلی و فایل main.go برای اجرای نسخه کلاینت، برخلاف فرض اولیه شما، در ریشه مخزن قرار ندارد و درون این پوشه تعبیه شده است.

اگر می‌خواهید خودتان فایل اجرایی سایفون را برای معماری روتر (` arm7,  arm64`) بسازید، ابتدا مطمئن شوید زبان Go روی کامپیوتر شما نصب است، سپس ترمینال را باز کرده و این دستورات را اجرا کنی

```bash

# برای powersell
# ۱. دریافت سورس کد رسمی هسته سایفون از مخزن Psiphon-Labs
دانلود مستقیم ZIP
https://github.com/Psiphon-Labs/psiphon-tunnel-core/archive/refs/heads/master.zip

# ۲. ورود به پوشه کلاینت متنی (کد کلاینت اصلی در این مسیر است)
cd psiphon-tunnel-core/ConsoleClient

فایل اطلاعات سرور را به این پوشه منتقل کنید embedded_servers.go
C:\....\psiphon-tunnel-core-master\ConsoleClient

# ۳. رفع تحریم دانلود پکیج‌های گالنگ در ویندوز (برای جلوگیری از خطای ۴۰۳)اگر نیاز بود
go env -w GOPROXY="https://goproxy.cn,direct"

# ۴. دانلود وابستگی‌های پروژه
go mod download

```


# برای (مدل GLinet MT3000) دارای پردازنده 64 بیتی با معماری ARM64 است.
```bash

$env:GOOS="linux"
$env:GOARCH="arm64"
go build -o psiphon-core

```
# برای  Google Wifi (مدل AC-1304) دارای پردازنده 32 بیتی با معماری ARMv7 است،
 
```bash

$env:GOOS="linux"
$env:GOARCH="arm"
$env:GOARM="7"
go build -o psiphon-core

```

فایل ساخته شده با نام `psiphon-core` را از طریق کلاینت‌های SFTP (برنامه‌هایی مثل MobaXterm یا WinSCP) به مسیر `/usr/bin/` روتر منتقل کنید.

---

## 📂 ساختار و مسیر فایل‌ها در روتر

وضعیت فایل‌ها در روتر به شرح زیر خواهد بود (فایل کانفیگ در مرحله بعدی مستقیماً توسط ترمینال ایجاد می‌شود و نیازی به انتقال دستی آن از ویندوز نیست):

| # | نوع آیتم | نام فایل / پوشه | مسیر قرارگیری در روتر | توضیحات |
| --- | --- | --- | --- | --- |
| ۱ | **فایل اجرایی اصلی** | `psiphon-core` | `/usr/bin/psiphon-core` | فایل کامپایل‌شده مرحله قبل سازگار با معماری پردازنده (مثلاً ARM64) |
| ۲ | **فایل تنظیمات** | `psiphon.config` | `/usr/bin/psiphon.config` | توسط دستور مرحله ۳ با ساختار دقیق camelCase ساخته می‌شود |
| ۳ | **پوشه دیتابیس داخلی** | `psiphon_data` | `/usr/bin/psiphon_data/` | محل ذخیره اطلاعات سرورها، کش (Cache) و لیست‌های به‌روزرسانی |

---

## 🚀 ۲. آماده‌سازی و نصب پیش‌نیازها (روی روتر)

پس از انتقال فایل باینری به پوشه `/usr/bin/`، دستورات زیر را در ترمینال روتر اجرا کنید تا دسترسی‌های لازم صادر شده و ابزار پیش‌نیاز `socat` نصب شود:

```bash
# مجاز کردن دسترسی فایل باینری و ساخت پوشه دیتا
chmod +x /usr/bin/psiphon-core
mkdir -p /usr/bin/psiphon_data

# به‌روزرسانی مخازن روتر و نصب ابزار socat جهت ریدایرکت ترافیک
OpenWrt 24
opkg update && opkg install socat
OpenWrt 25
apk --update-cache add socat


```

---

## 📝 ۳. ساخت فایل کانفیگ استاندارد سایفون (`psiphon.config`)

⚠️ **نکته بسیار مهم:** این دستور را به صورت **کاملاً مستقل و جداگانه** در ترمینال روتر پیست کنید و اینتر بزنید. کلیدها دقیقاً با حروف کوچک استاندارد (`camelCase`) تنظیم شده‌اند تا توسط هسته Go نادیده گرفته نشوند و پورت‌ها ثابت بمانند. مقدار `tunnelPoolSize` نیز برای شانس اتصال بالاتر روی ۶ تنظیم شده است:

```bash
cat << 'INPUT_EOF' > /usr/bin/psiphon.config
{
  "formatVersion": 1,
  "socksProxyPort": 10808,
  "httpProxyPort": 10809,
  "clientPlatform": "Windows_10.0.26200_11",
  "clientVersion": "187",
  "dataRootDirectory": "/usr/bin/psiphon_data",
  "egressRegion": "ALL",
  "propagationChannelId": "0000000000000000",
  "sponsorId": "0000000000000000",
  "serverEntrySignaturePublicKey": "sHuUVTWaRyh5pZwy4UguSgkwmBe0EHtJJkoF5WrxmvA=",
  "useIndistinguishableTLS": true,
  "tunnelPoolSize": 6,
  "splitTunnel": false
}
INPUT_EOF

```

> 🔍 **تست صحت ساخت فایل:** پس از اجرای دستور بالا، می‌توانید با زدن کامند `cat /usr/bin/psiphon.config` مطمئن شوید که محتویات فایل به درستی و با حروف کوچک ذخیره شده است.

---

## ⚡ ۴. اسکریپت راه‌انداز داینامیک و هوشمند (با قابلیت انتخاب کشور)

این اسکریپت ابتدا پروسه‌های قدیمی را به طور کامل پاکسازی می‌کند. همچنین زمان هندشیک به ۳۰ ثانیه افزایش یافته است تا تانل فرصت کافی برای باز کردن ۶ کانال موازی در شبکه تحت فیلترینگ شدید را داشته باشد.

> 💡 **راهنمای انتخاب لوکیشن (TARGET_REGION):**
> در خط اول اسکریپت زیر، متغیر `TARGET_REGION` را برابر با کد دو حرفی کشور مورد نظر خود (با حروف بزرگ) قرار دهید. (`ALL` یعنی اتصال به سریع‌ترین سرور)
> | کد کشور | نام کشور | | کد کشور | نام کشور |
> | :---: | :--- | | :---: | :--- |
> | **`AT`** | اتریش (Austria) | | **`IT`** | ایتالیا (Italy) |
> | **`BE`** | بلژیک (Belgium) | | **`JP`** | ژاپن (Japan) |
> | **`CA`** | کانادا (Canada) | | **`NL`** | هلند (Netherlands) |
> | **`CH`** | سوئیس (Switzerland) | | **`NO`** | نروژ (Norway) |
> | **`DE`** | آلمان (Germany) | | **`PL`** | لهستان (Poland) |
> | **`DK`** | دانمارک (Denmark) | | **`SE`** | سوئد (Sweden) |
> | **`ES`** | اسپانیا (Spain) | | **`SG`** | سنگاپور (Singapore) |
> | **`FI`** | فنلاند (Finland) | | **`US`** | ایالات متحده (United States) |
> | **`FR`** | فرانسه (France) | | **`GB`** | بریتانیا (United Kingdom) |

```bash
# 🌍 تعیین کشور خروجی (کد دو حرفی بزرگ یا ALL برای سریع‌ترین سرور)
TARGET_REGION="ALL"

echo "تنظیم لوکیشن سایفون روی: $TARGET_REGION"
# تغییر خودکار کشور در فایل کانفیگ اصلاح‌شده (رعایت دقیق حروف کوچک egressRegion)
sed -i "s/\"egressRegion\": \".*\"/\"egressRegion\": \"$TARGET_REGION\"/g" /usr/bin/psiphon.config

# ۱. بستن پروسه‌های قدیمی و پاکسازی کامل کش آی‌پی‌های قدیمی جهت رفع انسداد
killall -9 psiphon-core socat 2>/dev/null
rm -rf /usr/bin/psiphon_data/*

# ۲. اجرای هسته اصلی سایفون در پس‌زمینه و ذخیره لاگ در حافظه موقت RAM
/usr/bin/psiphon-core -config /usr/bin/psiphon.config -dataRootDirectory /usr/bin/psiphon_data > /tmp/psiphon.log 2>&1 &

# ۳. صبر برای هندشیک اولیه و دور زدن فیلترینگ شدید (۳۰ ثانیه زمان استاندارد شبکه ایران است)
echo "در حال تلاش سخت برای عبور از فیلترینگ... لطفا ۳۰ ثانیه کامل صبر کنید..."
sleep 30

# ۴. استخراج فوق‌العاده دقیق پورت‌های رندوم سایفون از داخل لاگ فایل JSON (انطباق با حروف کوچک در لاگ)
SOCKS_PORT=$(grep "ListeningSocksProxyPort" /tmp/psiphon.log | grep -o '"port":[0-9]*' | cut -d':' -f2)
HTTP_PORT=$(grep "ListeningHttpProxyPort" /tmp/psiphon.log | grep -o '"port":[0-9]*' | cut -d':' -f2)

echo "پورت‌های رندوم شناسایی شده از لاگ -> SOCKS: $SOCKS_PORT | HTTP: $HTTP_PORT"

# ۵. تشخیص خودکار آی‌پای داخلی روتر شما (LAN IP)
ROUTER_IP=$(ubus call network.interface.lan status | jsonfilter -e '@["ipv4-address"][0].address')
echo "آی‌پای تشخیص داده شده روتر شما: $ROUTER_IP"

# ۶. برقراری پل ارتباطی توسط socat به آی‌پای داینامیک روتر (روی پورت‌های ثابت ۱۰۸۰۸ و ۱۰۸۰۹)
socat TCP-LISTEN:10809,fork,bind=$ROUTER_IP TCP:127.0.0.1:$HTTP_PORT &
socat TCP-LISTEN:10808,fork,bind=$ROUTER_IP TCP:127.0.0.1:$SOCKS_PORT &

# ۷. باز کردن فایروال بومی OpenWrt 24.10 (nftables / fw4) جهت قبول دسترسی کلاینت‌ها از شبکه داخلی
nft add rule inet fw4 input iifname "br-lan" tcp dport 10808-10809 accept 2>/dev/null

echo "سایفون با موفقیت با لوکیشن $TARGET_REGION و پورت‌های ثابت روی شبکه داخلی فعال شد!"

```

---

## ⚙️ ۵. راه‌اندازی به عنوان سرویس دائمی سیستم (`/etc/init.d/psiphon`)

اگر می‌خواهید دستورات بالا به صورت یک سرویس استاندارد در بیاید تا بتوانید آن را به صورت یک پارچه کنترل کنید یا کاری کنید که بعد از روشن شدن روتر خودکار اجرا شود، مراحل زیر را طی کنید:

۱. کل کد زیر را کپی کرده و در ترمینال روتر اجرا کنید تا فایل سرویس به صورت خودکار ساخته شود (با اصلاح کامل لاجیک فراخوانی حروف کوچک):

```bash
cat << 'SERVICE_EOF' > /etc/init.d/psiphon
#!/bin/sh /etc/rc.common

START=99
USE_PROCD=1

start_service() {
    procd_open_instance "psiphon"
    procd_set_param command /bin/sh -c '
        killall -9 psiphon-core socat 2>/dev/null
        rm -rf /usr/bin/psiphon_data/*
        /usr/bin/psiphon-core -config /usr/bin/psiphon.config -dataRootDirectory /usr/bin/psiphon_data > /tmp/psiphon.log 2>&1 &
        sleep 25
        SOCKS_PORT=$(grep "ListeningSocksProxyPort" /tmp/psiphon.log | grep -o '\''"port":[0-9]*'\'' | cut -d'\'':'\'' -f2)
        HTTP_PORT=$(grep "ListeningHttpProxyPort" /tmp/psiphon.log | grep -o '\''"port":[0-9]*'\'' | cut -d'\'':'\'' -f2)
        ROUTER_IP=$(ubus call network.interface.lan status | jsonfilter -e '\''@["ipv4-address"][0].address'\'')
        socat TCP-LISTEN:10809,fork,bind=$ROUTER_IP TCP:127.0.0.1:$HTTP_PORT &
        socat TCP-LISTEN:10808,fork,bind=$ROUTER_IP TCP:127.0.0.1:$SOCKS_PORT &
        nft add rule inet fw4 input iifname "br-lan" tcp dport 10808-10809 accept 2>/dev/null
    '
    procd_set_param respawn
    procd_close_instance
}

stop_service() {
    killall -9 psiphon-core socat 2>/dev/null
    /etc/init.d/firewall restart
}
SERVICE_EOF

```

⚠️ **مرحله حیاتی (رفع خطای Permission denied):** فایل‌های ایجاد شده در پوشه `init.d` به طور پیش‌فرض دسترسی اجرای سیستم‌عامل را ندارند. حتماً و قطعاً باید دستور زیر را اجرا کنید تا اجازه دسترسی فعال‌سازی برای سرویس صادر شود، در غیر این‌صورت با خطای منع دسترسی مواجه خواهید شد:

```bash
chmod +x /etc/init.d/psiphon

```

۲. حالا می‌توانید سرویس را مدیریت کنید:

* **روشن کردن تانل سایفون:** `/etc/init.d/psiphon start`
* **خاموش کردن کامل سیستم:** `/etc/init.d/psiphon stop`
* **فعال‌سازی اجرای خودکار پس از روشن شدن روتر:** `/etc/init.d/psiphon enable`

---

## 🛑 ۶. دستور خاموش کردن و غیرفعال‌سازی دستی

اگر مایل به استفاده از سیستم سرویس نیستید، هر زمان که خواستید سایفون و پل‌های ارتباطی دستی آن را متوقف کنید، این دستور را اجرا کنید:

```bash
# متوقف کردن هسته سایفون و پروسه‌های socat
killall -9 psiphon-core socat 2>/dev/null

# ری‌استارت فایروال روتر جهت پاکسازی قوانین موقت باز شده
/etc/init.d/firewall restart

echo "سایفون و پل‌های ارتباطی با موفقیت غیرفعال و خاموش شدند."

```

---

## 💻 ۷. تنظیمات کلاینت‌ها (ویندوز، گوشی، مرورگر)

برای استفاده از اینترنت بدون فیلتر در دستگاه‌های متصل به روتر، مشخصات پروکسی زیر را در تنظیمات سیستم‌عامل یا افزونه‌های مرورگر (مانند FoxyProxy) وارد کنید:

* **نوع پروکسی:** `HTTP` یا `SOCKS5`
* **آدرس آی‌پای:** آی‌پای مدیریت روتر شما (مثلاً `192.168.18.1`)
* **پورت اچ‌تی‌تی‌پي (HTTP Port):** `10809`
* **پورت ساکس (SOCKS Port):** `10808`

---

## 📊 ۸. ساختار خروجی لاگ‌های موفقیت‌آمیز سیستم

جهت اطمینان از صحت عملکرد هسته سایفون، پس از استارت زدن باید لاگ‌های سیستم وضعیت درستی را گزارش کنند. نمونه خروجی سالم به شرح زیر است:

```text
{"data":{"ID":"UNKNOWN"},"noticeType":"NetworkID","timestamp":"2026-07-08T19:29:20.923Z"}
{"data":{"port":10808},"noticeType":"ListeningSocksProxyPort","timestamp":"2026-07-08T19:29:20.927Z"}
{"data":{"port":10809},"noticeType":"ListeningHttpProxyPort","timestamp":"2026-07-08T19:29:20.927Z"}
{"data":{"regions":["AT","BE","CA","CH","DE","DK","ES","FI","FR","GB","IT","JP","NL","NO","PL","SE","SG","US"]},"noticeType":"AvailableEgressRegions"}
{"data":{"region":"US"},"noticeType":"ConnectedServerRegion"}

```

> 💡 **نکته:** خط آخر (`ConnectedServerRegion`) نشانه نهایی انجام موفقیت‌آمیز هندشیک و برقراری اینترنت آزاد است.

---

## ⚡ ۹. تست اتصال سایفون و راستی‌آزمایی تانل

به دلیل اینکه پورت‌های ثابت بر روی آی‌پای داخلی روتر شما بایند (Bind) شده‌اند، برای تست گرفتن با دستور `curl` باید مستقیماً آدرس آی‌پي روتر را صدا بزنید و حواستان باشد هیچ علامت پرانتزی در زمان کپی کدهای گیت‌هاب وارد ترمینال نشود:

* **مشاهده وضعیت زنده لاگ کانکشن (بررسی خطوط ConnectedServerRegion یا خطاهای احتمالی):**
```bash
tail -n 25 /tmp/psiphon.log

```


* **بررسی باز بودن پورت‌های ثابت روی آی‌پای داخلی روتر:**
```bash
netstat -tulpn | grep -E '10808|10809'

```


* **تست فرار از فیلترینگ پورت HTTP (نمایش آی‌پای خارجی سرور متصل شده):**
```bash
curl -x [http://192.168.18.1:10809](http://192.168.18.1:10809) [https://ifconfig.me](https://ifconfig.me)

```


* **تست فرار از فیلترینگ پورت SOCKS5:**
```bash
curl --socks5-hostname 192.168.18.1:10808 [https://ifconfig.me](https://ifconfig.me)

```



---

## 🗑️ ۱۰. حذف کامل و بی‌بازگشت سایفون (Uninstall)

اگر به هر دلیلی خواستید تمام فایل‌ها، پوشه‌های دیتابیس، کش‌های لوسی (LuCI) و ردپای سایفون را به طور کامل و سراسری از روی سیستم‌عامل روتر پاک کنید، اسکریپت زیر را به صورت یکجا کپی کرده و در ترمینال روتر اجرا کنید:

```bash
# ۱. پاکسازی کامل کش لوسی و ری‌استارت سرویس رابط کاربری
rm -rf /tmp/luci-indexcache /tmp/luci-modulecache
/etc/init.d/rpcd restart

# ۲. توقف کامل تمام پردازش‌های مربوطه
/etc/init.d/psiphon stop 2>/dev/null
killall -9 psiphon-core socat psiphon 2>/dev/null

# ۳. حذف فایل‌های شناخته‌شده و مسیرهای اصلی
rm -f /usr/bin/psiphon-core
rm -rf /usr/bin/psiphon_data
rm -f /etc/config/psiphon
rm -f /etc/init.d/psiphon
rm -f /www/luci-static/resources/view/services/psiphon.js
rm -f /tmp/psiphon*

# ۴. پاک کردن لاگ‌ها و فایل‌های موقت
rm -f /tmp/psiphon.log
rm -f /tmp/psiphon*

# ۵. جستجوی سراسری و حذف هرگونه فایل یا پوشه باقی‌مانده با نام psiphon
find / -name "*psiphon*" -exec rm -rf {} + 2>/dev/null

# ۶. پاکسازی مجدد کش لوسی و راه‌اندازی نهایی سرویس سیستم
rm -rf /tmp/luci-indexcache /tmp/luci-modulecache
/etc/init.d/rpcd restart

echo "Everything related to Psiphon has been completely wiped!"

```

