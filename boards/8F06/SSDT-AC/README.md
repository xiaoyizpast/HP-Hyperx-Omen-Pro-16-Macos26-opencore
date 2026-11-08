# SSDT-AC — 修正 HP HyperX OMEN PRO 16（主板 8F06）的交流电状态

## 用途

这台机器的 DSDT 里，电源状态方法 `_PSR` 读的是 `H2RA` 内存窗口
（`0xFE700000 + 0x340`）里的 `R400` 位。macOS 读这个窗口拿不到真实值（实测恒为 0），
于是**插着充电器也一直显示 `Battery Power`**，电量百分比正常但"是否接电"永远错。

本 SSDT 改为读取**标准 EC RAM 的 `0x40` 字节 bit0**：

| 状态 | EC `0x40` 的值 | bit0 |
|---|---|---|
| 插电 | `0x0B` | 1 |
| 拔电 | `0x02` | 0 |

并在电源插拔时通知 `ACAD`，让状态实时更新。

## 适用机型

**仅 HP 8F06 主板**（HP HyperX OMEN PRO 16 / OMEN 16，子系统 ID `103c:8f06`）。

EC 偏移和字段布局因机型/BIOS 批次而异，**其他机型不要直接使用**。

## 安装

把 `SSDT-AC.aml` 放进 `EFI/OC/ACPI/`，然后在 `config.plist` 里加三处：

### 1. ACPI → Add

```xml
<dict>
  <key>Comment</key><string>HP 8F06 AC status from EC RAM 0x40 bit0</string>
  <key>Enabled</key><true/>
  <key>Path</key><string>SSDT-AC.aml</string>
</dict>
```

### 2. ACPI → Patch（两条）

| Comment | Find | Replace | TableSignature |
|---|---|---|---|
| `_PSR to XPSR rename` | `5F 50 53 52`（`_PSR`） | `58 50 53 52`（`XPSR`） | `DSDT` |
| `_Q20 to XQ20 rename` | `5F 51 32 30`（`_Q20`） | `58 51 32 30`（`XQ20`） | `DSDT` |

其它字段保持默认（`Count=1`、`Limit=0`、`Mask`/`ReplaceMask` 为空）。

> 必须先重命名再用本 SSDT，否则会与 DSDT 里的原方法重名冲突。

### 3. 重启

## 验证

```bash
pmset -g batt
# 插电: Now drawing from 'AC Power'
# 拔电: Now drawing from 'Battery Power'

system_profiler SPPowerDataType | grep -A3 "AC Charger"
# Connected: Yes / No
```

插拔后应在 1–2 秒内变化（由 `_Q20` 的通知触发）。

## 原理

```
原 DSDT:  _PSR -> If (ECON) { R400 } else { ACSB }     // R400 恒 0
本 SSDT:  _PSR -> (EC 0x40 bit0)                       // 插电=1
          _Q20 -> 调用原 XQ20，再比较 bit0 变化，Notify(ACAD, 0x80)
```

SSDT 里定义了一个独立的 `EmbeddedControl` 区域读取 `0x40`，
不改动 DSDT 原有字段，只接管 `_PSR` 与 `_Q20` 两个方法。

## 编译（可自行修改）

```bash
iasl -p SSDT-AC.aml SSDT-AC.dsl
```

需要 ACPI 编译器 `iasl`（ACPICA）。

## 风险与回滚

- EC 偏移写错会导致电池/交流电状态异常，但**不会损坏硬件**
- 回滚：`ACPI → Add` 里把 `SSDT-AC.aml` 设为 `false`，两条 Patch 也设为 `false`，重启即可
- 改之前建议备份整个 EFI

## 许可

MIT。可自由修改与再分发，请保留出处。
