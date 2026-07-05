**English** | [پارسی](README.md)


Here is the complete, fully translated, and well-structured English version of your documentation formatted as a single `README.md` file script.

I rearranged the sections logically (placing the **File Structure** near the top so users understand the layout first) and integrated your warning about the `Router.zip` file perfectly at the beginning.

Run this command in your computer's terminal to generate the final `README.md` file:

```bash
cat << 'EOF' > README.md
# OpenWrt Psiphon-Core Setup & Automation Guide

> 🛑 **NOTE:** The pre-compiled binary, configuration file, and required assets are already built and included inside the `Router.zip` folder. The compilation and setup steps below are detailed for verification and educational purposes. If using the zip assets, you only need to execute the runtime commands! 🛑

This project provides a comprehensive guide and an intelligent automation script to deploy, manage, and bridge the Linux-based Psiphon core (`psiphon-core`) on **OpenWrt** routers (specifically optimized for 64-bit processors with `aarch64_cortex-a53` architecture).

Due to censorship circumvention mechanisms, Psiphon binds to random SOCKS and HTTP ports every time it starts. This script dynamically captures these random ports from the system logs and bridges them to fixed ports on your local network (LAN).

---

## 📂 File Structure & Target Paths on the Router

To deploy this scenario on your router, the required files, directories, and their exact locations within the router's operating system (OpenWrt Linux) must be structured as follows:

| # | Item Type | File / Directory Name | Target Path on Router | Description |
|---|---|---|---|---|
| 1 | **Main Binary File** | `psiphon-core` | `/usr/bin/psiphon-core` | Compiled binary matching your router's architecture (e.g., GL-MT3000 utilizes MediaTek Filogic MT7981 with `ARM64` / `aarch64_cortex-a53` architecture). |
| 2 | **Configuration File** | `psiphon.config` | `/usr/bin/psiphon.config` | Contains client configurations, obfuscation keys, and local port binds. |
| 3 | **Internal Data Directory** | `psiphon_data` | `/usr/bin/psiphon_data/` | Stores internal server lists, handshake cache, and configuration updates. |
| 4 | **Temporary Log File** | `psiphon.log` | `/tmp/psiphon.log` | Generated automatically in volatile memory (`/tmp`) for the script to extract dynamic random ports. |

> 💡 **File Transfer Tip:** You can connect to your router using applications like **MobaXterm** or **WinSCP** (via SFTP or SCP protocol) to upload the `psiphon-core` binary directly into the `/usr/bin/` directory.

---

## 🛠️ 1. Compiling the Binary File (On your Computer)

If you wish to manually compile the Psiphon core binary from the official Labs repository for your router's architecture (`arm64`), open a terminal on your computer and run the following commands:

```bash
# 1. Clone the official Psiphon Labs repository
git clone [https://github.com/Psiphon-Labs/psiphon-tunnel-core.git](https://github.com/Psiphon-Labs/psiphon-tunnel-core.git)

# 2. Navigate to the project root directory
cd psiphon-tunnel-core

# 3. Download dependencies and set environment variables for 64-bit Linux ARM
go mod download
export GOOS=linux
export GOARCH=arm64

# 4. Compile a highly optimized and lightweight binary for the router
go build -ldflags="-s -w" -o psiphon-core .

```

Once completed, transfer the generated `psiphon-core` file to the `/usr/bin/` directory on your router.

---

## 🚀 2. Preparation & Prerequisites Installation (On the Router)

Run these commands in the router's terminal to grant execution permissions and install the required `socat` utility:

```bash
# Grant execution permission to the binary and create the data directory
chmod +x /usr/bin/psiphon-core
mkdir -p /usr/bin/psiphon_data

# Update package lists and install socat for port redirection
opkg update && opkg install socat

```

---

## 📝 3. Creating the Public Configuration File (`psiphon.config`)

Copy and paste the following block entirely into your router's terminal to generate a standardized configuration file without any personal tracking or identifying keys:

```bash
cat << 'INPUT_EOF' > /usr/bin/psiphon.config
{
  "SocksProxyPort": 10808,
  "HttpProxyPort": 10809,
  "ClientPlatform": "Windows_10.0.26200_11",
  "ClientVersion": "187",
  "DataRootDirectory": "/usr/bin/psiphon_data",
  "EgressRegion": "US",
  "PropagationChannelId": "0000000000000000",
  "SponsorId": "0000000000000000",
  "ServerEntrySignaturePublicKey": "sHuUVTWaRyh5pZwy4UguSgkwmBe0EHtJJkoF5WrxmvA=",
  "UseIndistinguishableTLS": true
}
INPUT_EOF

```

---

## ⚡ 4. Dynamic & Intelligent Startup Script (On the Router)

> ⚠️ **CRITICAL NOTE:** If your router's local IP address is different from `192.168.0.1`, make sure to update the IP address in the `socat` lines (Section 5) with your actual router gateway IP.

Copy and execute the following script in the router's terminal to initialize Psiphon and bridge the ports:

```bash
# 1. Terminate any existing instances to avoid port conflicts
killall -9 psiphon-core socat 2>/dev/null

# 2. Run Psiphon core in the background
/usr/bin/psiphon-core -config /usr/bin/psiphon.config -dataRootDirectory /usr/bin/psiphon_data > /tmp/psiphon.log 2>&1 &

# 3. Wait a few seconds for Psiphon to establish the tunnel and open internal ports
echo "Starting Psiphon... Please wait 7 seconds..."
sleep 7

# 4. Automatically extract dynamic random ports from the log file
SOCKS_PORT=$(http_port=$(cat /tmp/psiphon.log | grep -o '"port":[0-9]*' | cut -d':' -f2); echo $http_port | awk '{print $1}')
HTTP_PORT=$(http_port=$(cat /tmp/psiphon.log | grep -o '"port":[0-9]*' | cut -d':' -f2); echo $http_port | awk '{print $2}')

echo "Detected Ports -> SOCKS: $SOCKS_PORT | HTTP: $HTTP_PORT"

# 5. Establish stable port forwarding via socat to the router's LAN IP (Ports 10808 and 10809)
socat TCP-LISTEN:10809,fork,bind=192.168.0.1 TCP:127.0.0.1:$HTTP_PORT &
socat TCP-LISTEN:10808,fork,bind=192.168.0.1 TCP:127.0.0.1:$SOCKS_PORT &

# 6. Append firewall rules to accept incoming traffic from the LAN interface
iptables -I INPUT -p tcp -i br-lan --dport 10808:10809 -j ACCEPT

echo "Psiphon has been successfully bound to fixed LAN ports!"

```

---

## 🛑 5. Deactivation & Teardown Commands

Whenever you need to completely stop Psiphon, kill the bridged processes, and clear the firewall rules, run the following command in your router's terminal:

```bash
# 1. Kill Psiphon core and socat processes
killall -9 psiphon-core socat 2>/dev/null

# 2. Remove the firewall rule that allowed traffic through ports 10808 and 10809
iptables -D INPUT -p tcp -i br-lan --dport 10808:10809 -j ACCEPT 2>/dev/null

echo "Psiphon and all bridged connections have been successfully deactivated."

```

---

## 💻 6. Client Configuration (Windows, Mobile, Browser Extensions)

Once the automation script runs successfully on the router, you can route your client device traffic through the proxy using the following parameters (e.g., inside FoxyProxy or your operating system's proxy settings):

* **Proxy Type:** `HTTP`
* **IP Address:** `192.168.0.1` (Your router's local gateway IP address)
* **Port:** `10809`
EOF

```

```
