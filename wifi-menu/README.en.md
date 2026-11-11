# WiFi Menu — MT7925 menu bar Wi-Fi client

A small menu bar front end for the **MediaTek MT7925** on **macOS 26.0**.

macOS 26.0 has no native Wi-Fi driver for this card. The `MtkWlan` kext exposes the
card as an **Ethernet** interface, so there is no Wi-Fi pane in System Settings.
This app wraps the `mtkwifi` command line tool in a menu bar client.

> **Status: archived fallback for macOS 26.0.**
> On macOS 26.7.1 (25G241) and 26.7.2 (25G332) use the official
> [MtkWlanNative](https://github.com/watchthelight-labs/WTLWifiMenu) front end instead;
> this app is not needed there.

## Requirements

1. `MtkWlan.kext` installed (this app ships no driver — see
   [WTLMtkWireless](https://github.com/watchthelight-labs/WTLMtkWireless))
2. An Ethernet-style interface such as `en2` present in the system
3. macOS 26.0 (25A354)

## Install

```bash
./install.sh                  # basic install
./install.sh --with-autojoin  # also join saved networks at boot
```

Uninstall:

```bash
./uninstall.sh
```

## Features

- Menu bar shows icon only (connected: `wifi`, disconnected: `wifi.slash`)
- Opening the menu triggers a live scan (2–4 seconds, no password)
- Saved and open networks join without a prompt; new WPA2 networks show a password field
- After joining an open network, opens the captive-portal page (follows redirects, up to 4 tries)
- Menu items: refresh / rescan / open login page / disconnect / quit

## Permissions

`mtkwifi` needs root for scan and join. The installer:

1. Installs `mtkwifi` into `/usr/local/bin` owned by root, not writable by the user
2. Writes `/etc/sudoers.d/mtkwifi` allowing **only three commands**:

```
ALL=(root) NOPASSWD: /usr/local/bin/mtkwifi scan --wait,
                     /usr/local/bin/mtkwifi join *,
                     /usr/local/bin/mtkwifi disconnect
```

Networks that need a password still go through the system authorization dialog. The
password is written to a one-time 0600 temp file and removed immediately; it never
appears in the command line.

## Limitations

- Not a native Wi-Fi pane: no menu bar Wi-Fi list, no preferred-networks settings
- 1–2 seconds of downtime when switching networks
- No WPA2-Enterprise (`MtkWlan` itself does not support it)
- x86_64 and macOS 26 only

## Binary version

The `mtkwifi` binary comes from the Recovery folder of
`mt7925-wifi-bundle-0.12.1+0.4.16` and includes the 8a4de8e fix for `mtkwifi add`.

## License

- This app (`main.swift`, `install.sh`, etc.): MIT
- `mtkwifi` binary: from WTLMtkWireless, **ISC**, see `LICENSE-mtkwifi.txt`
