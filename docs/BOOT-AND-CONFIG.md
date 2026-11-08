# 为什么 OpenCore 要这样配 · 以及 HP 的引导为什么这么怪

本文解释配置里每一处"看起来多余"的设置，以及这台 HP 固件的引导行为。

---

# 一、OpenCore 配置逐项说明

## 1. 平台是 AMD，所以内核要打补丁

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

## 2. 显卡是「非官方驱动」，所以 boot-args 很长

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

## 3. Booter Quirks：我们**没有**听验证器的建议

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

## 4. 无线网卡是 MT7925，所以有两个"非标准"动作

**Wi-Fi**：`MtkWlan.kext` 在 macOS 26.0 上只提供**以太网前端**（原生 Wi-Fi 菜单要求 26.7.1/26.7.2），
所以系统里会多一个 `en2`，需要用 `mtkwifi` 工具或附带的菜单栏 App 连接。

**蓝牙**：除了 `MtkBt.kext` + `BlueToolFixup.kext`，还必须在 NVRAM 里放**两个键**，
否则 `bluetoothd` 会退回 UART 占位控制器：

```
bluetoothExternalDongleFailed    = <00>                            1 字节
bluetoothInternalControllerInfo  = <0000000000000000000000000000>  必须正好 14 字节
```

这是 BlueToolFixup 2.7.0 起的要求，**16 字节会触发 `CFDataGetLength != 14` 而失败**。
这两个键就写在 `NVRAM → Add` 与 `NVRAM → Delete` 里。

## 5. 触控板是 I2C，所以驱动顺序不能乱

`VoodooI2C` 的加载顺序必须是：

```
VoodooI2CServices → VoodooGPIO → VoodooI2C → VoodooInput → VoodooI2CHID
```

以及 `-vi2c-force-polling`：这台机器的 GPIO 中断在 macOS 下不稳定，强制轮询才不丢手势。
`ECEnabler` 则是为了让 macOS 能读取超过 8 位的 EC 字段（电池容量等）。

## 6. 音频走的是 NullMoth 自带的 NMXAudio

macOS 26 移除了 `AppleHDA.kext`，所以 ALC245 没有原生驱动。
本机的播放通路由 NullMoth 包的 `NMXAudio` 提供（`/Library/Extensions`，不在 EFI 里）。
这也是为什么 EFI 里**没有** AppleALC —— 装了也不会接管，反而可能冲突。

## 7. 交流电显示靠自写 SSDT

HP 的 DSDT 里 `_PSR` 读的是 `H2RA` 窗口（`0xFE700000 + 0x340`）的 `R400`，
而 macOS 读这个窗口拿不到真实值（实测恒为 0）。

`SSDT-AC.aml` 改为读**标准 EC RAM 的 `0x40` bit0**（插电=1、拔电=0，与 `R400` 镜像），
并接管 `_Q20` 在插拔时发 `Notify(ACAD, 0x80)`。配套两条重命名：
`_PSR → XPSR`、`_Q20 → XQ20`。

> 这是**本机型专用**的，换机型必须删掉，否则电池/电源状态会错乱。

## 8. SMBIOS 选 MacBookPro16,2 的原因

- macOS 26 只支持 2018 年以后的 Mac；`MacBookPro16,2` 是受支持且最接近的机型
- `ProcessorType = 3841`（Xeon W）让「关于本机」显示正常，不然会显示未知 CPU
- 试过 `MacBookPro16,4`（蓝牙仍走 UART）、`MacPro6,1`（2013 机型，macOS 26 不支持，直接**禁止符号**）

---

# 二、HP 这台机器的引导为什么这么"猎奇"

## 现象

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

## 原因

UEFI 的启动项存在 NVRAM 的 `Boot####` 变量里，由 `BootOrder` 排序。规范允许固件
**只使用自己认识的条目**，HP 的固件就是这么做的：

1. 它把「Windows Boot Manager」固定写成 `Boot0000`，路径是 `bootmgfw.efi`
2. 它有自己的 "OS Boot Manager" 逻辑，会忽略/覆盖第三方写入的条目
3. 它不会主动去扫 `\EFI\BOOT\`（所以 UEFI 规范的 fallback 路径在这里不生效）

结果就是：**固件的启动路径被焊死在 `bootmgfw.efi` 这个文件名上**，
谁占了这个文件，谁就被启动。

## 于是有了这个方案

```
固件 → \EFI\Microsoft\Boot\bootmgfw.efi（内容 = OpenCore 启动器）
     → OpenCore 菜单
     → 选 Windows 时，用 BlessOverride 转到 bootmgfw-orig.efi（原版 Windows 引导器）
```

- 原版 Windows 引导器改名保留为 `bootmgfw-orig.efi`
- `Misc → BlessOverride` 加一条 `\EFI\Microsoft\Boot\bootmgfw-orig.efi`

## 为什么 LauncherOption / BootProtect 没用

- `BootProtect` 在 OpenCore 1.0.9 里**已被移除**，配置里写它会报
  `OCS: No schema for BootProtect`，不会生效
- `LauncherOption = Full` 只是把现有启动项指向当前启动文件（仍然是 `bootmgfw.efi`）
- `LauncherOption = Short` 想指向 `BOOTX64.EFI`，但固件不扫这条路径时依然无效

## 副作用与注意事项

1. **Windows 大版本更新**可能把 `bootmgfw.efi` 换回原版 → 又变成直接进 Windows，
   需要重新把 OC 启动器放回去
2. 改这个文件前**务必备份**，否则可能两个系统都进不去
3. 如果你不介意用 F9 启动菜单手动选，其实可以不折腾这个方案，
   保持 `\EFI\BOOT\BOOTX64.EFI` 为 OC、`bootmgfw.efi` 为原版即可
