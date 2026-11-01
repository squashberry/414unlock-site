# Build script to generate 414Unlock Windows release and installer bundle
param(
    [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"

$ProjectRoot = Resolve-Path "$PSScriptRoot\.."
$IPhoneAppDir = "$ProjectRoot\apps\unlock_iphone"
$ReleaseDir = "$IPhoneAppDir\build\windows\x64\runner\Release"
$OutputDir = "$ProjectRoot\build\installer"

Write-Host ">>> 414Unlock Installer Build Pipeline <<<" -ForegroundColor Cyan

# 1. Compile Flutter Windows Release if needed
if (-not $SkipBuild) {
    Write-Host "Building Windows Release binary..." -ForegroundColor Yellow
    Push-Location $IPhoneAppDir
    try {
        flutter build windows --release
    } finally {
        Pop-Location
    }
}

if (-not (Test-Path "$ReleaseDir\414Unlock.exe")) {
    Write-Error "Release executable not found at: $ReleaseDir\414Unlock.exe"
    exit 1
}

# 2. Ensure output directory exists
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

# 3. Check for Inno Setup compiler
$isccCandidates = @(
    "iscc.exe",
    "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
    "$env:LOCALAPPDATA\Programs\Inno Setup 7\ISCC.exe",
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "${env:ProgramFiles}\Inno Setup 6\ISCC.exe"
)

$isccPath = $null
foreach ($candidate in $isccCandidates) {
    if (Get-Command $candidate -ErrorAction SilentlyContinue) {
        $isccPath = $candidate
        break
    }
    if (Test-Path $candidate) {
        $isccPath = $candidate
        break
    }
}

if ($isccPath) {
    Write-Host "Found Inno Setup compiler: $isccPath" -ForegroundColor Green
    Write-Host "Compiling installer: 414Unlock_Setup.exe ..." -ForegroundColor Yellow
    & $isccPath "$PSScriptRoot\414unlock_setup.iss"
    Write-Host "Inno Setup installer created at: $OutputDir\414Unlock_Setup.exe" -ForegroundColor Green
} else {
    Write-Host "Inno Setup compiler (ISCC.exe) not found; packaging native distribution bundle..." -ForegroundColor Yellow
}

# 4. Package standalone ZIP distribution
$ZipPath = "$OutputDir\414Unlock_Windows_Portable.zip"
Write-Host "Creating standalone ZIP bundle: $ZipPath ..." -ForegroundColor Yellow
Compress-Archive -Path "$ReleaseDir\*" -DestinationPath $ZipPath -Force

Write-Host ""
Write-Host "Installer assets ready in: $OutputDir" -ForegroundColor Green
Get-ChildItem -Path $OutputDir | Select-Object Name, Length, LastWriteTime | Format-Table -AutoSize
