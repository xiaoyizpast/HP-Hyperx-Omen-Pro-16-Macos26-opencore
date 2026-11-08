#!/usr/bin/env python3
"""从各项目官方 GitHub Release 下载驱动到 boards/8F06/EFI/OC/Kexts。"""
import json, os, shutil, sys, tarfile, tempfile, urllib.request, zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
DEST = os.path.join(HERE, "boards", "8F06", "EFI", "OC", "Kexts")

# (repo, 需要的 kext 名, 说明)
MANIFEST = [
    ("acidanthera/Lilu",            ["Lilu.kext"],                                "Lilu"),
    ("acidanthera/VirtualSMC",      ["VirtualSMC.kext", "SMCBatteryManager.kext",
                                     "SMCLightSensor.kext"],                      "VirtualSMC 家族"),
    ("acidanthera/WhateverGreen",   ["WhateverGreen.kext"],                       "WhateverGreen"),
    ("acidanthera/BrightnessKeys",  ["BrightnessKeys.kext"],                      "BrightnessKeys"),
    ("acidanthera/NVMeFix",         ["NVMeFix.kext"],                             "NVMeFix"),
    ("acidanthera/RestrictEvents",  ["RestrictEvents.kext"],                      "RestrictEvents"),
    ("dhinakg/AMFIPass",            ["AMFIPass.kext"],                            "AMFIPass"),
    ("1Revenger1/ECEnabler",        ["ECEnabler.kext"],                           "ECEnabler"),
    ("VoodooI2C/VoodooI2C",         ["VoodooI2C.kext", "VoodooI2CHID.kext"],      "VoodooI2C (GPL-3.0)"),
    ("acidanthera/VoodooPS2",       ["VoodooPS2Controller.kext"],                 "VoodooPS2"),
    ("Mieze/RTL8111_driver_for_OS_X", ["RealtekRTL8111.kext"],                    "RTL8111"),
    ("USBToolBox/kext",             ["USBToolBox.kext", "UTBDefault.kext"],       "USBToolBox"),
    ("acidanthera/BrcmPatchRAM",    ["BlueToolFixup.kext"],                       "BlueToolFixup (GPL-2.0)"),
    ("jwise/HoRNDIS",               ["HoRNDIS.kext"],                             "HoRNDIS (RNDIS)"),
    ("watchthelight-labs/WTLMtkWireless", ["MtkWlan.kext"],                       "MT7925 Wi-Fi"),
    ("watchthelight-labs/WTLMtkBluetooth", ["MtkBt.kext"],                        "MT7925 蓝牙固件"),
]

API = "https://api.github.com"
HEADERS = {"Accept": "application/vnd.github+json", "User-Agent": "efi-fetch"}

def get(url):
    req = urllib.request.Request(url, headers=HEADERS)
    return urllib.request.urlopen(req, timeout=30)

def pick_asset(assets):
    zips = [a for a in assets if a["name"].endswith(".zip")]
    rel = [a for a in zips if "RELEASE" in a["name"].upper() and "DEBUG" not in a["name"].upper()]
    return (rel or zips or [None])[0]

def extract(path, out):
    if zipfile.is_zipfile(path):
        with zipfile.ZipFile(path) as z: z.extractall(out)
    elif tarfile.is_tarfile(path):
        with tarfile.open(path) as t: t.extractall(out)

def main():
    os.makedirs(DEST, exist_ok=True)
    ok, fail = [], []
    for repo, wanted, label in MANIFEST:
        try:
            rel = json.load(get(f"{API}/repos/{repo}/releases/latest"))
            asset = pick_asset(rel.get("assets", []))
            if not asset:
                raise RuntimeError("no zip asset")
            print(f"[{label}] {rel['tag_name']} -> {asset['name']}")
            with tempfile.TemporaryDirectory() as td:
                f = os.path.join(td, asset["name"])
                req = urllib.request.Request(asset["url"],
                        headers={"Accept": "application/octet-stream", "User-Agent": "efi-fetch"})
                with urllib.request.urlopen(req, timeout=120) as r, open(f, "wb") as o:
                    shutil.copyfileobj(r, o)
                ex = os.path.join(td, "x"); os.makedirs(ex)
                extract(f, ex)
                found = 0
                for root, dirs, _ in os.walk(ex):
                    for d in list(dirs):
                        if d in wanted:
                            src = os.path.join(root, d)
                            shutil.rmtree(os.path.join(DEST, d), ignore_errors=True)
                            shutil.copytree(src, os.path.join(DEST, d))
                            found += 1
                if found == 0:
                    raise RuntimeError("kext not found in archive")
                ok.append((label, rel["tag_name"]))
        except Exception as e:
            print(f"[{label}] FAILED: {e}")
            fail.append((label, str(e)))
    print("\n完成:", len(ok), "失败:", len(fail))
    for l, v in ok: print(f"  ✓ {l} {v}")
    for l, e in fail: print(f"  ✗ {l}: {e}")
    print("\n注意：VoodooI2C(GPL-3.0) 与 BlueToolFixup(GPL-2.0) 由你自行从官方仓库获取，")
    print("      本脚本只是自动化下载，不分发二进制。")
    return 1 if fail else 0

if __name__ == "__main__":
    sys.exit(main())
