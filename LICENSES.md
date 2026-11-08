# 许可证说明

本仓库**不包含**任何第三方驱动的二进制文件（`boards/8F06/EFI/OC/Kexts/` 为空），
由使用者通过 `fetch-kexts.sh` 从各项目官方 Release 获取。

## 本仓库自身内容

`config.plist` 的结构、`SSDT-AC` 源码、文档与脚本：

```
MIT License

Copyright (c) 2026 <你的名字>

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## 第三方项目

| 项目 | 许可证 | 链接 |
|---|---|---|
| OpenCorePkg | BSD-3-Clause | https://github.com/acidanthera/OpenCorePkg/blob/master/LICENSE.txt |
| Lilu | BSD-3-Clause | https://github.com/acidanthera/Lilu/blob/master/LICENSE.txt |
| VirtualSMC | BSD-3-Clause | https://github.com/acidanthera/VirtualSMC/blob/master/LICENSE.txt |
| WhateverGreen | BSD-3-Clause | https://github.com/acidanthera/WhateverGreen/blob/master/LICENSE.txt |
| BrightnessKeys | BSD-3-Clause | https://github.com/acidanthera/BrightnessKeys/blob/master/LICENSE.txt |
| RestrictEvents | BSD-3-Clause | https://github.com/acidanthera/RestrictEvents/blob/master/LICENSE.txt |
| NVMeFix | 见仓库 | https://github.com/acidanthera/NVMeFix |
| AppleMCEReporterDisabler | 见仓库 | https://github.com/acidanthera/AppleMCEReporterDisabler |
| AMFIPass | 见仓库 | https://github.com/dhinakg/AMFIPass |
| ECEnabler | 见仓库 | https://github.com/1Revenger1/ECEnabler |
| **VoodooI2C** | **GPL-3.0** | https://github.com/VoodooI2C/VoodooI2C/blob/master/LICENSE |
| VoodooPS2 | 见仓库 | https://github.com/acidanthera/VoodooPS2 |
| **BrcmPatchRAM（BlueToolFixup）** | **GPL-2.0** | https://github.com/acidanthera/BrcmPatchRAM/blob/master/LICENSE |
| RealtekRTL8111 | 见仓库 | https://github.com/Mieze/RTL8111_driver_for_OS_X |
| HoRNDIS | 见仓库 | https://github.com/jwise/HoRNDIS |
| USBToolBox | 见仓库 | https://github.com/USBToolBox/kext |
| MtkWlan | ISC | https://github.com/watchthelight-labs/WTLMtkWireless |
| MtkBt | 见仓库 | https://github.com/watchthelight-labs/WTLMtkBluetooth |
| NullMoth NVIDIA driver | 见仓库 | https://github.com/nullmoth/nvidia-macos-driver |

**GPL 说明**：VoodooI2C（GPL-3.0）与 BrcmPatchRAM（GPL-2.0）若要以二进制形式再分发，
必须同时提供对应源码或书面要约。本仓库选择不分发，因此不承担该义务；
如果你要打包，请自行补充源码。
