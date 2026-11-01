# 414Unlock Windows Native Installer Script
# Conforms to APP_UPDATE_CONTRACT.md and includes pre-install update check.
param(
    [switch]$Silent,
    [switch]$NoLaunch
)

$ErrorActionPreference = "Stop"

$AppName = "414Unlock"
$AppVersion = "1.0.0"
$Endpoint = "https://414unlock-auth-api.414unlock.workers.dev/api/app/update?version=$AppVersion&platform=windows"
$SourceDir = "$PSScriptRoot\..\apps\unlock_iphone\build\windows\x64\runner\Release"

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "       414Unlock Windows Setup (v$AppVersion)     " -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# 1. Pre-installation update check
Write-Host "[1/5] Checking for installer updates..." -ForegroundColor Gray
try {
    $response = Invoke-RestMethod -Uri $Endpoint -Method Get -TimeoutSec 5 -Headers @{ "Cache-Control" = "no-store" } -ErrorAction SilentlyContinue
    if ($response -and $response.ok -eq $true -and $response.updateAvailable -eq $true) {
        $latest = $response.latestVersion
        $releaseUrl = $response.releaseUrl
        $notes = $response.releaseNotes
        Write-Host ""
        Write-Host ">>> A newer version is available: v$latest <<<" -ForegroundColor Yellow
        Write-Host "Release notes: $notes" -ForegroundColor Gray
        Write-Host ""

        if (-not $Silent) {
            $choice = Read-Host "Would you like to open the latest release page instead? (Y/N)"
            if ($choice -match "^[Yy]") {
                if ($releaseUrl -match "^https://") {
                    Start-Process $releaseUrl
                    Write-Host "Opening $releaseUrl ... Setup aborted." -ForegroundColor Green
                    exit 0
                }
            }
        }
    } else {
        Write-Host "Installer package is up to date." -ForegroundColor Green
    }
} catch {
    Write-Host "Update server unreachable; continuing with local package." -ForegroundColor Gray
}

# 2. Check source release files
if (-not (Test-Path "$SourceDir\414Unlock.exe")) {
    Write-Error "Release build not found at: $SourceDir. Please run 'flutter build windows --release' first."
    exit 1
}

# 3. Terminate running instance if any
Write-Host "[2/5] Stopping any running 414Unlock processes..." -ForegroundColor Gray
Get-Process -Name "414Unlock" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 500

# 4. Copy files to destination
$InstallDir = "$env:LOCALAPPDATA\Programs\$AppName"
Write-Host "[3/5] Installing 414Unlock to: $InstallDir ..." -ForegroundColor Gray
if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
}

Copy-Item -Path "$SourceDir\*" -Destination $InstallDir -Recurse -Force

# 5. Create Start Menu and Desktop Shortcuts
Write-Host "[4/5] Creating Start Menu & Desktop shortcuts..." -ForegroundColor Gray
$WshShell = New-Object -ComObject WScript.Shell

# Desktop shortcut
$DesktopPath = [Environment]::GetFolderPath("Desktop")
$Shortcut = $WshShell.CreateShortcut("$DesktopPath\$AppName.lnk")
$Shortcut.TargetPath = "$InstallDir\414Unlock.exe"
$Shortcut.WorkingDirectory = $InstallDir
$Shortcut.Description = "414Unlock - iPhone Device Utility"
$Shortcut.Save()

# Start Menu shortcut
$StartMenuPath = [Environment]::GetFolderPath("Programs")
$Shortcut = $WshShell.CreateShortcut("$StartMenuPath\$AppName.lnk")
$Shortcut.TargetPath = "$InstallDir\414Unlock.exe"
$Shortcut.WorkingDirectory = $InstallDir
$Shortcut.Description = "414Unlock - iPhone Device Utility"
$Shortcut.Save()

# 6. Configure auto-start in Windows system tray by default
Write-Host "[5/5] Configuring automatic startup in system tray..." -ForegroundColor Gray
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name $AppName -Value "`"$InstallDir\414Unlock.exe`" --tray" -Force

# 7. Register in Windows Add/Remove Programs
$UninstallKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\$AppName"
New-Item -Path $UninstallKey -Force | Out-Null
Set-ItemProperty -Path $UninstallKey -Name "DisplayName" -Value "414Unlock"
Set-ItemProperty -Path $UninstallKey -Name "DisplayVersion" -Value $AppVersion
Set-ItemProperty -Path $UninstallKey -Name "Publisher" -Value "414Unlock"
Set-ItemProperty -Path $UninstallKey -Name "InstallLocation" -Value $InstallDir
Set-ItemProperty -Path $UninstallKey -Name "DisplayIcon" -Value "$InstallDir\414Unlock.exe"

Write-Host ""
Write-Host "==========================================" -ForegroundColor Green
Write-Host "   414Unlock was installed successfully!   " -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green
Write-Host ""

if (-not $NoLaunch) {
    Write-Host "Launching 414Unlock..." -ForegroundColor Cyan
    Start-Process "$InstallDir\414Unlock.exe"
}
