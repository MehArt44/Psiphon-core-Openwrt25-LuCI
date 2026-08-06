#!/bin/sh

echo "=================================================="
echo "  Psiphon-core-Openwrt25-LuCI Auto Installer     "
echo "  Version: v1.0.0                                "
echo "=================================================="

REPO="MehArt44/Psiphon-core-Openwrt25-LuCI"
VERSION="v1.0.0"

# ==================================================
# گام 1: شناسایی معماری، دانلود و قرارگیری در /usr/bin
# ==================================================
ARCH=$(uname -m)
echo "[*] Step 1: Detecting CPU Architecture: $ARCH"

case "$ARCH" in
    x86_64)           DL_ARCH="amd64" ;;
    i386|i486|i586|i686) DL_ARCH="386" ;;
    aarch64)          DL_ARCH="arm64" ;;
    armv7l|armv7)     DL_ARCH="armv7" ;;
    armv5tejl|armv5)  DL_ARCH="armv5" ;;
    mips)             DL_ARCH="mips" ;;
    mipsel)           DL_ARCH="mipsle" ;;
    mips64el)         DL_ARCH="mips64le" ;;
    *) echo "[!] Unsupported architecture: $ARCH"; exit 1 ;;
esac

BIN_URL="https://github.com/$REPO/releases/download/$VERSION/psiphon-core-$DL_ARCH"

mkdir -p /usr/bin
echo "[*] Downloading psiphon-core ($DL_ARCH) to /usr/bin/psiphon-core..."
wget -O /usr/bin/psiphon-core "$BIN_URL"

if [ $? -ne 0 ]; then
    echo "[!] Error downloading psiphon-core. Check connection or release URL."
    exit 1
fi

chmod +x /usr/bin/psiphon-core
echo "[+] psiphon-core successfully installed in /usr/bin/"

# ==================================================
# گام 2: دانلود psiphon_data.zip و استخراج در /usr/bin
# ==================================================
echo "[*] Step 2: Downloading psiphon_data.zip..."
DATA_URL="https://raw.githubusercontent.com/$REPO/main/psiphon_data.zip"

wget -O /tmp/psiphon_data.zip "$DATA_URL"

if [ $? -ne 0 ]; then
    echo "[!] Error downloading psiphon_data.zip."
    exit 1
fi

echo "[*] Extracting psiphon_data.zip to /usr/bin/..."
unzip -o /tmp/psiphon_data.zip -d /usr/bin/
rm -f /tmp/psiphon_data.zip
echo "[+] psiphon_data successfully extracted to /usr/bin/"

# ==================================================
# گام 3: دریافت کدهای اصلی و اجرای گروه‌های کانفیگ
# ==================================================
echo "[*] Step 3: Downloading repository files..."
wget -O /tmp/repo.zip "https://github.com/$REPO/archive/refs/heads/main.zip"
unzip -o /tmp/repo.zip -d /tmp/
cp -r /tmp/Psiphon-core-Openwrt25-LuCI-main/* /
rm -rf /tmp/repo.zip /tmp/Psiphon-core-Openwrt25-LuCI-main

echo "[*] Applying Configurations (Groups 1-7)..."

echo "-> GROUP 1: Core Permissions & RPCD ACL"
# کدهای گروه 1


echo "-> GROUP 2: Base UCI Configuration"
# کدهای گروه 2


echo "-> GROUP 3: LuCI Menu Registration"
# کدهای گروه 3


echo "-> GROUP 4: Init.d Service Script Generation"
# کدهای گروه 4


echo "-> GROUP 5: Firewall and Routing Configurations"
# کدهای گروه 5


echo "-> GROUP 6: LuCI Frontend (View Script)"
# کدهای گروه 6


echo "-> GROUP 7: Service Restart & Cache Cleanup"
if [ -f /etc/init.d/rpcd ]; then
    /etc/init.d/rpcd restart
fi
if [ -f /etc/init.d/uhttpd ]; then
    /etc/init.d/uhttpd restart
fi
rm -rf /tmp/luci-modulecache/
rm -rf /tmp/luci-indexcache

echo "=================================================="
echo " Installation Completed Successfully! "
echo "=================================================="
