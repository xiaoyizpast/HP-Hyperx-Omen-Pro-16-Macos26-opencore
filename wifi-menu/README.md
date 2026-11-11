# WiFi Menu — MT7925 菜单栏 Wi-Fi 客户端

给 macOS 26.0 上的 **MediaTek MT7925** 补一个图形界面。

macOS 26.0 没有这张卡的原生 Wi-Fi 驱动，`MtkWlan` 驱动只提供「以太网前端」，
系统设置里没有 Wi-Fi 面板。这个菜单栏 App 用 `mtkwifi` 工具把常用操作包起来。

## 状态：26.0 的归档备选方案

macOS 26.7.1（25G241）和 26.7.2（25G332）请使用官方的 [MtkWlanNative](https://github.com/watchthelight-labs/WTLWifiMenu)，本 App 不再需要。

[English](README.en.md)

## 前提

1. 已安装 `MtkWlan.kext`（本 App 不含驱动，见 [WTLMtkWireless](https://github.com/watchthelight-labs/WTLMtkWireless)）
2. 系统里已出现 `en2` 这类以太网接口
3. macOS 26.0 / 25A354（26.7.1+ 请用官方的 `MtkWlanNative`，不需要本 App）

## 安装

```bash
./install.sh                  # 基础安装
./install.sh --with-autojoin  # 额外安装「开机自动连接已保存网络」
```

卸载：

```bash
./uninstall.sh
```

## 功能

- 菜单栏**只显示图标**（连上 `wifi`，断开 `wifi.slash`）
- 点开菜单即**实时扫描**（免密，2–4 秒出结果）
- 已保存 / 开放网络**免密连接**；新 WPA2 网络弹密码框
- 连上开放网络后自动打开校园网门户（跟随重定向，最多重试 4 次）
- 菜单项：刷新 / 重新扫描 / 打开登录页 / 断开 / 退出

## 权限说明

`mtkwifi` 的扫描与连接需要 root。安装脚本做了两件事：

1. 把 `mtkwifi` 装到 `/usr/local/bin`（root 所有，用户不可写，避免提权）
2. 写入 `/etc/sudoers.d/mtkwifi`，**只放行三条命令**：

```
ALL=(root) NOPASSWD: /usr/local/bin/mtkwifi scan --wait,
                     /usr/local/bin/mtkwifi join *,
                     /usr/local/bin/mtkwifi disconnect
```

需要密码的网络仍然走系统授权框；密码写一次性 0600 临时文件，结束后立即删除，
不会出现在命令行参数里。

## 已知限制

- 不是原生 Wi-Fi 面板：没有菜单栏 Wi-Fi 列表、没有「首选网络」设置项
- 切换网络时会有 1–2 秒断线
- 不支持 WPA2-Enterprise（`MtkWlan` 驱动本身不支持）
- 仅 x86_64、macOS 26

## 版本说明

`mtkwifi` 取自 `mt7925-wifi-bundle-0.12.1+0.4.16` 的 Recovery 目录，
包含 8a4de8e 对 `mtkwifi add` 的修复。

## 许可证

- 本 App（`main.swift`、`install.sh` 等）：MIT
- `mtkwifi` 二进制：来自 WTLMtkWireless，**ISC 许可**，见 `LICENSE-mtkwifi.txt`
