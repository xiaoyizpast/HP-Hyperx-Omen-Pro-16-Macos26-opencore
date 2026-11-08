# 附加工具（可选，非引导必需）

这些是本机额外做的两套小工具，源码附上供参考，均可用 MIT 协议使用。

## clamshell/ 合盖模式

- `clamshell-daemon.sh`：轮询合盖状态；接外接屏时 `pmset disablesleep 1`，
  合盖把内屏背光设为 0，开盖恢复
- `dbright.c`：读写显示器亮度（IOKit `IODisplaySetFloatParameter`）
- `displays.c`：枚举在线显示器（`CGDisplayIsBuiltin` 区分内外屏）
- `com.local.clamshell.plist`：LaunchDaemon，开机自启

编译：

```bash
clang -O2 -framework IOKit -framework CoreFoundation -o dbright dbright.c
clang -O2 -framework CoreGraphics -o displays displays.c
sudo cp com.local.clamshell.plist /Library/LaunchDaemons/
sudo launchctl load -w /Library/LaunchDaemons/com.local.clamshell.plist
```

> 注意：`disablesleep` 会阻止系统睡眠。只在接外接屏、需要合盖继续运行时使用。

## wifimenu/ Wi-Fi 菜单栏 App

MT7925 在 macOS 26.0 上只有以太网前端，没有原生 Wi-Fi 菜单。
`main.swift` 是一个菜单栏客户端：

- 菜单栏只显示图标
- 展开时触发实时扫描（需要免密 sudo 白名单）
- 已保存/开放网络免密连接，新网络弹密码框
- 连上开放网络自动打开校园网门户

编译与权限（sudoers 白名单）见源码顶部注释与 `DRIVERS.md`。

> 已构建好的 App 与安装脚本单独打包为 `wifi-menu-share.zip`（含 `install.sh`）。
