#!/bin/bash
#
# WireGuard Split Tunnel - Universal Installation Script
# 
# Usage:
#   ./install.sh                    # Interactive installation
#   ./install.sh client.conf        # Client installation with config
#   sudo ./install.sh                # Server installation (Linux)
#
# Script automatically detects:
#   - Operating system (Linux/macOS)
#   - Role (server/client)
#   - Linux distribution
#   - All necessary settings
#

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${CYAN}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║     WireGuard Split Tunnel - Universal Installation     ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""

# Detect OS
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    OS="linux"
elif [[ "$OSTYPE" == "darwin"* ]]; then
    OS="macos"
elif [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]]; then
    echo -e "${RED}For Windows, use install.ps1${NC}"
    exit 1
else
    echo -e "${RED}Unsupported OS: $OSTYPE${NC}"
    exit 1
fi

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Load .env if exists
if [ -f ".env" ]; then
    set +a
    source .env 2>/dev/null || true
    set -a
fi

# Determine role - auto-detect if config file is provided
ROLE_CHOICE=""
if [ -n "$1" ] && [ -f "$1" ] && [[ "$1" == *.conf ]]; then
    # Config file provided - assume client installation
    ROLE_CHOICE="2"
    echo -e "${GREEN}Config file detected: $1${NC}"
    echo -e "${GREEN}Auto-selected mode: Client${NC}"
    echo ""
else
    echo -e "${CYAN}What do you want to install?${NC}"
    echo "1) VPN Server (WireGuard server)"
    echo "2) VPN Client (connect to server)"
    echo ""
    read -p "Choose (1 or 2): " ROLE_CHOICE
fi

if [ "$ROLE_CHOICE" != "1" ] && [ "$ROLE_CHOICE" != "2" ]; then
    echo -e "${RED}Invalid choice${NC}"
    exit 1
fi

# ============================================================================
# SERVER INSTALLATION
# ============================================================================
if [ "$ROLE_CHOICE" = "1" ]; then
    echo ""
    echo -e "${CYAN}=== WireGuard Server Installation ===${NC}"
    echo ""
    
    # Check root
    if [ "$EUID" -ne 0 ]; then 
        echo -e "${RED}Error: Run script with sudo${NC}"
        echo "  sudo ./install.sh"
        exit 1
    fi
    
    # Detect Linux distribution
    if [ "$OS" != "linux" ]; then
        echo -e "${RED}Server can only be installed on Linux${NC}"
        exit 1
    fi
    
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO=$ID
    else
        echo -e "${RED}Unable to detect Linux distribution${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}Distribution: $DISTRO${NC}"
    echo ""
    
    # Install WireGuard
    echo -e "${CYAN}Installing WireGuard...${NC}"
    case $DISTRO in
        ubuntu|debian)
            apt-get update -qq
            apt-get install -y wireguard wireguard-tools qrencode curl >/dev/null 2>&1
            ;;
        centos|rhel|fedora)
            if [ "$DISTRO" = "fedora" ]; then
                dnf install -y wireguard-tools qrencode curl >/dev/null 2>&1
            else
                yum install -y epel-release >/dev/null 2>&1
                yum install -y wireguard-tools qrencode curl >/dev/null 2>&1
            fi
            ;;
        arch|manjaro)
            pacman -S --noconfirm wireguard-tools qrencode curl >/dev/null 2>&1
            ;;
        *)
            echo -e "${RED}Unsupported distribution. Please install WireGuard manually.${NC}"
            exit 1
            ;;
    esac
    echo -e "${GREEN}✓ WireGuard installed${NC}"
    
    # Enable IP forwarding
    echo -e "${CYAN}Configuring IP forwarding...${NC}"
    if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
        echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
        echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.conf
    fi
    sysctl -p >/dev/null 2>&1
    echo -e "${GREEN}✓ IP forwarding enabled${NC}"
    
    # Create WireGuard directory
    WG_DIR="/etc/wireguard"
    mkdir -p $WG_DIR
    cd $WG_DIR
    
    # Generate server keys if not exist
    if [ ! -f server_private.key ]; then
        echo -e "${CYAN}Generating server keys...${NC}"
        wg genkey | tee server_private.key | wg pubkey > server_public.key
        chmod 600 server_private.key
        chmod 644 server_public.key
        echo -e "${GREEN}✓ Keys created${NC}"
    else
        echo -e "${YELLOW}Server keys already exist${NC}"
    fi
    
    SERVER_PRIVATE_KEY=$(cat server_private.key)
    SERVER_PUBLIC_KEY=$(cat server_public.key)
    
    # Detect server IP
    echo -e "${CYAN}Detecting server IP address...${NC}"
    if [ -z "$SERVER_IP" ]; then
        SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || curl -s icanhazip.com 2>/dev/null || echo "")
    fi
    if [ -z "$SERVER_IP" ]; then
        read -p "Enter server public IP address: " SERVER_IP
    fi
    echo -e "${GREEN}✓ Server IP: $SERVER_IP${NC}"
    
    # Detect network interface
    INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
    if [ -z "$INTERFACE" ]; then
        read -p "Enter network interface name (e.g., eth0): " INTERFACE
    fi
    
    # VPN configuration
    VPN_NETWORK=${VPN_NETWORK:-"10.0.0.0/24"}
    SERVER_VPN_IP=${SERVER_VPN_IP:-"10.0.0.1"}
    WG_PORT=${WG_PORT:-51820}
    
    # Create server config
    echo -e "${CYAN}Creating server configuration...${NC}"
    cat > wg0.conf <<EOF
[Interface]
Address = $SERVER_VPN_IP/24
ListenPort = $WG_PORT
PrivateKey = $SERVER_PRIVATE_KEY
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o $INTERFACE -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o $INTERFACE -j MASQUERADE

EOF
    chmod 600 wg0.conf
    echo -e "${GREEN}✓ Configuration created${NC}"
    
    # Configure firewall
    echo -e "${CYAN}Configuring firewall...${NC}"
    if command -v ufw &> /dev/null; then
        ufw allow $WG_PORT/udp >/dev/null 2>&1 || true
        echo -e "${GREEN}✓ UFW configured${NC}"
    elif command -v firewall-cmd &> /dev/null; then
        firewall-cmd --permanent --add-port=$WG_PORT/udp >/dev/null 2>&1
        firewall-cmd --reload >/dev/null 2>&1
        echo -e "${GREEN}✓ Firewalld configured${NC}"
    elif command -v iptables &> /dev/null; then
        iptables -A INPUT -p udp --dport $WG_PORT -j ACCEPT 2>/dev/null || true
        echo -e "${GREEN}✓ IPTables configured${NC}"
    fi
    
    # Start WireGuard
    echo -e "${CYAN}Starting WireGuard...${NC}"
    systemctl enable wg-quick@wg0 >/dev/null 2>&1
    systemctl start wg-quick@wg0 >/dev/null 2>&1
    
    if systemctl is-active --quiet wg-quick@wg0; then
        echo -e "${GREEN}✓ WireGuard started${NC}"
    else
        echo -e "${YELLOW}⚠ WireGuard may not be running. Check: systemctl status wg-quick@wg0${NC}"
    fi
    
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║              Server installed successfully!              ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}Server information:${NC}"
    echo "  Public key: $SERVER_PUBLIC_KEY"
    echo "  IP address: $SERVER_IP"
    echo "  Port: $WG_PORT"
    echo ""
    echo -e "${CYAN}Creating client config:${NC}"
    echo ""
    read -p "Enter client name: " CLIENT_NAME
    if [ -z "$CLIENT_NAME" ]; then
        echo -e "${RED}Error: Client name cannot be empty${NC}"
        exit 1
    fi
    
    echo ""
    echo "Enter IP addresses to route through VPN:"
    echo "  Example: 192.168.1.100/32,10.0.0.50/32"
    echo "  For all traffic: 0.0.0.0/0,::/0"
    echo "  Can be left empty and filled later"
    read -p "IP addresses: " ALLOWED_IPS
    
    if [ -z "$ALLOWED_IPS" ]; then
        echo -e "${YELLOW}⚠ AllowedIPs is empty. Config will be created with comment for manual filling.${NC}"
        ALLOWED_IPS="# Specify IP addresses to route through VPN"
    fi
    
    # Create client config
    CLIENTS_DIR="$WG_DIR/clients"
    mkdir -p $CLIENTS_DIR
    cd $CLIENTS_DIR
    
    CLIENT_PRIVATE_KEY=$(wg genkey)
    CLIENT_PUBLIC_KEY=$(echo $CLIENT_PRIVATE_KEY | wg pubkey)
    
    # Determine next client IP
    LAST_IP=$(grep -oP '10\.0\.0\.\d+' $WG_DIR/wg0.conf 2>/dev/null | sort -t. -k4 -n | tail -1 | cut -d. -f4 || echo "1")
    NEXT_IP=$((LAST_IP + 1))
    CLIENT_VPN_IP="10.0.0.$NEXT_IP"
    
    CLIENT_DNS=${CLIENT_DNS:-"8.8.8.8"}
    
    # Create client config
    CLIENT_CONF="$CLIENTS_DIR/${CLIENT_NAME}.conf"
    if [[ "$ALLOWED_IPS" == *"#"* ]]; then
        # Template with comment
        cat > $CLIENT_CONF <<EOF
[Interface]
PrivateKey = $CLIENT_PRIVATE_KEY
Address = $CLIENT_VPN_IP/24
DNS = $CLIENT_DNS

[Peer]
PublicKey = $SERVER_PUBLIC_KEY
Endpoint = $SERVER_IP:$WG_PORT
AllowedIPs = 
# Specify IP addresses to route through VPN (split tunnel)
# Example: AllowedIPs = 192.168.1.100/32, 10.0.0.50/32
# For all traffic: AllowedIPs = 0.0.0.0/0, ::/0
EOF
    else
        # Config with IPs
        cat > $CLIENT_CONF <<EOF
[Interface]
PrivateKey = $CLIENT_PRIVATE_KEY
Address = $CLIENT_VPN_IP/24
DNS = $CLIENT_DNS

[Peer]
PublicKey = $SERVER_PUBLIC_KEY
Endpoint = $SERVER_IP:$WG_PORT
AllowedIPs = $ALLOWED_IPS
EOF
    fi
    
    # Add client to server config
    cat >> $WG_DIR/wg0.conf <<EOF

# Client: $CLIENT_NAME
[Peer]
PublicKey = $CLIENT_PUBLIC_KEY
AllowedIPs = $CLIENT_VPN_IP/32
EOF
    
    # Reload WireGuard
    wg syncconf wg0 <(wg-quick strip wg0) >/dev/null 2>&1
    
    echo ""
    echo -e "${GREEN}✓ Client config created: $CLIENT_CONF${NC}"
    echo ""
    echo -e "${CYAN}QR code for mobile devices:${NC}"
    qrencode -t ANSI < $CLIENT_CONF
    echo ""
    echo -e "${CYAN}Config content:${NC}"
    cat $CLIENT_CONF
    echo ""
    echo -e "${GREEN}Copy the config to client and run install.sh there!${NC}"
    exit 0
fi

# ============================================================================
# CLIENT INSTALLATION
# ============================================================================
if [ "$ROLE_CHOICE" = "2" ]; then
    echo ""
    echo -e "${CYAN}=== WireGuard Client Installation ===${NC}"
    echo ""
    
    # Check for config file
    CONFIG_FILE=""
    if [ -n "$1" ]; then
        CONFIG_FILE="$1"
    elif [ -f "client.conf" ]; then
        CONFIG_FILE="client.conf"
    elif [ -f "config/client.conf" ]; then
        CONFIG_FILE="config/client.conf"
    else
        echo -e "${YELLOW}Configuration file not found.${NC}"
        echo ""
        echo "Choose how to get the config:"
        echo "1) I have a config file"
        echo "2) Download from server (requires SSH access)"
        echo "3) Create manually (need server data)"
        echo ""
        read -p "Choose (1/2/3): " CONFIG_CHOICE
        
        case $CONFIG_CHOICE in
            1)
                read -p "Enter path to config file: " CONFIG_FILE
                ;;
            2)
                read -p "Enter server address (user@host): " SERVER_HOST
                read -p "Enter client config name: " CLIENT_NAME
                echo -e "${CYAN}Downloading config from server...${NC}"
                scp "$SERVER_HOST:/etc/wireguard/clients/${CLIENT_NAME}.conf" ./client.conf
                CONFIG_FILE="./client.conf"
                if [ ! -f "$CONFIG_FILE" ]; then
                    echo -e "${RED}Failed to download config${NC}"
                    exit 1
                fi
                echo -e "${GREEN}✓ Config downloaded${NC}"
                ;;
            3)
                read -p "Enter client private key: " CLIENT_PRIVATE_KEY
                read -p "Enter server public key: " SERVER_PUBLIC_KEY
                read -p "Enter server IP address: " SERVER_IP
                read -p "Enter port (default 51820): " WG_PORT
                WG_PORT=${WG_PORT:-51820}
                read -p "Enter client VPN IP (e.g., 10.0.0.2): " CLIENT_VPN_IP
                read -p "Enter IP addresses to route through VPN: " ALLOWED_IPS
                
                CLIENT_DNS=${CLIENT_DNS:-"8.8.8.8"}
                CLIENT_CONF="./client.conf"
                cat > $CLIENT_CONF <<EOF
[Interface]
PrivateKey = $CLIENT_PRIVATE_KEY
Address = $CLIENT_VPN_IP/24
DNS = $CLIENT_DNS

[Peer]
PublicKey = $SERVER_PUBLIC_KEY
Endpoint = $SERVER_IP:$WG_PORT
AllowedIPs = $ALLOWED_IPS
EOF
                CONFIG_FILE="$CLIENT_CONF"
                echo -e "${GREEN}✓ Config created${NC}"
                ;;
            *)
                echo -e "${RED}Invalid choice${NC}"
                exit 1
                ;;
        esac
    fi
    
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}Error: Config file not found: $CONFIG_FILE${NC}"
        exit 1
    fi
    
    # Check AllowedIPs
    ALLOWED_IPS=$(grep "^AllowedIPs" "$CONFIG_FILE" | cut -d'=' -f2 | xargs)
    if [ -z "$ALLOWED_IPS" ] || [[ "$ALLOWED_IPS" == *"#"* ]]; then
        echo ""
        echo -e "${YELLOW}⚠ WARNING: AllowedIPs field is empty!${NC}"
        echo "Specify IP addresses to route through VPN:"
        read -p "Enter IP addresses (comma-separated): " ALLOWED_IPS
        if [ -n "$ALLOWED_IPS" ]; then
            sed -i.bak "s|AllowedIPs =.*|AllowedIPs = $ALLOWED_IPS|" "$CONFIG_FILE"
            echo -e "${GREEN}✓ AllowedIPs updated${NC}"
        fi
    fi
    
    # macOS installation
    if [ "$OS" = "macos" ]; then
        echo -e "${CYAN}Installing for macOS...${NC}"
        
        # Check for Homebrew
        if ! command -v brew &> /dev/null; then
            echo -e "${CYAN}Installing Homebrew...${NC}"
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        fi
        
        # Install WireGuard GUI
        echo -e "${CYAN}Installing WireGuard GUI...${NC}"
        if ! brew list --cask wireguard 2>/dev/null; then
            brew install --cask wireguard >/dev/null 2>&1
        fi
        if ! command -v wg &> /dev/null; then
            brew install wireguard-tools >/dev/null 2>&1
        fi
        echo -e "${GREEN}✓ WireGuard installed${NC}"
        
        # Copy config
        WG_CONFIG_DIR="$HOME/Library/Application Support/WireGuard"
        mkdir -p "$WG_CONFIG_DIR"
        CONFIG_NAME=$(basename "$CONFIG_FILE" .conf)
        cp "$CONFIG_FILE" "$WG_CONFIG_DIR/${CONFIG_NAME}.conf"
        echo -e "${GREEN}✓ Config copied${NC}"
        
        # Open WireGuard GUI
        echo ""
        echo -e "${CYAN}Opening WireGuard GUI...${NC}"
        open -a WireGuard
        
        echo ""
        echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║              Client installed successfully!              ║${NC}"
        echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo "Config: $WG_CONFIG_DIR/${CONFIG_NAME}.conf"
        echo "In WireGuard GUI, click 'Activate' to connect"
        exit 0
    fi
    
    # Linux installation
    if [ "$OS" = "linux" ]; then
        echo -e "${CYAN}Installing for Linux...${NC}"
        
        # Check root
        if [ "$EUID" -ne 0 ]; then 
            echo -e "${RED}Error: Run script with sudo${NC}"
            echo "  sudo ./install.sh"
            exit 1
        fi
        
        # Detect Linux distribution
        if [ -f /etc/os-release ]; then
            . /etc/os-release
            DISTRO=$ID
        else
            echo -e "${RED}Unable to detect Linux distribution${NC}"
            exit 1
        fi
        
        # Install WireGuard
        echo -e "${CYAN}Installing WireGuard...${NC}"
        case $DISTRO in
            ubuntu|debian)
                apt-get update -qq
                apt-get install -y wireguard wireguard-tools >/dev/null 2>&1
                ;;
            centos|rhel|fedora)
                if [ "$DISTRO" = "fedora" ]; then
                    dnf install -y wireguard-tools >/dev/null 2>&1
                else
                    yum install -y epel-release >/dev/null 2>&1
                    yum install -y wireguard-tools >/dev/null 2>&1
                fi
                ;;
            arch|manjaro)
                pacman -S --noconfirm wireguard-tools >/dev/null 2>&1
                ;;
            *)
                echo -e "${RED}Unsupported distribution${NC}"
                exit 1
                ;;
        esac
        echo -e "${GREEN}✓ WireGuard installed${NC}"
        
        # Copy config
        CONFIG_NAME=$(basename "$CONFIG_FILE" .conf)
        if [ "$CONFIG_NAME" = "client" ]; then
            CONFIG_NAME="wg0"
        fi
        WG_CONFIG_DIR="/etc/wireguard"
        cp "$CONFIG_FILE" "$WG_CONFIG_DIR/${CONFIG_NAME}.conf"
        chmod 600 "$WG_CONFIG_DIR/${CONFIG_NAME}.conf"
        echo -e "${GREEN}✓ Config copied${NC}"
        
        # Enable and start service
        echo -e "${CYAN}Starting tunnel...${NC}"
        systemctl enable wg-quick@${CONFIG_NAME} >/dev/null 2>&1
        systemctl start wg-quick@${CONFIG_NAME} >/dev/null 2>&1
        
        sleep 2
        if systemctl is-active --quiet wg-quick@${CONFIG_NAME}; then
            echo -e "${GREEN}✓ Tunnel started${NC}"
            echo ""
            echo -e "${CYAN}Status:${NC}"
            wg show ${CONFIG_NAME}
        else
            echo -e "${RED}Error starting tunnel${NC}"
            systemctl status wg-quick@${CONFIG_NAME}
            exit 1
        fi
        
        echo ""
        echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║              Client installed successfully!              ║${NC}"
        echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo "Management:"
        echo "  Status: systemctl status wg-quick@${CONFIG_NAME}"
        echo "  Stop: systemctl stop wg-quick@${CONFIG_NAME}"
        echo "  Start: systemctl start wg-quick@${CONFIG_NAME}"
        exit 0
    fi
fi
