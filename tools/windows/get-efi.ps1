#requires -version 7.0
<#
  Zfan / Hackintosh-OMEN-8f06 - Windows EFI builder (minimal: boot + USB tethering)
  Every destructive step asks for confirmation. Any failure opens a prefilled GitHub issue.
#>
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ErrorActionPreference = "Stop"
$Repo   = "xiaoyizpast/Hackintosh-OMEN-8f06"
$Issue  = "https://github.com/$Repo/issues/new"
$Work   = Join-Path $env:TEMP ("omen-efi-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
$Log    = Join-Path $env:TEMP "omen-efi-build.log"

function Log($m) {
    $line = "[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $m
    Add-Content -Path $Log -Value $line
}
function Info($m, $t = "Zfan EFI") {
    Log $m
    [System.Windows.Forms.MessageBox]::Show($m, $t, "OK", "Information") | Out-Null
}
function Confirm($m, $t = "请确认") {
    Log ("CONFIRM: " + $m)
    $r = [System.Windows.Forms.MessageBox]::Show($m, $t, "YesNo", "Question")
    return ($r -eq "Yes")
}
function Fail($m) {
    Log ("FAIL: " + $m)
    [System.Windows.Forms.MessageBox]::Show($m, "失败", "OK", "Error") | Out-Null
    $body = "步骤失败：$m`n`n日志：$Log`n`n机器：$env:COMPUTERNAME`n时间：$(Get-Date -Format s)"
    $url = $Issue + "?title=" + [uri]::EscapeDataString("EFI 构建失败") + "&body=" + [uri]::EscapeDataString($body)
    Start-Process $url
    exit 1
}

# --- 管理员 ---
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    if (-not (Confirm "需要管理员权限来挂载 EFI 分区。现在以管理员身份重新启动脚本？")) { exit 0 }
    $hostExe = (Get-Process -Id $PID).Path
    Start-Process $hostExe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    exit
}

Info "本脚本会：`n1. 检查硬件是否为 HP HyperX OMEN PRO 16 (8F06)`n2. 下载最新 release 并构建最小 EFI（可启动 + USB 供网）`n3. 备份现有 EFI 并复制到 ESP`n4. 调整 UEFI 启动项`n`n构建完成后会弹出下一步说明。`n`n仅支持 8F06；其他机型请勿使用。" "Zfan EFI · 开始"

if (-not (Confirm "继续前请确认：`n- 已备份 BitLocker 恢复密钥（如有）`n- 知道如何在 BIOS 里切换启动项`n- 接受自行承担风险`n`n继续？")) { exit 0 }

# --- 硬件检查 ---
Info "开始硬件检查..." "步骤 1/4"
try {
    $board = (Get-CimInstance Win32_BaseBoard).Product
    $cpu   = (Get-CimInstance Win32_Processor | Select-Object -First 1).Name
    Log "board=$board cpu=$cpu"
} catch { Fail "无法读取硬件信息：$($_.Exception.Message)" }

$okBoard = $board -match "8F06"
$okCpu   = $cpu -match "9955HX"

$summary = "主板：$board`nCPU：$cpu`n`n匹配结果：`n  8F06: $okBoard`n  9955HX: $okCpu"
if (-not ($okBoard -and $okCpu)) {
    if (-not (Confirm "$summary`n`n硬件与目标机型不匹配。继续可能无法启动。仍要继续吗？")) { Fail "用户取消：硬件不匹配" }
} else {
    Info "$summary`n`n硬件匹配。" "步骤 1/4 · 通过"
}

# --- 下载最新 release ---
if (-not (Confirm "下一步：下载最新 release 并解压到临时目录。`n`n继续？")) { exit 0 }
Info "正在查询最新 release..." "步骤 2/4"
try {
    $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" -Headers @{ "User-Agent" = "Zfan-EFI" }
    $asset = $rel.assets | Where-Object { $_.name -like "*.zip" } | Select-Object -First 1
    if (-not $asset) { throw "release 中没有 zip 附件" }
    New-Item -ItemType Directory -Force -Path $Work | Out-Null
    $zip = Join-Path $Work $asset.name
    Log "download $($asset.browser_download_url)"
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zip
    Expand-Archive -Path $zip -DestinationPath $Work -Force
} catch { Fail "下载或解压 release 失败：$($_.Exception.Message)" }

$root = Get-ChildItem $Work -Directory | Where-Object { Test-Path (Join-Path $_.FullName "boards") } | Select-Object -First 1
if (-not $root) { Fail "release 结构异常：找不到 boards 目录" }
$efiSrc = Join-Path $root.FullName "boards\8F06\EFI"
if (-not (Test-Path $efiSrc)) { Fail "找不到 EFI 目录：$efiSrc" }
Info "release 已解压：$($root.Name)" "步骤 2/4 · 完成"

# --- 最小 kext ---
if (-not (Confirm "下一步：下载最小 kext 集合（Lilu、VirtualSMC、WhateverGreen、NVMeFix、USBToolBox），仅保证能启动和 USB 供网。`n`n完整驱动请装好 macOS 后在 macOS 里运行第二个脚本。`n`n继续？")) { exit 0 }
try {
    $manifest = Get-Content (Join-Path $root.FullName "tools\kexts.json") -Raw | ConvertFrom-Json
    $needed = $manifest.minimal
    $cache = Join-Path $Work "kext-cache"
    New-Item -ItemType Directory -Force -Path $cache | Out-Null
    $kextDir = Join-Path $efiSrc "OC\Kexts"
    New-Item -ItemType Directory -Force -Path $kextDir | Out-Null

    $repos = @{}
    foreach ($item in $manifest.full) { $repos[$item.repo] = $true }
    foreach ($k in $needed) {
        $entry = $manifest.full | Where-Object { $_.name -eq $k } | Select-Object -First 1
        if (-not $entry) { throw "manifest 缺少 $k" }
        $repo = $entry.repo
        $safe = $repo.Replace("/", "_")
        $dest = Join-Path $cache $safe
        if (-not (Test-Path $dest)) {
            $r = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/latest" -Headers @{ "User-Agent" = "Zfan-EFI" }
            $a = $r.assets | Where-Object { $_.name -like "*.zip" } | Select-Object -First 1
            if (-not $a) { throw "$repo 没有 zip 附件" }
            $z = Join-Path $cache ($safe + ".zip")
            Invoke-WebRequest -Uri $a.browser_download_url -OutFile $z
            Expand-Archive -Path $z -DestinationPath $dest -Force
        }
        $found = Get-ChildItem $dest -Recurse -Directory -Filter $k | Select-Object -First 1
        if (-not $found) { throw "$repo 中找不到 $k" }
        Copy-Item $found.FullName (Join-Path $kextDir $k) -Recurse -Force
        Log "kext $k <- $repo"
    }
} catch { Fail "下载 kext 失败：$($_.Exception.Message)" }
Info "最小 kext 已就位：$($needed -join ', ')" "步骤 3/4 · 完成"

# --- 备份并写入 ESP ---
if (-not (Confirm "下一步：挂载 EFI 分区、备份现有 EFI，然后写入新 EFI。`n`n这一步会修改启动分区，继续？")) { exit 0 }

try {
    $esp = Get-Partition | Where-Object { $_.GptType -eq "{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}" } | Select-Object -First 1
    if (-not $esp) { throw "找不到 EFI 系统分区" }
    $free = (68..90 | ForEach-Object { [char]$_ } | Where-Object { -not (Test-Path ($_ + ":\")) } | Select-Object -First 1)
    if (-not $free) { throw "没有可用的盘符" }
    $drive = "$free`:"
    Log "mount ESP -> $drive"
    mountvol $drive /S | Out-Null
    if (-not (Test-Path "$drive\")) { throw "EFI 分区挂载失败" }

    $backup = Join-Path ([Environment]::GetFolderPath("Desktop")) ("EFI-backup-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".zip")
    if (Test-Path "$drive\EFI") {
        Compress-Archive -Path "$drive\EFI" -DestinationPath $backup -Force
        Info "已备份现有 EFI 到：`n$backup" "备份完成"
    } else {
        Log "no existing EFI"
    }

    if (-not (Confirm "将写入 EFI 到 $drive。`n`n确认继续？")) { exit 0 }
    if (Test-Path "$drive\EFI") { Remove-Item "$drive\EFI" -Recurse -Force }
    Copy-Item $efiSrc "$drive\EFI" -Recurse -Force
    Info "EFI 已写入 $drive" "步骤 4/4 · 完成"
} catch { Fail "写入 EFI 失败：$($_.Exception.Message)" }

# --- 启动项 ---
if (Confirm "是否现在把 OpenCore 添加到 UEFI 启动项并置顶？`n`n如果失败，可以在 BIOS 的 Boot 菜单里手动添加。") {
    try {
        $enum = bcdedit /enum firmware
        $text = $enum -join "`n"
        $guid = $null
        $m = [regex]::Match($text, "(?s)identifier\s+(\{[0-9a-fA-F-]+\}).*?description\s+OpenCore")
        if ($m.Success) { $guid = $m.Groups[1].Value }
        if (-not $guid) {
            $out = bcdedit /create /d "OpenCore" /application osloader
            $m2 = [regex]::Match(($out -join " "), "(\{[0-9a-fA-F-]+\})")
            if (-not $m2.Success) { throw "创建启动项失败" }
            $guid = $m2.Groups[1].Value
            bcdedit /set $guid path "\EFI\OC\OpenCore.efi" | Out-Null
            bcdedit /set $guid device "partition=$drive" | Out-Null
        }
        bcdedit /set "{fwbootmgr}" displayorder $guid /addfirst | Out-Null
        Info "启动项已设置：$guid`n`n重启后如未进入 OpenCore，请到 BIOS 手动调整启动顺序。" "启动项完成"
    } catch {
        Info "自动设置启动项失败：$($_.Exception.Message)`n`n请重启进入 BIOS，在 Boot 菜单里添加 \EFI\OC\OpenCore.efi。" "启动项"
    }
}

# --- 结束 ---
$readme = Join-Path $root.FullName "README.md"
if (-not (Test-Path $readme)) { $readme = $null }
$msg = "EFI 构建完成。`n`n下一步：`n1. 重启进入 BIOS，确认从 OpenCore 启动`n2. 用 U 盘安装 macOS`n3. 安装完成后，在 macOS 里运行 tools/macos/get-efi.sh 补全驱动`n`n注意：Windows 阶段只保证能启动和 USB 供网；Wi-Fi、蓝牙、音频、触控板等由 macOS 脚本补全。`n`n日志：$Log"
if ($readme) { $msg += "`n`nREADME：$readme" }
Info $msg "完成"
if ($readme) { Start-Process notepad $readme }
