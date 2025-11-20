# WireGuard Split Tunnel - Client Installation for Windows
# Requires administrator privileges
# Usage: .\install.ps1 [config.conf] or .\install.ps1 -server IP -user USER -client CLIENT_NAME

param(
    [string]$ConfigFile = "",
    [string]$Server = "",
    [string]$User = "",
    [string]$Client = "",
    [string]$AllowedIPs = ""
)

Write-Host "╔═══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║        WireGuard Split Tunnel - Client Installer        ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Check for administrator privileges
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "⚠ Administrator privileges required!" -ForegroundColor Red
    Write-Host ""
    Write-Host "How to run:" -ForegroundColor Yellow
    Write-Host "1. Press Win + X" -ForegroundColor White
    Write-Host "2. Select 'Windows PowerShell (Admin)' or 'Terminal (Admin)'" -ForegroundColor White
    Write-Host "3. Run the script again" -ForegroundColor White
    Write-Host ""
    Read-Host "Press Enter to exit"
    exit 1
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptDir

# Function to read INI file
function Get-IniContent {
    param([string]$FilePath)
    $ini = @{}
    if (Test-Path $FilePath) {
        $section = ""
        Get-Content $FilePath | ForEach-Object {
            if ($_ -match "^\[(.+)\]$") {
                $section = $matches[1]
                $ini[$section] = @{}
            } elseif ($_ -match "^(.+?)\s*=\s*(.+)$") {
                $key = $matches[1].Trim()
                $value = $matches[2].Trim()
                if ($section) {
                    $ini[$section][$key] = $value
                } else {
                    $ini[$key] = $value
                }
            }
        }
    }
    return $ini
}

# Load server configuration
$serverConfig = @{}
$configIniPath = Join-Path $scriptDir "server-config.ini"
if (Test-Path $configIniPath) {
    $iniContent = Get-IniContent $configIniPath
    if ($iniContent.ContainsKey("server")) {
        $serverConfig = $iniContent["server"]
    }
    if ($iniContent.ContainsKey("client")) {
        $clientConfig = $iniContent["client"]
    }
}

# Get server settings from parameters, config file, or environment
$serverIP = $Server
if ([string]::IsNullOrWhiteSpace($serverIP)) {
    $serverIP = $serverConfig["ip"]
    if ([string]::IsNullOrWhiteSpace($serverIP)) {
        $serverIP = $env:WG_SERVER_IP
    }
}

$serverUser = $User
if ([string]::IsNullOrWhiteSpace($serverUser)) {
    $serverUser = $serverConfig["user"]
    if ([string]::IsNullOrWhiteSpace($serverUser)) {
        $serverUser = $env:WG_SERVER_USER
        if ([string]::IsNullOrWhiteSpace($serverUser)) {
            $serverUser = "root"
        }
    }
}

$clientName = $Client
if ([string]::IsNullOrWhiteSpace($clientName)) {
    $clientName = $clientConfig["name"]
    if ([string]::IsNullOrWhiteSpace($clientName)) {
        $clientName = $env:WG_CLIENT_NAME
        if ([string]::IsNullOrWhiteSpace($clientName)) {
            $clientName = "windows-client"
        }
    }
}

$allowedIPsConfig = $AllowedIPs
if ([string]::IsNullOrWhiteSpace($allowedIPsConfig)) {
    $allowedIPsConfig = $clientConfig["allowed_ips"]
    if ([string]::IsNullOrWhiteSpace($allowedIPsConfig)) {
        $allowedIPsConfig = $env:WG_ALLOWED_IPS
    }
}

# Auto-find or download configuration file
$configFile = $ConfigFile

if ([string]::IsNullOrWhiteSpace($configFile)) {
    # Try to find existing .conf files
    $confFiles = Get-ChildItem -Path . -Filter "*.conf" -File | Where-Object { $_.Name -ne "client.conf.template" }
    
    if ($confFiles.Count -eq 1) {
        $configFile = $confFiles[0].FullName
        Write-Host "✓ Config found: $($confFiles[0].Name)" -ForegroundColor Green
    } elseif ($confFiles.Count -gt 1) {
        Write-Host "Multiple config files found:" -ForegroundColor Yellow
        for ($i = 0; $i -lt $confFiles.Count; $i++) {
            Write-Host "  $($i+1). $($confFiles[$i].Name)" -ForegroundColor White
        }
        $choice = Read-Host "Select number (1-$($confFiles.Count))"
        if ($choice -match '^\d+$' -and [int]$choice -ge 1 -and [int]$choice -le $confFiles.Count) {
            $configFile = $confFiles[[int]$choice - 1].FullName
        } else {
            Write-Host "❌ Invalid choice" -ForegroundColor Red
            exit 1
        }
    } elseif (Test-Path "client.conf") {
        $configFile = "client.conf"
    } else {
        # Try to download from server
        if (-not [string]::IsNullOrWhiteSpace($serverIP)) {
            Write-Host "Config not found locally. Attempting to download from server..." -ForegroundColor Cyan
            Write-Host ""
            
            $remoteConfigPath = "/etc/wireguard/clients/${clientName}.conf"
            $localConfigPath = "${clientName}.conf"
            
            # Try SCP
            $scpSuccess = $false
            if (Get-Command scp -ErrorAction SilentlyContinue) {
                Write-Host "Downloading via SCP..." -ForegroundColor Cyan
                try {
                    $scpCommand = "scp"
                    if ($serverConfig.ContainsKey("ssh_key")) {
                        $scpCommand += " -i `"$($serverConfig['ssh_key'])`""
                    }
                    $scpCommand += " ${serverUser}@${serverIP}:${remoteConfigPath} `"${localConfigPath}`""
                    Invoke-Expression $scpCommand
                    if (Test-Path $localConfigPath) {
                        $configFile = $localConfigPath
                        $scpSuccess = $true
                        Write-Host "✓ Config downloaded: $localConfigPath" -ForegroundColor Green
                    }
                } catch {
                    Write-Host "⚠ SCP failed: $_" -ForegroundColor Yellow
                }
            }
            
            # If SCP failed, try to create config via Ansible
            if (-not $scpSuccess) {
                $ansiblePath = Join-Path $scriptDir "ansible"
                if (Test-Path (Join-Path $ansiblePath "generate-client.yml")) {
                    Write-Host ""
                    Write-Host "Config not found on server. Creating via Ansible..." -ForegroundColor Cyan
                    
                    if ([string]::IsNullOrWhiteSpace($allowedIPsConfig)) {
                        Write-Host ""
                        Write-Host "Enter IP addresses to route through VPN:" -ForegroundColor Yellow
                        Write-Host "Example: 192.168.1.100/32,10.0.0.50/32" -ForegroundColor Gray
                        $allowedIPsConfig = Read-Host "AllowedIPs"
                    }
                    
                    if (-not [string]::IsNullOrWhiteSpace($allowedIPsConfig)) {
                        Push-Location $ansiblePath
                        try {
                            $ansibleCmd = "ansible-playbook -i inventory.yml generate-client.yml -e `"client_name=${clientName}`" -e `"allowed_ips=${allowedIPsConfig}`""
                            Invoke-Expression $ansibleCmd
                            
                            # Try to download again
                            Start-Sleep -Seconds 2
                            if (Get-Command scp -ErrorAction SilentlyContinue) {
                                $scpCommand = "scp"
                                if ($serverConfig.ContainsKey("ssh_key")) {
                                    $scpCommand += " -i `"$($serverConfig['ssh_key'])`""
                                }
                                $scpCommand += " ${serverUser}@${serverIP}:${remoteConfigPath} `"../${localConfigPath}`""
                                Invoke-Expression $scpCommand
                                if (Test-Path "../${localConfigPath}") {
                                    Move-Item "../${localConfigPath}" $localConfigPath -Force
                                    $configFile = $localConfigPath
                                    Write-Host "✓ Config created and downloaded" -ForegroundColor Green
                                }
                            }
                        } catch {
                            Write-Host "⚠ Ansible not available or error occurred: $_" -ForegroundColor Yellow
                        } finally {
                            Pop-Location
                        }
                    }
                }
                
                # If still no config, ask user
                if ([string]::IsNullOrWhiteSpace($configFile) -or -not (Test-Path $configFile)) {
                    Write-Host ""
                    Write-Host "❌ Failed to get config automatically" -ForegroundColor Red
                    Write-Host ""
                    Write-Host "Options:" -ForegroundColor Yellow
                    Write-Host "1. Place .conf file in this folder" -ForegroundColor White
                    Write-Host "2. Specify path: .\install.ps1 path\to\config.conf" -ForegroundColor White
                    Write-Host "3. Create server-config.ini with server settings" -ForegroundColor White
                    Write-Host ""
                    Read-Host "Press Enter to exit"
                    exit 1
                }
            }
        } else {
            Write-Host "❌ Config not found!" -ForegroundColor Red
            Write-Host ""
            Write-Host "Options:" -ForegroundColor Yellow
            Write-Host "1. Place .conf file in this folder" -ForegroundColor White
            Write-Host "2. Specify path: .\install.ps1 path\to\config.conf" -ForegroundColor White
            Write-Host "3. Create server-config.ini with server settings" -ForegroundColor White
            Write-Host "4. Use parameters: .\install.ps1 -Server IP -User USER -Client NAME" -ForegroundColor White
            Write-Host ""
            Read-Host "Press Enter to exit"
            exit 1
        }
    }
}

if (-not (Test-Path $configFile)) {
    Write-Host "❌ Config file not found: $configFile" -ForegroundColor Red
    exit 1
}

Write-Host "Using config: $(Split-Path -Leaf $configFile)" -ForegroundColor Cyan
Write-Host ""

# Validate and fix config
$configContent = Get-Content $configFile -Raw -Encoding UTF8
$needsFix = $false

# Check Endpoint
if ($configContent -match "Endpoint\s*=\s*(.+?)(\r?\n|$)") {
    $endpoint = $matches[1].Trim()
    if ($endpoint -match "YOUR_SERVER_IP|SERVER_IP|:\['" -or $endpoint -match "^:\d+" -or $endpoint -notmatch "^\d+\.\d+\.\d+\.\d+:\d+$") {
        Write-Host "⚠ Endpoint is incorrect: $endpoint" -ForegroundColor Yellow
        if ([string]::IsNullOrWhiteSpace($serverIP)) {
            $serverIP = Read-Host "Enter server IP address"
        }
        $port = "51820"
        if ($serverConfig.ContainsKey("port")) {
            $port = $serverConfig["port"]
        }
        $configContent = $configContent -replace "Endpoint\s*=.*", "Endpoint = ${serverIP}:${port}"
        $needsFix = $true
    }
}

# Check AllowedIPs
if ($configContent -match "AllowedIPs\s*=\s*$" -or $configContent -match "AllowedIPs\s*=\s*#") {
    Write-Host "⚠ AllowedIPs is empty!" -ForegroundColor Yellow
    if ([string]::IsNullOrWhiteSpace($allowedIPsConfig)) {
        Write-Host "Enter IP addresses to route through VPN (comma-separated):" -ForegroundColor Cyan
        Write-Host "Example: 192.168.1.100/32,10.0.0.50/32" -ForegroundColor Gray
        $allowedIPsConfig = Read-Host "AllowedIPs"
    }
    if (-not [string]::IsNullOrWhiteSpace($allowedIPsConfig)) {
        $configContent = $configContent -replace "AllowedIPs\s*=.*", "AllowedIPs = $allowedIPsConfig"
        $needsFix = $true
    }
}

# Save fixed config
if ($needsFix) {
    $configContent | Out-File -FilePath $configFile -Encoding UTF8 -NoNewline
    Write-Host "✓ Config updated" -ForegroundColor Green
    Write-Host ""
}

# Install WireGuard GUI
Write-Host "Installing WireGuard..." -ForegroundColor Cyan
$wgGuiPath = "$env:ProgramFiles\WireGuard\wireguard.exe"
$wgInstalled = Test-Path $wgGuiPath

if (-not $wgInstalled) {
    # Try winget first
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Host "Installing via winget..." -ForegroundColor Cyan
        $wingetResult = winget install --id WireGuard.WireGuard -e --accept-package-agreements --accept-source-agreements --silent 2>&1
        Start-Sleep -Seconds 3
    } else {
        # Try chocolatey
        if (Get-Command choco -ErrorAction SilentlyContinue) {
            Write-Host "Installing via Chocolatey..." -ForegroundColor Cyan
            choco install wireguard -y
            Start-Sleep -Seconds 3
        } else {
            # Manual download
            Write-Host ""
            Write-Host "⚠ Automatic installation unavailable" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "Install WireGuard manually:" -ForegroundColor Cyan
            Write-Host "1. Open: https://www.wireguard.com/install/" -ForegroundColor White
            Write-Host "2. Download and install WireGuard for Windows" -ForegroundColor White
            Write-Host "3. Run this script again" -ForegroundColor White
            Write-Host ""
            $openBrowser = Read-Host "Open website in browser? (Y/N)"
            if ($openBrowser -eq "Y" -or $openBrowser -eq "y") {
                Start-Process "https://www.wireguard.com/install/"
            }
            Read-Host "Press Enter after installing WireGuard"
        }
    }
    
    # Verify installation
    Start-Sleep -Seconds 2
    $wgInstalled = Test-Path $wgGuiPath
    if (-not $wgInstalled) {
        Write-Host "❌ WireGuard not installed" -ForegroundColor Red
        Write-Host "Install WireGuard and run the script again" -ForegroundColor Yellow
        exit 1
    }
}

Write-Host "✓ WireGuard installed" -ForegroundColor Green

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

# Import config into WireGuard GUI automatically
Write-Host ""
Write-Host "Importing config into WireGuard..." -ForegroundColor Cyan

# Close WireGuard GUI if running to avoid conflicts
Get-Process -Name "wireguard" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

# Launch WireGuard GUI
Start-Process $wgGuiPath
Start-Sleep -Seconds 2

Write-Host "✓ Config ready to use" -ForegroundColor Green

Write-Host ""
Write-Host "╔═══════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║           Installation completed successfully!            ║" -ForegroundColor Green
Write-Host "╚═══════════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "📋 Config: $targetConfig" -ForegroundColor Cyan
Write-Host ""
Write-Host "📌 Next steps:" -ForegroundColor Yellow
Write-Host "1. In WireGuard window, find tunnel '$configName'" -ForegroundColor White
Write-Host "2. Click 'Activate' to connect" -ForegroundColor White
Write-Host ""
Write-Host "💡 Tunnel should appear automatically in the list" -ForegroundColor Gray
Write-Host ""
