# WireGuard Split Tunnel Setup

Automated solution for setting up WireGuard split tunnel with routing only specific IP addresses through VPN.

## Description

This project allows you to quickly deploy WireGuard VPN with split tunnel functionality:
- Only specified IP addresses are routed through VPN
- Other traffic goes directly
- Maximum installation automation
- Support for macOS, Linux, and Windows
- GUI clients for easy management

## Requirements

### Server
- Linux server (Ubuntu/Debian/CentOS/Fedora/Arch)
- Root access
- Public IP address

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
- `SELECTEL_API_TOKEN` - For automatic server control
- `SELECTEL_SERVER_ID` - Your Selectel server ID
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
1. On server: `sudo ./install.sh` → choose "1" (server) → enter client name and IP addresses
2. Copy config from server to client
3. On client: `./install.sh client.conf` → everything installs automatically!

---

## Detailed Installation (Legacy Method)

If you need more detailed control, use separate scripts:

### 1. Server Installation

```bash
# Clone the repository or copy files to the server
cd server
sudo chmod +x install.sh generate-client.sh
sudo ./install.sh
```

The script will automatically:
- Install WireGuard
- Generate server keys
- Configure firewall
- Start WireGuard service

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

# Create config with automatic server control (Selectel)
sudo ./generate-client.sh myclient "192.168.1.100/32" --auto-server-control
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

## Automatic Server Control (Selectel)

If you're using Selectel VPS with hourly billing, you can configure automatic server start/stop when connecting/disconnecting from VPN. This saves money by only paying when the VPN is actually in use.

### Setup Automatic Server Control

#### Step 1: Get Selectel API Token

1. Go to https://panel.selectel.com/
2. Navigate to: **API → Tokens**
3. Click **"Create Token"**
4. Give it a name (e.g., "VPN Auto Control")
5. Select permissions: **"Servers"** (read and write)
6. Copy the token (you won't see it again!)

#### Step 2: Find Server ID

1. Go to your server in Selectel panel
2. Server ID is in the URL: `.../servers/12345/...`
   Or check the server details page

#### Step 3: Generate Client Config with Auto-Control

On the server, generate client config with `--auto-server-control` flag:

```bash
cd server
sudo ./generate-client.sh myclient "192.168.1.100/32" --auto-server-control
```

This will add hooks to automatically start/stop the server.

#### Step 4: Configure on Client

When installing the client, the script will detect server control hooks and prompt you to configure API credentials:

```bash
cd client/macos  # or linux
./install.sh /path/to/client.conf
```

Or configure manually:

```bash
# macOS/Linux
~/.local/bin/selectel-config.sh setup  # macOS
/usr/local/bin/selectel-config.sh setup  # Linux
```

Enter your API token and Server ID when prompted.

#### Step 5: Test

```bash
# Test server control
selectel-server-control.sh status

# Test start/stop manually
selectel-server-control.sh start
selectel-server-control.sh stop
```

### How It Works

- **When you connect to VPN**: `PreUp` hook runs → Server starts automatically
- **When you disconnect**: `PostDown` hook runs → Server stops automatically

The server will:
- Start ~45 seconds before VPN connection (waiting for server to boot)
- Stop immediately when VPN disconnects
- Save money by only running when needed

### Manual Configuration

If you need to configure API credentials manually, edit `~/.selectel-vpn-config`:

```bash
export SELECTEL_API_TOKEN="your_token_here"
export SELECTEL_SERVER_ID="your_server_id_here"
```

**Or use `.env` file** (recommended):

```bash
# Copy example file
cp .env.example .env

# Edit .env file
nano .env

# Set your values:
SELECTEL_API_TOKEN=your_token_here
SELECTEL_SERVER_ID=your_server_id_here
```

The scripts will automatically load variables from `.env` file if it exists.

### Troubleshooting

**Server doesn't start:**
- Check API token permissions
- Verify Server ID is correct
- Check Selectel API status

**Script not found:**
- Make sure scripts are installed: `which selectel-server-control.sh`
- Re-run client install script

**Server starts but VPN doesn't connect:**
- Wait longer (server may need more time to boot)
- Check server is accessible: `ping <SERVER_IP>`


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
│   ├── windows/
│   │   └── install.ps1        # Windows installation (GUI) - detailed
│   └── scripts/
│       ├── selectel-server-control.sh  # Auto server start/stop
│       └── selectel-config.sh          # API configuration
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

1. **If you have console access (VPS panel):**
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

## VPS Recommendations

For maximum cost savings, consider:
- Russian VPS providers (Selectel, Timeweb, REG.RU)
- Minimum plans (1 CPU, 512MB RAM is sufficient)
- Ubuntu/Debian for easy installation

## License

For personal use.

## Support

If you encounter issues, check:
1. WireGuard logs on server and client
2. Firewall settings
3. Correct IP address specification in config
