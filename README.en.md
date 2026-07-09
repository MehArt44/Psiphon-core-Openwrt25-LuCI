**English** | [پارسی](README.md)


 

# OpenWrt 24.10 Psiphon-Core Setup & Automation Guide

🛑 Note: The pre-compiled binary, configuration files, and necessary scripts are already prepared inside the `Router.zip` folder. The build steps below are provided for verification purposes; you only need to execute the router commands. 🛑

This repository offers a comprehensive guide and an intelligent automation script to deploy, manage, and bridge the standalone Linux Psiphon core (`psiphon-core`) on **OpenWrt** routers (optimized for version 24.10 and 64-bit ARM architectures such as `aarch64_cortex-a53` on devices like the GL-MT3000).

The Go-based Psiphon core is strictly case-sensitive. This updated guide implements the precise `camelCase` configuration layout to solve the random port generation bug, forcing the core to respect fixed ports. Additionally, the tunnel pool allocation has been optimized to resolve handshake timeout errors (`EstablishTunnelTimeout`) under aggressive network censorship environments.

---

## 🛠️ 1. Compiling the Binary (On Your PC)

If you prefer to compile the Psiphon core binary for the router's architecture (`arm64`) manually, ensure the Go language environment is installed on your machine, then run the following commands in your terminal:

```bash
# 1. Clone the official Psiphon core repository
git clone [https://github.com/Psiphon-Labs/psiphon-tunnel-core.git](https://github.com/Psiphon-Labs/psiphon-tunnel-core.git)

# 2. Navigate to the project root directory
cd psiphon-tunnel-core

# 3. Download dependencies and set target architecture environment variables for 64-bit ARM Linux
go mod download
export GOOS=linux
export GOARCH=arm64

# 4. Compile a highly optimized, stripped, lightweight binary for the router
go build -ldflags="-s -w" -o psiphon-core .

```

Transfer the generated `psiphon-core` file to the router's `/usr/bin/` path using an SFTP client (e.g., MobaXterm or WinSCP).

---

## 📂 File Architecture and Paths on the Router

Before executing the deployment scripts, the file layout on the router must match the structure below (the configuration file will be safely generated via the terminal in Step 3, eliminating manual file editing or transfer issues):

| # | Item Type | File / Folder Name | Router Absolute Path | Description |
| --- | --- | --- | --- | --- |
| 1 | **Executable Binary** | `psiphon-core` | `/usr/bin/psiphon-core` | The compiled core binary matching the router's CPU architecture (e.g., ARM64). |
| 2 | **Configuration File** | `psiphon.config` | `/usr/bin/psiphon.config` | Automatically generated directly on the router using the precise `camelCase` structure. |
| 3 | **Internal Database** | `psiphon_data` | `/usr/bin/psiphon_data/` | Directory for storing server lists, handshake caches, and OTA updates. |

---

## 🚀 2. Environment Preparation & Prerequisites (On the Router)

After transferring the binary to `/usr/bin/`, execute the following commands in the router terminal to adjust execution permissions and install the network bridging dependency `socat`:

```bash
# Grant execution permissions to the binary and create the data directory
chmod +x /usr/bin/psiphon-core
mkdir -p /usr/bin/psiphon_data

# Update package repositories and install socat for dynamic traffic redirection
opkg update && opkg install socat

```

---

## 📝 3. Generating the Standard Psiphon Configuration (`psiphon.config`)

⚠️ **CRITICAL NOTE:** Execute this block **completely independently** in the router's CLI interface. All JSON keys are formatted strictly in `camelCase` to prevent the Go binary from ignoring the user-defined ports. The `tunnelPoolSize` parameter is set to `6` to maximize handshake success under severe protocol filtering:

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

> 🔍 **Verification:** Run `cat /usr/bin/psiphon.config` to verify the payload was cleanly written and saved without truncation.

---

## ⚡ 4. Dynamic Router Bootstrapping & Orchestration Script

This automation script clears dead background instances and targets. It extends the initial handshake sleep period to 30 seconds to provide the core adequate time to spin up 6 parallel multiplexed tunnel paths.

> 💡 **Egress Region Selection Code Guide:**
> Modify the `TARGET_REGION` variable on line 1 using a standard uppercase two-letter ISO country code code. (Set to `"ALL"` to bind to the lowest-latency node).
> | Country Code | Region Name | | Country Code | Region Name |
> | :---: | :--- | | :---: | :--- |
> | **`AT`** | Austria | | **`IT`** | Italy |
> | **`BE`** | Belgium | | **`JP`** | Japan |
> | **`CA`** | Canada | | **`NL`** | Netherlands |
> | **`CH`** | Switzerland | | **`NO`** | Norway |
> | **`DE`** | Germany | | **`PL`** | Poland |
> | **`DK`** | Denmark | | **`SE`** | Sweden |
> | **`ES`** | Spain | | **`SG`** | Singapore |
> | **`FI`** | Finland | | **`US`** | United States |
> | **`FR`** | France | | **`GB`** | United Kingdom |

```bash
# 🌍 Define the egress location (ISO 2-letter uppercase or ALL for optimal performance)
TARGET_REGION="ALL"

echo "Setting Psiphon region target to: $TARGET_REGION"
# Inject target region directly while preserving strict camelCase keys
sed -i "s/\"egressRegion\": \".*\"/\"egressRegion\": \"$TARGET_REGION\"/g" /usr/bin/psiphon.config

# 1. Kill stale processes and flush old blocked server entry caches
killall -9 psiphon-core socat 2>/dev/null
rm -rf /usr/bin/psiphon_data/*

# 2. Launch the core module in the background and pipe runtime logs to volatile RAM cache
/usr/bin/psiphon-core -config /usr/bin/psiphon.config -dataRootDirectory /usr/bin/psiphon_data > /tmp/psiphon.log 2>&1 &

# 3. Allow sufficient initialization window for handshake negotiations (30 seconds recommended)
echo "Negotiating tunnel layers... Please wait 30 seconds..."
sleep 30

# 4. Extract runtime random ports generated by the system from the log stream
SOCKS_PORT=$(grep "ListeningSocksProxyPort" /tmp/psiphon.log | grep -o '"port":[0-9]*' | cut -d':' -f2)
HTTP_PORT=$(grep "ListeningHttpProxyPort" /tmp/psiphon.log | grep -o '"port":[0-9]*' | cut -d':' -f2)

echo "Discovered dynamic runtime ports -> SOCKS: $SOCKS_PORT | HTTP: $HTTP_PORT"

# 5. Interrogate the system bus interface to locate the active LAN Gateway IP
ROUTER_IP=$(ubus call network.interface.lan status | jsonfilter -e '@["ipv4-address"][0].address')
echo "Detected LAN interface interface binding address: $ROUTER_IP"

# 6. Bridge traffic targets from local sockets to the accessible static LAN gateway ports
socat TCP-LISTEN:10809,fork,bind=$ROUTER_IP TCP:127.0.0.1:$HTTP_PORT &
socat TCP-LISTEN:10808,fork,bind=$ROUTER_IP TCP:127.0.0.1:$SOCKS_PORT &

# 7. Inject explicit rules into OpenWrt 24.10's native nftables architecture (fw4 framework)
nft add rule inet fw4 input iifname "br-lan" tcp dport 10808-10809 accept 2>/dev/null

echo "Psiphon core has been successfully stabilized on static LAN ports!"

```

---

## ⚙️ 5. Implementing a Permanent Init System Service (`/etc/init.d/psiphon`)

To build a persistent system service that automatically starts up when the router boots, follow the procedure below:

1. Execute this block directly to generate the init script file:

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

⚠️ **CRITICAL STEP (Preventing Permission Denied Errors):** Newly created scripts under the `init.d` directory do not carry executable flags by default. You **must** execute the command below to grant execution rights, otherwise the service engine will throw a permission denied crash:

```bash
chmod +x /etc/init.d/psiphon

```

2. Service execution control references:

* **Start Tunnel Engine:** `/etc/init.d/psiphon start`
* **Stop Tunnel Engine:** `/etc/init.d/psiphon stop`
* **Enable Persistent Boot Start:** `/etc/init.d/psiphon enable`

---

## 🛑 6. Manual Termination Command

If you choose not to deploy the persistent service model, use this explicit sequence to gracefully spin down core threads and tear down dynamic socket forwarders:

```bash
# Terminate runtime core instances and bridge listeners
killall -9 psiphon-core socat 2>/dev/null

# Cycle the native firewall interface to sweep out temporary rules
/etc/init.d/firewall restart

echo "Psiphon engine and socket bridging hooks have been successfully destroyed."

```

---

## 💻 7. Client Configuration Reference (Windows, Android, iOS, Browsers)

To route client terminal traffic through the unblocked gateway channels, pass these manual server entries inside your device proxy options or extensions (e.g., FoxyProxy):

* **Proxy Protocol Type:** `HTTP` or `SOCKS5`
* **Gateway Binding Address:** Your router management LAN IP (e.g., `192.168.18.1`)
* **HTTP Target Port:** `10809`
* **SOCKS Target Port:** `10808`

---

## 📊 8. Validating Success Logs

A healthy connection lifecycle should generate JSON diagnostic logs matching the structured output below:

```text
{"data":{"ID":"UNKNOWN"},"noticeType":"NetworkID","timestamp":"2026-07-08T19:29:20.923Z"}
{"data":{"port":10808},"noticeType":"ListeningSocksProxyPort","timestamp":"2026-07-08T19:29:20.927Z"}
{"data":{"port":10809},"noticeType":"ListeningHttpProxyPort","timestamp":"2026-07-08T19:29:20.927Z"}
{"data":{"regions":["AT","BE","CA","CH","DE","DK","ES","FI","FR","GB","IT","JP","NL","NO","PL","SE","SG","US"]},"noticeType":"AvailableEgressRegions"}
{"data":{"region":"US"},"noticeType":"ConnectedServerRegion"}

```

> 💡 **Insight:** The generation of the final `"ConnectedServerRegion"` line confirms a successful cryptographic handshake and an active circuit layout.

---

## ⚡ 9. Connection Testing & Tunnel Verification

Because the forwarding listeners are bound directly to the router's internal LAN IP, proxy verification calls utilizing `curl` must explicitly point to the gateway node. Ensure no extraneous brackets or formatting artifacts are passed into the CLI:

* **Inspect live connection event traces and look for potential error frames:**
```bash
tail -n 25 /tmp/psiphon.log

```


* **Verify active port allocation and listener state matrices:**
```bash
netstat -tulpn | grep -E '10808|10809'

```


* **Test the HTTP proxy pipe interface to display your external egress IP node address:**
```bash
curl -x [http://192.168.18.1:10809](http://192.168.18.1:10809) [https://ifconfig.me](https://ifconfig.me)

```


* **Test the SOCKS5 proxy pipe interface:**
```bash
curl --socks5-hostname 192.168.18.1:10808 [https://ifconfig.me](https://ifconfig.me)

```



---

## 🗑️ 10. Complete System Uninstallation Script

If you wish to cleanly purge all application binaries, databases, runtime log profiles, and volatile index caches from the underlying storage tree, copy and paste this pipeline block into your terminal:

```bash
# 1. Clear LuCI index caches and recycle the remote procedure service framework
rm -rf /tmp/luci-indexcache /tmp/luci-modulecache
/etc/init.d/rpcd restart

# 2. Gracefully halt active service instances and background worker loops
/etc/init.d/psiphon stop 2>/dev/null
killall -9 psiphon-core socat psiphon 2>/dev/null

# 3. Purge system paths and static configurations
rm -f /usr/bin/psiphon-core
rm -rf /usr/bin/psiphon_data
rm -f /etc/config/psiphon
rm -f /etc/init.d/psiphon
rm -f /www/luci-static/resources/view/services/psiphon.js
rm -f /tmp/psiphon*

# 4. Remove temporary logging dumps
rm -f /tmp/psiphon.log

# 5. Perform a global sweep to intercept and delete isolated instances
find / -name "*psiphon*" -exec rm -rf {} + 2>/dev/null

# 6. Re-index web framework assets and force a complete system layout reload
rm -rf /tmp/luci-indexcache /tmp/luci-modulecache
/etc/init.d/rpcd restart

echo "Everything related to Psiphon has been completely wiped!"

```

```
---

```
