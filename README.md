# HP HyperX OMEN PRO 16（主板 8F06）· Ryzen 9 9955HX + RTX 5060 Laptop · macOS 26 Tahoe

一份在 **HP HyperX OMEN PRO 16 (8F06)**（子系统 ID `103c:8f06`）上跑通 macOS 26 的 OpenCore 配置、
踩坑记录与驱动清单。**不是通用 EFI**，其他机型请勿直接套用。

- 系统：macOS 26.0 Tahoe（25A354）实测通过
- 引导：OpenCore 1.0.9
- 显卡：NullMoth 第三方驱动 2.8.1（**不在本仓库**）

[English](README.en.md) · 简体中文

---

> ⚠️ **使用前必读：[DISCLAIMER.md](DISCLAIMER.md)**

> 📌 **v1 之后的新踩坑与文件获取方式：[PITFALLS-2.md](PITFALLS-2.md)**（不含风扇控制）
>
> ⛔ **CPU 功耗墙与频率上限在 macOS 下不可调整**：[说明](PITFALLS-2.md#0-cpu-功耗与频率限制不可调整)


## Zfan：风扇控制（已支持）

本仓库配套 **Zfan** —— macOS 下的风扇手动控制 App，通过 EC 直接控制两个风扇：

- 预设：安静 45% / 平衡 65% / 狂暴 100% / 自动
- 手动温度曲线、EPP 五档、关闭 CPB、电池自动省电
- 菜单栏常驻、总览折线图、设置自动保存

一键补全运行环境：

```bash
sudo bash zfan/setup.sh
```

详见 [zfan/README.md](zfan/README.md)。

---

> 💬 **QQ 交流群：1109117425**（问题反馈、EFI 交流）

> 🤝 **CPU 频率限制需要开发者协作**：Zfan 只做了读取与 EPP 调节，真正的频率上限需要 SMU mailbox 或 HP WMI 的实现经验。欢迎 @[watchthelight](https://github.com/watchthelight)（MT7925 驱动、MSR 调试经验）、@[MasonDye](https://github.com/MasonDye)（OmenXHub）、@[breadeding](https://github.com/breadeding)（OmenSuperHub）、@[JamesCJ60](https://github.com/JamesCJ60)（UXTU / SMU）、@[FlyGoat](https://github.com/FlyGoat)（RyzenAdj）一起补全。相关结论见 [PITFALLS-2.md](PITFALLS-2.md#0-cpu-功耗与频率限制不可调整)。 —— 内容来源说明、NVIDIA 驱动硬件风险警告与责任限制。

## 一、当前实现情况

| 功能 | 状态 | 说明 |
|---|---|---|
| 引导 / 开机 | ✅ | 正常进桌面 |
| 显卡 Metal | ✅ | NullMoth 2.8.1，Metal **4** |
| 内屏 2560×1600@240 | ✅ | 正常 |
| 外接屏 1080p@300 | ✅ | 扩展模式，可设为主屏 |
| Wi-Fi MT7925 | ✅ | 26.7.2 原生前端（MtkWlanNative 0.4.15）；26.0 用 `mtkwifi` 或 WiFi Menu |
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

## 26.7.2 升级记录（2026-11-10）

| 项 | 结果 |
|---|---|
| 系统 | macOS 26.7.2（25G332），Darwin 25.6.0 |
| 显卡 | NullMoth 2.8.1，Metal 4 |
| 原生 Wi-Fi | MtkWlanNative 0.4.15 + `mtkfe=native mtknativeif=1`，`en1` 为 Wi-Fi 端口 |
| 固件更新 | `MaxBIOSVersion=true`，System Firmware 9999.999.999.999.999 |
| CPU 频率/功耗 | `kern.cpufreq` / `kern.cpupower` 正常（约 5.0 GHz / 55 W） |
| 音频 | ALC245 输出/输入正常 |

升级后**仍需补全**的项目：

| 项目 | 状态 | 说明 |
|---|---|---|
| H.264 硬解 | ❌ | NullMoth 仅支持 HEVC（`H264: false / HEVC: true`） |
| GPU 功耗/频率 | ❌ | 驱动不暴露，只有利用率/显存 |
| 键盘背光/RGB | ❌ | 无驱动，EC 寄存器未逆向 |
| 指纹 / Thunderbolt | ❌ | 本机未检测到对应硬件 |
| Wi-Fi 6GHz | ⚠️ | 驱动仅 2.4/5GHz |
| HoRNDIS 开机加载 | ⚠️ | 手动 `kmutil load` 可用，开机注入后被内核拒绝 |
| 内建麦克风 | ⚠️ | 设备存在，录音底噪偏大 |

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

> 具体每一项为什么这么配见**第四节**；HP 引导的特殊性见**第五节**；发布与使用风险见**第六节**。

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

---

本节解释配置里每一处「看起来多余」的设置。


## 四、OpenCore 配置逐项说明

### 1. 平台是 AMD，所以内核要打补丁

macOS 内核默认假设运行在 Intel 上，AMD 平台必须打补丁。`Kernel → Patch` 里的条目全部来自
[AMD Vanilla 指南](https://github.com/AMD-OSX/AMD_Vanilla)：

| 补丁 | 为什么需要 |
|---|---|
| `cpuid_cores_per_package` 强制常量 | AMD 的 CPUID 布局与 Intel 不同，不修正会算错核心数 |
| `_commpage_populate` 移除 `rdmsr` | AMD 没有 Intel 的 MSR，执行会崩 |
| `_cpuid_set_generic_info` 系列 | 屏蔽 `rdmsr(0x8B)`、放开 leaf 7、伪装 GenuineIntel |
| `_cpuid_set_cpufamily` 强制 Penryn | 让 XNU 选中兼容的 CPU family |
| `_i386_init` 移除 3 处 `rdmsr` | 同上 |
| **移除 non-monotonic time panic** | Zen 平台 TSC 行为导致内核误判时间倒退而 panic |
| **`_mtrr_update_action` fix PAT** | AMD 的 MTRR/PAT 与 Intel 不同，不修会花屏/卡死 |
| **IOPCIFamily `probeBusGated` 关 10-bit tag** | AM5 芯片组 PCIe 枚举问题 |
| **IOPCIFamily `IOPCIIsHotplugPort`** | AM5 PCI 总线枚举修复 |

> 这些补丁**不是可选优化**，删掉任何一条基本都会 panic 或无法启动。

### 2. 显卡是「非官方驱动」，所以 boot-args 很长

NVIDIA RTX 50 系在 macOS 上没有任何官方驱动，靠
[NullMoth](https://github.com/nullmoth/nvidia-macos-driver) 这个第三方 Metal 驱动。

| 设置 | 原因 |
|---|---|
| `nvfb=1 nvaccel=1 nvfbheads=4` | 打开 framebuffer、加速器，并声明 4 个显示头 |
| `-nvkmsnosmooth` | 该驱动建议关闭 NVKMS 平滑同步，否则唤醒/切换模式异常 |
| `nvrmacpibl=1` | 让驱动接管内屏背光；**不加就没有亮度调节** |
| `gfxrst=4` | 与 WhateverGreen 共存时，避免开机画面读到已释放内存导致 panic |
| `amfi=0x80` + `amfi_get_out_of_my_way=0x1` | 驱动未签名，必须绕过 AMFI |
| `csr-active-config 0x0A43` | 允许加载未签名 kext（/Library/Extensions 里的 NVRM 系列） |
| `Kernel → Block: IONDRVFramebuffer` | 否则固件 framebuffer 会抢走 display index 0，NVRMFB 无法接管 |

> 如果没有装 NVIDIA 驱动，这一整组参数和 Block 都应该去掉，并把 SIP 恢复默认。

### 3. Booter Quirks：我们**没有**听验证器的建议

网上验证器会报两条"错误"，让你把 `DevirtualiseMmio` 和 `SetupVirtualMap` 改成 `false`。
**在这台机器上照做会导致无法启动。**

实测现象（把两个都改 false 后）：

```
EB|LOG:EXITBS:START] 2026-11-07T03:00:29
（之后没有任何输出，内核根本没被加载）
```

`boot.efi` 退出启动服务后无法给内核分配内存，卡死在交接阶段。
所以这两个 Quirk 在 HP HyperX OMEN PRO 16 (8F06) + Ryzen 9000 上必须保持：

```xml
<key>DevirtualiseMmio</key><true/>
<key>SetupVirtualMap</key><true/>
```

其余保持默认：`RebuildAppleMemoryMap`、`ProvideCustomSlide`、`SyncRuntimePermissions`、
`AllowRelocationBlock` 均为 true。

### 4. 无线网卡是 MT7925，所以有两个"非标准"动作

**Wi-Fi**：`MtkWlan.kext` 在 macOS 26.0 上只提供**以太网前端**（原生 Wi-Fi 菜单要求 26.7.1/26.7.2），
系统里会多一个以太网接口（本机是 `en1`，取决于已有网卡数量），需要用 `mtkwifi` 工具或附带的菜单栏 App 连接。

- 驱动 0.12.1，固件 `MtkFwVersion = ____000000-20260813113118`
- 本机实测：`en1` 获取到 IP、成为默认路由、`ping 1.1.1.1` 正常
- 原生 Wi-Fi 面板缺失属预期行为，已向作者提交记录：[WTLMtkWireless#6](https://github.com/watchthelight-labs/WTLMtkWireless/issues/6)
- 新增的踩坑与文件获取方式见 [PITFALLS-2.md](PITFALLS-2.md)

**蓝牙**：除了 `MtkBt.kext` + `BlueToolFixup.kext`，还必须在 NVRAM 里放**两个键**，
否则 `bluetoothd` 会退回 UART 占位控制器：

```
bluetoothExternalDongleFailed    = <00>                            1 字节
bluetoothInternalControllerInfo  = <0000000000000000000000000000>  必须正好 14 字节
```

这是 BlueToolFixup 2.7.0 起的要求，**16 字节会触发 `CFDataGetLength != 14` 而失败**。
这两个键就写在 `NVRAM → Add` 与 `NVRAM → Delete` 里。

### 5. 触控板是 I2C，所以驱动顺序不能乱

`VoodooI2C` 的加载顺序必须是：

```
VoodooI2CServices → VoodooGPIO → VoodooI2C → VoodooInput → VoodooI2CHID
```

以及 `-vi2c-force-polling`：这台机器的 GPIO 中断在 macOS 下不稳定，强制轮询才不丢手势。
`ECEnabler` 则是为了让 macOS 能读取超过 8 位的 EC 字段（电池容量等）。

### 6. 音频走的是 NullMoth 自带的 NMXAudio

macOS 26 移除了 `AppleHDA.kext`，所以 ALC245 没有原生驱动。
本机的播放通路由 NullMoth 包的 `NMXAudio` 提供（`/Library/Extensions`，不在 EFI 里）。
这也是为什么 EFI 里**没有** AppleALC —— 装了也不会接管，反而可能冲突。

### 7. 交流电显示靠自写 SSDT

HP 的 DSDT 里 `_PSR` 读的是 `H2RA` 窗口（`0xFE700000 + 0x340`）的 `R400`，
而 macOS 读这个窗口拿不到真实值（实测恒为 0）。

`SSDT-AC.aml` 改为读**标准 EC RAM 的 `0x40` bit0**（插电=1、拔电=0，与 `R400` 镜像），
并接管 `_Q20` 在插拔时发 `Notify(ACAD, 0x80)`。配套两条重命名：
`_PSR → XPSR`、`_Q20 → XQ20`。

> 这是**本机型专用**的，换机型必须删掉，否则电池/电源状态会错乱。
>
> 完整安装说明、编译好的 AML 与源码在 [`boards/8F06/SSDT-AC/`](boards/8F06/SSDT-AC/)。

### 8. SMBIOS 选 MacBookPro16,2 的原因

- macOS 26 只支持 2018 年以后的 Mac；`MacBookPro16,2` 是受支持且最接近的机型
- `ProcessorType = 3841`（Xeon W）让「关于本机」显示正常，不然会显示未知 CPU
- 试过 `MacBookPro16,4`（蓝牙仍走 UART）、`MacPro6,1`（2013 机型，macOS 26 不支持，直接**禁止符号**）

---

---

## 五、HP 8F06 的引导：为什么必须占用 `bootmgfw.efi`

### 现象

- 固件启动项指向 `\EFI\Microsoft\Boot\bootmgfw.efi`
- **不扫描** `\EFI\BOOT\BOOTX64.EFI`
- 用 `bless` 或 OC 新建的启动项，重启后优先级会被重置/忽略
- 把 `bootmgfw.efi` 换成 OpenCore → 能进 OC
- 把 `bootmgfw.efi` 换回 Windows → **直接进 Windows，OC 完全跳过**

日志证据：

```
OCB: No existing option at Boot0000, invalid
OCB: 0 -> Boot0000 = HD(1,GPT,...)/\EFI\Microsoft\Boot\bootmgfw.efi
```

### 原因

UEFI 的启动项存在 NVRAM 的 `Boot####` 变量里，由 `BootOrder` 排序。规范允许固件
**只使用自己认识的条目**，HP 的固件就是这么做的：

1. 它把「Windows Boot Manager」固定写成 `Boot0000`，路径是 `bootmgfw.efi`
2. 它有自己的 "OS Boot Manager" 逻辑，会忽略/覆盖第三方写入的条目
3. 它不会主动去扫 `\EFI\BOOT\`（所以 UEFI 规范的 fallback 路径在这里不生效）

结果就是：**固件的启动路径被焊死在 `bootmgfw.efi` 这个文件名上**，
谁占了这个文件，谁就被启动。

### 于是有了这个方案

```
固件 → \EFI\Microsoft\Boot\bootmgfw.efi（内容 = OpenCore 启动器）
     → OpenCore 菜单
     → 选 Windows 时，用 BlessOverride 转到 bootmgfw-orig.efi（原版 Windows 引导器）
```

- 原版 Windows 引导器改名保留为 `bootmgfw-orig.efi`
- `Misc → BlessOverride` 加一条 `\EFI\Microsoft\Boot\bootmgfw-orig.efi`

### 为什么 LauncherOption / BootProtect 没用

- `BootProtect` 在 OpenCore 1.0.9 里**已被移除**，配置里写它会报
  `OCS: No schema for BootProtect`，不会生效
- `LauncherOption = Full` 只是把现有启动项指向当前启动文件（仍然是 `bootmgfw.efi`）
- `LauncherOption = Short` 想指向 `BOOTX64.EFI`，但固件不扫这条路径时依然无效

### 副作用与注意事项

1. **Windows 大版本更新**可能把 `bootmgfw.efi` 换回原版 → 又变成直接进 Windows，
   需要重新把 OC 启动器放回去
2. 改这个文件前**务必备份**，否则可能两个系统都进不去
3. 如果你不介意用 F9 启动菜单手动选，其实可以不折腾这个方案，
   保持 `\EFI\BOOT\BOOTX64.EFI` 为 OC、`bootmgfw.efi` 为原版即可

---

## 六、发布前风险清单

> 以下是技术与合规层面的风险提示，不构成法律意见。发布前请自行判断。

### 1. 许可证（最高优先级）

| 组件 | 许可证 | 分发二进制的要求 |
|---|---|---|
| VoodooI2C / VoodooI2CHID | **GPL-3.0** | 必须随附完整源码或书面要约 |
| BlueToolFixup（BrcmPatchRAM） | **GPL-2.0** | 同上 |
| Lilu / VirtualSMC / WhateverGreen / BrightnessKeys / RestrictEvents | BSD-3 | 保留版权声明 |
| MtkWlan / MtkBt | ISC | 保留版权声明 |
| AppleALC | BSD-3 | — |
| **SimpleHDA** | 见仓库 | **内含苹果 AppleHDA 载荷，属于苹果版权代码，不要分发** |
| NullMoth NVIDIA 驱动 | 见仓库 | 含 NVIDIA 固件，授权不明，**不要转发** |

**本仓库的做法**：`boards/8F06/EFI/OC/Kexts/` 留空，由 `fetch-kexts.sh` 从官方 Release 下载，
仓库本身不分发任何第三方二进制，从根上规避 GPL 的源码义务。

如果你坚持打包全部 kext（图省事），至少要做到：

- 在仓库里附上 GPL 项目的**完整对应源码**（或有效期三年的书面要约）
- 保留所有版权头与 LICENSE 文件
- 明确标注每个 kext 的版本与来源

### 2. 苹果的许可与法务

- 在非苹果硬件上安装 macOS 违反 Apple 的软件许可协议（EULA）。
- 苹果历史上对**分发 macOS 安装镜像**的仓库发过 DMCA；对 EFI 配置一般容忍，
  但没有保证。仓库名建议避免直接使用 "macOS Installer" 之类的表述。
- 不要上传任何苹果原版文件：`boot.efi`、`AppleHDA`、`BaseSystem.dmg`、`AppleALC` 里的苹果载荷等。
- 不要使用苹果 Logo / "Apple" 商标做仓库图标。

### 3. 隐私（已在本次打包中处理）

已处理：

- `SystemSerialNumber` → `C02XXXXXXXXXX`
- `MLB` → 17 个 0
- `SystemUUID` → 全 0
- `ROM` → `001122334455`
- 删除了所有 `config.plist.bak-*` 备份（里面含真实序列号）
- 未包含 `opencore-*.txt` 启动日志（含 NVRAM/设备信息）
- 未包含 `SysReport/`（含完整 ACPI 与 SMBIOS）

发布前请再自查一遍：

```bash
grep -r "你的真实序列号" .
grep -rE "C02[A-Z0-9]{9}" .
grep -ri "serial" boards/8F06/EFI/OC/config.plist
```

### 4. 安全降级（必须在 README 显著位置说明）

本配置包含：

| 设置 | 影响 |
|---|---|
| `csr-active-config = 0x0A43` | 关闭部分 SIP（kext 签名、文件系统保护） |
| `amfi=0x80` + `amfi_get_out_of_my_way=0x1` | 绕过 AMFI，允许未签名内核扩展 |
| `SecureBootModel = Disabled` | 关闭安全启动模型 |

这些是 NullMoth NVIDIA 驱动工作的**必要条件**，但会显著降低系统安全性。
使用者需要明确知道：装了这套 EFI，系统不再是安全启动状态。

### 5. 硬件/数据风险

- `SSDT-AC.aml` 依赖 HP HyperX OMEN PRO 16 (8F06) 的 EC 布局（`0x40` bit0）。**不同批次/BIOS 版本可能不同**，
  用错会出现电池/交流电状态异常。
- 部分 HP 固件只从 `\EFI\Microsoft\Boot\bootmgfw.efi` 启动。若照搬「替换 bootmgfw」的做法，
  **操作失误会导致既进不了 macOS 也进不了 Windows**。务必先备份原文件。
- 双系统用户要注意：Windows 大版本更新可能覆盖 `bootmgfw.efi`。

### 6. 声誉与支持成本

- 明确写「仅 HP HyperX OMEN PRO 16 (8F06) / Ryzen 9 9955HX + RTX 5060 验证过」，避免别人套用到其他机型后怪你。
- 加免责声明：按此配置操作造成的任何损失由使用者自负。
- 建议开 Issues 模板，要求附 `ioreg`、`kmutil showloaded`、启动日志。

### 7. 发布前检查清单

- [ ] `boards/8F06/EFI/OC/Kexts/` 为空
- [ ] 没有 `config.plist.bak-*` / `config.plist.SAFE-*`
- [ ] 没有 `opencore-*.txt` / `SysReport/`
- [ ] SMBIOS 是占位值
- [ ] README 写明安全降级与已知限制
- [ ] 每个第三方项目都有链接与许可证说明（见 `DRIVERS.md`）
- [ ] 自己的脚本/文档加一个 LICENSE（建议 MIT）
- [ ] 不含苹果原版文件与 NVIDIA 驱动

---

## 七、目录结构

```
boards/8F06/EFI/BOOT/BOOTx64.efi           OpenCore 启动器
boards/8F06/EFI/OC/OpenCore.efi            OpenCore 1.0.9 DEBUG
boards/8F06/EFI/OC/config.plist            已匿名化配置
boards/8F06/EFI/OC/ACPI/                   SSDT（含本机型专用 SSDT-AC）
boards/8F06/EFI/OC/Drivers/                OpenRuntime / HfsPlus / OpenCanopy / ResetNvramEntry
boards/8F06/EFI/OC/Resources/              OpenCanopy 资源
boards/8F06/EFI/OC/Kexts/                  空目录，用脚本下载
fetch-kexts.sh                 一键下载驱动
DRIVERS.md                     驱动清单（版本/来源/许可证）
STATUS.md                      实测状态与复现命令
LICENSES.md / LICENSE          许可证
boards/8F06/ACPI-SOURCES/                  SSDT-AC 源码
boards/8F06/SSDT-AC/                       SSDT-AC 独立包（说明 + AML + DSL + LICENSE）
tools/                         合盖脚本、亮度工具、Wi-Fi 菜单栏 App
```

---

## 八、说明

- 本仓库**不包含**任何第三方驱动二进制（GPL 与苹果版权原因），由脚本从官方 Release 获取。
- 所有驱动版权归原作者，链接见 [DRIVERS.md](DRIVERS.md)。
- 使用本配置造成的任何后果由使用者自负；请先阅读第六节「发布前风险清单」。

## 致谢

OpenCore / Lilu / VirtualSMC / WhateverGreen / AppleALC / VoodooI2C / VoodooPS2 /
BrcmPatchRAM / USBToolBox / NVMeFix / RestrictEvents / BrightnessKeys / ECEnabler /
AMFIPass / AppleMCEReporterDisabler / RTL8111 / HoRNDIS /
WTLMtkWireless / WTLMtkBluetooth / NullMoth NVIDIA driver
以及 [AMD Vanilla](https://github.com/AMD-OSX/AMD_Vanilla) 的内核补丁。
完整链接见 [DRIVERS.md](DRIVERS.md)。
