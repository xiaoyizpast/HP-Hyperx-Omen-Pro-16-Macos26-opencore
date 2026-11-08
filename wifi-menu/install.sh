#!/bin/bash
# WiFi Menu 安装脚本（需要管理员密码）
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
ME="$(id -un)"

echo "==> 1/5 安装 mtkwifi 到 /usr/local/bin（root 所有，避免提权风险）"
sudo install -o root -g wheel -m 755 "$DIR/mtkwifi" /usr/local/bin/mtkwifi

echo "==> 2/5 配置 sudoers 白名单（只放行扫描/连接/断开）"
TMP=$(mktemp)
printf '%s ALL=(root) NOPASSWD: /usr/local/bin/mtkwifi scan --wait, /usr/local/bin/mtkwifi join *, /usr/local/bin/mtkwifi disconnect\n' "$ME" > "$TMP"
sudo install -o root -g wheel -m 440 "$TMP" /etc/sudoers.d/mtkwifi
rm -f "$TMP"
sudo visudo -cf /etc/sudoers.d/mtkwifi

echo "==> 3/5 复制 App 到 ~/Applications"
mkdir -p "$HOME/Applications"
rm -rf "$HOME/Applications/WiFi Menu.app"
cp -R "$DIR/WiFi Menu.app" "$HOME/Applications/"

echo "==> 4/5 安装开机自启"
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$HOME/Library/LaunchAgents/com.local.wifimenu.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.local.wifimenu</string>
  <key>ProgramArguments</key>
  <array><string>$HOME/Applications/WiFi Menu.app/Contents/MacOS/WifiMenu</string></array>
  <key>RunAtLoad</key><true/>
  <key>LimitLoadToSessionType</key><string>Aqua</string>
</dict>
</plist>
PLIST
launchctl unload "$HOME/Library/LaunchAgents/com.local.wifimenu.plist" 2>/dev/null || true
launchctl load -w "$HOME/Library/LaunchAgents/com.local.wifimenu.plist"

echo "==> 5/5 可选：开机自动连接已保存的网络"
if [ "$1" = "--with-autojoin" ]; then
  cat > /tmp/com.local.mtkwifi-autojoin.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.local.mtkwifi-autojoin</string>
  <key>ProgramArguments</key>
  <array><string>/usr/local/bin/mtkwifi</string><string>autojoin</string><string>--wait</string><string>60</string></array>
  <key>RunAtLoad</key><true/>
  <key>StandardOutPath</key><string>/var/log/mtkwifi-autojoin.log</string>
  <key>StandardErrorPath</key><string>/var/log/mtkwifi-autojoin.log</string>
</dict>
</plist>
PLIST
  sudo install -o root -g wheel -m 644 /tmp/com.local.mtkwifi-autojoin.plist /Library/LaunchDaemons/
  sudo launchctl unload /Library/LaunchDaemons/com.local.mtkwifi-autojoin.plist 2>/dev/null || true
  sudo launchctl load -w /Library/LaunchDaemons/com.local.mtkwifi-autojoin.plist
  rm -f /tmp/com.local.mtkwifi-autojoin.plist
else
  echo "    跳过（如需开机自动连接：./install.sh --with-autojoin）"
fi

open "$HOME/Applications/WiFi Menu.app" 2>/dev/null || true
echo
echo "完成。菜单栏右上角应出现 Wi-Fi 图标。"
