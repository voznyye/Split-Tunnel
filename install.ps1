# WireGuard Split Tunnel - Universal Installation for Windows
# Requires administrator privileges

Write-Host "╔═══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║     WireGuard Split Tunnel - Universal Installation     ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Check for administrator privileges
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "Error: Run PowerShell as administrator" -ForegroundColor Red
    Write-Host "Right-click PowerShell → Run as administrator" -ForegroundColor Yellow
    exit 1
}

Write-Host "For Windows, only client installation is available." -ForegroundColor Yellow
Write-Host ""

# Find configuration file
$configFile = $null
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

if ($args.Count -gt 0) {
    $configFile = $args[0]
} elseif (Test-Path "client.conf") {
    $configFile = "client.conf"
} elseif (Test-Path "config\client.conf") {
    $configFile = "config\client.conf"
} else {
    Write-Host "Configuration file not found." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Choose how to get the config:"
    Write-Host "1) I have a config file"
    Write-Host "2) Download from server (requires SSH access)"
    Write-Host "3) Create manually (need server data)"
    Write-Host ""
    $configChoice = Read-Host "Choose (1/2/3)"
    
    switch ($configChoice) {
        "1" {
            $configFile = Read-Host "Enter path to config file"
        }
        "2" {
            $serverHost = Read-Host "Enter server address (user@host)"
            $clientName = Read-Host "Enter client config name"
            Write-Host "Downloading config from server..." -ForegroundColor Cyan
            
            # Try scp (if available) or suggest manual download
            if (Get-Command scp -ErrorAction SilentlyContinue) {
                scp "$serverHost`:/etc/wireguard/clients/${clientName}.conf" ".\client.conf"
                $configFile = ".\client.conf"
            } else {
                Write-Host "scp not found. Use WinSCP or another SFTP client" -ForegroundColor Yellow
                Write-Host "Server path: /etc/wireguard/clients/${clientName}.conf" -ForegroundColor Yellow
                $configFile = Read-Host "Enter path to downloaded file"
            }
        }
        "3" {
            $clientPrivateKey = Read-Host "Enter client private key"
            $serverPublicKey = Read-Host "Enter server public key"
            $serverIP = Read-Host "Enter server IP address"
            $wgPort = Read-Host "Enter port (default 51820)"
            if ([string]::IsNullOrWhiteSpace($wgPort)) { $wgPort = "51820" }
            $clientVPNIP = Read-Host "Enter client VPN IP (e.g., 10.0.0.2)"
            $allowedIPs = Read-Host "Enter IP addresses to route through VPN"
            
            $clientDNS = "8.8.8.8"
            $clientConf = ".\client.conf"
            
            @"
[Interface]
PrivateKey = $clientPrivateKey
Address = $clientVPNIP/24
DNS = $clientDNS

[Peer]
PublicKey = $serverPublicKey
Endpoint = ${serverIP}:${wgPort}
AllowedIPs = $allowedIPs
"@ | Out-File -FilePath $clientConf -Encoding UTF8
            
            $configFile = $clientConf
            Write-Host "✓ Config created" -ForegroundColor Green
        }
        default {
            Write-Host "Invalid choice" -ForegroundColor Red
            exit 1
        }
    }
}

if (-not (Test-Path $configFile)) {
    Write-Host "Error: Config file not found: $configFile" -ForegroundColor Red
    exit 1
}

# Check for IP addresses in AllowedIPs
$configContent = Get-Content $configFile -Raw
if ($configContent -match "AllowedIPs\s*=\s*$" -or $configContent -match "AllowedIPs\s*=\s*#") {
    Write-Host ""
    Write-Host "⚠ WARNING: AllowedIPs field is empty!" -ForegroundColor Yellow
    $allowedIPs = Read-Host "Enter IP addresses to route through VPN (comma-separated)"
    if (-not [string]::IsNullOrWhiteSpace($allowedIPs)) {
        $configContent = $configContent -replace "AllowedIPs\s*=.*", "AllowedIPs = $allowedIPs"
        $configContent | Out-File -FilePath $configFile -Encoding UTF8 -NoNewline
        Write-Host "✓ AllowedIPs updated" -ForegroundColor Green
    }
}

# Install WireGuard GUI
Write-Host ""
Write-Host "Installing WireGuard GUI..." -ForegroundColor Cyan
$wgGuiPath = "$env:ProgramFiles\WireGuard\wireguard.exe"
$wgInstalled = Test-Path $wgGuiPath

if (-not $wgInstalled) {
    # Try to install via winget
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Host "Installing via winget..." -ForegroundColor Cyan
        winget install --id WireGuard.WireGuard -e --accept-package-agreements --accept-source-agreements --silent
        Start-Sleep -Seconds 5
    } else {
        Write-Host ""
        Write-Host "winget not found. Install WireGuard manually:" -ForegroundColor Yellow
        Write-Host "1. Download from https://www.wireguard.com/install/" -ForegroundColor Yellow
        Write-Host "2. Install WireGuard" -ForegroundColor Yellow
        Write-Host "3. Run this script again" -ForegroundColor Yellow
        Write-Host ""
        Read-Host "Press Enter after installing WireGuard"
    }
    
    Start-Sleep -Seconds 2
    $wgInstalled = Test-Path $wgGuiPath
    if (-not $wgInstalled) {
        Write-Host "Error: WireGuard GUI not installed" -ForegroundColor Red
        exit 1
    }
}

Write-Host "✓ WireGuard GUI installed" -ForegroundColor Green

# Copy config to WireGuard directory
Write-Host ""
Write-Host "Copying config..." -ForegroundColor Cyan
$wgConfigDir = "$env:ProgramFiles\WireGuard\Data\Configurations"
if (-not (Test-Path $wgConfigDir)) {
    New-Item -ItemType Directory -Path $wgConfigDir -Force | Out-Null
}

$configName = [System.IO.Path]::GetFileNameWithoutExtension($configFile)
$targetConfig = Join-Path $wgConfigDir "$configName.conf"
Copy-Item $configFile $targetConfig -Force

Write-Host "✓ Config copied: $targetConfig" -ForegroundColor Green

# Launch WireGuard GUI
Write-Host ""
Write-Host "Launching WireGuard GUI..." -ForegroundColor Cyan
Start-Process $wgGuiPath

Write-Host ""
Write-Host "╔═══════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║              Client installed successfully!              ║" -ForegroundColor Green
Write-Host "╚═══════════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "Config: $targetConfig" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "1. WireGuard GUI should open automatically" -ForegroundColor White
Write-Host "2. Click 'Import tunnel(s) from file' or use File menu" -ForegroundColor White
Write-Host "3. Select file: $targetConfig" -ForegroundColor White
Write-Host "4. Click 'Activate' to connect" -ForegroundColor White
Write-Host ""
Write-Host "You can also manage tunnels from the WireGuard system tray icon" -ForegroundColor Cyan
Write-Host ""
