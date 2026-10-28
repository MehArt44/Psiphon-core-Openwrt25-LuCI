**English** | [Persian](README.md) | [Chinese](README.zh.md)

# Psiphon VPN + CDN Fronting

Guide for installing, setting up, and automating Psiphon-Core along with a graphical LuCI panel on OpenWrt 25.

This project is a fully operational guide for connecting the Psiphon Linux core (psiphon-core) to the LuCI JavaScript graphical user interface on the OpenWrt 25 operating system. All service control buttons, configuration fields (ports, country, protocol), and the IP status monitoring / DNS leak prevention section are fully synchronized.

## 🚀 Easy Installation Guide

For a quick install, simply connect to your router via an SSH client (such as PuTTY or Terminal) and run the following commands:

```bash
wget -O /tmp/install.sh https://raw.githubusercontent.com/MehArt44/Psiphon-core-Openwrt25-LuCI/main/install.sh
sh /tmp/install.sh

```

> ⏳ Download and installation may take up to 10 minutes; please be patient.

## 🛠️ Manual Installation Guide

### 1. Download the file matching your router

From the Releases section, identify your router's CPU architecture by running the following command on the router:

```bash
uname -m
```

### 2. Transfer the file to the router

1. After the download finishes, rename the file to `psiphon-core`.
2. Transfer it to the router using tools such as MobaXterm or SCP.
3. Place it in the `/usr/bin` folder on the router:

```bash
/usr/bin/psiphon-core
```

### 3. Deploy the infrastructure and full graphical panel code

Move the file `Psiphon VPN 2.0.42_manual.setup.sh` to `/tmp` and run the following command:

```bash
sh "/tmp/Psiphon VPN 2.0.42_manual.setup.sh"
```

### ✅ 4. Getting started

1. Enable **Auto Connect (Enable)** and **Full Tunnel Mode**.
2. After every change, you must click **Save & Apply** for the settings to be saved.
3. Click **Start** so that these two files/folders are created:

```bash
/tmp/psiphon/ca.psiphon.PsiphonTunnel.tunnel-core/datastore/psiphon.boltdb
/tmp/psiphon/psiphon.config
```

## 🗑️ Complete Removal of Psiphon from the System (Uninstall) — TEST mode

Transfer `Uninstall.sh` to the router and run one of the following commands:

```bash
sh Uninstall.sh            # with confirmation
sh Uninstall.sh -y         # without prompting
sh Uninstall.sh -y --purge # full removal
```

The installer (`install.sh`) also supports these options and downloads nothing in uninstall mode:

```bash
sh /tmp/install.sh --uninstall
sh /tmp/install.sh --purge
```

**Removal steps:**

- **Stop and release:** stops and disables the service and releases the kill switch so the LAN internet is not left blocked. If psiphon-core or the watcher are still alive, they are terminated as well.
- **Network cleanup:** the helper's own cleanup runs first, followed by a separate manual cleanup as a fallback. The fallback restores the nft tables, ip rules 990 and 1000, route table 100, tun0 (only if Psiphon created it), IPv6 on the WAN, the DNS file in dnsmasq, the DoH engine, and the dnsmasq upstreams.
- **File removal:** the application files, the firewall zone and forwarding, and the entries in `/etc/sysupgrade.conf` are deleted.
- **Final verification:** finally, it checks for leftovers and tests the router's internet access and local DNS.

**Options:**

- `--purge`: in addition to everything else, also deletes the config, the datastore, and the core binary.
- `--remove-deps`: removes the https-dns-proxy and tcpdump packages.
- `--reset-confdir`: restores the confdir value in dnsmasq.

## 🧪 Full test suite (Test_Full.sh)

```bash
sh Test_Full.sh            # non-intrusive tests
sh Test_Full.sh --quick    # static checks only
sh Test_Full.sh --full     # including start/stop tests and the CDN scanner
sh Test_Full.sh --only helper,live
```

- **env:** prerequisites, kmod-tun, ca-bundle, TLS, flash space, and nftables.
- **files:** installed files, permissions, syntax, menu and ACL JSONs, and the core binary flags.
- **config:** UCI values and conflicts between options, the firewall zone, the confdir in dnsmasq, and sysupgrade entries.
- **helper:** offline test of the helper itself; the generated core config, log parsers, subnet calculation, MTU and MSS, and CDN ranges and sampling are checked.

## 🖥️ LuCI Environment for Psiphon

Note: after every change, click **Save & Apply**, then click **Start**.

<img width="1992" height="1912" alt="Psiphon VPN" src="https://github.com/user-attachments/assets/71b58768-c9d6-455a-a47a-9973182afa96" />

**Save & Apply**

<img width="734" height="1274" alt="image" src="https://github.com/user-attachments/assets/298ec61e-ed5c-4a87-a59a-da9ee662972e" />

To check your IP and DNS leaks:

```bash
https://browserleaks.com/dns
https://browserleaks.com/ip
```

<img width="1572" height="1472" alt="image" src="https://github.com/user-attachments/assets/a9f5d3bf-5246-4025-aa10-36f1231e04d8" />
