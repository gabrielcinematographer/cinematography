<#
.SYNOPSIS
    Fresh clean-up and performance tune for a Windows 10/11 laptop
    (tuned for photo / video / colour work).

.DESCRIPTION
    Safe by default: it creates a System Restore point first, never touches
    passwords, cookies, documents or media, and never disables Defender,
    Windows Update or the firewall.

    Run from an *Administrator* PowerShell window:
        Set-ExecutionPolicy -Scope Process Bypass -Force
        .\windows-optimize.ps1

    Optional switches:
        -PowerPlan Ultimate   Use the "Ultimate Performance" plan (max speed, more heat/battery drain)
        -PowerPlan Balanced   Keep Windows' default plan (best for battery)
        -SetDns               Switch DNS to Cloudflare (1.1.1.1) + Google (8.8.8.8) for faster lookups
        -ResetNetwork         Full Winsock/TCP-IP reset (fixes broken networking; needs a reboot)
        -SkipRepair           Skip the slow DISM/SFC system-file repair
        -SkipUpdates          Skip Windows Update / winget app upgrades
#>
[CmdletBinding()]
param(
    [ValidateSet('High', 'Ultimate', 'Balanced')]
    [string]$PowerPlan = 'High',
    [switch]$SetDns,
    [switch]$ResetNetwork,
    [switch]$SkipRepair,
    [switch]$SkipUpdates
)

$ErrorActionPreference = 'Continue'
$LogDir = Join-Path $env:USERPROFILE 'Desktop\LaptopOptimization'
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
Start-Transcript -Path (Join-Path $LogDir "optimize-$(Get-Date -Format yyyyMMdd-HHmm).log") | Out-Null

function Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Info($msg) { Write-Host "    $msg" -ForegroundColor Gray }
function Warn($msg) { Write-Host "    ! $msg" -ForegroundColor Yellow }

function Get-FolderSizeMB($path) {
    if (-not (Test-Path $path)) { return 0 }
    $sum = (Get-ChildItem $path -Recurse -Force -ErrorAction SilentlyContinue |
            Measure-Object -Property Length -Sum).Sum
    return [math]::Round(($sum / 1MB), 1)
}

function Clear-Folder($path) {
    if (Test-Path $path) {
        Get-ChildItem $path -Force -ErrorAction SilentlyContinue |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# --- 0. Pre-flight -----------------------------------------------------------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host 'Please right-click PowerShell and choose "Run as administrator", then run this again.' -ForegroundColor Red
    Stop-Transcript | Out-Null
    exit 1
}

Step 'System snapshot (before)'
$os  = Get-CimInstance Win32_OperatingSystem
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$gpu = Get-CimInstance Win32_VideoController
$sysDrive = Get-PSDrive -Name ($env:SystemDrive.TrimEnd(':'))
$freeBeforeGB = [math]::Round($sysDrive.Free / 1GB, 1)
Info "OS:   $($os.Caption) build $($os.BuildNumber)"
Info "CPU:  $($cpu.Name.Trim()) ($($cpu.NumberOfCores) cores / $($cpu.NumberOfLogicalProcessors) threads)"
Info "RAM:  $([math]::Round($os.TotalVisibleMemorySize / 1MB, 1)) GB"
$gpu | ForEach-Object { Info "GPU:  $($_.Name)  (driver $($_.DriverVersion), $($_.DriverDate))" }
Info "Free space on $($env:SystemDrive): $freeBeforeGB GB"
if ($os.Caption -match 'Windows 10') {
    Warn 'Windows 10 is past end of support. Upgrade to Windows 11 if this laptop qualifies (see README).'
}

Step 'Creating a System Restore point (your undo button)'
try {
    Enable-ComputerRestore -Drive "$($env:SystemDrive)\" -ErrorAction SilentlyContinue
    Checkpoint-Computer -Description 'Before laptop optimization' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
    Info 'Restore point created.'
} catch {
    Warn "Could not create restore point ($($_.Exception.Message)). Windows only allows one per 24h - continuing."
}

# --- 1. Junk / cache clean-up ------------------------------------------------
Step 'Cleaning temporary files and caches'
$targets = @(
    "$env:TEMP",
    "$env:WINDIR\Temp",
    "$env:LOCALAPPDATA\CrashDumps",
    "$env:LOCALAPPDATA\Microsoft\Windows\INetCache",
    "$env:LOCALAPPDATA\D3DSCache",                # DirectX shader cache (rebuilds automatically)
    "$env:LOCALAPPDATA\NVIDIA\DXCache",
    "$env:LOCALAPPDATA\NVIDIA\GLCache",
    "$env:LOCALAPPDATA\AMD\DxCache",
    "$env:ProgramData\Microsoft\Windows\WER\ReportArchive",
    "$env:ProgramData\Microsoft\Windows\WER\ReportQueue"
)
foreach ($t in $targets) {
    $mb = Get-FolderSizeMB $t
    if ($mb -gt 0) { Clear-Folder $t; Info ("{0,8} MB  {1}" -f $mb, $t) }
}

# Browser caches only (NOT cookies, logins, history or bookmarks). Skipped if the browser is open.
$browsers = @{
    'chrome'  = @("$env:LOCALAPPDATA\Google\Chrome\User Data")
    'msedge'  = @("$env:LOCALAPPDATA\Microsoft\Edge\User Data")
    'brave'   = @("$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data")
    'firefox' = @("$env:LOCALAPPDATA\Mozilla\Firefox\Profiles")
}
foreach ($b in $browsers.Keys) {
    if (Get-Process -Name $b -ErrorAction SilentlyContinue) {
        Warn "$b is open - close it and re-run to clear its cache."
        continue
    }
    foreach ($root in $browsers[$b]) {
        if (-not (Test-Path $root)) { continue }
        Get-ChildItem $root -Directory -Recurse -Depth 2 -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -in @('Cache', 'Code Cache', 'GPUCache', 'cache2', 'ShaderCache', 'GrShaderCache') } |
            ForEach-Object {
                $mb = Get-FolderSizeMB $_.FullName
                Clear-Folder $_.FullName
                if ($mb -gt 0) { Info ("{0,8} MB  {1} cache" -f $mb, $b) }
            }
    }
}

# Windows Update download cache
Stop-Service wuauserv, bits -Force -ErrorAction SilentlyContinue
$mb = Get-FolderSizeMB "$env:WINDIR\SoftwareDistribution\Download"
Clear-Folder "$env:WINDIR\SoftwareDistribution\Download"
Info ("{0,8} MB  Windows Update download cache" -f $mb)
Start-Service wuauserv, bits -ErrorAction SilentlyContinue

# Delivery Optimization cache
try { Delete-DeliveryOptimizationCache -Force -ErrorAction Stop; Info 'Delivery Optimization cache cleared.' } catch {}

Clear-RecycleBin -Force -ErrorAction SilentlyContinue
Info 'Recycle Bin emptied.'

# Built-in Disk Cleanup with the safe categories pre-selected
$vc = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches'
$cats = 'Temporary Files', 'Temporary Setup Files', 'Old ChkDsk Files', 'Setup Log Files',
        'Windows Error Reporting Files', 'Thumbnail Cache', 'Update Cleanup',
        'Delivery Optimization Files', 'Device Driver Packages', 'Windows Upgrade Log Files'
foreach ($c in $cats) {
    if (Test-Path "$vc\$c") { Set-ItemProperty "$vc\$c" -Name StateFlags0777 -Value 2 -Type DWord -ErrorAction SilentlyContinue }
}
Info 'Running Disk Cleanup (can take a few minutes)...'
Start-Process cleanmgr.exe -ArgumentList '/sagerun:777' -Wait -WindowStyle Hidden

# --- 2. Repair Windows system files -----------------------------------------
if (-not $SkipRepair) {
    Step 'Repairing Windows system files (DISM + SFC, 10-30 minutes)'
    DISM /Online /Cleanup-Image /RestoreHealth
    sfc /scannow
    DISM /Online /Cleanup-Image /StartComponentCleanup
}

# --- 3. Storage --------------------------------------------------------------
Step 'Optimising drives (TRIM for SSDs, defrag only for hard disks)'
Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' } | ForEach-Object {
    Info "Optimising $($_.DriveLetter):"
    Optimize-Volume -DriveLetter $_.DriveLetter -ErrorAction SilentlyContinue
}
Info 'Drive health:'
Get-PhysicalDisk | ForEach-Object {
    Info ("{0} [{1}] health={2} status={3}" -f $_.FriendlyName, $_.MediaType, $_.HealthStatus, $_.OperationalStatus)
    if ($_.MediaType -eq 'HDD') { Warn 'This is a spinning hard disk. Swapping to an NVMe/SATA SSD is the biggest speed upgrade you can make.' }
}

# --- 4. CPU / power ----------------------------------------------------------
Step "Power plan: $PowerPlan"
switch ($PowerPlan) {
    'Ultimate' {
        $out = powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2>$null
        if ($out -match '([0-9a-f\-]{36})') { powercfg -setactive $Matches[1]; Info 'Ultimate Performance active.' }
        else { powercfg -setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c; Warn 'Ultimate not available on this edition; using High performance.' }
    }
    'High'     { powercfg -setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>$null; Info 'High performance active.' }
    'Balanced' { powercfg -setactive 381b4222-f694-41f0-9685-ff5bb260df02; Info 'Balanced active.' }
}
# When plugged in: CPU allowed to 100%, never throttled by the plan
powercfg -setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX 100
powercfg -setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 5
powercfg -setactive SCHEME_CURRENT
Info 'Tip: always edit / render while plugged in - laptops cut CPU and GPU power on battery.'

# Visual effects: keep smooth fonts and thumbnails, drop the animations
Set-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' -Name VisualFXSetting -Value 3 -Type DWord -ErrorAction SilentlyContinue
Set-ItemProperty 'HKCU:\Control Panel\Desktop' -Name MenuShowDelay -Value '50' -ErrorAction SilentlyContinue
Set-ItemProperty 'HKCU:\Control Panel\Desktop\WindowMetrics' -Name MinAnimate -Value '0' -ErrorAction SilentlyContinue
Info 'Window animations reduced; font smoothing and thumbnails kept.'

# --- 5. GPU ------------------------------------------------------------------
Step 'GPU tuning'
# Hardware-accelerated GPU scheduling (Windows 10 2004+ with a supported driver; takes effect after reboot)
New-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Name HwSchMode -Value 2 -PropertyType DWord -Force | Out-Null
Info 'Hardware-accelerated GPU scheduling: ON (after reboot).'
# Game Mode helps any GPU-heavy foreground app
New-Item 'HKCU:\Software\Microsoft\GameBar' -Force | Out-Null
Set-ItemProperty 'HKCU:\Software\Microsoft\GameBar' -Name AutoGameModeEnabled -Value 1 -Type DWord
Info 'Game Mode: ON.'

# Force creative apps onto the dedicated (high-performance) GPU on dual-GPU laptops
$gpuPrefKey = 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences'
New-Item $gpuPrefKey -Force | Out-Null
$appPatterns = @(
    "$env:ProgramFiles\Adobe\*\Adobe Premiere Pro.exe",
    "$env:ProgramFiles\Adobe\*\AfterFX.exe",
    "$env:ProgramFiles\Adobe\*\Adobe Media Encoder.exe",
    "$env:ProgramFiles\Adobe\*\Photoshop.exe",
    "$env:ProgramFiles\Adobe\*\Lightroom.exe",
    "$env:ProgramFiles\Blackmagic Design\DaVinci Resolve\Resolve.exe",
    "$env:ProgramFiles\Blender Foundation\*\blender.exe",
    "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
    "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
)
foreach ($p in $appPatterns) {
    Get-Item $p -ErrorAction SilentlyContinue | ForEach-Object {
        Set-ItemProperty $gpuPrefKey -Name $_.FullName -Value 'GpuPreference=2;'
        Info "High-performance GPU -> $($_.Name)"
    }
}
$gpu | ForEach-Object {
    if ($_.Name -match 'NVIDIA') { Warn 'NVIDIA: install the latest *Studio* driver via the NVIDIA App (more stable for Premiere/Resolve).' }
    if ($_.Name -match 'AMD|Radeon') { Warn 'AMD: install the latest Adrenalin driver from amd.com/support.' }
    if ($_.Name -match 'Intel') { Info 'Intel graphics: update with Intel Driver & Support Assistant.' }
}

# --- 6. Internet / network ---------------------------------------------------
Step 'Network tuning'
ipconfig /flushdns | Out-Null
Info 'DNS cache flushed.'
netsh int tcp set global autotuninglevel=normal | Out-Null
netsh int tcp set global rss=enabled | Out-Null
Info 'TCP receive auto-tuning and RSS set to optimal defaults.'

# Stop Windows sharing your upload bandwidth with strangers for updates
New-Item 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' -Force | Out-Null
Set-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' -Name DODownloadMode -Value 1 -Type DWord
Info 'Delivery Optimization limited to your local network.'

# Wi-Fi adapter power saving off (fewer drops / lag spikes)
Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object Status -eq 'Up' | ForEach-Object {
    try {
        $pm = Get-NetAdapterPowerManagement -Name $_.Name -ErrorAction Stop
        if ($pm.AllowComputerToTurnOffDevice -ne 'Unsupported') {
            $pm.AllowComputerToTurnOffDevice = 'Disabled'
            $pm | Set-NetAdapterPowerManagement -ErrorAction Stop
            Info "Power saving off for adapter: $($_.Name) ($($_.LinkSpeed))"
        }
    } catch {}
}
powercfg -setacvalueindex SCHEME_CURRENT 19cbb8fa-5279-450e-9fac-8a3d5fedd0c1 12bbebe6-58d6-4636-95bb-3217ef867c1a 0 2>$null
powercfg -setactive SCHEME_CURRENT

if ($SetDns) {
    Get-NetAdapter -Physical | Where-Object Status -eq 'Up' | ForEach-Object {
        Set-DnsClientServerAddress -InterfaceIndex $_.ifIndex -ServerAddresses ('1.1.1.1', '8.8.8.8', '1.0.0.1', '8.8.4.4')
        Info "DNS set to Cloudflare + Google on $($_.Name)"
    }
}
if ($ResetNetwork) {
    netsh winsock reset | Out-Null
    netsh int ip reset | Out-Null
    Warn 'Network stack reset - reboot required. You may need to re-enter your Wi-Fi password.'
}

# --- 7. Background noise -----------------------------------------------------
Step 'Reducing background clutter'
$cdm = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
foreach ($v in 'SilentInstalledAppsEnabled', 'SubscribedContent-338388Enabled', 'SubscribedContent-338389Enabled',
               'SubscribedContent-353694Enabled', 'SubscribedContent-353696Enabled', 'SystemPaneSuggestionsEnabled',
               'SoftLandingEnabled') {
    Set-ItemProperty $cdm -Name $v -Value 0 -Type DWord -ErrorAction SilentlyContinue
}
New-Item 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' -Force | Out-Null
Set-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' -Name Enabled -Value 0 -Type DWord
Info 'Suggested-app auto-installs, tips and advertising ID turned off.'

Info 'Programs that launch at startup (disable the ones you do not need in Task Manager > Startup apps):'
Get-CimInstance Win32_StartupCommand | Sort-Object Name | ForEach-Object { Info "  - $($_.Name)" }

Info 'Top 10 memory users right now:'
Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 10 | ForEach-Object {
    Info ("  {0,-30} {1,6} MB" -f $_.ProcessName, [math]::Round($_.WorkingSet64 / 1MB))
}

# --- 8. Updates --------------------------------------------------------------
if (-not $SkipUpdates) {
    Step 'Updating apps and Windows'
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        winget source update
        winget upgrade --all --silent --accept-source-agreements --accept-package-agreements --include-unknown
    } else {
        Warn 'winget not found - install "App Installer" from the Microsoft Store to enable one-click app updates.'
    }
    Start-Process 'UsoClient.exe' -ArgumentList 'StartInteractiveScan' -ErrorAction SilentlyContinue
    Info 'Windows Update scan started - finish it in Settings > Windows Update (include optional driver updates).'
}

Step 'Security: Defender quick scan'
try { Update-MpSignature -ErrorAction Stop; Start-MpScan -ScanType QuickScan -ErrorAction Stop; Info 'No action needed unless Windows Security reports threats.' }
catch { Warn 'Defender not available (a third-party antivirus may be installed).' }

# --- 9. Reports --------------------------------------------------------------
Step 'Writing health reports to your Desktop\LaptopOptimization folder'
powercfg /batteryreport /output (Join-Path $LogDir 'battery-report.html') | Out-Null
Info 'battery-report.html - compare "Full charge capacity" to "Design capacity". Below ~70% = replace the battery.'
powercfg /energy /duration 20 /output (Join-Path $LogDir 'energy-report.html') | Out-Null
Info 'energy-report.html - lists drivers/devices wasting power.'

$sysDrive = Get-PSDrive -Name ($env:SystemDrive.TrimEnd(':'))
$freeAfterGB = [math]::Round($sysDrive.Free / 1GB, 1)
Step 'Done'
Info "Free space: $freeBeforeGB GB -> $freeAfterGB GB (+$([math]::Round($freeAfterGB - $freeBeforeGB, 1)) GB)"
Warn 'RESTART the laptop now so the GPU, network and power changes take effect.'
Stop-Transcript | Out-Null
