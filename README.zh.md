**Chinese** | [Persian](README.md) | [English](README.en.md)

# Psiphon VPN + CDN Fronting

在 OpenWrt 25 上安装、设置和自动化 Psiphon-Core 及其图形化 LuCI 面板的指南。

本项目提供了一个完全可用的指南，用于将 Psiphon Linux 核心（psiphon-core）与 OpenWrt 25 操作系统上的 LuCI JavaScript 图形用户界面连接起来。所有的服务控制按钮、配置字段（端口、国家、协议）以及 IP 状态监控 / 防止 DNS 泄漏部分均已完全同步。

## 🚀 简易安装指南

要快速安装，只需通过 SSH 客户端（如 PuTTY 或 Terminal）连接到您的路由器，然后运行以下命令：

```bash
wget -O /tmp/install.sh https://raw.githubusercontent.com/MehArt44/Psiphon-core-Openwrt25-LuCI/main/install.sh
sh /tmp/install.sh

```

> ⏳ 下载和安装最多可能需要 10 分钟，请耐心等待。

## 🛠️ 手动安装指南

### 1. 下载与您路由器匹配的文件

在 Releases（发布）部分下载文件之前，请先在路由器上运行以下命令来识别 CPU 架构：

```bash
uname -m
```

### 2. 将文件传输到路由器

1. 下载完成后，将文件重命名为 `psiphon-core`。
2. 使用 MobaXterm 或 SCP 等工具将其传输到路由器。
3. 将其放入路由器上的 `/usr/bin` 文件夹：

```bash
/usr/bin/psiphon-core
```

### 3. 部署基础架构及完整图形面板代码

将文件 `Psiphon VPN 2.0.42_manual.setup.sh` 移动到 `/tmp` 文件夹，并运行以下命令：

```bash
sh "/tmp/Psiphon VPN 2.0.42_manual.setup.sh"
```

### ✅ 4. 开始使用

1. 启用 **Auto Connect (Enable)** 和 **Full Tunnel Mode**。
2. 每次更改后，都必须点击 **Save & Apply**（保存并应用）才能保存设置。
3. 点击 **Start**（启动），系统会创建以下两个文件/文件夹：

```bash
/tmp/psiphon/ca.psiphon.PsiphonTunnel.tunnel-core/datastore/psiphon.boltdb
/tmp/psiphon/psiphon.config
```

## 🗑️ 从系统中彻底移除 Psiphon（卸载）— 测试模式

将 `Uninstall.sh` 传输到路由器，然后运行以下命令之一：

```bash
sh Uninstall.sh            # 需确认
sh Uninstall.sh -y         # 无需询问
sh Uninstall.sh -y --purge # 完全删除
```

安装脚本（`install.sh`）同样支持这些选项，且在卸载模式下不会下载任何内容：

```bash
sh /tmp/install.sh --uninstall
sh /tmp/install.sh --purge
```

**卸载步骤：**

- **停止并释放：** 停止并禁用服务，同时释放 kill switch，以免 LAN 网络保持断开。如果 psiphon-core 或 watcher 仍在运行，也会将其终止。
- **网络清理：** 首先运行 helper 自带的 cleanup，然后再执行一次独立的手动清理作为后备。该后备清理会还原 nft 表、ip rule 990 和 1000、路由表 100、tun0（仅当由 Psiphon 创建时）、WAN 上的 IPv6、dnsmasq 中的 DNS 文件、DoH 引擎以及 dnsmasq 的上游服务器。
- **删除文件：** 删除程序文件、防火墙 zone 和 forwarding，以及 `/etc/sysupgrade.conf` 中的条目。
- **最终验证：** 最后检查是否有残留，并测试路由器的互联网访问和本地 DNS。

**选项：**

- `--purge`：除上述内容外，还会删除配置、datastore 和 core 二进制文件。
- `--remove-deps`：删除 https-dns-proxy 和 tcpdump 软件包。
- `--reset-confdir`：还原 dnsmasq 中的 confdir 值。

## 🧪 完整测试（Test_Full.sh）

```bash
sh Test_Full.sh            # 非侵入式测试
sh Test_Full.sh --quick    # 仅静态检查
sh Test_Full.sh --full     # 包含启动/停止测试和 CDN 扫描器
sh Test_Full.sh --only helper,live
```

- **env：** 前置条件、kmod-tun、ca-bundle、TLS、闪存空间和 nftables。
- **files：** 已安装的文件、权限、语法、menu 和 ACL 的 JSON，以及 core 二进制文件的标志。
- **config：** UCI 值及选项之间的冲突、防火墙 zone、dnsmasq 中的 confdir 以及 sysupgrade 条目。
- **helper：** helper 本身的离线测试；会检查为 core 生成的配置、日志解析器、子网计算、MTU 与 MSS，以及 CDN 范围和采样。

## 🖥️ Psiphon 的 LuCI 环境

注意：每次更改后，请点击 **Save & Apply**（保存并应用），然后点击 **Start**（启动）。

<img width="1992" height="1912" alt="Psiphon VPN" src="https://github.com/user-attachments/assets/71b58768-c9d6-455a-a47a-9973182afa96" />

**Save & Apply**

<img width="734" height="1274" alt="image" src="https://github.com/user-attachments/assets/298ec61e-ed5c-4a87-a59a-da9ee662972e" />

检查 IP 和 DNS 泄漏：

```bash
https://browserleaks.com/dns
https://browserleaks.com/ip
```

<img width="1572" height="1472" alt="image" src="https://github.com/user-attachments/assets/a9f5d3bf-5246-4025-aa10-36f1231e04d8" />
