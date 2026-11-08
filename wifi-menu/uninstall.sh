#!/bin/bash
set -e
launchctl unload "$HOME/Library/LaunchAgents/com.local.wifimenu.plist" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/com.local.wifimenu.plist"
rm -rf "$HOME/Applications/WiFi Menu.app"
sudo rm -f /etc/sudoers.d/mtkwifi
sudo launchctl unload /Library/LaunchDaemons/com.local.mtkwifi-autojoin.plist 2>/dev/null || true
sudo rm -f /Library/LaunchDaemons/com.local.mtkwifi-autojoin.plist
echo "已卸载（/usr/local/bin/mtkwifi 保留，不需要可自行删除）"
