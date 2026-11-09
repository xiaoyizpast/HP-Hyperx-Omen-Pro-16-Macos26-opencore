# 更新日志

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
