# WireGuard Split Tunnel Client Installation (Windows)
# Requires PowerShell with administrator privileges

Write-Host "=== WireGuard Split Tunnel Client Installation (Windows) ===" -ForegroundColor Cyan
Write-Host ""

# Check for administrator privileges
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "Error: This script must be run as administrator" -ForegroundColor Red
    Write-Host "Right-click PowerShell and select 'Run as administrator'" -ForegroundColor Yellow
    exit 1
}

# Check for WireGuard GUI
$wgGuiPath = "$env:ProgramFiles\WireGuard\wireguard.exe"
$wgInstalled = Test-Path $wgGuiPath

if (-not $wgInstalled) {
    Write-Host "WireGuard GUI not found. Installing via winget..." -ForegroundColor Yellow
    
    # Try to install via winget
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Host "Installing WireGuard GUI via winget..."
        winget install --id WireGuard.WireGuard -e --accept-package-agreements --accept-source-agreements
        Start-Sleep -Seconds 3
    } else {
        Write-Host ""
        Write-Host "winget not found. Please install WireGuard GUI manually:" -ForegroundColor Yellow
        Write-Host "1. Download WireGuard from https://www.wireguard.com/install/" -ForegroundColor Yellow
        Write-Host "2. Install WireGuard (includes GUI)" -ForegroundColor Yellow
        Write-Host "3. Run this script again" -ForegroundColor Yellow
        Write-Host ""
        $continue = Read-Host "Press Enter after installing WireGuard or 'q' to exit"
        if ($continue -eq 'q') {
            exit 1
        }
    }
    
    # Check after installation
    Start-Sleep -Seconds 2
    $wgInstalled = Test-Path $wgGuiPath
    if (-not $wgInstalled) {
        Write-Host "Error: WireGuard GUI not installed. Please install manually and run the script again." -ForegroundColor Red
        exit 1
    }
}

Write-Host "✓ WireGuard GUI installed" -ForegroundColor Green
Write-Host ""

# Find configuration file
$configFile = $null
if ($args.Count -gt 0) {
    $configFile = $args[0]
} elseif (Test-Path "client.conf") {
    $configFile = "client.conf"
} elseif (Test-Path "..\config\client.conf") {
    $configFile = "..\config\client.conf"
} else {
    Write-Host "Configuration file not found."
    $configFile = Read-Host "Enter path to WireGuard config"
}

if (-not (Test-Path $configFile)) {
    Write-Host "Error: Configuration file not found: $configFile" -ForegroundColor Red
    exit 1
}

# Check for IP addresses in AllowedIPs
$configContent = Get-Content $configFile -Raw
if ($configContent -match "AllowedIPs\s*=\s*$" -or $configContent -match "AllowedIPs\s*=\s*#") {
    Write-Host ""
    Write-Host "⚠ WARNING: AllowedIPs field is empty or contains comments!" -ForegroundColor Yellow
    Write-Host "Open the file and specify IP addresses to route through VPN:" -ForegroundColor Yellow
    Write-Host "  notepad $configFile" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Example:" -ForegroundColor Yellow
    Write-Host "  AllowedIPs = 192.168.1.100/32, 10.0.0.50/32" -ForegroundColor Yellow
    Write-Host ""
    Read-Host "Press Enter after filling in AllowedIPs"
}

# Copy config to WireGuard directory
$wgConfigDir = "$env:ProgramFiles\WireGuard\Data\Configurations"
if (-not (Test-Path $wgConfigDir)) {
    New-Item -ItemType Directory -Path $wgConfigDir -Force | Out-Null
}

$configName = [System.IO.Path]::GetFileNameWithoutExtension($configFile)
$targetConfig = Join-Path $wgConfigDir "$configName.conf"
Copy-Item $configFile $targetConfig -Force

Write-Host "✓ Configuration copied to: $targetConfig" -ForegroundColor Green
Write-Host ""

# Launch WireGuard GUI
Write-Host "Launching WireGuard GUI..." -ForegroundColor Cyan
Start-Process $wgGuiPath

Write-Host ""
Write-Host "=== Installation completed ===" -ForegroundColor Green
Write-Host ""
Write-Host "WireGuard GUI should open automatically." -ForegroundColor Cyan
Write-Host "Configuration file: $targetConfig" -ForegroundColor Green
Write-Host ""
Write-Host "The configuration is ready to use - just click 'Activate' in the GUI." -ForegroundColor Yellow
Write-Host ""
Write-Host "You can also manage tunnels from the WireGuard system tray icon" -ForegroundColor Cyan
Write-Host ""

