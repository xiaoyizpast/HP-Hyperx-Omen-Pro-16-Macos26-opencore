# 新增踩坑记录（v1 之后）

## 0. CPU 功耗与频率限制：不可调整

结论先说：**在 macOS 下无法设置 CPU 功耗墙，也无法精确限制最高频率。**

| 手段 | 结果 |
|---|---|
| BIOS WMI（PL1/PL2/PL4/TPP） | Windows 侧用 `hpqBIntM` 命令 `0x20008` / type `0x29`；macOS 没有 WMI 栈，内核求值 ACPI 会死锁 |
| 写 P-State 表（MSR `0xC0010064`） | 改完 APG 频率不变（SMU 控制），且曾导致死机 |
| EPP（`AMDRyzenCPMUPMUserClient` selector 24/25） | 只影响加速偏好，单核仍会到 5.5 GHz |
| 关闭 CPB（MSR `0xC0010015`） | 能硬性封顶到基频（约 2.3–2.5 GHz），代价是性能大幅下降 |
| SMU mailbox | 未公开 Zen 5 偏移，风险极高 |

因此本项目的定位是：**不提供功耗墙/频率上限功能**，只用风扇与 EPP 做温度管理。

---

本文记录 **v1 发布之后**新遇到的问题与处理方式。风扇控制由配套的 **Zfan** 提供（已支持），见 [zfan/README.md](zfan/README.md)。

---

## 1. 内存容量显示不一致

**现象**

- 某些监控工具显示 16 GB，但机器实际是 32 GB
- `hw.physmem` 只有 2 GB
- `hw.usermem` 是负数

**实测**

```bash
sysctl -n hw.memsize     # 34359738368（32 GB，正确）
system_profiler SPMemoryDataType   # 2 × 16 GB SK Hynix 5600 MHz
```

**结论**

- 以 `hw.memsize` / 「关于本机」为准
- `hw.physmem`、`hw.usermem` 在 AMD + OpenCore 下不可信，属于 XNU 统计适配问题
- 工具若只读单条 SMBIOS Type 17，会误显示 16 GB

---

## 2. CPU 实时频率读不到

**现象**

```bash
sysctl hw.cpufrequency      # 固定 2500000000（2.5 GHz），不随负载变化
```

系统没有暴露实时频率的接口。

**可行方式**

| 方式 | 说明 |
|---|---|
| AMD Power Gadget | 唯一开箱可读，显示每核频率 |
| 自建只读 kext + APERF/MPERF | 读 MSR `0xE7` / `0xE8`，比值 × 标称频率 |

**风险**：并非所有平台都实现这两个 MSR，`rdmsr` 可能触发 #GP，建议只在手动触发时读取，不要开机自动读。

---

## 3. CPU 功耗：用 RAPL

AMD 支持 RAPL 能量计数：

| MSR | 含义 |
|---|---|
| `0xC0010299` | 能量单位（`bits 12:8`） |
| `0xC001029A` | 核心能量 |
| `0xC001029B` | 封装能量 |

两次采样求差：

```
功率(W) = (E1 - E0) / (2^unit) / 采样秒数
```

同样属于只读 MSR，建议手动触发。

---

## 4. GPU 遥测缺失

NullMoth 驱动只暴露：

- `Device Utilization %`
- `GPU Memory Utilization %`
- 显存相关统计（`inUseVidMemoryBytes`、`vramFreeBytes`）

**没有** core clock、memory clock、board power。

GPU 温度可从 EC `0xB7` 读取（这是传感器，不属于风扇控制）。

---

## 5. 功耗墙在 BIOS WMI，不在 EC

参考 Windows 侧开源实现（[OmenSuperHub](https://github.com/breadeding/OmenSuperHub)、[OmenXHub](https://github.com/MasonDye/OmenXHub)）：

```csharp
// PL1 + PL2
SendOmenBiosWmi(0x29, new byte[] { value, value, 0xFF, 0xFF }, 0);
// PL4
SendOmenBiosWmi(0x29, new byte[] { 0xFF, 0xFF, value, 0xFF }, 0);
// TPP
SendOmenBiosWmi(0x29, new byte[] { 0xFF, 0xFF, 0xFF, value }, 0);
```

底层是 `hpqBIntM` WMI 类，命令 `0x20008`，commandType `0x29`。

**macOS 上没有 WMI 栈**。实测在 kext 里求值 ACPI WMI 方法（`\_SB.WMID.WMAA`）会**直接死锁**。

**结论**：不要从内核里调用 ACPI，功耗墙在 macOS 下无法通过官方途径设置。

---

## 6. 改 P-State 表无效且危险

读取 MSR `0xC0010064` 起的表，本机只有两档：

| P-State | FID | DID | 解码 |
|---|---|---|---|
| P0 | 244 | 1 | 6100 MHz（SMU 实际限到 5.5） |
| P1 | 195 | 1 | 4875 MHz |

把 P0 的 FID 改成 188（4.7 GHz）后：

- APG 频率**没有变化**
- 曾出现死机

**原因**：Zen 5 的实际频率由 **SMU 固件**控制，操作系统改 MSR 表它不认；频率/电压不配套时全核写入会直接挂死。

**结论**：不要写 P-State 表。

---

## 7. EPP 可调，但不封顶

`AMDRyzenCPUPowerManagement` 的 UserClient 提供：

| selector | 作用 |
|---|---|
| 23 | 读状态 `[enabled, eppValue]` |
| 24 | 启用/关闭 |
| 25 | 设置 EPP（0–255） |

实测 EPP 只影响加速偏好，单核仍会冲到 5.5 GHz。

真正能封顶的只有 **关闭 CPB**（MSR `0xC0010015`），代价是掉到基频（约 2.3–2.5 GHz）。

---

## 8. Windows 驱动加载失败

RWEverything 的内核驱动未签名，在开启 HVCI / 驱动签名强制的 Windows 11 上会被拦截。

替代方案：

- **PawnIO**（签名驱动，UXTU 自带）
- **HWiNFO**（传感器读取，不需要自装驱动）
- **UXTU**（SMU 侧调功耗/频率，部分机型支持 `max-cpuclk`）

---

## 9. 工具与源码参考

| 项目 | 用途 |
|---|---|
| [OmenSuperHub](https://github.com/breadeding/OmenSuperHub) | Windows 侧 PL/TGP/风扇实现参考 |
| [OmenXHub](https://github.com/MasonDye/OmenXHub) | 同上，C# 实现 |
| [UXTU](https://github.com/JamesCJ60/Universal-x86-Tuning-Utility) | SMU 调参，含 `max-cpuclk` 命令 |
| [RyzenAdj](https://github.com/FlyGoat/RyzenAdj) | Linux 侧 SMU 调参参考 |

---

## 10. 结论汇总

| 需求 | 结论 |
|---|---|
| 读 CPU 频率 | 仅 APG 或自建 APERF/MPERF 只读 |
| 读 CPU 功耗 | RAPL 只读可行 |
| 读 GPU 功耗/频率 | 驱动不暴露，不可行 |
| 设功耗墙 | BIOS WMI，macOS 无解 |
| 精确限频 | SMU 控制，改 MSR 无效且危险 |
| 硬性限频 | 关 CPB，锁基频 |

---

# 文件获取方式

## OpenCore 与常用 kext

```bash
# OpenCore
curl -L -o OpenCore.zip https://github.com/acidanthera/OpenCorePkg/releases/latest/download/OpenCore-1.0.9-RELEASE.zip

# Lilu / WhateverGreen / AppleALC
curl -L -o Lilu.zip https://github.com/acidanthera/Lilu/releases/latest/download/Lilu-1.6.9-RELEASE.zip
curl -L -o WEG.zip  https://github.com/acidanthera/WhateverGreen/releases/latest/download/WhateverGreen-1.6.9-RELEASE.zip
curl -L -o ALC.zip  https://github.com/acidanthera/AppleALC/releases/latest/download/AppleALC-1.9.4-RELEASE.zip

# VirtualSMC（本机使用 1.3.9，SMCSuperIO 取 1.3.8）
curl -L -o VirtualSMC.zip https://github.com/acidanthera/VirtualSMC/releases/download/1.3.8/VirtualSMC-1.3.8-RELEASE.zip
```

> 本仓库根目录的 `fetch-kexts.sh` / `fetch-kexts.py` 已按上述来源整理，可直接运行。

## 不在本仓库的驱动

| 驱动 | 获取方式 |
|---|---|
| NullMoth NVIDIA 驱动 2.8.1 | 从 NullMoth / 1401 官方发布渠道获取，本仓库不提供 |
| SMCAMDProcessor 3.34.0（含 CPPC） | 私有构建，源码未公开；从你的 EFI 来源获取 |
| AMD Power Gadget | 随 SMCAMDProcessor 发布包提供 |

## Windows 侧工具

| 工具 | 地址 |
|---|---|
| HWiNFO | https://www.hwinfo.com/download/ |
| PawnIO | https://pawnio.eu/ |
| OmenSuperHub | https://github.com/breadeding/OmenSuperHub/releases |
| OmenXHub | https://github.com/MasonDye/OmenXHub/releases |
| UXTU | https://github.com/JamesCJ60/Universal-x86-Tuning-Utility/releases |

## 校验

下载后建议核对：

```bash
unzip -l VirtualSMC.zip | head
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' VirtualSMC.kext/Contents/Info.plist
```

kext 版本需与 OpenCore 配置中的 `MinKernel` / `MaxKernel` 匹配，避免加载失败。

## 16. 内核 printf 不支持 `%f`

`kern.cpufreq` / `kern.cpupower` 一直返回 `"f"`，根因不是缓冲区，而是**内核 `snprintf` 不支持浮点格式**：`"%.0f"` 只输出了格式串末尾的 `f`。

修复：全部改成整数格式化。

```c
snprintf(out, sizeof(out), "%u", (unsigned)(mhz + 0.5));
unsigned mw = (unsigned)(watts * 1000.0 + 0.5);
snprintf(out, sizeof(out), "%u.%03u", mw / 1000, mw % 1000);
```

验证输出：`kern.cpufreq: 5038`、`kern.cpupower: 55.021`。

## 17. 屏蔽 macOS 固件更新

`PlatformInfo → Generic → MaxBIOSVersion = true` 会把 `BIOSVersion` 强制设为
`9999.999.999.999.999`，系统不再推送或尝试刷写固件。

验证：

```bash
system_profiler SPHardwareDataType | grep "System Firmware Version"
# 9999.999.999.999.999
```

## 18. 26.7.2 升级与原生 Wi-Fi

- 安装包：Apple 目录 `142-50020`（BUILD 25G332，18.4 GB）
- 系统更新器 `softwareupdate --fetch-full-installer` 会假成功只生成 29 MB 空壳；
  直接从目录下载 `InstallAssistant.pkg` 再 `installer -pkg` 才可靠
- 空间不足时，把安装器 App 放大到独立 APFS 卷（`disk0s9`），不要动 APFS 容器前部空间
- 原生 Wi-Fi 需要 **MtkWlanNative 0.4.15** + `mtkfe=native mtknativeif=1`
- 26.7.2 上 `MtkWlanNative` 加载后 `system_profiler SPAirPortDataType` 显示
  “Third-Party Wireless Card / MtkWlanNative 0.4.15”，`en1` 为 Wi-Fi 端口
- 26.0 没有原生面板，用归档的 `wifi-menu/` 作为备选前端

## 19. 手动安装 Command Line Tools

`softwareupdate --download "Command Line Tools for Xcode-26.6"` 长时间无进度时，
可以直接从 Apple 软件更新目录取包（产品 `140-17812`）：

```bash
BASE="https://swcdn.apple.com/content/downloads/33/19/140-17812-A_21ZLMMLY4E/zu3xwktttpoe71qiawhzgzvqss6rovawsa"
curl -L -O "$BASE/CLTools_Executables_Universal.pkg"
curl -L -O "$BASE/CLTools_macOS_SDK.pkg"
curl -L -O "$BASE/CLTools_macOSNMOS_SDK.pkg"
curl -L -O "$BASE/CLTools_SwiftBackDeploy.pkg"
sudo installer -pkg CLTools_Executables_Universal.pkg -target /
# 其余三个按同样顺序安装
```

装完 `xcode-select -p` 应指向 `/Library/Developer/CommandLineTools`。
