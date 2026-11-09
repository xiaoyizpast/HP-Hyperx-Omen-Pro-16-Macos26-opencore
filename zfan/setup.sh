#!/bin/bash
# Zfan 运行环境补全脚本（HP HyperX OMEN PRO 16 / 8F06）
set -uo pipefail

RED=$'\033[31m'; GRN=$'\033[32m'; YLW=$'\033[33m'; RST=$'\033[0m'
say() { printf "%s\n" "$*"; }
ok()  { printf "%s✔%s %s\n" "$GRN" "$RST" "$*"; }
warn(){ printf "%s!%s %s\n" "$YLW" "$RST" "$*"; }
die() { printf "%s✘%s %s\n" "$RED" "$RST" "$*"; exit 1; }
ask() {
  local a
  a=$(osascript -e "display dialog \"$1\" buttons {\"取消\",\"继续\"} default button \"继续\" with title \"Zfan 环境补全\"" 2>/dev/null)
  [[ "$a" == *"继续"* ]]
}

[[ $EUID -eq 0 ]] || exec sudo -E bash "$0" "$@"

say "Zfan 环境补全"
say "1) 检查硬件  2) 写入 EC kext  3) 安装 App/CLI  4) 自启  5) 校验"
ask "本脚本会修改 EFI 与 /Applications、/usr/local/bin。\n\n请确认已备份 EFI。继续？" || exit 0

CPU=$(sysctl -n machdep.cpu.brand_string 2>/dev/null)
MODEL=$(sysctl -n hw.model 2>/dev/null)
say "CPU: $CPU"
say "Model: $MODEL"
[[ "$CPU" == *"9955HX"* ]] || { warn "CPU 不是 9955HX，脚本仍会继续但可能不适用"; ask "继续？" || exit 1; }

# 定位脚本目录与 EFI
HERE=$(cd "$(dirname "$0")" && pwd)
KEXT_SRC="$HERE/kext/ECFanPMIO.kext"
[[ -d "$KEXT_SRC" ]] || die "找不到 $KEXT_SRC"

ESP=$(diskutil list | awk '/EFI EFI/ {print $NF; exit}')
[[ -n "$ESP" ]] || die "找不到 EFI 分区"
diskutil mount "$ESP" >/dev/null 2>&1 || die "挂载 $ESP 失败"
VOL="/Volumes/EFI"
[[ -d "$VOL/EFI" ]] || die "EFI 未挂载到 $VOL"
ok "EFI: $VOL ($ESP)"

# 备份
BACKUP="$HOME/Desktop/EFI-backup-zfan-$(date +%Y%m%d-%H%M%S).zip"
(cd "$VOL" && zip -qr "$BACKUP" EFI) && ok "已备份 EFI 到 $BACKUP"

ask "将 ECFanPMIO.kext 写入 EFI 并启用 config 项。继续？" || exit 0
mkdir -p "$VOL/EFI/OC/Kexts"
rm -rf "$VOL/EFI/OC/Kexts/ECFanPMIO.kext"
cp -R "$KEXT_SRC" "$VOL/EFI/OC/Kexts/"
python3 - "$VOL/EFI/OC/config.plist" <<'PY' || die "修改 config.plist 失败"
import plistlib, sys
p = sys.argv[1]
d = plistlib.load(open(p, "rb"))
k = d["Kernel"]["Add"]
for e in k:
    if e.get("BundlePath") == "ECFanPMIO.kext":
        e["Enabled"] = True
        break
else:
    k.append({"Arch":"x86_64","BundlePath":"ECFanPMIO.kext","Comment":"Zfan EC fan control",
              "Enabled":True,"ExecutablePath":"Contents/MacOS/ECFanPMIO","MaxKernel":"","MinKernel":"",
              "PlistPath":"Contents/Info.plist"})
plistlib.dump(d, open(p, "wb"), sort_keys=False)
print("config.plist updated")
PY
ok "ECFanPMIO.kext 已写入并启用"

# 安装 App / CLI / 自启
ask "安装 Zfan.app、fan、amd-epp 与登录自启。继续？" || exit 0
APP_SRC=""
for c in "$HERE/../Zfan.app" "/Applications/Zfan.app"; do
  [[ -d "$c" ]] && APP_SRC="$c" && break
done
if [[ -n "$APP_SRC" ]]; then
  rm -rf "/Applications/Zfan.app"
  cp -R "$APP_SRC" "/Applications/Zfan.app"
  ok "Zfan.app 已安装"
else
  warn "未找到 Zfan.app，跳过 App 安装（可稍后安装 Zfan-2.3.0.pkg）"
fi
install -d /usr/local/bin
[[ -f "$HERE/bin/fan" ]] && install -m 755 "$HERE/bin/fan" /usr/local/bin/fan && ok "fan 已安装"
[[ -f "$HERE/bin/amd-epp" ]] && install -m 755 "$HERE/bin/amd-epp" /usr/local/bin/amd-epp && ok "amd-epp 已安装"

AG="/Library/LaunchAgents/com.local.fancontrol.plist"
mkdir -p /Library/LaunchAgents
cat > "$AG" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.local.fancontrol</string>
  <key>ProgramArguments</key><array><string>/Applications/Zfan.app/Contents/MacOS/FanControl</string></array>
  <key>RunAtLoad</key><true/>
  <key>LimitLoadToSessionType</key><string>Aqua</string>
</dict></plist>
PLIST
launchctl bootout gui/$(id -u) "$AG" 2>/dev/null || true
launchctl bootstrap gui/$(id -u) "$AG" 2>/dev/null || true
ok "LaunchAgent 已安装"

# 校验
if sysctl kern.ecfan >/dev/null 2>&1; then
  ok "kern.ecfan 可用：$(sysctl -n kern.ecfan)"
else
  warn "kern.ecfan 暂不可用，需要重启加载 kext"
fi

say ""
say "完成。请重启一次，然后打开 Zfan.app。"
say "恢复：删掉 EFI 里的 ECFanPMIO.kext 或回滚 $BACKUP"
