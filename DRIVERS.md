# 驱动清单与来源

> 版本为本机实测通过的版本。所有项目版权归原作者，链接为官方仓库。

## 一、引导

| 组件 | 版本 | 来源 | 许可证 |
|---|---|---|---|
| OpenCore | 1.0.9 (DEBUG) | https://github.com/acidanthera/OpenCorePkg | BSD-3-Clause |
| OpenCanopy 资源 | 随 OpenCore | 同上（Acidanthera） | 见仓库 |
| HfsPlus.efi | 随 OpenCore | 同上 | BSD-3-Clause |
| OpenRuntime.efi | 随 OpenCore | 同上 | BSD-3-Clause |

## 二、核心 kext

| kext | 版本 | 作用 | 来源 | 许可证 |
|---|---|---|---|---|
| Lilu | 1.7.3 | 内核补丁框架（多数插件的依赖） | https://github.com/acidanthera/Lilu | BSD-3-Clause |
| VirtualSMC | 1.3.9 | SMC 模拟 | https://github.com/acidanthera/VirtualSMC | BSD-3-Clause |
| SMCBatteryManager | 1.3.9 | 电池电量/健康度 | 同上 | BSD-3-Clause |
| SMCLightSensor | 1.3.9 | 环境光传感器接口 | 同上 | BSD-3-Clause |
| WhateverGreen | 1.7.2 | 显卡修补（配合 NVIDIA 驱动） | https://github.com/acidanthera/WhateverGreen | BSD-3-Clause |
| BrightnessKeys | 1.0.4 | F1/F2 亮度键 | https://github.com/acidanthera/BrightnessKeys | BSD-3-Clause |
| NVMeFix | 1.1.4 | NVMe 电源管理修补 | https://github.com/acidanthera/NVMeFix | 见仓库 |
| RestrictEvents | 1.1.7 | 屏蔽不必要的系统事件 | https://github.com/acidanthera/RestrictEvents | BSD-3-Clause |
| AMFIPass | 1.4.1 | AMFI 放行（配合 `amfi=0x80`） | https://github.com/dhinakg/AMFIPass | 见仓库 |
| AppleMCEReporterDisabler | 1.2 | 关闭 MCE 报告（AMD 平台常用） | https://github.com/acidanthera/AppleMCEReporterDisabler | 见仓库 |
| ECEnabler | 1.0.6 | 读取超过 8 位的 EC 字段 | https://github.com/1Revenger1/ECEnabler | 见仓库 |

## 三、输入设备

| kext | 版本 | 作用 | 来源 | 许可证 |
|---|---|---|---|---|
| VoodooI2C | 2.9.1 | I2C 触控板/触摸屏总线 | https://github.com/VoodooI2C/VoodooI2C | **GPL-3.0** |
| VoodooI2CHID | 2.9.1 | I2C HID 设备（精密触控板） | 同上 | **GPL-3.0** |
| VoodooPS2Controller | 2.3.8 | PS/2 键盘与触控板 | https://github.com/acidanthera/VoodooPS2 | 见仓库 |

## 四、网络

| kext | 版本 | 作用 | 来源 | 许可证 |
|---|---|---|---|---|
| MtkWlan | 0.12.1 | MediaTek MT7925 Wi-Fi（PCIe） | https://github.com/watchthelight-labs/WTLMtkWireless | ISC |
| MtkBt | 0.2.4 | MT7925 蓝牙固件加载（USB） | https://github.com/watchthelight-labs/WTLMtkBluetooth | 见仓库 |
| BlueToolFixup | 2.7.3 | 让 bluetoothd 接受第三方蓝牙控制器 | https://github.com/acidanthera/BrcmPatchRAM | **GPL-2.0** |
| RealtekRTL8111 | 2.4.2 | 有线网卡 | https://github.com/Mieze/RTL8111_driver_for_OS_X | 见仓库 |
| HoRNDIS | 9.2 | USB 网络共享（手机热点） | https://github.com/jwise/HoRNDIS | 见仓库 |
| USBToolBox + UTBDefault | 1.2.0 | USB 端口映射框架（当前为占位，未做映射） | https://github.com/USBToolBox/kext | 见仓库 |

## 五、显卡（**不包含在本 EFI 中**）

| 组件 | 版本 | 说明 |
|---|---|---|
| NullMoth NVIDIA 驱动 | 2.8.1 | 安装在 `/Library/Extensions`，不在 EFI 里 |
| 来源 | https://github.com/nullmoth/nvidia-macos-driver | 安装器：https://github.com/nullmoth/1401 |

安装后获得：Metal 4、NVENC/NVDEC（HEVC 硬解可用，H.264 不支持）。
**该驱动包含 NVIDIA 固件与第三方代码，请从官方渠道获取，不要随 EFI 转发。**

## 六、ACPI（SSDT）

| 文件 | 作用 | 说明 |
|---|---|---|
| SSDT-EC.aml | 补全 EC 设备 | 通用 |
| SSDT-PLUG-ALT.aml | AMD CPU 电源管理 | AMD 平台 |
| SSDT-RTCAWAC.aml | AWAC 实时时钟修补 | 本机型 |
| SSDT-USB-Reset.aml | USB 端口复位 | 本机型 |
| SSDT-USBX.aml | USB 供电参数 | 通用 |
| SSDT-XOSI.aml | OSI 重命名配合 | 通用 |
| **SSDT-AC.aml** | **修正交流电状态** | **仅 HP HyperX OMEN PRO 16 (8F06)**：读 EC `0x40` bit0 |

配套 `ACPI → Patch`：

- `_STA → XSTA`（AWAC）
- `_OSI → XOSI`
- `_PSR → XPSR`（配合 SSDT-AC）
- `_Q20 → XQ20`（配合 SSDT-AC 的插拔通知）

## 七、boot-args 说明

```
debug=0x100 keepsyms=1 -amfipassbeta -vi2c-force-polling revpatch=sbvmm
nvfb=1 nvaccel=1 nvfbheads=4 -nvkmsnosmooth gfxrst=4 nvrmacpibl=1
amfi_get_out_of_my_way=0x1 amfi=0x80 ipc_control_port_options=0
```

| 参数 | 作用 |
|---|---|
| `nvfb=1 nvaccel=1 nvfbheads=4` | NullMoth 驱动：framebuffer + 加速器 + 4 个显示头 |
| `-nvkmsnosmooth` | 关闭 NVKMS 平滑同步（该驱动建议） |
| `nvrmacpibl=1` | 让 NVIDIA 驱动接管内屏背光 |
| `gfxrst=4` | 与 WhateverGreen 共存时的复位参数 |
| `amfi=0x80` / `amfi_get_out_of_my_way=0x1` | 放行未签名驱动（安全降级，**必读 RISKS.md**） |
| `-amfipassbeta` | AMFIPass 测试模式 |
| `-vi2c-force-polling` | VoodooI2C 强制轮询 |
| `revpatch=sbvmm` | RestrictEvents：修正机型相关显示 |
| `debug=0x100 keepsyms=1` | 保留崩溃符号（不影响显示） |

## 八、验证命令

```bash
# 驱动是否加载
kmutil showloaded | grep -Ei 'lilu|virtualsmc|whatevergreen|mtk|nvrm|voodoo'

# Wi-Fi
networksetup -listallhardwareports          # 应出现 en2（以以太网形态）
sudo ~/bin/mtkwifi status                   # 需要 mtkwifi 工具

# 蓝牙
system_profiler SPBluetoothDataType | head  # State: On / THIRD_PARTY_DONGLE

# 声卡
system_profiler SPAudioDataType | grep -A4 ALC245

# 电池/交流电
pmset -g batt                               # 插电应显示 AC Power

# 显卡
system_profiler SPDisplaysDataType | grep -E 'Chipset|Metal'
```

## 九、试过但没成功的方案

| 方案 | 结果 |
|---|---|
| 内置麦克风（AppleALC + SimpleHDA，layout 11） | 录音仍是恒定底噪，无声 |
| SMBIOS 换 `MacBookPro16,4` / `MacPro6,1` 修蓝牙 UART 映射 | 前者仍 UART，后者触发禁止符号 |
| 强制 `BT_HCI_TRANSPORT` 环境变量 / NVRAM | 驱动不读，无效 |
| 显示器镜像（内屏 60Hz + 外屏 300Hz） | 导致 Dock 严重掉帧 |
