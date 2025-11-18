# WireGuard Split Tunnel Setup for VDS by Selectel

Automated solution for setting up WireGuard split tunnel with routing only specific IP addresses through VPN, optimized for **VDS by Selectel**.

## Description

This project allows you to quickly deploy WireGuard VPN with split tunnel functionality on **VDS by Selectel**:
- Only specified IP addresses are routed through VPN
- Other traffic goes directly
- Maximum installation automation
- Support for macOS, Linux, and Windows
- GUI clients for easy management (automatically installed and launched)

## Requirements

### Server
- **VDS by Selectel** (recommended: VDS Starter or VDS Basic)
- Linux OS (Ubuntu/Debian recommended)
- Root access
- Public IP address (Russian IP guaranteed with Selectel)

### Clients
- macOS, Linux, or Windows
- Administrator privileges for installation

## Configuration

### Environment Variables

The project supports configuration via `.env` file. Copy `.env.example` to `.env` and fill in your values:

```bash
cp .env.example .env
# Edit .env with your settings
```

**Important:** Never commit `.env` file to version control! It contains sensitive data.

Key variables:
- `SERVER_IP` - Server public IP (auto-detected if empty)
- `WG_PORT` - WireGuard port (default: 51820)
- `CLIENT_DNS` - DNS for clients (default: 8.8.8.8)

See `.env.example` for all available options.

## Quick Start

### 🚀 One Script for Everything!

Simply run `install.sh` (or `install.ps1` for Windows) and follow the instructions:

#### Linux/macOS

```bash
# Clone the project
git clone <repository_url>
cd Split-Tunnel

# Run installation
chmod +x install.sh

# For server (Linux only):
sudo ./install.sh

# For client:
./install.sh                    # Interactive mode
./install.sh client.conf         # With existing config
```

The script automatically:
1. ✅ Detects your OS
2. ✅ Asks what to install (server or client)
3. ✅ Performs all installation automatically
4. ✅ For server: creates client config and shows QR code
5. ✅ For client: helps get config and installs everything needed

#### Windows

```powershell
# Run PowerShell as administrator
.\install.ps1
```

**Usage example:**
1. On Selectel VDS: `sudo ./install.sh` → choose "1" (server) → enter client name and IP addresses
2. Copy config from server to client
3. On client: `./install.sh client.conf` → everything installs automatically, GUI opens ready to use!

---

## Detailed Installation (Legacy Method)

If you need more detailed control, use separate scripts:

### 1. Server Installation

```bash
# Clone the repository or copy files to your Selectel VDS
cd server
sudo chmod +x install.sh generate-client.sh
sudo ./install.sh
```

The script will automatically:
- Install WireGuard
- Generate server keys
- Configure firewall
- Start WireGuard service
- Secure SSH access

### 2. Create Client Config

```bash
cd server
sudo ./generate-client.sh <client_name> [IP_addresses]
```

Examples:
```bash
# Create a template (IP addresses need to be filled manually)
sudo ./generate-client.sh myclient

# Create config with specified IPs
sudo ./generate-client.sh myclient "192.168.1.100/32,10.0.0.50/32"
```

Config will be created in `/etc/wireguard/clients/<client_name>.conf`

### 3. Client Installation

#### macOS

```bash
cd client/macos
chmod +x install.sh
./install.sh [path_to_config]
```

The script will:
- Install WireGuard GUI via Homebrew
- Copy config to WireGuard directory
- Open WireGuard GUI for easy management

#### Linux

```bash
cd client/linux
chmod +x install.sh
sudo ./install.sh [path_to_config]
```

The script will:
- Install WireGuard tools
- Try to install GUI if available
- Configure and start the tunnel

#### Windows

Run PowerShell as administrator:

```powershell
cd client\windows
.\install.ps1 [path_to_config]
```

The script will:
- Install WireGuard GUI via winget
- Copy config to WireGuard directory
- Launch WireGuard GUI

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
├── install.sh                # 🚀 Universal installation script (Linux/macOS)
├── install.ps1               # 🚀 Universal installation script (Windows)
├── .env.example              # Environment variables template
├── .gitignore                # Git ignore rules
├── server/
│   ├── install.sh            # WireGuard server installation (detailed)
│   ├── generate-client.sh    # Client config generation
│   └── wg0.conf.template     # Server config template
├── client/
│   ├── macos/
│   │   └── install.sh        # macOS installation (GUI) - detailed
│   ├── linux/
│   │   └── install.sh         # Linux installation - detailed
│   └── windows/
│       └── install.ps1        # Windows installation (GUI) - detailed
├── config/
│   └── client.conf.template  # Client config template
├── scripts/
│   └── load-env.sh           # Environment loader utility
└── README.md                 # Documentation
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

**Stop:**
```bash
sudo systemctl stop wg-quick@wg0
```

**View connected clients:**
```bash
sudo wg show wg0
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

**Note:** If GUI is installed, you can also manage tunnels through it

#### Windows

Use WireGuard GUI:
- Right-click WireGuard icon in system tray
- Select tunnel and activate/deactivate
- Or use the GUI application

**Using CLI:**
```powershell
wg-quick up "path\to\config.conf"
wg-quick down "path\to\config.conf"
```

## Security

- All keys are generated automatically
- Private keys are stored with 600 permissions
- Firewall is configured automatically
- **SSH access is secured automatically:**
  - Password authentication disabled (if SSH keys are present)
  - Root login via password disabled (key-based only)
  - Rate limiting: max 4 SSH connections per minute
  - Maximum 3 authentication attempts
  - X11 forwarding disabled
  - Empty passwords disabled
- Strong server passwords are recommended
- **Important:** Make sure you have SSH keys configured before running the installation script, otherwise password authentication will remain enabled for safety

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

### SSH Access Issues

If you're locked out of SSH after installation:

1. **If you have console access (Selectel panel):**
   - Restore SSH config backup: `cp /etc/ssh/sshd_config.backup.* /etc/ssh/sshd_config`
   - Restart SSH: `systemctl restart sshd`

2. **To add SSH keys before installation:**
   ```bash
   # On your local machine, generate key if needed:
   ssh-keygen -t ed25519 -C "your_email@example.com"
   
   # Copy public key to server:
   ssh-copy-id root@your_server_ip
   
   # Or manually:
   cat ~/.ssh/id_ed25519.pub | ssh root@your_server_ip "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys"
   ```

3. **Check SSH configuration:**
   ```bash
   sshd -t  # Test SSH config
   systemctl status sshd  # Check SSH service
   ```

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
5. **Deploy server** and follow installation instructions below

## License

For personal use.

## Support

If you encounter issues, check:
1. WireGuard logs on server and client
2. Firewall settings
3. Correct IP address specification in config
