# 实测状态记录

测试环境：HP HyperX OMEN PRO 16（8F06）· Ryzen 9 9955HX · RTX 5060 Laptop ·
macOS 26.0 (25A354) · OpenCore 1.0.9 · NullMoth 2.8.1

| 项目 | 状态 | 验证方式 |
|---|---|---|
| 开机 / 引导 | ✅ | 正常进桌面 |
| 显卡 Metal 4 | ✅ | `system_profiler SPDisplaysDataType` 显示 Metal 4 |
| 内屏 2560×1600@240 | ✅ | 正常 |
| 外接屏 1080p@300 | ✅ | 正常（扩展模式） |
| Wi-Fi MT7925 | ✅ | 连接成功，WPA2 四次握手完整，网关 2.5 ms |
| 蓝牙 MT7925 | ✅ | `State: On`、`THIRD_PARTY_DONGLE`、可配对 |
| 音频输出 | ✅ | 内置扬声器有声 |
| 亮度调节 | ✅ | `AppleBacklightDisplay=3`，`NVRMBacklightHandler=1` |
| 电池电量 | ✅ | 百分比/健康度正常 |
| 交流电状态 | ✅ | 由 SSDT-AC 修正（EC `0x40` bit0） |
| 触控板 | ✅ | 多指手势正常 |
| 键盘 | ✅ | 正常 |
| 摄像头 | ✅ | UVC 正常 |
| 有线网卡 | ✅ | RTL8111 正常 |
| USB 网络共享 | ✅ | HoRNDIS 正常 |
| 合盖模式 | ✅ | 外接屏时禁睡，合盖熄内屏（脚本） |
| 内置麦克风 | ❌ | 录音为恒定底噪（-65 dBFS 直线） |
| H.264 硬解 | ❌ | `VTIsHardwareDecodeSupported` 返回 NO（HEVC 为 YES） |
| 风扇/温度 | ❌ | AMD 平台无 SMC 传感器 |
| 外接屏热插拔 | ⚠️ | 拔插后可能黑屏，重启恢复 |
| 关机速度 | ⚠️ | 偶发 shutdown stall 报告 |

## 复现命令

```bash
# 显卡
system_profiler SPDisplaysDataType | grep -E 'Chipset|Metal|Resolution'

# 蓝牙
system_profiler SPBluetoothDataType | head -14

# 声卡
system_profiler SPAudioDataType | grep -A4 ALC245

# 电池
pmset -g batt
```
