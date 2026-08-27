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

echo "Psiphon VPN 2.0.40 _ has been completely uninstalled from the system. "