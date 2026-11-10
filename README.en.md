# HP HyperX OMEN PRO 16 (board 8F06) · Ryzen 9 9955HX + RTX 5060 Laptop · macOS 26 Tahoe

An OpenCore configuration, field notes and driver list for running **macOS 26** on the
**HP HyperX OMEN PRO 16 (8F06)** (subsystem `103c:8f06`). **Not a universal EFI** — do not
use it on other models.

- OS: macOS 26.0 Tahoe (25A354), verified
- Bootloader: OpenCore 1.0.9
- GPU: NullMoth third-party driver 2.8.1 (**not included** in this repository)

[简体中文](README.md) · English

---

> ⚠️ **Read first: [DISCLAIMER.md](DISCLAIMER.md)** — sources, NVIDIA driver hardware risk, liability.

> 📌 **Post-v1 pitfalls and how to obtain files: [PITFALLS-2.md](PITFALLS-2.md)**

> ⛔ **CPU power limits and frequency caps are not adjustable on macOS** — see [PITFALLS-2.md](PITFALLS-2.md)

> 💬 **QQ group: 1109117425**

## Zfan: fan control (supported)

This repository ships **Zfan**, a macOS fan control app that drives both fans through the EC:

- Presets: Quiet 45% / Balanced 65% / Beast 100% / Auto
- Manual temperature curve, five EPP presets, CPB toggle, battery auto power save
- Menu bar metrics, overview charts, settings auto-save

One-command setup:

```bash
sudo bash zfan/setup.sh
```

See [zfan/README.en.md](zfan/README.en.md).

---

## Status

| Feature | Status | Notes |
|---|---|---|
| Boot | ✅ | Reaches the desktop |
| Metal | ✅ | NullMoth 2.8.1, Metal 4 |
| Internal display 2560×1600@240 | ✅ | |
| External display 1080p@300 | ✅ | Extended mode |
| Wi-Fi MT7925 | ✅ | Ethernet front end (`en1` on this unit); native panel requires 26.7.x |
| Bluetooth MT7925 | ✅ | `State: On`, pairable |
| Audio | ✅ | Speakers and headphones |
| Brightness | ✅ | Hardware backlight (`nvrmacpibl=1`) |
| Battery | ✅ | Percentage / health |
| AC state | ✅ | Custom SSDT-AC |
| Trackpad | ✅ | Multi-touch gestures |
| Fan control | ✅ | Zfan (`zfan/`) |
| CPU power / frequency cap | ❌ | Not adjustable on macOS |

## macOS 26.7.2 upgrade notes (2026-11-10)

| Item | Result |
|---|---|
| OS | macOS 26.7.2 (25G332), Darwin 25.6.0 |
| GPU | NullMoth 2.8.1, Metal 4 |
| Native Wi-Fi | MtkWlanNative 0.4.15 + `mtkfe=native mtknativeif=1`, `en1` is the Wi-Fi port |
| Firmware updates | `MaxBIOSVersion=true`, System Firmware 9999.999.999.999.999 |
| CPU frequency / power | `kern.cpufreq` / `kern.cpupower` (about 5.0 GHz / 55 W) |
| Audio | ALC245 output and input working |

Still incomplete after the upgrade:

| Item | Status | Notes |
|---|---|---|
| H.264 hardware decode | Missing | NullMoth supports HEVC only (`H264: false / HEVC: true`) |
| GPU power / clocks | Missing | Not exposed by the driver |
| Keyboard backlight / RGB | Missing | No driver, EC registers not reversed |
| Fingerprint / Thunderbolt | Missing | No matching hardware detected |
| Wi-Fi 6 GHz | Partial | Driver covers 2.4/5 GHz only |
| HoRNDIS at boot | Partial | Manual `kmutil load` works; boot injection is rejected |
| Internal microphone | Partial | Present but noisy |

## Getting the EFI

Two scripts, one per platform:

| Platform | Script | What it does |
|---|---|---|
| Windows | `tools/windows/get-efi.ps1` | Hardware check (8F06 / 9955HX), minimal EFI (boot + USB tethering), ESP backup/write, UEFI boot entry. **PowerShell 7 required.** |
| macOS | `tools/macos/get-efi.sh` | Download latest release, back up and write EFI, install all drivers, apply verified boot-args and Bluetooth NVRAM keys |

Both scripts ask for confirmation at every destructive step and open a prefilled GitHub issue on failure.
See [tools/README.md](tools/README.md).

> Windows PowerShell 5.1 is not supported: the script detects it and opens Microsoft's PowerShell 7 installation page.

## Risks

- Editing the EFI can make the machine unbootable. Keep a rescue USB and know how to roll back `config.plist`.
- No guarantee against hardware damage.
- The Windows script only guarantees "boots + USB tethering"; everything else is completed by the macOS script.

## Help wanted: CPU frequency limits

Zfan only reads telemetry and adjusts EPP. A real frequency cap needs SMU mailbox or HP WMI
knowledge. Contributions welcome — see the mention list in the Chinese README
([README.md](README.md)) and [PITFALLS-2.md](PITFALLS-2.md).

## Repository layout

```
boards/8F06/        EFI, ACPI sources, SSDT-AC
tools/              EFI acquisition scripts (Windows / macOS), kext manifest
zfan/               fan control app, kext, CLI, setup script
PITFALLS-2.md       post-v1 pitfalls and file sources
CHANGELOG.md        release notes
DRIVERS.md          driver list (version / source / license)
STATUS.md           verification log
DISCLAIMER.md       sources, hardware risk, liability
```

## License

MIT for this repository's own files. Third-party drivers keep their original licenses — see
[LICENSES.md](LICENSES.md).
