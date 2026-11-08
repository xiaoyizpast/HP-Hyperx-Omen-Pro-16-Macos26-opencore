# 发布前风险清单

> 以下是技术与合规层面的风险提示，不构成法律意见。发布前请自行判断。

## 1. 许可证（最高优先级）

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

## 2. 苹果的许可与法务

- 在非苹果硬件上安装 macOS 违反 Apple 的软件许可协议（EULA）。
- 苹果历史上对**分发 macOS 安装镜像**的仓库发过 DMCA；对 EFI 配置一般容忍，
  但没有保证。仓库名建议避免直接使用 "macOS Installer" 之类的表述。
- 不要上传任何苹果原版文件：`boot.efi`、`AppleHDA`、`BaseSystem.dmg`、`AppleALC` 里的苹果载荷等。
- 不要使用苹果 Logo / "Apple" 商标做仓库图标。

## 3. 隐私（已在本次打包中处理）

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

## 4. 安全降级（必须在 README 显著位置说明）

本配置包含：

| 设置 | 影响 |
|---|---|
| `csr-active-config = 0x0A43` | 关闭部分 SIP（kext 签名、文件系统保护） |
| `amfi=0x80` + `amfi_get_out_of_my_way=0x1` | 绕过 AMFI，允许未签名内核扩展 |
| `SecureBootModel = Disabled` | 关闭安全启动模型 |

这些是 NullMoth NVIDIA 驱动工作的**必要条件**，但会显著降低系统安全性。
使用者需要明确知道：装了这套 EFI，系统不再是安全启动状态。

## 5. 硬件/数据风险

- `SSDT-AC.aml` 依赖 HP HyperX OMEN PRO 16 (8F06) 的 EC 布局（`0x40` bit0）。**不同批次/BIOS 版本可能不同**，
  用错会出现电池/交流电状态异常。
- 部分 HP 固件只从 `\EFI\Microsoft\Boot\bootmgfw.efi` 启动。若照搬「替换 bootmgfw」的做法，
  **操作失误会导致既进不了 macOS 也进不了 Windows**。务必先备份原文件。
- 双系统用户要注意：Windows 大版本更新可能覆盖 `bootmgfw.efi`。

## 6. 声誉与支持成本

- 明确写「仅 HP HyperX OMEN PRO 16 (8F06) / Ryzen 9 9955HX + RTX 5060 验证过」，避免别人套用到其他机型后怪你。
- 加免责声明：按此配置操作造成的任何损失由使用者自负。
- 建议开 Issues 模板，要求附 `ioreg`、`kmutil showloaded`、启动日志。

## 7. 发布前检查清单

- [ ] `boards/8F06/EFI/OC/Kexts/` 为空
- [ ] 没有 `config.plist.bak-*` / `config.plist.SAFE-*`
- [ ] 没有 `opencore-*.txt` / `SysReport/`
- [ ] SMBIOS 是占位值
- [ ] README 写明安全降级与已知限制
- [ ] 每个第三方项目都有链接与许可证说明（见 `DRIVERS.md`）
- [ ] 自己的脚本/文档加一个 LICENSE（建议 MIT）
- [ ] 不含苹果原版文件与 NVIDIA 驱动
