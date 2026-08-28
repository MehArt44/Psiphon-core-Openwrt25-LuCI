
**English** | [Persian](README.md)



Guide for installing, setting up, and automating Psiphon-Core along with a graphical LuCI panel on OpenWrt 25.

This project is a fully operational guide for connecting the Psiphon Linux core (psiphon-core) to the LuCI JavaScript graphical user interface on the OpenWrt 25 operating system. All service control buttons, configuration fields (ports, country, protocol), and the IP status monitoring / DNS leak prevention section are fully synchronized.

## 🚀 Easy Installation Guide

For a quick install, simply connect to your router via an SSH client (such as PuTTY or Terminal) and run the following command:

```bash
wget -O /tmp/install.sh https://raw.githubusercontent.com/MehArt44/Psiphon-core-Openwrt25-LuCI/main/install.sh
sh /tmp/install.sh
```

## 🚀 Manual Installation Guide

**🛠️ 1. Download the file matching your router**

From the Releases section, identify your router's CPU architecture by running the following command on the router:

```bash
uname -m
```

**🚀 2. Transfer the files to the router**

1. After the download finishes, rename the file to `psiphon-core`.
2. Transfer it to the router using tools such as MobaXterm or SCP.
3. Move it to the `/usr/bin` folder on the router:

```bash
/usr/bin/psiphon-core
```

**📁 3. Deploy the infrastructure and full graphical panel code**

Move the file `Psiphon VPN 2.0.40.sh` to the following folder:

`"/tmp/Psiphon VPN 2.0.40.sh"`

and run the following command:

```bash
sh "/tmp/Psiphon VPN 2.0.40.sh"
```

# 🗑️ Complete and Irreversible Removal of Psiphon from the System (Uninstall)

Transfer the file into the router, then run the following command:

```bash
sh "/tmp/Uninstall.sh"
```

## LuCI Environment for Psiphon

Note: after every change, click **Save & Apply**, then click **Start**.

<img width="1616" height="1602" alt="image" src="https://github.com/user-attachments/assets/a3460d87-24bc-4907-afa6-a63d4523b88f" />

```bash
https://browserleaks.com/dns
https://browserleaks.com/ip
```

<img width="1578" height="1589" alt="image" src="https://github.com/user-attachments/assets/a96214aa-08a6-407f-823a-779e26be24d6" />

