**Chinese** | [Persian](README.md) | [English](README.en.md)


在 OpenWrt 25 上安装、设置和自动化 Psiphon-Core 及其图形化 LuCI 面板的指南。

本项目提供了一个完全可用的指南，用于将 Psiphon Linux 核心（psiphon-core）与 OpenWrt 25 操作系统上的 LuCI JavaScript 图形用户界面连接起来。所有的服务控制按钮、配置字段（端口、国家、协议）以及 IP 状态监控 / 防止 DNS 泄漏部分均已完全同步。

## 🚀 简易安装指南

要快速安装，只需通过 SSH 客户端（ PuTTY / Terminal）连接到您的路由器，然后运行以下命令：
MobaXterm / SCP

```bash

wget -O /tmp/install.sh https://raw.githubusercontent.com/MehArt44/Psiphon-core-Openwrt25-LuCI/main/install.sh

sh /tmp/install.sh

```

## 🚀 手动安装指南

**🛠️ 1. 下载与您路由器匹配的文件**

在 Releases（发布）部分，通过在路由器上运行以下命令来识别您路由器的 CPU 架构：

```bash
uname -m

```

**🚀 2. 将文件传输到路由器**

1. 下载完成后，将文件重命名为 `psiphon-core`。
2. 使用 MobaXterm 或 SCP 等工具将其传输到路由器。
3. 将其移动到路由器上的 `/usr/bin` 文件夹中：

```bash
/usr/bin/psiphon-core

```

**📁 3. 部署基础架构及完整图形面板代码**

将文件 `Psiphon VPN 2.0.40.sh` 移动到以下文件夹：

`"/tmp/Psiphon VPN 2.0.40.sh"`

并运行以下命令：

```bash
sh "/tmp/Psiphon VPN 2.0.40.sh"

```

# 🗑️ 从系统中彻底、不可逆转地移除 Psiphon（卸载）

将文件传输到路由器中，然后运行以下命令：

```bash
sh "/tmp/Uninstall.sh"

```

## Psiphon 的 LuCI 环境

注意：每次更改后，请点击 **Save & Apply**（保存并应用），然后点击 **Start**（启动）。
<img width="1616" height="1602" alt="image" src="https://github.com/user-attachments/assets/a3460d87-24bc-4907-afa6-a63d4523b88f" />


```bash
https://browserleaks.com/dns](https://browserleaks.com/dns
https://browserleaks.com/ip](https://browserleaks.com/ip
```
<img width="1578" height="1589" alt="image" src="https://github.com/user-attachments/assets/a96214aa-08a6-407f-823a-779e26be24d6" />

```
