# Windows Laptop Optimization Toolkit

A single script, `windows-optimize.ps1`, that cleans up and tunes a Windows 10/11 laptop for speed, fast internet and GPU-heavy creative work (Premiere, Resolve, After Effects, Photoshop, Lightroom).

## How to run

1. Copy `windows-optimize.ps1` to the laptop (for example, to your Desktop).
2. Click Start, type **PowerShell**, right-click it and choose **Run as administrator**.
3. Run:
   ```powershell
   cd $env:USERPROFILE\Desktop
   Set-ExecutionPolicy -Scope Process Bypass -Force
   .\windows-optimize.ps1
   ```
4. **Restart** when it finishes. A full run takes 20–45 minutes, mostly the system-file repair.

### Options

| Switch | What it does |
|---|---|
| `-PowerPlan Ultimate` | Maximum-performance power plan (more heat and battery drain) |
| `-PowerPlan Balanced` | Keep the default plan (best battery life) |
| `-SetDns` | Use Cloudflare/Google DNS (often faster page loads) |
| `-ResetNetwork` | Full network stack reset. Only use it if the internet is broken or flaky. |
| `-SkipRepair` | Skip the slow DISM/SFC repair |
| `-SkipUpdates` | Skip Windows Update and winget app upgrades |

Example: `.\windows-optimize.ps1 -PowerPlan Ultimate -SetDns`

## What it does

- **Safety first:** creates a System Restore point. It never touches passwords, cookies, documents or media, and never disables Defender, the firewall or Windows Update.
- **Clean-up:** temp files, crash dumps, GPU shader caches, browser caches (not logins), the Windows Update cache, the Recycle Bin and Disk Cleanup.
- **Repair:** `DISM /RestoreHealth`, `sfc /scannow` and component-store cleanup.
- **Storage:** TRIM for SSDs and a drive-health check.
- **CPU/power:** High or Ultimate performance plan, full CPU when plugged in, fewer UI animations.
- **GPU:** hardware-accelerated GPU scheduling and Game Mode, and it moves installed creative apps and browsers onto the dedicated GPU.
- **Internet:** DNS flush, TCP auto-tuning, Wi-Fi power saving off, and it stops update uploads to strangers (optional DNS switch).
- **Background:** turns off suggested-app installs, tips and the ad ID, and lists startup apps and top memory users.
- **Updates:** runs `winget upgrade --all`, starts a Windows Update scan and a Defender quick scan.
- **Reports:** writes battery and energy reports plus a full log to `Desktop\LaptopOptimization`.

To undo: Start → type **Create a restore point** → **System Restore** → choose *"Before laptop optimization"*.

## Do these by hand (a script can't)

1. **Graphics driver:** NVIDIA → install the **Studio** driver via the NVIDIA App. AMD → Adrenalin from amd.com. Intel → Intel Driver & Support Assistant.
2. **BIOS/firmware and chipset:** get them from the laptop maker's support page (Dell SupportAssist, Lenovo Vantage, HP Support Assistant, ASUS MyASUS).
3. **Windows 11:** Windows 10 is out of support. Check Settings → Windows Update. If the laptop qualifies, upgrade.
4. **Startup apps:** Task Manager → *Startup apps* → disable anything you don't need at boot.
5. **Uninstall bloat:** Settings → Apps → remove trial antivirus, OEM extras you don't use and old toolbars.
6. **Browser:** keep one browser, turn on *Use graphics acceleration*, remove unused extensions, and enable Memory Saver / Sleeping tabs.
7. **Internet:** sit near the router and use 5 GHz or 6 GHz Wi-Fi, or plug in Ethernet for big uploads. Restart the router, and test at speed.cloudflare.com.
8. **Premiere/Resolve:** put the media cache on the fastest SSD, use proxies for 4K+ footage and set the GPU as the render engine (CUDA/OpenCL/Metal).

## Hardware upgrades that make the biggest difference

Software tuning only frees up what the hardware already has. To get close to a *2027-level* machine, these have the most impact, in order:

1. **Hard disk → NVMe SSD** (if `Drive health` shows `HDD`). This is the single biggest jump.
2. **RAM to 16–32 GB** if it's upgradeable (8 GB is the bottleneck for 4K editing).
3. **Clean the fans and replace the thermal paste.** Dusty laptops throttle the CPU and GPU hard.
4. **New battery** if `battery-report.html` shows full charge capacity below ~70% of design capacity.
5. **Wi-Fi 6E/7 card** (M.2 swap) if the router supports it.
