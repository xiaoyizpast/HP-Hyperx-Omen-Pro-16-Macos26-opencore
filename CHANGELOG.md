# 更新日志

## v1.2.5（2026-11-10）

### 新增

- 26.7.2（25G332）升级验证：NullMoth 2.8.1、Metal 4、ALC245、MtkWlanNative 0.4.15
- 原生 Wi-Fi：MtkWlanNative + `mtkfe=native mtknativeif=1`
- 屏蔽固件更新：`MaxBIOSVersion=true`
- CPU 频率/功耗：修复内核 `%f` 问题，`kern.cpufreq` / `kern.cpupower` 正常
- `PITFALLS-2.md` 新增第 16–19 节

### 修复

- `ECFanPMIO.kext` sysctl 浮点格式化
- 26.0 的 WiFi Menu 归档为备选方案

## v1.2.3（2026-11-10）

### 新增

- **Zfan 风扇控制（已支持）**：`zfan/`
  - `zfan/README.md`：功能、安装、数据来源、安全说明
  - `zfan/setup.sh`：一键补全运行环境（写 kext、装 App/CLI、自启、校验）
  - `zfan/kext/`：`ECFanPMIO.kext` 及源码
  - `zfan/bin/`：`fan`、`amd-epp`
  - `zfan/src/main.swift`：App 源码
- 根 `README.md` 顶部加入 **Zfan：风扇控制（已支持）** 段落

### 更新

- `PITFALLS-2.md`：说明风扇控制由 Zfan 提供
- Release 附件同时包含 EFI 包与 Zfan 安装包

## v1.2.1（2026-11-10）

- `tools/windows/get-efi.ps1` 改为 **PowerShell 7**（`#requires -version 7.0`）
  - 提权重启时复用当前宿主（`pwsh`），不再固定调用 `powershell.exe`
  - 去掉 PowerShell 7 中已废弃的 `-UseBasicParsing`
  - 硬件检查只保留主板 **8F06** 与 CPU **9955HX**，**不再检查显卡**

## v1.2.0（2026-11-10）

### 新增

- `tools/windows/get-efi.ps1`：Windows 侧最小 EFI 构建
  - 硬件检查（8F06 / 9955HX / RTX 5060）
  - 下载最新 release、补最小 kext（Lilu、VirtualSMC、WhateverGreen、NVMeFix、USBToolBox）
  - 挂载 ESP、备份现有 EFI、写入、调整 UEFI 启动项
  - 每一步都有确认框，失败自动打开预填 issue
  - 完成后弹出 README 指引
- `tools/macos/get-efi.sh`：macOS 侧补全
  - 下载最新 release、备份并写入 EFI
  - 按 `tools/kexts.json` 补全全部驱动（含 MtkWlan / MtkBt）
  - 写入已验证的 boot-args 与蓝牙 NVRAM 键
  - 每步确认，失败自动开 issue
  - 明确警告可能无法开机、需具备救援能力
- `tools/kexts.json`：驱动清单（仓库 → kext 名）
- `tools/README.md`：两份脚本的使用顺序与风险

### 更新

- `PITFALLS-2.md`：新增「CPU 功耗与频率限制不可调整」结论
- `README.md`：顶部加入该结论链接与脚本入口

## v1.1.0（2026-11-10）

文档与验证更新，不含风扇控制。

### 新增

- `PITFALLS-2.md`：v1 之后的新踩坑与文件获取方式
  - 内存容量在 AMD 平台显示不一致（`hw.physmem` / `hw.usermem` 不可信）
  - CPU 实时频率无系统接口，只能 APG 或 APERF/MPERF
  - CPU 功耗可用 RAPL 读取
  - GPU 功耗/频率驱动不暴露
  - 功耗墙在 BIOS WMI，macOS 内核求值 ACPI 会死锁
  - 修改 P-State 表无效且会导致死机
  - EPP 可调但不封顶，只有关 CPB 能锁基频
  - Windows 驱动被 HVCI 拦截，改用 PawnIO / HWiNFO / UXTU
- `CHANGELOG.md`（本文件）

### 更新

- `README.md`
  - Wi-Fi 接口说明改为按实际网卡数量命名（本机为 `en1`，非固定 `en2`）
  - 补充 26.0 无原生 Wi-Fi 面板的说明与上游 issue 链接
  - 链接 `PITFALLS-2.md`
- `STATUS.md`
  - Wi-Fi 状态改为「以太网前端 `en1` 联网正常；26.0 无原生 Wi-Fi 面板」

### 验证

- `kmutil showloaded`：`org.watchthelight.MtkWlan 0.12.1`、`org.watchthelight.MtkBt 0.2.4`
- `en1`：`182.151.161.216/22`，默认路由，`ping 1.1.1.1` 平均 76 ms
- 上游记录：[WTLMtkWireless#6](https://github.com/watchthelight-labs/WTLMtkWireless/issues/6)

### 说明

本版本不包含风扇控制相关内容；风扇/功耗调优不在本仓库范围内。
