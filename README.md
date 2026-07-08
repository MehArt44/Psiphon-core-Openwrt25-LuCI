**پارسی** | [English](README.en.md)



# OpenWrt 24.10 Psiphon-Core Setup & Automation Guide

🛑فایل کامپایل شده و کانفیگ و... ساخته شده در پوشه `Router.zip` وجود دارد و برای اطمینان مراحل ساخت شرح داده شده است؛ فقط دستورات را باید اجرا کنید🛑

این پروژه یک راهنمای جامع و اسکریپت هوشمند برای راه‌اندازی، مدیریت و جفت‌کردن هسته لینوکسی سایفون (`psiphon-core`) با روترهای مبتنی بر **OpenWrt** (به ویژه نسخه 24.10 و پردازنده‌های ۶۴ بیتی با معماری `aarch64_cortex-a53` مانند GL-MT3000) است.

به دلیل محدودیت‌های دسترسی، سایفون در هر بار اجرا پورت‌های SOCKS و HTTP کاملاً تصادفی (Random) باز می‌کند. این اسکریپت به صورت داینامیک پورت‌ها را از لاگ سیستم شکار کرده، آی‌پای داخلی روتر شما را به صورت خودکار تشخیص می‌دهد و آن‌ها را روی پورت‌های ثابت شبکه داخلی لایو می‌کند. همچنین قابلیت انتخاب کشور خروجی (لوکیشن سرور) در این نسخه اضافه شده است.

---

## 🛠️ ۱. آموزش کامپایل فایل باینری (روی کامپیوتر)

اگر می‌خواهید خودتان فایل اجرایی سایفون را برای معماری روتر (`arm64`) بسازید، ابتدا مطمئن شوید زبان Go روی کامپیوتر شما نصب است، سپس ترمینال را باز کرده و این دستورات را اجرا کنید:

```bash
# ۱. دریافت سورس کد رسمی هسته سایفون از مخزن Psiphon-Labs
git clone [https://github.com/Psiphon-Labs/psiphon-tunnel-core.git](https://github.com/Psiphon-Labs/psiphon-tunnel-core.git)

# ۲. ورود به پوشه اصلی پروژه (کدها مستقیماً در ریشه این مخزن هستند)
cd psiphon-tunnel-core

# ۳. دانلود وابستگی‌ها و تنظیم متغیرهای محیطی برای لینوکس ۶۴ بیتی ARM
go mod download
export GOOS=linux
export GOARCH=arm64

# ۴. کامپایل فوق‌العاده بهینه، بدون دباگ و سبک برای روتر
go build -ldflags="-s -w" -o psiphon-core .

```

فایل ساخته شده با نام `psiphon-core` را از طریق کلاینت‌های SFTP (برنامه‌هایی مثل MobaXterm یا WinSCP) به مسیر `/usr/bin/` روتر منتقل کنید.

---

## 📂 ساختار و مسیر فایل‌ها در روتر

قبل از شروع اسکریپت‌های روتر، باید ۳ فایل زیر را آماده کرده و به مسیرهای مشخص شده در روتر منتقل کنید:

| # | نوع آیتم | نام فایل / پوشه | مسیر قرارگیری در روتر | توضیحات |
| --- | --- | --- | --- | --- |
| ۱ | **فایل اجرایی اصلی** | `psiphon-core` | `/usr/bin/psiphon-core` | فایل کامپایل‌شده مرحله قبل سازگار با معماری پردازنده (مثلاً ARM64) |
| ۲ | **فایل تنظیمات** | `psiphon.config` | `/usr/bin/psiphon.config` | حاوی مشخصات کلاینت، ساختار امنیتی و تنظیمات پایه |
| ۳ | **پوشه دیتابیس داخلی** | `psiphon_data` | `/usr/bin/psiphon_data/` | محل ذخیره اطلاعات سرورها، کش (Cache) و لیست‌های به‌روزرسانی |

---

## 🚀 ۲. آماده‌سازی و نصب پیش‌نیازها (روی روتر)

پس از انتقال فایل‌ها به پوشه `/usr/bin/`، دستورات زیر را در ترمینال روتر اجرا کنید تا دسترسی‌های لازم صادر شده و ابزار پیش‌نیاز `socat` نصب شود:

```bash
# مجاز کردن دسترسی فایل باینری و ساخت پوشه دیتا
chmod +x /usr/bin/psiphon-core
mkdir -p /usr/bin/psiphon_data

# به‌روزرسانی مخازن روتر و نصب ابزار socat جهت ریدایرکت ترافیک
opkg update && opkg install socat

```

---

## 📝 ۳. ساخت فایل کانفیگ عمومی سایفون (`psiphon.config`)

دستور زیر را به صورت کامل کپی کرده و در ترمینال روتر پیست کنید تا فایل تنظیمات استاندارد اولیه ساخته شود (موقعیت کشور در مرحله بعد به صورت داینامیک مدیریت می‌شود):

```bash
cat << 'INPUT_EOF' > /usr/bin/psiphon.config
{
  "SocksProxyPort": 10808,
  "HttpProxyPort": 10809,
  "ClientPlatform": "Windows_10.0.26200_11",
  "ClientVersion": "187",
  "DataRootDirectory": "/usr/bin/psiphon_data",
  "EgressRegion": "ALL",
  "PropagationChannelId": "0000000000000000",
  "SponsorId": "0000000000000000",
  "ServerEntrySignaturePublicKey": "sHuUVTWaRyh5pZwy4UguSgkwmBe0EHtJJkoF5WrxmvA=",
  "UseIndistinguishableTLS": true
}
INPUT_EOF

```

---

## ⚡ ۴. اسکریپت راه‌انداز داینامیک و هوشمند (با قابلیت انتخاب کشور)

این اسکریپت به صورت کاملاً خودکار **آی‌پای داخلی روتر شما** را پیدا کرده، کشور انتخابی را در کانفیگ اعمال می‌کند و پورت‌های تصادفی را استخراج می‌نماید.

> ⚠️ **نکته بسیار مهم برای کپی کامندها:** هنگام کپی کردن دستورات متنی، مراقب باشید فرمت‌های پنهان یا ساختار لینک مرورگرها کپی نشود تا در محیط ترمینال با خطای سینتکس (`syntax error`) مواجه نشوید.

> 💡 **راهنمای انتخاب لوکیشن (TARGET_REGION):**
> در خط اول اسکریپت زیر، متغیر `TARGET_REGION` را برابر با کد دو حرفی کشور مورد نظر خود (با حروف بزرگ) قرار دهید.
> * **`ALL`** : اتصال به سریع‌ترین سرور با بهترین بازدهی (Best Performance)
> 
> 
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
# تغییر خودکار کشور در فایل کانفیگ بدون نیاز به ادیت دستی
sed -i "s/\"EgressRegion\": \".*\"/\"EgressRegion\": \"$TARGET_REGION\"/g" /usr/bin/psiphon.config

# ۱. بستن پروسه‌های قدیمی برای جلوگیری از تداخل پورت‌ها
killall -9 psiphon-core socat 2>/dev/null

# ۲. اجرای هسته اصلی سایفون در پس‌زمینه و ذخیره لاگ در حافظه موقت RAM
/usr/bin/psiphon-core -config /usr/bin/psiphon.config -dataRootDirectory /usr/bin/psiphon_data > /tmp/psiphon.log 2>&1 &

# ۳. صبر برای هندشیک اولیه و باز شدن پورت‌های داخلی (با توجه به شلوغی شبکه ایران، ۱۵ ثانیه زمان مناسبی است)
echo "در حال تلاش برای عبور از فیلترینگ... ۱۵ ثانیه صبر کنید..."
sleep 15

# ۴. استخراج فوق‌العاده دقیق پورت‌های رندوم سایفون از داخل لاگ فایل JSON
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

## 🔍 ۵. دستورات عیب‌یابی و راستی‌آزمایی اتصال

برای اینکه مطمئن شوید سایفون به درستی متصل شده و ترافیک در جریان است، از این دستورات استفاده کنید:

* **مشاهده وضعیت و کشور متصل شده در لاگ:**
در خطوط آخر لاگ باید عبارت `"noticeType":"ConnectedServerRegion"` را ببینید که نشانه اتصال موفق به سرور است.
```bash
tail -n 20 /tmp/psiphon.log

```


* **بررسی باز بودن پورت‌های ثابت روی روتر:**
این دستور باید دو خط حاوی وضعیت `LISTEN` را روی آی‌پای داخلی روتر شما نشان دهد.
```bash
netstat -tulpn | grep -E '10808|10809'

```


* **تست مستقیم فرار از فیلترینگ داخل روتر:**
با استفاده از این دستور تمیز، اگر اتصال برقرار باشد آی‌پای خارجی و بدون فیلتر سرور سایفون به شما نمایش داده می‌شود:
```bash
curl -x [http://127.0.0.1:10809](http://127.0.0.1:10809) [https://ifconfig.me](https://ifconfig.me)

```



---

## ⚙️ ۶. راه‌اندازی به عنوان سرویس دائمی سیستم (`/etc/init.d/psiphon`)

اگر می‌خواهید دستورات بالا به صورت یک سرویس استاندارد در بیاید تا بتوانید با دستوراتی مثل `/etc/init.d/psiphon start` آن را کنترل کنید یا کاری کنید که بعد از روشن شدن روتر خودکار اجرا شود، مراحل زیر را طی کنید:

۱. کل کد زیر را کپی کرده و در ترمینال روتر اجرا کنید تا فایل سرویس به صورت خودکار ساخته شود:

```bash
cat << 'SERVICE_EOF' > /etc/init.d/psiphon
#!/bin/sh /etc/rc.common

START=99
USE_PROCD=1

start_service() {
    procd_open_instance "psiphon"
    procd_set_param command /bin/sh -c '
        killall -9 psiphon-core socat 2>/dev/null
        /usr/bin/psiphon-core -config /usr/bin/psiphon.config -dataRootDirectory /usr/bin/psiphon_data > /tmp/psiphon.log 2>&1 &
        sleep 12
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

۲. صادر کردن دسترسی اجرایی به فایل سرویس:

```bash
chmod +x /etc/init.d/psiphon

```

۳. حالا می‌توانید سرویس را مدیریت کنید:

* **روشن کردن سایفون:** `/etc/init.d/psiphon start`
* **خاموش کردن سایفون:** `/etc/init.d/psiphon stop`
* **فعال‌سازی اجرای خودکار پس از بوت شدن روتر:** `/etc/init.d/psiphon enable`

---

## 🛑 ۷. دستور خاموش کردن و غیرفعال‌سازی دستی

اگر مایل به استفاده از سیستم سرویس نیستید، هر زمان که خواستید سایفون و پل‌های ارتباطی دستی آن را متوقف کنید، این دستور را اجرا کنید:

```bash
# متوقف کردن هسته سایفون و پروسه‌های socat
killall -9 psiphon-core socat 2>/dev/null

# ری‌استارت فایروال روتر جهت پاکسازی قوانین موقت باز شده
/etc/init.d/firewall restart

echo "سایفون و پل‌های ارتباطی با موفقیت غیرفعال و خاموش شدند."

```

---

## 💻 ۸. تنظیمات کلاینت‌ها (ویندوز، گوشی، مرورگر)

برای استفاده از اینترنت بدون فیلتر در دستگاه‌های متصل به روتر، مشخصات پروکسی زیر را در تنظیمات سیستم‌عامل یا افزونه‌های مرورگر (مانند FoxyProxy) وارد کنید:

* **نوع پروکسی:** `HTTP` یا `SOCKS5`
* **آدرس آی‌پای:** آی‌پای مدیریت روتر شما (مثلاً `192.168.18.1`)
* **پورت اچ‌تی‌تی‌پي (HTTP Port):** `10809`
* **پورت ساکس (SOCKS Port):** `10808`

---

## 🗑️ ۹. حذف کامل و بی‌بازگشت سایفون (Uninstall)

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

```
---

```
