# WireGuard Split Tunnel - Client Installation for Windows
# Requires administrator privileges
# Usage: .\install.ps1 [config.conf]

Write-Host "╔═══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║        WireGuard Split Tunnel - Client Installer        ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Check for administrator privileges
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "⚠ Требуются права администратора!" -ForegroundColor Red
    Write-Host ""
    Write-Host "Как запустить:" -ForegroundColor Yellow
    Write-Host "1. Нажмите Win + X" -ForegroundColor White
    Write-Host "2. Выберите 'Windows PowerShell (Admin)' или 'Terminal (Admin)'" -ForegroundColor White
    Write-Host "3. Запустите скрипт снова" -ForegroundColor White
    Write-Host ""
    Read-Host "Нажмите Enter для выхода"
    exit 1
}

# Auto-find configuration file
$configFile = $null
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptDir

# Priority: command line argument > *.conf in current dir > client.conf
if ($args.Count -gt 0) {
    $configFile = $args[0]
    if (-not (Test-Path $configFile)) {
        Write-Host "❌ Файл не найден: $configFile" -ForegroundColor Red
        exit 1
    }
} else {
    # Auto-find .conf files
    $confFiles = Get-ChildItem -Path . -Filter "*.conf" -File | Where-Object { $_.Name -ne "client.conf.template" }
    
    if ($confFiles.Count -eq 1) {
        $configFile = $confFiles[0].FullName
        Write-Host "✓ Найден конфиг: $($confFiles[0].Name)" -ForegroundColor Green
    } elseif ($confFiles.Count -gt 1) {
        Write-Host "Найдено несколько конфигов:" -ForegroundColor Yellow
        for ($i = 0; $i -lt $confFiles.Count; $i++) {
            Write-Host "  $($i+1). $($confFiles[$i].Name)" -ForegroundColor White
        }
        $choice = Read-Host "Выберите номер (1-$($confFiles.Count))"
        if ($choice -match '^\d+$' -and [int]$choice -ge 1 -and [int]$choice -le $confFiles.Count) {
            $configFile = $confFiles[[int]$choice - 1].FullName
        } else {
            Write-Host "❌ Неверный выбор" -ForegroundColor Red
            exit 1
        }
    } elseif (Test-Path "client.conf") {
        $configFile = "client.conf"
    } else {
        Write-Host "❌ Конфиг не найден!" -ForegroundColor Red
        Write-Host ""
        Write-Host "Поместите файл .conf в эту папку или укажите путь:" -ForegroundColor Yellow
        Write-Host "  .\install.ps1 путь\к\конфигу.conf" -ForegroundColor White
        Write-Host ""
        Read-Host "Нажмите Enter для выхода"
        exit 1
    }
}

Write-Host "Используется конфиг: $(Split-Path -Leaf $configFile)" -ForegroundColor Cyan
Write-Host ""

# Validate and fix config
$configContent = Get-Content $configFile -Raw -Encoding UTF8
$needsFix = $false

# Check Endpoint
if ($configContent -match "Endpoint\s*=\s*(.+?)(\r?\n|$)") {
    $endpoint = $matches[1].Trim()
    if ($endpoint -match "YOUR_SERVER_IP|SERVER_IP|:\['" -or $endpoint -match "^:\d+" -or $endpoint -notmatch "^\d+\.\d+\.\d+\.\d+:\d+$") {
        Write-Host "⚠ Endpoint указан неправильно: $endpoint" -ForegroundColor Yellow
        $serverIP = Read-Host "Введите IP адрес сервера (например: 45.8.251.107)"
        $port = Read-Host "Введите порт (по умолчанию 51820)"
        if ([string]::IsNullOrWhiteSpace($port)) { $port = "51820" }
        $configContent = $configContent -replace "Endpoint\s*=.*", "Endpoint = ${serverIP}:${port}"
        $needsFix = $true
    }
}

# Check AllowedIPs
if ($configContent -match "AllowedIPs\s*=\s*$" -or $configContent -match "AllowedIPs\s*=\s*#") {
    Write-Host "⚠ AllowedIPs пусто!" -ForegroundColor Yellow
    Write-Host "Укажите IP адреса для маршрутизации через VPN (через запятую):" -ForegroundColor Cyan
    Write-Host "Пример: 88.212.250.100/32,88.212.249.37/32" -ForegroundColor Gray
    $allowedIPs = Read-Host "AllowedIPs"
    if (-not [string]::IsNullOrWhiteSpace($allowedIPs)) {
        $configContent = $configContent -replace "AllowedIPs\s*=.*", "AllowedIPs = $allowedIPs"
        $needsFix = $true
    }
}

# Save fixed config
if ($needsFix) {
    $configContent | Out-File -FilePath $configFile -Encoding UTF8 -NoNewline
    Write-Host "✓ Конфиг обновлен" -ForegroundColor Green
    Write-Host ""
}

# Install WireGuard GUI
Write-Host "Установка WireGuard..." -ForegroundColor Cyan
$wgGuiPath = "$env:ProgramFiles\WireGuard\wireguard.exe"
$wgInstalled = Test-Path $wgGuiPath

if (-not $wgInstalled) {
    # Try winget first
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Host "Установка через winget..." -ForegroundColor Cyan
        $wingetResult = winget install --id WireGuard.WireGuard -e --accept-package-agreements --accept-source-agreements --silent 2>&1
        Start-Sleep -Seconds 3
    } else {
        # Try chocolatey
        if (Get-Command choco -ErrorAction SilentlyContinue) {
            Write-Host "Установка через Chocolatey..." -ForegroundColor Cyan
            choco install wireguard -y
            Start-Sleep -Seconds 3
        } else {
            # Manual download
            Write-Host ""
            Write-Host "⚠ Автоматическая установка недоступна" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "Установите WireGuard вручную:" -ForegroundColor Cyan
            Write-Host "1. Откройте: https://www.wireguard.com/install/" -ForegroundColor White
            Write-Host "2. Скачайте и установите WireGuard для Windows" -ForegroundColor White
            Write-Host "3. Запустите этот скрипт снова" -ForegroundColor White
            Write-Host ""
            $openBrowser = Read-Host "Открыть сайт в браузере? (Y/N)"
            if ($openBrowser -eq "Y" -or $openBrowser -eq "y") {
                Start-Process "https://www.wireguard.com/install/"
            }
            Read-Host "Нажмите Enter после установки WireGuard"
        }
    }
    
    # Verify installation
    Start-Sleep -Seconds 2
    $wgInstalled = Test-Path $wgGuiPath
    if (-not $wgInstalled) {
        Write-Host "❌ WireGuard не установлен" -ForegroundColor Red
        Write-Host "Установите WireGuard и запустите скрипт снова" -ForegroundColor Yellow
        exit 1
    }
}

Write-Host "✓ WireGuard установлен" -ForegroundColor Green

# Copy config to WireGuard directory
Write-Host ""
Write-Host "Копирование конфига..." -ForegroundColor Cyan
$wgConfigDir = "$env:ProgramFiles\WireGuard\Data\Configurations"
if (-not (Test-Path $wgConfigDir)) {
    New-Item -ItemType Directory -Path $wgConfigDir -Force | Out-Null
}

$configName = [System.IO.Path]::GetFileNameWithoutExtension($configFile)
$targetConfig = Join-Path $wgConfigDir "$configName.conf"
Copy-Item $configFile $targetConfig -Force

Write-Host "✓ Конфиг скопирован: $targetConfig" -ForegroundColor Green

# Import config into WireGuard GUI automatically
Write-Host ""
Write-Host "Импорт конфига в WireGuard..." -ForegroundColor Cyan

# Close WireGuard GUI if running to avoid conflicts
Get-Process -Name "wireguard" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

# Launch WireGuard GUI
Start-Process $wgGuiPath
Start-Sleep -Seconds 2

# Try to import config using WireGuard CLI
$wgExe = Join-Path (Split-Path $wgGuiPath) "wg.exe"
if (Test-Path $wgExe) {
    # WireGuard GUI automatically detects configs in Configurations folder
    # The config should appear automatically
    Write-Host "✓ Конфиг готов к использованию" -ForegroundColor Green
} else {
    Write-Host "✓ WireGuard GUI открыт" -ForegroundColor Green
}

Write-Host ""
Write-Host "╔═══════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║           Установка завершена успешно!                   ║" -ForegroundColor Green
Write-Host "╚═══════════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "📋 Конфиг: $targetConfig" -ForegroundColor Cyan
Write-Host ""
Write-Host "📌 Что дальше:" -ForegroundColor Yellow
Write-Host "1. В окне WireGuard найдите туннель '$configName'" -ForegroundColor White
Write-Host "2. Нажмите 'Activate' для подключения" -ForegroundColor White
Write-Host ""
Write-Host "💡 Туннель должен появиться автоматически в списке" -ForegroundColor Gray
Write-Host ""
