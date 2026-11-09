# 获取 EFI 的两种方式

| 平台 | 脚本 | 作用 |
|---|---|---|
| Windows | `windows/get-efi.ps1` | **PowerShell 7** 脚本。硬件检查（主板 8F06、CPU 9955HX，不含显卡）→ 构建**最小 EFI**（能启动 + USB 供网）→ 写入 ESP → 调整启动项。每步有确认框，失败自动开 issue。 |
| macOS | `macos/get-efi.sh` | 下载最新 release → 备份并写入 EFI → **补全全部驱动** → 应用已验证的 boot-args / 蓝牙 NVRAM。每步有确认框，失败自动开 issue。 |

## 运行环境

- Windows 脚本需要 **PowerShell 7**（`pwsh.exe`），不支持 Windows PowerShell 5.1
  - 若在 5.1 下运行，脚本会弹窗提示并打开[微软官方安装说明](https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-windows)
  - 安装：`winget install --id Microsoft.PowerShell --source winget`
- macOS 脚本需要 macOS 自带 `bash` / `osascript` / `python3`

## 使用顺序

1. Windows 下运行 `get-efi.ps1`，得到可启动的 EFI 和安装环境
2. 安装 macOS
3. 进入 macOS 后运行 `get-efi.sh`，补全 Wi-Fi、蓝牙、音频、触控板等驱动

## 风险提示

- 修改 EFI 可能导致**无法开机**
- 使用前必须会：U 盘救援、挂载 ESP、回退 `config.plist`
- 不保证不会损坏硬件
- Windows 脚本只保证“能启动 + USB 供网”，其余功能由 macOS 脚本补全

## 失败处理

两个脚本在失败时都会：

1. 弹出错误说明
2. 打开 GitHub 新建 issue 页面，预填标题和日志路径

也可以手动提交：https://github.com/xiaoyizpast/Hackintosh-OMEN-8f06/issues/new
