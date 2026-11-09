# Zfan — Fan Control for HP HyperX OMEN PRO 16 (8F06)

**Fan control is supported.** Zfan is the companion macOS app for this repository. It drives both fans directly through the embedded controller (PMIO).

| Item | Value |
|---|---|
| Model | HP HyperX OMEN PRO 16 (board `103c:8f06`) |
| OS | macOS 12+ (verified on macOS 26.0) |
| Control | EC manual mode `0x62=0x0E`, target `0x34/0x35` (100 RPM units) |
| Telemetry | EC `0xB0–0xB3` / `0x57` / `0xB7` |
| CPU power / frequency | RAPL / APERF-MPERF (read-only) |
| Author | xiaoyizpast · MIT |

## Features

- Fan presets: Quiet 45% / Balanced 65% / Beast 100% / Auto
- Manual temperature curve (4 draggable points, applied every 2 s, 100% above 95 °C)
- EPP presets: Performance / Lean Performance / Balanced / Lean Power Save / Power Save
- Disable CPB (locks to base clock, battery mode)
- Battery auto power save (EPP 255 + CPB off)
- Menu bar item with selectable metrics (CPU/GPU temperature, fan RPM, CPU frequency, memory)
- Finder-style sidebar, overview cards and line charts, settings auto-save
- Debug mode and diagnostic bundle export

## One-command environment setup

```bash
sudo bash zfan/setup.sh
```

The script will:

1. Check model and macOS environment
2. Install `ECFanPMIO.kext` into EFI and enable it under `Kernel → Add`
3. Install `Zfan.app` into `/Applications`
4. Install `fan` and `amd-epp` into `/usr/local/bin`
5. Install the login LaunchAgent
6. Verify `sysctl kern.ecfan` and ask for a reboot

Every step asks for confirmation; failures print rollback hints.

## Manual install

1. Copy `zfan/kext/ECFanPMIO.kext` into `EFI/OC/Kexts/`
2. Add and enable it in `config.plist` under `Kernel → Add` (`BundlePath=ECFanPMIO.kext`)
3. Install `Zfan-2.3.0.pkg` (or drag `Zfan.app` into `/Applications`)
4. Reboot and confirm `sysctl kern.ecfan` returns data

## CLI

```bash
fan status / 70 / max / auto
amd-epp status
amd-epp value 255
amd-epp cpb off
```

## Safety

- The kext never touches the EC at boot; it only acts when `sysctl` or the app requests it
- All EC transactions have IBF/OBF timeouts
- If the EC state becomes inconsistent, run `fan auto` or power-cycle the machine
- Do not pin 100% permanently
- CPU power limits and precise frequency caps are **not adjustable**; see [PITFALLS-2.md](../PITFALLS-2.md)

## Data sources

| Metric | Source | Status |
|---|---|---|
| CPU / GPU temperature | EC `0x57` / `0xB7` | ✅ |
| Fan RPM | EC `0xB0–0xB3` | ✅ |
| CPU frequency | APERF/MPERF | ✅ (reboot required) |
| CPU power | RAPL | ✅ (reboot required) |
| GPU power / clocks | Not exposed by the driver | ❌ |

## License

MIT · xiaoyizpast
