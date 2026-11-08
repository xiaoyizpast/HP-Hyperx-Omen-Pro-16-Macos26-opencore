# HP HyperX OMEN PRO 16（主板 8F06）· Ryzen 9 9955HX + RTX 5060 Laptop · macOS 26 Tahoe

一份在 **HP HyperX OMEN PRO 16 (8F06)**（子系统 ID `103c:8f06`）上跑通 macOS 26 的 OpenCore 配置、
踩坑记录与驱动清单。**不是通用 EFI**，其他机型请勿直接套用。

- 系统：macOS 26.0 Tahoe（25A354）实测通过
- 引导：OpenCore 1.0.9
- 显卡：NullMoth 第三方驱动 2.8.1（**不在本仓库**）

[English](README.en.md) · 简体中文

---

## 一、当前实现情况

| 功能 | 状态 | 说明 |
|---|---|---|
| 引导 / 开机 | ✅ | 正常进桌面 |
| 显卡 Metal | ✅ | NullMoth 2.8.1，Metal **4** |
| 内屏 2560×1600@240 | ✅ | 正常 |
| 外接屏 1080p@300 | ✅ | 扩展模式，可设为主屏 |
| Wi-Fi MT7925 | ✅ | 需 `mtkwifi` 工具或附带菜单栏 App |
| 蓝牙 MT7925 | ✅ | `State: On` / `THIRD_PARTY_DONGLE`，可配对 |
| 音频输出 | ✅ | 内置扬声器、耳机 |
| 亮度调节 | ✅ | 硬件背光（`nvrmacpibl=1`） |
| 电池电量 | ✅ | 百分比 / 健康度 |
| 交流电状态 | ✅ | 自写 SSDT-AC 修正（本机型专用） |
| 触控板 | ✅ | 多指手势 |
| 键盘 | ✅ | 正常 |
| 摄像头 | ✅ | UVC |
| 有线网卡 | ✅ | RTL8111 |
| USB 网络共享 | ✅ | HoRNDIS |
| 合盖模式 | ✅ | 附脚本：接外屏禁睡、合盖熄内屏 |
| **内置麦克风** | ❌ | 录音只有恒定底噪；AppleALC + SimpleHDA 也无效 |
| **H.264 硬解** | ❌ | HEVC 支持，H.264 不支持（驱动限制） |
| **风扇/温度** | ❌ | AMD 平台无 SMC 传感器 |
| **外接屏热插拔** | ⚠️ | 拔插后可能黑屏，重启恢复 |
| **关机速度** | ⚠️ | 偶发 shutdown stall |
| **AMD 核显** | ❌ | 已 `disable-gpu` 屏蔽（macOS 无驱动） |

---

## 二、安装步骤

1. **备份你自己的 EFI**，再把本仓库的 `boards/8F06/EFI/` 覆盖到 EFI 分区。
2. `./fetch-kexts.sh` —— 从各项目官方 Release 下载驱动到 `boards/8F06/EFI/OC/Kexts/`。
3. **生成你自己的 SMBIOS**（仓库里是占位值）：
   - [GenSMBIOS](https://github.com/corpnewt/GenSMBIOS) 选 `MacBookPro16,2`
   - 填 `PlatformInfo → Generic` 的 Serial / MLB / SystemUUID
   - `ROM` 设成你 `en0` 的 MAC（6 字节）
4. **安装 NVIDIA 驱动**（本仓库不含）：
   - [NullMoth driver](https://github.com/nullmoth/nvidia-macos-driver) + [1401](https://github.com/nullmoth/1401)
   - 不装的话只有基本显示，没有 Metal 加速
5. 重启。

> 具体每一项为什么这么配，见 **[docs/BOOT-AND-CONFIG.md](docs/BOOT-AND-CONFIG.md)**；
> 发布/使用的法律与安全风险见 **[RISKS.md](RISKS.md)**。

---

## 三、踩坑记录（本机实际遇到的全部问题）

### 引导 / 内核

| # | 现象 | 原因 | 解决 |
|---|---|---|---|
| 1 | 改完配置卡在 `EB\|LOG:EXITBS:START`，之后无输出 | 验证器建议把 `DevirtualiseMmio`、`SetupVirtualMap` 改成 `false`，但这块 AM5 板子必须为 `true`，否则 boot.efi 无法给内核分配内存 | 两个 Quirk 保持 `true`（**别听验证器**） |
| 2 | 换 SMBIOS 为 `MacPro6,1` 后出现**禁止符号** | macOS 26 只支持 2018 年以后的 Mac，2013 机型被拒绝 | 回退到 `MacBookPro16,2` |
| 3 | 以为 HP 固件只认 `BOOTX64.EFI`，把 `bootmgfw.efi` 换成 OC | 实际固件只从 `\EFI\Microsoft\Boot\bootmgfw.efi` 启动，不扫 `\EFI\BOOT\` | 见下方「HP 引导」小节 |
| 4 | 配了 `BootProtect = Bootstrap` 却没生成 `Bootstrap.efi` | OpenCore 1.0.9 **已移除**该键，日志报 `OCS: No schema for BootProtect` | 改用 `LauncherOption`；或直接采用 `bootmgfw` 占位方案 |
| 5 | 改了 `boot-args` 但没生效 | OpenCore 的 `NVRAM → Add` **不覆盖已存在的变量** | 同时在 `NVRAM → Delete` 里登记同名键 |

### 蓝牙

| # | 现象 | 原因 | 解决 |
|---|---|---|---|
| 6 | 蓝牙 `State: Off`、`Address: NULL`、芯片显示 `BCM_4350C2` | `bluetoothd` 按 SMBIOS 走 UART 通道，去找 `/dev/cu.BLTH` | 见下一条 |
| 7 | 加了 `bluetoothHostControllerSwitchBehavior=always` 仍无效 | 该开关只影响"是否优先外置"，不改变传输类型 | 真正需要的是下面两个 NVRAM 键 |
| 8 | 强制 `BT_HCI_TRANSPORT=USB` 写进 NVRAM 也不读 | 它是**环境变量**，不是 NVRAM 键 | 放弃该方案 |
| 9 | **关键**：蓝牙始终不工作 | BlueToolFixup 2.7.0+ 要求两个 NVRAM 键，缺了会退回 UART 占位 | `bluetoothExternalDongleFailed=<00>`（1 字节）+ `bluetoothInternalControllerInfo=<0000000000000000000000000000>`（**必须正好 14 字节**，16 字节会报 `CFDataGetLength != 14`） |

### Wi-Fi

| # | 现象 | 原因 | 解决 |
|---|---|---|---|
| 10 | 系统设置里没有 Wi-Fi 面板 | `MtkWlanNative` 只支持 macOS **26.7.1 / 26.7.2** 两个 build | 26.0 只能用以太网前端；附带的菜单栏 App 作为替代 |
| 11 | `mtkwifi scan` 提示 `needs root` | 扫描需要 root 权限 | 加 sudoers 白名单（只放行 `scan --wait`），或手动 `sudo` |
| 12 | 开机能连、过一会断 | 保存的网络不会自动连接 | 用 LaunchDaemon 开机跑 `mtkwifi autojoin` |
| 13 | `mtkwifi add` 报 `mkdir ... No such file or directory` | 它不会递归创建 `/Library/Application Support/legion` | 先手动 `mkdir -p` 该目录 |
| 14 | 菜单栏 App 连新网络报 `not saved` | `list --json` 里的 `joinable` 表示"驱动支持该加密"，**不是**"已保存密码" | 先试免密，返回 `is not saved` 再弹密码框 |
| 15 | 带密码连接在后台跑不通 | `--ask` 需要 tty | 用 `expect` 提供伪终端；密码写一次性 600 文件，不走命令行参数 |

### 音频 / 麦克风

| # | 现象 | 原因 | 解决 |
|---|---|---|---|
| 16 | 有音频设备但扬声器没声 | 默认输出被设成了 `NVIDIA HDMI`（没接显示器） | 把默认输出切到 ALC245 |
| 17 | 想用 AppleALC 修麦克风，装了 SimpleHDA 仍无声 | macOS 26 删了 `AppleHDA`；且 ALC245 被 NullMoth 的 `NMXAudio` 抢占，AppleHDA 根本没接管 | 放弃；需要麦克风请用 USB/耳麦 |
| 18 | 录音全是恒定底噪 | NMXAudio 的输入通路没有真实采集 | 同上 |

### 电池 / 电源

| # | 现象 | 原因 | 解决 |
|---|---|---|---|
| 19 | 插电也显示 `Battery Power` | DSDT 的 `_PSR` 读 `H2RA` 窗口（`0xFE700000+0x340`）的 `R400`，macOS 读不到真实值 | 自写 `SSDT-AC` 改读 EC RAM `0x40` bit0，并重命名 `_PSR→XPSR`、`_Q20→XQ20` |
| 20 | 一度以为 `R830` bit15 是 AC 标志 | 它其实是**电池功率的符号位**（负=放电），插拔都可能是 0 | 用 EC `0x40` bit0（插电 `0x0B`、拔电 `0x02`） |
| 21 | 睡眠唤醒后系统卡顿 | `hibernatemode 3` + `standby 1` 会走休眠镜像恢复 | 改 `hibernatemode 0`、`standby 0` |

### 显示

| # | 现象 | 原因 | 解决 |
|---|---|---|---|
| 22 | Dock/界面严重掉帧 | 内屏 60Hz + 外屏 300Hz 处于**硬件镜像**模式 | 解除镜像改扩展，外屏设为主屏 |
| 23 | 合盖就睡眠，外接屏断 | `AppleClamshellCausesSleep = Yes` | `pmset disablesleep 1` + 合盖把内屏背光置 0（附脚本） |

---

## 四、HP HyperX OMEN PRO 16 (8F06) 的引导：为什么必须占用 `bootmgfw.efi`

HP 固件把启动项固定写成 `Boot0000 = \EFI\Microsoft\Boot\bootmgfw.efi`，
**不扫描** `\EFI\BOOT\BOOTX64.EFI`，也会忽略/重置第三方写入的 NVRAM 启动项。

日志证据：

```
OCB: No existing option at Boot0000, invalid
OCB: 0 -> Boot0000 = HD(1,GPT,...)/\EFI\Microsoft\Boot\bootmgfw.efi
```

因此方案是：

```
固件 → bootmgfw.efi（内容换成 OpenCore 启动器）
     → OpenCore 菜单
     → 选 Windows 时由 BlessOverride 转到 bootmgfw-orig.efi
```

- 原版引导器改名 `bootmgfw-orig.efi` 保留
- `Misc → BlessOverride` 填 `\EFI\Microsoft\Boot\bootmgfw-orig.efi`

**副作用**：Windows 大版本更新可能覆盖 `bootmgfw.efi`，届时会直接进 Windows，
需要重新把 OC 启动器放回去。改之前务必备份。

---

## 五、目录结构

```
boards/8F06/EFI/BOOT/BOOTx64.efi           OpenCore 启动器
boards/8F06/EFI/OC/OpenCore.efi            OpenCore 1.0.9 DEBUG
boards/8F06/EFI/OC/config.plist            已匿名化配置
boards/8F06/EFI/OC/ACPI/                   SSDT（含本机型专用 SSDT-AC）
boards/8F06/EFI/OC/Drivers/                OpenRuntime / HfsPlus / OpenCanopy / ResetNvramEntry
boards/8F06/EFI/OC/Resources/              OpenCanopy 资源
boards/8F06/EFI/OC/Kexts/                  空目录，用脚本下载
fetch-kexts.sh                 一键下载驱动
docs/BOOT-AND-CONFIG.md        配置逐项解释 + HP 引导分析
DRIVERS.md                     驱动清单（版本/来源/许可证）
STATUS.md                      实测状态与复现命令
RISKS.md                       发布风险清单
LICENSES.md / LICENSE          许可证
boards/8F06/ACPI-SOURCES/                  SSDT-AC 源码
tools/                         合盖脚本、亮度工具、Wi-Fi 菜单栏 App
```

---

## 六、说明

- 本仓库**不包含**任何第三方驱动二进制（GPL 与苹果版权原因），由脚本从官方 Release 获取。
- 所有驱动版权归原作者，链接见 [DRIVERS.md](DRIVERS.md)。
- 使用本配置造成的任何后果由使用者自负；请先阅读 [RISKS.md](RISKS.md)。

## 致谢

OpenCore / Lilu / VirtualSMC / WhateverGreen / AppleALC / VoodooI2C / VoodooPS2 /
BrcmPatchRAM / USBToolBox / NVMeFix / RestrictEvents / BrightnessKeys / ECEnabler /
AMFIPass / AppleMCEReporterDisabler / RTL8111 / HoRNDIS /
WTLMtkWireless / WTLMtkBluetooth / NullMoth NVIDIA driver
以及 [AMD Vanilla](https://github.com/AMD-OSX/AMD_Vanilla) 的内核补丁。
完整链接见 [DRIVERS.md](DRIVERS.md)。
