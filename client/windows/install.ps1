# WireGuard client installation for Windows
# Requires administrator privileges

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { Write-Host "Error: Run as administrator" -ForegroundColor Red; exit 1 }

Write-Host "=== WireGuard Client Installation ===" -ForegroundColor Cyan

# Install WireGuard GUI
$wgGuiPath = "$env:ProgramFiles\WireGuard\wireguard.exe"
if (-not (Test-Path $wgGuiPath)) {
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        winget install --id WireGuard.WireGuard -e --accept-package-agreements --accept-source-agreements --silent
        Start-Sleep -Seconds 5
    } else {
        Write-Host "winget not found. Install WireGuard manually from https://www.wireguard.com/install/" -ForegroundColor Yellow
        Read-Host "Press Enter after installing"
    }
    if (-not (Test-Path $wgGuiPath)) { Write-Host "Error: WireGuard not installed" -ForegroundColor Red; exit 1 }
}

# Find config file
$configFile = if ($args.Count -gt 0) { $args[0] } elseif (Test-Path "client.conf") { "client.conf" } elseif (Test-Path "..\config\client.conf") { "..\config\client.conf" } else { Read-Host "Enter config path" }
if (-not (Test-Path $configFile)) { Write-Host "Error: Config not found: $configFile" -ForegroundColor Red; exit 1 }

# Check AllowedIPs
$configContent = Get-Content $configFile -Raw
if ($configContent -match "AllowedIPs\s*=\s*$" -or $configContent -match "AllowedIPs\s*=\s*#") {
    Write-Host "⚠ WARNING: AllowedIPs is empty!" -ForegroundColor Yellow
    Write-Host "Edit: notepad $configFile" -ForegroundColor Cyan
    Read-Host "Press Enter after editing"
}

# Copy config
$wgConfigDir = "$env:ProgramFiles\WireGuard\Data\Configurations"
New-Item -ItemType Directory -Path $wgConfigDir -Force | Out-Null
$configName = [System.IO.Path]::GetFileNameWithoutExtension($configFile)
Copy-Item $configFile "$wgConfigDir\$configName.conf" -Force

# Launch GUI
Start-Process $wgGuiPath

Write-Host ""
Write-Host "=== Installation Complete ===" -ForegroundColor Green
Write-Host "Config: $wgConfigDir\$configName.conf" -ForegroundColor Cyan
Write-Host "Click 'Activate' in WireGuard GUI" -ForegroundColor Yellow
