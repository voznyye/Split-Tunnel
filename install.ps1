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

# Function to pause before exit
function Pause-BeforeExit {
    Write-Host ""
    Write-Host "Press any key to exit..." -ForegroundColor Yellow
    try {
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    } catch {
        Read-Host "Press Enter to exit" | Out-Null
    }
}

# Function to request admin privileges
function Request-AdminPrivileges {
    try {
        $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        $isAdmin = $false
    }
    
    if (-not $isAdmin) {
        Write-Host "Administrator privileges required!" -ForegroundColor Yellow
        Write-Host "Requesting administrator privileges..." -ForegroundColor Cyan
        
        try {
            $scriptPath = $null
            if ($MyInvocation.MyCommand.Path) {
                $scriptPath = $MyInvocation.MyCommand.Path
            }
            if (-not $scriptPath -and $PSCommandPath) {
                $scriptPath = $PSCommandPath
            }
            if (-not $scriptPath -or $scriptPath -like "*install-temp*") {
                try {
                    $exePath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
                    if ($exePath -and (Test-Path $exePath)) {
                        $scriptPath = $exePath
                    }
                } catch {
                    # Ignore errors
                }
            }
            if (-not $scriptPath) {
                if (Test-Path ".\install.exe") {
                    $scriptPath = ".\install.exe"
                } elseif (Test-Path ".\install.ps1") {
                    $scriptPath = ".\install.ps1"
                } else {
                    $scriptPath = $MyInvocation.MyCommand.Name
                }
            }
            
            $argList = New-Object System.Collections.ArrayList
            if ($ConfigFile) {
                $argList.Add("-ConfigFile") | Out-Null
                $argList.Add($ConfigFile) | Out-Null
            }
            if ($Server) {
                $argList.Add("-Server") | Out-Null
                $argList.Add($Server) | Out-Null
            }
            if ($User) {
                $argList.Add("-User") | Out-Null
                $argList.Add($User) | Out-Null
            }
            if ($Client) {
                $argList.Add("-Client") | Out-Null
                $argList.Add($Client) | Out-Null
            }
            if ($AllowedIPs) {
                $argList.Add("-AllowedIPs") | Out-Null
                $argList.Add($AllowedIPs) | Out-Null
            }
            
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            if ($scriptPath -like "*.exe" -and (Test-Path $scriptPath)) {
                $psi.FileName = $scriptPath
                $psi.Arguments = ($argList -join " ")
            } else {
                $psi.FileName = "powershell.exe"
                $fileArg = $scriptPath
                if ($fileArg -match '\s') {
                    $fileArg = "& '$scriptPath'"
                }
                $argString = "-ExecutionPolicy Bypass -NoProfile -File $fileArg"
                if ($argList.Count -gt 0) {
                    $argString += " " + ($argList -join " ")
                }
                $psi.Arguments = $argString
            }
            $psi.Verb = "runas"
            $psi.UseShellExecute = $true
            
            $process = [System.Diagnostics.Process]::Start($psi)
            if ($process) {
                $process.WaitForExit()
                exit $process.ExitCode
            } else {
                throw "Failed to start process"
            }
        } catch {
            Write-Host "Failed to request administrator privileges: $_" -ForegroundColor Red
            Write-Host ""
            Write-Host "Please run this script as Administrator:" -ForegroundColor Yellow
            Write-Host "1. Right-click on install.exe" -ForegroundColor White
            Write-Host "2. Select 'Run as administrator'" -ForegroundColor White
            Write-Host ""
            Pause-BeforeExit
            exit 1
        }
    }
}

# Request admin privileges first
Request-AdminPrivileges

# Set error handling after functions are defined
$ErrorActionPreference = "Continue"
$script:ErrorOccurred = $false

try {
    Write-Host "===============================================================" -ForegroundColor Cyan
    Write-Host "        WireGuard Split Tunnel - Client Installer" -ForegroundColor Cyan
    Write-Host "===============================================================" -ForegroundColor Cyan
    Write-Host ""

    # Get script directory
    $scriptDir = $null
    try {
        if ($MyInvocation.MyCommand.Path) {
            $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
        }
    } catch {
        # Ignore
    }
    
    if (-not $scriptDir -and $PSCommandPath) {
        try {
            $scriptDir = Split-Path -Parent $PSCommandPath
        } catch {
            # Ignore
        }
    }
    
    if (-not $scriptDir -or $scriptDir -like "*install-temp*") {
        try {
            $exePath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
            if ($exePath -and (Test-Path $exePath)) {
                $scriptDir = Split-Path -Parent $exePath
            }
        } catch {
            # Ignore
        }
    }
    
    if (-not $scriptDir) {
        $scriptDir = Get-Location
    }
    
    try {
        $scriptDir = [System.IO.Path]::GetFullPath($scriptDir)
        Set-Location $scriptDir -ErrorAction Stop
    } catch {
        Write-Host "Warning: Could not set working directory: $_" -ForegroundColor Yellow
    }

    # Function to read INI file
    function Get-IniContent {
        param([string]$FilePath)
        $ini = @{}
        if (Test-Path $FilePath) {
            try {
                $section = ""
                Get-Content $FilePath -ErrorAction Stop | ForEach-Object {
                    $line = $_.Trim()
                    if ($line -match '^\[(.+)\]$') {
                        $section = $matches[1]
                        $ini[$section] = @{}
                    } elseif ($line -match '^(.+?)\s*=\s*(.+)$') {
                        $key = $matches[1].Trim()
                        $value = $matches[2].Trim()
                        if ($section) {
                            $ini[$section][$key] = $value
                        } else {
                            $ini[$key] = $value
                        }
                    }
                }
            } catch {
                Write-Host "Warning: Could not read config file: $_" -ForegroundColor Yellow
            }
        }
        return $ini
    }

    # Load server configuration
    $serverConfig = @{}
    $clientConfig = @{}
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

    # Get server settings
    $serverIP = $Server
    if (-not $serverIP) {
        if ($serverConfig.ContainsKey("ip")) {
            $serverIP = $serverConfig["ip"]
        }
        if (-not $serverIP) {
            $serverIP = $env:WG_SERVER_IP
        }
    }
    
    if (-not $serverIP) {
        Write-Host "Server configuration not found." -ForegroundColor Yellow
        Write-Host ""
        $serverIP = Read-Host "Enter server IP address (or press Enter to skip and use local config file)"
    }

    $serverUser = $User
    if (-not $serverUser) {
        if ($serverConfig.ContainsKey("user")) {
            $serverUser = $serverConfig["user"]
        }
        if (-not $serverUser) {
            $serverUser = $env:WG_SERVER_USER
        }
        if (-not $serverUser) {
            $serverUser = "root"
        }
    }

    $clientName = $Client
    if (-not $clientName) {
        if ($clientConfig.ContainsKey("name")) {
            $clientName = $clientConfig["name"]
        }
        if (-not $clientName) {
            $clientName = $env:WG_CLIENT_NAME
        }
        if (-not $clientName) {
            $clientName = "windows-client"
        }
    }

    $allowedIPsConfig = $AllowedIPs
    if (-not $allowedIPsConfig) {
        if ($clientConfig.ContainsKey("allowed_ips")) {
            $allowedIPsConfig = $clientConfig["allowed_ips"]
        }
        if (-not $allowedIPsConfig) {
            $allowedIPsConfig = $env:WG_ALLOWED_IPS
        }
    }

    # Auto-find or download configuration file
    $configFile = $ConfigFile

    if (-not $configFile) {
        try {
            $confFiles = @()
            if (Test-Path ".") {
                $confFiles = Get-ChildItem -Path "." -Filter "*.conf" -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne "client.conf.template" }
            }
            
            if ($confFiles.Count -eq 1) {
                $configFile = $confFiles[0].FullName
                Write-Host "Config found: $($confFiles[0].Name)" -ForegroundColor Green
            } elseif ($confFiles.Count -gt 1) {
                Write-Host "Multiple config files found:" -ForegroundColor Yellow
                for ($i = 0; $i -lt $confFiles.Count; $i++) {
                    Write-Host "  $($i+1). $($confFiles[$i].Name)" -ForegroundColor White
                }
                $choice = Read-Host "Select number (1-$($confFiles.Count))"
                if ($choice -match '^\d+$') {
                    $idx = [int]$choice - 1
                    if ($idx -ge 0 -and $idx -lt $confFiles.Count) {
                        $configFile = $confFiles[$idx].FullName
                    } else {
                        Write-Host "Invalid choice" -ForegroundColor Red
                        throw "Invalid config file selection"
                    }
                } else {
                    Write-Host "Invalid choice" -ForegroundColor Red
                    throw "Invalid config file selection"
                }
            } elseif (Test-Path "client.conf") {
                $configFile = "client.conf"
                Write-Host "Config found: client.conf" -ForegroundColor Green
            } else {
                # Try to download from server if server IP is provided
                if ($serverIP) {
                    Write-Host "Config not found locally. Attempting to download from server..." -ForegroundColor Cyan
                    Write-Host ""
                    
                    $remoteConfigPath = "/etc/wireguard/clients/$clientName.conf"
                    $localConfigPath = "$clientName.conf"
                    
                    # Try SCP
                    $scpSuccess = $false
                    if (Get-Command scp -ErrorAction SilentlyContinue) {
                        Write-Host "Downloading via SCP..." -ForegroundColor Cyan
                        try {
                            $scpArgs = @()
                            if ($serverConfig.ContainsKey("ssh_key") -and $serverConfig["ssh_key"]) {
                                $scpArgs += "-i"
                                $scpArgs += $serverConfig["ssh_key"]
                            }
                            $scpArgs += "${serverUser}@${serverIP}:$remoteConfigPath"
                            $scpArgs += $localConfigPath
                            
                            $scpProcess = Start-Process -FilePath "scp" -ArgumentList $scpArgs -Wait -PassThru -NoNewWindow
                            if ($scpProcess.ExitCode -eq 0 -and (Test-Path $localConfigPath)) {
                                $configFile = $localConfigPath
                                $scpSuccess = $true
                                Write-Host "Config downloaded: $localConfigPath" -ForegroundColor Green
                            } else {
                                Write-Host "SCP download failed" -ForegroundColor Yellow
                            }
                        } catch {
                            Write-Host "SCP failed: $_" -ForegroundColor Yellow
                        }
                    } else {
                        Write-Host "SCP not available - skipping download" -ForegroundColor Yellow
                    }
                    
                    # If SCP failed, try to create config via Ansible
                    if (-not $scpSuccess) {
                        $ansiblePath = Join-Path $scriptDir "ansible"
                        if (Test-Path (Join-Path $ansiblePath "generate-client.yml")) {
                            Write-Host ""
                            Write-Host "Config not found on server. Creating via Ansible..." -ForegroundColor Cyan
                            
                            if (-not $allowedIPsConfig) {
                                Write-Host ""
                                Write-Host "Enter IP addresses to route through VPN:" -ForegroundColor Yellow
                                Write-Host "Example: 192.168.1.100/32,10.0.0.50/32" -ForegroundColor Gray
                                $allowedIPsConfig = Read-Host "AllowedIPs"
                            }
                            
                            if ($allowedIPsConfig) {
                                Push-Location $ansiblePath
                                try {
                                    $ansibleArgs = @("-i", "inventory.yml", "generate-client.yml", "-e", "client_name=$clientName", "-e", "allowed_ips=$allowedIPsConfig")
                                    $ansibleProcess = Start-Process -FilePath "ansible-playbook" -ArgumentList $ansibleArgs -Wait -PassThru -NoNewWindow
                                    
                                    # Try to download again
                                    Start-Sleep -Seconds 2
                                    if (Get-Command scp -ErrorAction SilentlyContinue) {
                                        $scpArgs = @()
                                        if ($serverConfig.ContainsKey("ssh_key") -and $serverConfig["ssh_key"]) {
                                            $scpArgs += "-i"
                                            $scpArgs += $serverConfig["ssh_key"]
                                        }
                                        $scpArgs += "${serverUser}@${serverIP}:$remoteConfigPath"
                                        $scpArgs += "../$localConfigPath"
                                        
                                        $scpProcess = Start-Process -FilePath "scp" -ArgumentList $scpArgs -Wait -PassThru -NoNewWindow
                                        if ($scpProcess.ExitCode -eq 0 -and (Test-Path "../$localConfigPath")) {
                                            Move-Item "../$localConfigPath" $localConfigPath -Force
                                            $configFile = $localConfigPath
                                            Write-Host "Config created and downloaded" -ForegroundColor Green
                                        }
                                    }
                                } catch {
                                    Write-Host "Ansible not available or error occurred: $_" -ForegroundColor Yellow
                                } finally {
                                    Pop-Location
                                }
                            }
                        }
                    }
                }
                
                # If still no config, ask user to provide one
                if (-not $configFile -or -not (Test-Path $configFile)) {
                    Write-Host ""
                    Write-Host "Config file not found!" -ForegroundColor Red
                    Write-Host ""
                    Write-Host "Please provide a WireGuard config file:" -ForegroundColor Yellow
                    Write-Host "1. Place a .conf file in this folder: $scriptDir" -ForegroundColor White
                    Write-Host "2. Or specify path when running: .\install.exe -ConfigFile path\to\config.conf" -ForegroundColor White
                    Write-Host ""
                    $manualPath = Read-Host "Or enter path to config file now (or press Enter to exit)"
                    if ($manualPath -and (Test-Path $manualPath)) {
                        $configFile = $manualPath
                    } else {
                        throw "Config file not found"
                    }
                }
            }
        } catch {
            Write-Host "Error finding config files: $_" -ForegroundColor Red
            throw
        }
    }

    if (-not (Test-Path $configFile)) {
        Write-Host "Config file not found: $configFile" -ForegroundColor Red
        throw "Config file not found: $configFile"
    }

    Write-Host "Using config: $(Split-Path -Leaf $configFile)" -ForegroundColor Cyan
    Write-Host ""

    # Validate and fix config
    try {
        $configContent = Get-Content $configFile -Raw -Encoding UTF8 -ErrorAction Stop
        $needsFix = $false

        # Check Endpoint
        if ($configContent -match 'Endpoint\s*=\s*(.+?)(\r?\n|$)') {
            $endpoint = $matches[1].Trim()
            if ($endpoint -match 'YOUR_SERVER_IP|SERVER_IP|:\[' -or $endpoint -match '^:\d+' -or $endpoint -notmatch '^\d+\.\d+\.\d+\.\d+:\d+$') {
                Write-Host "Endpoint is incorrect: $endpoint" -ForegroundColor Yellow
                if (-not $serverIP) {
                    $serverIP = Read-Host "Enter server IP address"
                }
                $port = "51820"
                if ($serverConfig.ContainsKey("port") -and $serverConfig["port"]) {
                    $port = $serverConfig["port"]
                }
                $endpointValue = "$serverIP`:$port"
                $configContent = $configContent -replace 'Endpoint\s*=.*', "Endpoint = $endpointValue"
                $needsFix = $true
            }
        }

        # Check AllowedIPs
        if ($configContent -match 'AllowedIPs\s*=\s*$' -or $configContent -match 'AllowedIPs\s*=\s*#') {
            Write-Host "AllowedIPs is empty!" -ForegroundColor Yellow
            if (-not $allowedIPsConfig) {
                Write-Host "Enter IP addresses to route through VPN (comma-separated):" -ForegroundColor Cyan
                Write-Host "Example: 192.168.1.100/32,10.0.0.50/32" -ForegroundColor Gray
                $allowedIPsConfig = Read-Host "AllowedIPs"
            }
            if ($allowedIPsConfig) {
                $configContent = $configContent -replace 'AllowedIPs\s*=.*', "AllowedIPs = $allowedIPsConfig"
                $needsFix = $true
            }
        }

        # Save fixed config
        if ($needsFix) {
            $configContent | Out-File -FilePath $configFile -Encoding UTF8 -NoNewline -ErrorAction Stop
            Write-Host "Config updated" -ForegroundColor Green
            Write-Host ""
        }
    } catch {
        Write-Host "Warning: Could not validate/fix config: $_" -ForegroundColor Yellow
        Write-Host "Continuing with original config..." -ForegroundColor Yellow
    }

    # Install WireGuard GUI
    Write-Host "Checking WireGuard installation..." -ForegroundColor Cyan
    $wgGuiPath = "$env:ProgramFiles\WireGuard\wireguard.exe"
    $wgInstalled = Test-Path $wgGuiPath

    if (-not $wgInstalled) {
        Write-Host "WireGuard not found. Installing..." -ForegroundColor Cyan
        
        # Try winget first
        $installSuccess = $false
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            Write-Host "Installing via winget..." -ForegroundColor Cyan
            try {
                $wingetProcess = Start-Process -FilePath "winget" -ArgumentList @("install", "--id", "WireGuard.WireGuard", "-e", "--accept-package-agreements", "--accept-source-agreements", "--silent") -Wait -PassThru -NoNewWindow
                Start-Sleep -Seconds 5
                $wgInstalled = Test-Path $wgGuiPath
                if ($wgInstalled) {
                    $installSuccess = $true
                    Write-Host "WireGuard installed via winget" -ForegroundColor Green
                }
            } catch {
                Write-Host "winget installation failed: $_" -ForegroundColor Yellow
            }
        }
        
        # Try chocolatey if winget failed
        if (-not $installSuccess -and (Get-Command choco -ErrorAction SilentlyContinue)) {
            Write-Host "Installing via Chocolatey..." -ForegroundColor Cyan
            try {
                $chocoProcess = Start-Process -FilePath "choco" -ArgumentList @("install", "wireguard", "-y") -Wait -PassThru -NoNewWindow
                Start-Sleep -Seconds 5
                $wgInstalled = Test-Path $wgGuiPath
                if ($wgInstalled) {
                    $installSuccess = $true
                    Write-Host "WireGuard installed via Chocolatey" -ForegroundColor Green
                }
            } catch {
                Write-Host "Chocolatey installation failed: $_" -ForegroundColor Yellow
            }
        }
        
        # Manual download if automatic installation failed
        if (-not $installSuccess) {
            Write-Host ""
            Write-Host "Automatic installation unavailable" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "Please install WireGuard manually:" -ForegroundColor Cyan
            Write-Host "1. Open: https://www.wireguard.com/install/" -ForegroundColor White
            Write-Host "2. Download and install WireGuard for Windows" -ForegroundColor White
            Write-Host "3. Run this script again" -ForegroundColor White
            Write-Host ""
            $openBrowser = Read-Host "Open website in browser? (Y/N)"
            if ($openBrowser -eq "Y" -or $openBrowser -eq "y") {
                try {
                    Start-Process "https://www.wireguard.com/install/"
                } catch {
                    Write-Host "Could not open browser" -ForegroundColor Yellow
                }
            }
            Read-Host "Press Enter after installing WireGuard" | Out-Null
            
            # Verify installation
            $wgInstalled = Test-Path $wgGuiPath
            if (-not $wgInstalled) {
                Write-Host "WireGuard not installed" -ForegroundColor Red
                Write-Host "Please install WireGuard and run the script again" -ForegroundColor Yellow
                throw "WireGuard not installed"
            }
        }
    } else {
        Write-Host "WireGuard already installed" -ForegroundColor Green
    }

    # Copy config to WireGuard directory
    Write-Host ""
    Write-Host "Copying config..." -ForegroundColor Cyan
    try {
        $wgConfigDir = "$env:ProgramFiles\WireGuard\Data\Configurations"
        if (-not (Test-Path $wgConfigDir)) {
            New-Item -ItemType Directory -Path $wgConfigDir -Force -ErrorAction Stop | Out-Null
        }

        $configName = [System.IO.Path]::GetFileNameWithoutExtension($configFile)
        $targetConfig = Join-Path $wgConfigDir "$configName.conf"
        Copy-Item $configFile $targetConfig -Force -ErrorAction Stop

        Write-Host "Config copied: $targetConfig" -ForegroundColor Green
    } catch {
        Write-Host "Failed to copy config: $_" -ForegroundColor Red
        throw
    }

    # Import config into WireGuard GUI automatically
    Write-Host ""
    Write-Host "Importing config into WireGuard..." -ForegroundColor Cyan

    try {
        # Close WireGuard GUI if running
        Get-Process -Name "wireguard" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1

        # Launch WireGuard GUI
        Start-Process $wgGuiPath -ErrorAction Stop
        Start-Sleep -Seconds 3

        Write-Host "Config ready to use" -ForegroundColor Green
    } catch {
        Write-Host "Could not launch WireGuard GUI: $_" -ForegroundColor Yellow
        Write-Host "Config has been copied. Please start WireGuard manually." -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "===============================================================" -ForegroundColor Green
    Write-Host "           Installation completed successfully!" -ForegroundColor Green
    Write-Host "===============================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Config: $targetConfig" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Yellow
    Write-Host "1. In WireGuard window, find tunnel '$configName'" -ForegroundColor White
    Write-Host "2. Click 'Activate' to connect" -ForegroundColor White
    Write-Host ""
    Write-Host "Tunnel should appear automatically in the list" -ForegroundColor Gray
    Write-Host ""
    
    # Pause before exit on success
    Write-Host "Press any key to exit..." -ForegroundColor Gray
    try {
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    } catch {
        Read-Host "Press Enter to exit" | Out-Null
    }

} catch {
    $script:ErrorOccurred = $true
    Write-Host ""
    Write-Host "===============================================================" -ForegroundColor Red
    Write-Host "                    Installation Failed" -ForegroundColor Red
    Write-Host "===============================================================" -ForegroundColor Red
    Write-Host ""
    Write-Host "Error: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please check:" -ForegroundColor Yellow
    Write-Host "1. You have administrator privileges" -ForegroundColor White
    Write-Host "2. WireGuard config file is valid" -ForegroundColor White
    Write-Host "3. You have internet connection" -ForegroundColor White
    Write-Host ""
    Pause-BeforeExit
    exit 1
}
