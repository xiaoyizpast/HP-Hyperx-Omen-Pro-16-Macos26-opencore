#!/bin/bash
# Zfan / Hackintosh-OMEN-8f06 - macOS 侧：补全驱动 + 已验证调整项
# 每一步都会弹确认框；失败会打开 GitHub issue。
set -uo pipefail

REPO="xiaoyizpast/Hackintosh-OMEN-8f06"
ISSUE="https://github.com/$REPO/issues/new"
WORK="$(mktemp -d /tmp/omen-efi.XXXXXX)"
LOG="$WORK/build.log"
exec > >(tee -a "$LOG") 2>&1

say()  { osascript -e "display dialog \"$1\" buttons {\"好\"} default button \"好\" with title \"Zfan EFI\"" >/dev/null; }
ask()  { osascript -e "display dialog \"$1\" buttons {\"取消\",\"继续\"} default button \"继续\" with title \"Zfan EFI\"" 2>/dev/null | grep -q "继续"; }
fail() {
  osascript -e "display dialog \"失败：$1\n\n日志：$LOG\" buttons {\"好\"} with icon stop with title \"Zfan EFI\"" >/dev/null
  open "$ISSUE?title=$(python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))" "EFI 补全失败")&body=$(python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))" "步骤：$1%0A日志：$LOG")"
  exit 1
}

say "本脚本会：\n1. 检查机型\n2. 下载最新 release\n3. 备份现有 EFI 并写入\n4. 补全驱动（Lilu/VirtualSMC/音频/触控板/Wi-Fi/蓝牙等）\n5. 应用已验证的 boot-args 与蓝牙 NVRAM 设置\n\n警告：\n- 修改 EFI 可能导致无法开机\n- 需要你会用 U 盘救援、会回退 OpenCore\n- 不保证不会损坏硬件\n\n继续即表示你接受以上风险。"

ask "继续前确认：\n- 已备份当前可用的 EFI\n- 有可启动的 macOS 安装 U 盘\n- 知道如何 mount ESP 并回滚 config.plist\n\n继续？" || exit 0

# 1. 硬件检查
say "检查硬件..."
BOARD=$(ioreg -l 2>/dev/null | grep -o '"board-id" = <"[^"]*"' | head -1)
MODEL=$(sysctl -n hw.model 2>/dev/null)
CPU=$(sysctl -n machdep.cpu.brand_string 2>/dev/null)
GPU=$(system_profiler SPDisplaysDataType 2>/dev/null | grep -m1 "Chipset Model" | sed 's/.*: //')
[ "$(uname -m)" = "x86_64" ] || fail "当前不是 Intel/AMD x86_64 环境"
echo "board=$BOARD model=$MODEL cpu=$CPU gpu=$GPU"
if ! echo "$CPU" | grep -qi "9955HX"; then
  ask "CPU 不是 9955HX（当前：$CPU）。继续可能无法启动。仍要继续？" || exit 0
fi
say "硬件：\n$MODEL\n$CPU\n$GPU"

# 2. 下载最新 release
ask "下载最新 release 到临时目录？" || exit 0
REL_JSON="$WORK/release.json"
curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" -o "$REL_JSON" || fail "查询 release 失败"
ASSET_URL=$(python3 - "$REL_JSON" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
for a in d.get("assets",[]):
    if a["name"].endswith(".zip"):
        print(a["browser_download_url"]); break
PY
)
[ -n "$ASSET_URL" ] || fail "release 中没有 zip 附件"
ZIP="$WORK/pkg.zip"
curl -fL --progress-bar "$ASSET_URL" -o "$ZIP" || fail "下载 release 失败"
unzip -q "$ZIP" -d "$WORK/pkg" || fail "解压失败"
ROOT=$(find "$WORK/pkg" -maxdepth 2 -type d -name "boards" | head -1 | xargs dirname)
EFI_SRC="$ROOT/boards/8F06/EFI"
[ -d "$EFI_SRC" ] || fail "release 中找不到 8F06 EFI"
say "release 已解压：\n$(basename "$ROOT")"

# 3. 挂载 ESP + 备份
ask "将挂载 EFI 分区并备份现有 EFI。继续？" || exit 0
ESP=$(diskutil list | awk '/EFI EFI/ {print $NF; exit}')
[ -n "$ESP" ] || fail "找不到 EFI 分区"
osascript -e "do shell script \"diskutil mount $ESP\" with administrator privileges" >/dev/null || fail "挂载 $ESP 失败"
VOL="/Volumes/EFI"
[ -d "$VOL/EFI" ] || fail "EFI 分区未挂载到 $VOL"
BACKUP="$HOME/Desktop/EFI-backup-$(date +%Y%m%d-%H%M%S).zip"
(cd "$VOL" && zip -qr "$BACKUP" EFI) || fail "备份失败"
say "已备份到：\n$BACKUP"

# 4. 写入 EFI
ask "将用新 EFI 覆盖 $VOL/EFI。\n\n确认写入？" || exit 0
rm -rf "$VOL/EFI"
cp -R "$EFI_SRC" "$VOL/EFI" || fail "复制 EFI 失败"

# 5. 补全驱动
ask "开始下载完整驱动集合（约 10 个仓库的最新 release）。\n\n继续？" || exit 0
MANIFEST="$ROOT/tools/kexts.json"
[ -f "$MANIFEST" ] || fail "缺少 tools/kexts.json"
KEXT_DIR="$VOL/EFI/OC/Kexts"
mkdir -p "$KEXT_DIR"
python3 - "$MANIFEST" "$WORK/kext-cache" "$KEXT_DIR" <<'PY' || fail "驱动下载失败"
import json, os, subprocess, sys, urllib.request, zipfile, shutil
manifest, cache, dest = sys.argv[1], sys.argv[2], sys.argv[3]
data = json.load(open(manifest))
os.makedirs(cache, exist_ok=True)
headers = {"User-Agent": "Zfan-EFI"}
by_repo = {}
for item in data["full"]:
    by_repo.setdefault(item["repo"], []).append(item["name"])
for repo, names in by_repo.items():
    safe = repo.replace("/", "_")
    d = os.path.join(cache, safe)
    if not os.path.isdir(d):
        req = urllib.request.Request(f"https://api.github.com/repos/{repo}/releases/latest", headers=headers)
        rel = json.load(urllib.request.urlopen(req, timeout=60))
        asset = next((a for a in rel.get("assets", []) if a["name"].endswith(".zip")), None)
        if not asset: raise RuntimeError(f"{repo}: no zip asset")
        z = os.path.join(cache, safe + ".zip")
        urllib.request.urlretrieve(asset["browser_download_url"], z)
        with zipfile.ZipFile(z) as zf: zf.extractall(d)
    for name in names:
        found = None
        for root, dirs, files in os.walk(d):
            if os.path.basename(root) == name:
                found = root; break
        if not found: raise RuntimeError(f"{repo}: {name} not found")
        target = os.path.join(dest, name)
        if os.path.exists(target): shutil.rmtree(target)
        shutil.copytree(found, target)
        print("kext:", name, "<-", repo)
PY
say "驱动已补全：\n$(ls "$KEXT_DIR" | tr '\n' ' ')"

# 6. 已验证调整项
VER=$(sw_vers -productVersion)
MTK_NATIVE=""
case "$VER" in 26.7.1|26.7.2) MTK_NATIVE="mtkfe=native mtknativeif=1";; esac
export MTK_NATIVE
ask "应用已验证的 boot-args 和蓝牙 NVRAM 设置？\n\n这会修改 config.plist 与 NVRAM。继续？" || exit 0
python3 - "$VOL/EFI/OC/config.plist" <<'PY' || fail "修改 config.plist 失败"
import plistlib, sys
p = sys.argv[1]
d = plistlib.load(open(p, "rb"))
args = ("debug=0x100 keepsyms=1 -amfipassbeta -vi2c-force-polling revpatch=sbvmm "
        "nvfb=1 nvaccel=1 nvfbheads=4 -nvkmsnosmooth amfi_get_out_of_my_way=0x1 amfi=0x80 "
        "ipc_control_port_options=0 gfxrst=4 nvrmacpibl=1 -amdcppcactive -amdpnopchk")
if os.environ.get("MTK_NATIVE"):
    args += " " + os.environ["MTK_NATIVE"]
nv = d.setdefault("NVRAM", {}).setdefault("Add", {})
guid = "7C436110-AB2A-4BBB-A880-FE41995C9F82"
node = nv.setdefault(guid, {})
node["boot-args"] = args
# 蓝牙：BlueToolFixup 2.7.x 要求
node["bluetoothExternalDongleFailed"] = b"\x00"
node["bluetoothInternalControllerInfo"] = b"\x00" * 14
plistlib.dump(d, open(p, "wb"), sort_keys=False)
print("config.plist updated")
PY
osascript -e 'do shell script "nvram bluetoothExternalDongleFailed=%00" with administrator privileges' >/dev/null 2>&1 || true
osascript -e 'do shell script "nvram bluetoothInternalControllerInfo=%00%00%00%00%00%00%00%00%00%00%00%00%00%00" with administrator privileges' >/dev/null 2>&1 || true

# 7. 收尾
say "完成。\n\n下一步：\n1. 重启并按 F9/F10 选择 OpenCore\n2. 如无法启动：进入恢复系统，或用备份 $BACKUP 回滚\n3. NullMoth 显卡驱动需在 macOS 内单独安装（不在 EFI 中）\n4. SMBIOS 序列号如为空，请自行生成\n\n日志：$LOG"
open "$ROOT/README.md" 2>/dev/null || true
