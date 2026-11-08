# HP HyperX OMEN PRO 16 (board 8F06) · Ryzen 9 9955HX + RTX 5060 Laptop · macOS 26 Tahoe

An OpenCore configuration, a list of every pitfall hit during installation, and a driver
status report for **HP HyperX OMEN PRO 16 (8F06)** (subsystem ID `103c:8f06`). **Not a generic EFI** — do not
use it on other models.

- OS: macOS 26.0 Tahoe (25A354), tested
- Bootloader: OpenCore 1.0.9
- GPU: NullMoth third-party driver 2.8.1 (**not included**)

[简体中文](README.md) · English

---

> ⚠️ **Read first: [DISCLAIMER.md](DISCLAIMER.md)** — content sources, hardware risk warning for the NVIDIA driver, and limitation of liability.

## 1. What works

| Feature | Status | Notes |
|---|---|---|
| Boot | ✅ | Reaches the desktop |
| GPU / Metal | ✅ | NullMoth 2.8.1, **Metal 4** |
| Internal panel 2560×1600@240 | ✅ | |
| External 1080p@300 | ✅ | Extended, can be primary |
| Wi-Fi MT7925 | ✅ | Needs `mtkwifi` CLI or the bundled menu-bar app |
| Bluetooth MT7925 | ✅ | `State: On`, `THIRD_PARTY_DONGLE`, pairable |
| Audio output | ✅ | Speakers and headphones |
| Brightness | ✅ | Hardware backlight via `nvrmacpibl=1` |
| Battery level | ✅ | Percentage and health |
| AC adapter state | ✅ | Fixed by a custom SSDT-AC (this model only) |
| Trackpad | ✅ | Multi-touch |
| Keyboard | ✅ | |
| Camera | ✅ | UVC |
| Ethernet | ✅ | RTL8111 |
| USB tethering | ✅ | HoRNDIS |
| Clamshell mode | ✅ | Script: no sleep with an external display, panel off when the lid closes |
| **Internal microphone** | ❌ | Constant noise floor only; AppleALC + SimpleHDA did not help |
| **H.264 hardware decode** | ❌ | HEVC works, H.264 does not (driver limitation) |
| **Fans / temperatures** | ❌ | AMD platform has no SMC sensors |
| **External display hotplug** | ⚠️ | May go black after replug; reboot recovers |
| **Shutdown speed** | ⚠️ | Occasional `shutdown stall` reports |
| **AMD iGPU** | ❌ | Disabled via `disable-gpu` (no macOS driver) |

---

## 2. Installation

1. **Back up your own EFI**, then copy this `boards/8F06/EFI/` to the EFI partition.
2. Run `./fetch-kexts.sh` to download every kext from the official releases into `boards/8F06/EFI/OC/Kexts/`.
3. **Generate your own SMBIOS** (the repo ships placeholders):
   - Use [GenSMBIOS](https://github.com/corpnewt/GenSMBIOS), pick `MacBookPro16,2`
   - Fill Serial / MLB / SystemUUID under `PlatformInfo → Generic`
   - Set `ROM` to your `en0` MAC (6 bytes)
4. **Install the NVIDIA driver** (not included):
   - [NullMoth driver](https://github.com/nullmoth/nvidia-macos-driver) + [1401](https://github.com/nullmoth/1401)
   - Without it you only get a basic framebuffer, no Metal.
5. Reboot.

> Why every setting is the way it is: **[docs/BOOT-AND-CONFIG.md](docs/BOOT-AND-CONFIG.md)**.
> Legal and security risks: **[RISKS.md](RISKS.md)**.

---

## 3. Pitfalls (everything that actually went wrong)

### Boot / kernel

| # | Symptom | Cause | Fix |
|---|---|---|---|
| 1 | Boot stops after `EB\|LOG:EXITBS:START` with no further output | Config validators tell you to set `DevirtualiseMmio` and `SetupVirtualMap` to `false`; on this AM5 board that leaves boot.efi unable to place the kernel | Keep both `true` — ignore the validator |
| 2 | Prohibited sign (🚫) after switching SMBIOS to `MacPro6,1` | macOS 26 dropped pre-2018 Macs | Revert to `MacBookPro16,2` |
| 3 | Assumed the firmware only boots `BOOTX64.EFI` and replaced `bootmgfw.efi` with OpenCore | The firmware actually boots `\EFI\Microsoft\Boot\bootmgfw.efi` and never scans `\EFI\BOOT\` | See the HP boot section below |
| 4 | `BootProtect = Bootstrap` produced no `Bootstrap.efi` | Removed in OpenCore 1.0.9 (`OCS: No schema for BootProtect`) | Use `LauncherOption`, or the `bootmgfw` takeover described below |
| 5 | Changed `boot-args` but nothing changed | `NVRAM → Add` does **not** overwrite existing variables | Also register the key under `NVRAM → Delete` |

### Bluetooth

| # | Symptom | Cause | Fix |
|---|---|---|---|
| 6 | `State: Off`, `Address: NULL`, chipset shows `BCM_4350C2` | `bluetoothd` maps this SMBIOS to UART and looks for `/dev/cu.BLTH` | See #9 |
| 7 | `bluetoothHostControllerSwitchBehavior=always` did nothing | It only controls dongle preference, not the transport type | Not the fix |
| 8 | `BT_HCI_TRANSPORT=USB` in NVRAM was ignored | It is read as an **environment variable**, not from NVRAM | Abandoned |
| 9 | **Root cause** | BlueToolFixup 2.7.0+ requires two NVRAM keys, otherwise `bluetoothd` falls back to the UART placeholder | `bluetoothExternalDongleFailed = <00>` (1 byte) and `bluetoothInternalControllerInfo = <0000000000000000000000000000>` (**exactly 14 bytes**; 16 bytes triggers `CFDataGetLength != 14`) |

### Wi-Fi

| # | Symptom | Cause | Fix |
|---|---|---|---|
| 10 | No Wi-Fi pane in System Settings | `MtkWlanNative` only supports macOS **26.7.1 / 26.7.2** | On 26.0 you only get the Ethernet front end; use the bundled menu-bar app |
| 11 | `mtkwifi scan` says `needs root` | Scanning requires root | Add a narrow sudoers rule (only `scan --wait`) or run with `sudo` |
| 12 | Connects at boot, later drops | Saved networks are not auto-joined | LaunchDaemon that runs `mtkwifi autojoin` at boot |
| 13 | `mtkwifi add` fails with `mkdir ... No such file or directory` | It does not create the parent directory | `mkdir -p "/Library/Application Support/legion"` first |
| 14 | Menu-bar app reports `not saved` for a new network | In `list --json`, `joinable` means "driver supports this security", **not** "password saved" | Try passwordless first; on `is not saved`, prompt for the passphrase |
| 15 | Password join cannot run unattended | `--ask` requires a tty | Drive it with `expect`; keep the password in a one-shot 0600 file, never in argv |

### Audio / microphone

| # | Symptom | Cause | Fix |
|---|---|---|---|
| 16 | Audio devices exist but speakers are silent | Default output was `NVIDIA HDMI` (no display attached) | Switch default output to ALC245 |
| 17 | AppleALC + SimpleHDA did not make the mic work | macOS 26 removed `AppleHDA`, and `NMXAudio` (NullMoth) still owns the ALC245 codec | Gave up; use a USB mic or headset |
| 18 | Recordings contain a constant noise floor only | The NMXAudio input path has no real capture | Same as above |

### Battery / power

| # | Symptom | Cause | Fix |
|---|---|---|---|
| 19 | `Battery Power` even when plugged in | `_PSR` reads `R400` in the `H2RA` window (`0xFE700000+0x340`), which macOS reads as 0 | Custom `SSDT-AC` reads EC RAM `0x40` bit 0; rename `_PSR→XPSR`, `_Q20→XQ20` |
| 20 | Briefly assumed `R830` bit 15 was the AC flag | It is the sign bit of battery power (negative = discharging) | Use EC `0x40` bit 0 (`0x0B` plugged, `0x02` unplugged) |
| 21 | Laggy after sleep/wake | `hibernatemode 3` + `standby 1` restore from a hibernation image | `hibernatemode 0`, `standby 0` |

### Displays

| # | Symptom | Cause | Fix |
|---|---|---|---|
| 22 | Severe Dock/UI frame drops | Internal 60 Hz and external 300 Hz were in **hardware mirror** mode | Disable mirroring, use extended mode, make the external display primary |
| 23 | Closing the lid sleeps the machine and kills the external display | `AppleClamshellCausesSleep = Yes` | `pmset disablesleep 1` + set internal backlight to 0 on lid close (bundled script) |

---

## 4. Why this HP firmware is unusual

HP's firmware hardcodes the boot entry as
`Boot0000 = \EFI\Microsoft\Boot\bootmgfw.efi`, never scans `\EFI\BOOT\BOOTX64.EFI`,
and ignores/resets boot entries written by third parties.

Log evidence:

```
OCB: No existing option at Boot0000, invalid
OCB: 0 -> Boot0000 = HD(1,GPT,...)/\EFI\Microsoft\Boot\bootmgfw.efi
```

So the only reliable approach is to occupy that path:

```
Firmware → bootmgfw.efi (now the OpenCore launcher)
         → OpenCore picker
         → Windows is reached through BlessOverride → bootmgfw-orig.efi
```

- Keep the original Windows loader renamed to `bootmgfw-orig.efi`
- Add `\EFI\Microsoft\Boot\bootmgfw-orig.efi` to `Misc → BlessOverride`

**Side effect:** a Windows feature update may restore the original `bootmgfw.efi`,
which makes the machine boot straight into Windows again. Back up before changing anything.

---

## 5. Layout

```
boards/8F06/EFI/BOOT/BOOTx64.efi          OpenCore launcher
boards/8F06/EFI/OC/OpenCore.efi           OpenCore 1.0.9 DEBUG
boards/8F06/EFI/OC/config.plist           Sanitized configuration
boards/8F06/EFI/OC/ACPI/                  SSDTs (including the model-specific SSDT-AC)
boards/8F06/EFI/OC/Drivers/               OpenRuntime / HfsPlus / OpenCanopy / ResetNvramEntry
boards/8F06/EFI/OC/Resources/             OpenCanopy resources
boards/8F06/EFI/OC/Kexts/                 Empty; populated by fetch-kexts.sh
fetch-kexts.sh                Downloads all kexts from official releases
docs/BOOT-AND-CONFIG.md       Per-setting rationale + HP boot analysis
DRIVERS.md                    Driver list (version / source / license)
STATUS.md                     Test results and verification commands
RISKS.md                      Publication risk checklist
LICENSES.md / LICENSE         Licensing
boards/8F06/ACPI-SOURCES/                 SSDT-AC source
tools/                        Clamshell script, brightness tools, Wi-Fi menu-bar app
```

---

## 6. Notes

- No third-party binaries are bundled (GPL and Apple copyright reasons); the script fetches
  them from the official releases.
- All drivers belong to their respective authors — see [DRIVERS.md](DRIVERS.md).
- Use at your own risk; read [RISKS.md](RISKS.md) first.

## Credits

OpenCore / Lilu / VirtualSMC / WhateverGreen / AppleALC / VoodooI2C / VoodooPS2 /
BrcmPatchRAM / USBToolBox / NVMeFix / RestrictEvents / BrightnessKeys / ECEnabler /
AMFIPass / AppleMCEReporterDisabler / RTL8111 / HoRNDIS /
WTLMtkWireless / WTLMtkBluetooth / NullMoth NVIDIA driver,
plus the kernel patches from [AMD Vanilla](https://github.com/AMD-OSX/AMD_Vanilla).
Full links in [DRIVERS.md](DRIVERS.md).
