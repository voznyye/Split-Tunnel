# WireGuard Split Tunnel Setup for VDS by Selectel

Automated solution for setting up WireGuard split tunnel with routing only specific IP addresses through VPN, optimized for **VDS by Selectel**.

## Description

This project allows you to quickly deploy WireGuard VPN with split tunnel functionality on **VDS by Selectel**:
- Only specified IP addresses are routed through VPN
- Other traffic goes directly
- Server installation via Ansible (no manual access required)
- Simple client installation scripts
- Support for macOS, Linux, and Windows
- GUI clients for easy management

## Requirements

### Server Setup
- **VDS by Selectel** (recommended: VDS Starter or VDS Basic)
- Linux OS (Ubuntu/Debian recommended)
- SSH access (key-based or password)
- Ansible installed on your local machine

### Client Setup
- macOS, Linux, or Windows
- Administrator privileges for installation

## Quick Start

### 1. Server Installation (via Ansible)

```bash
# 1. Install Ansible (if not installed)
# macOS:
brew install ansible

# Linux (Ubuntu/Debian):
sudo apt-get install ansible

# Or via pip:
pip install ansible

# 2. Configure inventory
cd ansible
cp inventory.yml.example inventory.yml
# Edit inventory.yml and set your server IP and SSH user

# 3. Install WireGuard server
ansible-playbook -i inventory.yml playbook.yml

# 4. Create client configuration
ansible-playbook -i inventory.yml generate-client.yml \
  -e 'client_name=myclient' \
  -e 'allowed_ips=192.168.1.100/32,10.0.0.50/32'

# 5. Download client configuration
scp root@your-server:/etc/wireguard/clients/myclient.conf ./
```

**Ansible Benefits:**
- ✅ No manual server access required
- ✅ Idempotent - can run multiple times safely
- ✅ Easy multi-server management
- ✅ Configuration versioning
- ✅ Automatic client config generation

See detailed Ansible documentation: [ansible/README.md](ansible/README.md)

### 2. Client Installation

#### macOS/Linux

```bash
# Clone the project (or just download install.sh)
git clone <repository_url>
cd Split-Tunnel

# Make script executable
chmod +x install.sh

# Install with config file
./install.sh myclient.conf

# Or interactive mode (will help you get config)
./install.sh
```

The script automatically:
- ✅ Detects your OS
- ✅ Installs WireGuard (GUI on macOS, CLI on Linux)
- ✅ Configures and starts tunnel
- ✅ Opens GUI on macOS

#### Windows

**Простая установка (3 шага):**

1. **Запустите PowerShell от администратора:**
   - Нажмите `Win + X`
   - Выберите "Windows PowerShell (Admin)" или "Terminal (Admin)"

2. **Перейдите в папку с проектом и запустите:**
   ```powershell
   cd C:\path\to\Split-Tunnel
   .\install.ps1
   ```
   
   Скрипт автоматически найдет файл `.conf` в текущей папке!

3. **В WireGuard GUI нажмите "Activate"** - готово!

**Или укажите конфиг вручную:**
```powershell
.\install.ps1 myclient.conf
```

**Что делает скрипт автоматически:**
- ✅ Находит конфиг файл автоматически
- ✅ Проверяет и исправляет Endpoint если нужно
- ✅ Устанавливает WireGuard GUI (через winget или Chocolatey)
- ✅ Копирует конфиг в нужную папку
- ✅ Открывает WireGuard GUI
- ✅ Конфиг появляется автоматически в списке туннелей

## Split Tunnel Configuration

### Specifying IP Addresses for Routing

Open the client config and fill in the `AllowedIPs` field:

```ini
[Peer]
PublicKey = <SERVER_PUBLIC_KEY>
Endpoint = <SERVER_IP>:51820
AllowedIPs = 192.168.1.100/32, 10.0.0.50/32
```

**Important:**
- Specify IP addresses separated by commas
- Use CIDR format (e.g., `/32` for a single IP)
- Only specified IPs will go through VPN
- Other traffic goes directly

### Configuration Examples

**Single IP:**
```
AllowedIPs = 192.168.1.100/32
```

**Multiple IPs:**
```
AllowedIPs = 192.168.1.100/32, 10.0.0.50/32, 172.16.0.1/32
```

**Subnet:**
```
AllowedIPs = 192.168.1.0/24
```

**All traffic (full tunnel):**
```
AllowedIPs = 0.0.0.0/0, ::/0
```

## Project Structure

```
Split-Tunnel/
├── install.sh                # Client installer (macOS/Linux)
├── install.ps1               # Client installer (Windows)
├── ansible/                  # Server automation
│   ├── playbook.yml          # Server installation playbook
│   ├── generate-client.yml   # Client generation playbook
│   ├── inventory.yml.example # Inventory template
│   └── roles/wireguard/      # WireGuard role
└── README.md                 # This file
```

## Management

### Server

**Check status:**
```bash
sudo wg show
sudo systemctl status wg-quick@wg0
```

**Restart:**
```bash
sudo systemctl restart wg-quick@wg0
```

**View connected clients:**
```bash
sudo wg show wg0
```

**Create new client (via Ansible):**
```bash
cd ansible
ansible-playbook -i inventory.yml generate-client.yml \
  -e 'client_name=newclient' \
  -e 'allowed_ips=192.168.1.101/32'
```

### Client

#### macOS

**Using GUI:**
- Open WireGuard from Applications
- Manage tunnels from the menu bar icon
- Click to activate/deactivate tunnels

**Using CLI:**
```bash
sudo wg show
sudo wg-quick down <config_name>
sudo wg-quick up <config_name>
```

#### Linux

**Check status:**
```bash
sudo wg show
systemctl status wg-quick@<config_name>
```

**Stop:**
```bash
sudo systemctl stop wg-quick@<config_name>
```

**Start:**
```bash
sudo systemctl start wg-quick@<config_name>
```

#### Windows

Use WireGuard GUI:
- Right-click WireGuard icon in system tray
- Select tunnel and activate/deactivate
- Or use the GUI application

## Troubleshooting

### Server Not Starting

1. Check logs: `sudo journalctl -u wg-quick@wg0`
2. Ensure port 51820 is open in firewall
3. Check configuration: `sudo wg-quick strip wg0`

### Client Not Connecting

1. Check that IP addresses are specified in `AllowedIPs`
2. Ensure server is reachable: `ping <SERVER_IP>`
3. Check port: `nc -uv <SERVER_IP> 51820`
4. Verify keys in config

### Traffic Not Going Through VPN

1. Ensure IP addresses are correctly specified in `AllowedIPs`
2. Check routes: `ip route` (Linux) or `netstat -rn` (macOS)
3. Verify tunnel is active: `sudo wg show`

## VDS by Selectel Recommendations

This project is optimized for **VDS by Selectel**. Recommended configuration:

### Recommended Plans

**VDS Starter** (minimum, ~100-150₽/month if running 24/7):
- 1 CPU core
- 512 MB RAM
- 10 GB SSD
- Unlimited traffic
- **Perfect for 1-5 clients**

**VDS Basic** (recommended, ~200-250₽/month if running 24/7):
- 1 CPU core
- 1 GB RAM
- 20 GB SSD
- Unlimited traffic
- **Perfect for 5-10 clients**

### Why Selectel VDS?

- ✅ **Russian IP addresses** - guaranteed
- ✅ **Hourly billing** - pay only for usage time
- ✅ **Low prices** - from 0.15₽/hour
- ✅ **Reliable infrastructure** - Moscow and St. Petersburg datacenters
- ✅ **Easy management** - simple control panel

### Getting Started with Selectel

1. **Sign up**: https://selectel.ru/services/cloud/servers/
2. **Choose plan**: VDS Starter or VDS Basic
3. **Select region**: Moscow (MS1) or St. Petersburg (SPB) for Russian IP
4. **Choose OS**: Ubuntu 22.04 LTS (recommended)
5. **Deploy server** and follow Ansible installation instructions above

## License

For personal use.

## Support

If you encounter issues, check:
1. WireGuard logs on server and client
2. Firewall settings
3. Correct IP address specification in config
4. Ansible playbook output for server issues
