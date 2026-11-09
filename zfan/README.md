# Zfan —— HP HyperX OMEN PRO 16（8F06）风扇控制

[English](README.en.md)

**风扇控制已支持。** Zfan 是本仓库配套的 macOS 风扇/性能控制 App，通过 EC（PMIO）直接控制这把机器的两个风扇。

| 项目 | 说明 |
|---|---|
| 机型 | HP HyperX OMEN PRO 16（主板 `103c:8f06`） |
| 系统 | macOS 12+（本机在 macOS 26.0 验证） |
| 控制方式 | EC 手动模式 `0x62=0x0E`，目标 `0x34/0x35`（单位 100 RPM） |
| 转速/温度 | EC `0xB0–0xB3` / `0x57` / `0xB7` |
| CPU 功耗/频率 | RAPL / APERF-MPERF（只读） |
| 作者 | xiaoyizpast · MIT |

## 功能

- 风扇预设：安静 45% / 平衡 65% / 狂暴 100% / 自动
- 手动温度曲线（4 点拖拽，每 2 秒应用，≥95°C 自动拉满）
- EPP 五档（性能 / 偏性能 / 平衡 / 偏省电 / 省电）
- 关闭 CPB（锁基频，续航模式）
- 电池自动省电（EPP 255 + 关 CPB）
- 菜单栏常驻，可勾选显示 CPU/GPU 温度、风扇、CPU 频率、内存
- 访达风格侧栏、总览卡片 + 折线图、设置自动保存
- 调试模式与诊断包导出

## 一键补全运行环境

```bash
sudo bash zfan/setup.sh
```

脚本会：

1. 检查机型与 macOS 环境
2. 把 `ECFanPMIO.kext` 放进 EFI，并在 `Kernel → Add` 中启用
3. 安装 `Zfan.app` 到 `/Applications`
4. 安装 `fan`、`amd-epp` 到 `/usr/local/bin`
5. 安装登录自启 LaunchAgent
6. 校验 `sysctl kern.ecfan`，提示重启

每一步都有确认；失败会给出回滚提示。

## 手动安装

1. 把 `zfan/kext/ECFanPMIO.kext` 放进 `EFI/OC/Kexts/`
2. 在 `config.plist` 的 `Kernel → Add` 添加并启用（`BundlePath=ECFanPMIO.kext`）
3. 安装 `Zfan-2.3.0.pkg`（或直接把 `Zfan.app` 拖进 `/Applications`）
4. 重启，确认 `sysctl kern.ecfan` 有输出

## 命令行

```bash
fan status / 70 / max / auto
amd-epp status
amd-epp value 255
amd-epp cpb off
```

## 安全与风险

- kext 启动时不访问 EC，只有读取 `sysctl` 或 App 操作时才访问
- 所有 EC 事务带 IBF/OBF 超时
- 极端情况下 EC 状态可能异常：`fan auto` 或**彻底关机**可恢复
- 不建议长期锁定 100%
- CPU 功耗墙与精确频率上限**不可调整**，见 [PITFALLS-2.md](../PITFALLS-2.md#0-cpu-功耗与频率限制不可调整)

## 数据来源与限制

| 指标 | 来源 | 状态 |
|---|---|---|
| CPU / GPU 温度 | EC `0x57` / `0xB7` | ✅ |
| 风扇转速 | EC `0xB0–0xB3` | ✅ |
| CPU 频率 | APERF/MPERF | ✅（需重启加载 kext） |
| CPU 功耗 | RAPL | ✅（需重启） |
| GPU 功耗 / 频率 | 驱动不暴露 | ❌ |

## 许可

MIT，作者 xiaoyizpast。
