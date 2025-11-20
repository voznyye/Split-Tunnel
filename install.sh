#!/bin/bash
#
# WireGuard Split Tunnel - Client Installation Script
# 
# Usage:
#   ./install.sh [client.conf]        # Install client with config file
#
# Script automatically:
#   - Detects OS (Linux/macOS)
#   - Installs WireGuard
#   - Configures and starts tunnel
#

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${CYAN}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║        WireGuard Split Tunnel - Client Installer        ║${NC}"
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

# Find configuration file
CONFIG_FILE=""
if [ -n "$1" ]; then
    CONFIG_FILE="$1"
elif [ -f "client.conf" ]; then
    CONFIG_FILE="client.conf"
else
    echo -e "${YELLOW}Configuration file not found.${NC}"
    echo ""
    echo "Choose how to get the config:"
    echo "1) I have a config file"
    echo "2) Download from server (requires SSH access)"
    echo ""
    read -p "Choose (1/2): " CONFIG_CHOICE
    
    case $CONFIG_CHOICE in
        1)
            read -p "Enter path to config file: " CONFIG_FILE
            ;;
        2)
            read -p "Enter server address (user@host): " SERVER_HOST
            read -p "Enter client config name: " CLIENT_NAME
            echo -e "${CYAN}Downloading config from server...${NC}"
            if scp "$SERVER_HOST:/etc/wireguard/clients/${CLIENT_NAME}.conf" ./client.conf 2>/dev/null; then
                CONFIG_FILE="./client.conf"
                if [ -f "$CONFIG_FILE" ]; then
                    echo -e "${GREEN}✓ Config downloaded${NC}"
                else
                    echo -e "${RED}Failed to download config${NC}"
                    exit 1
                fi
            else
                echo -e "${RED}✗ Failed to download config${NC}"
                echo ""
                echo -e "${YELLOW}The config file '/etc/wireguard/clients/${CLIENT_NAME}.conf' was not found on the server.${NC}"
                echo ""
                echo -e "${CYAN}To create the config on the server, use Ansible:${NC}"
                echo -e "  ${GREEN}cd ansible${NC}"
                echo -e "  ${GREEN}ansible-playbook -i inventory.yml generate-client.yml -e 'client_name=${CLIENT_NAME}' -e 'allowed_ips=IP1/32,IP2/32'${NC}"
                echo ""
                exit 1
            fi
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

# Check and fix Endpoint
ENDPOINT=$(grep "^Endpoint" "$CONFIG_FILE" | cut -d'=' -f2 | xargs)
if [[ "$ENDPOINT" == *"YOUR_SERVER_IP"* ]] || [[ "$ENDPOINT" == *"SERVER_IP"* ]] || [[ -z "$ENDPOINT" ]] || [[ ! "$ENDPOINT" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+$ ]] && [[ ! "$ENDPOINT" =~ ^[a-zA-Z0-9.-]+:[0-9]+$ ]]; then
    echo ""
    echo -e "${YELLOW}⚠ WARNING: Endpoint is missing or invalid!${NC}"
    echo "Current Endpoint: ${ENDPOINT:-'(empty)'}"
    echo ""
    echo "Enter server IP address and port (e.g., 192.168.1.100:51820):"
    read -p "Server Endpoint: " SERVER_ENDPOINT
    if [ -n "$SERVER_ENDPOINT" ]; then
        # Remove port if user included it, we'll add it properly
        SERVER_ENDPOINT=$(echo "$SERVER_ENDPOINT" | sed 's/:.*$//')
        PORT=$(grep "^Endpoint" "$CONFIG_FILE" | grep -oE ':[0-9]+' | cut -d: -f2 || echo "51820")
        read -p "Port (default $PORT): " INPUT_PORT
        PORT=${INPUT_PORT:-$PORT}
        
        sed -i.bak "s|^Endpoint =.*|Endpoint = $SERVER_ENDPOINT:$PORT|" "$CONFIG_FILE" 2>/dev/null || \
        sed -i '' "s|^Endpoint =.*|Endpoint = $SERVER_ENDPOINT:$PORT|" "$CONFIG_FILE" 2>/dev/null || true
        echo -e "${GREEN}✓ Endpoint updated${NC}"
    else
        echo -e "${RED}Error: Endpoint is required${NC}"
        exit 1
    fi
fi

# Check AllowedIPs
ALLOWED_IPS=$(grep "^AllowedIPs" "$CONFIG_FILE" | cut -d'=' -f2 | xargs)
if [ -z "$ALLOWED_IPS" ] || [[ "$ALLOWED_IPS" == *"#"* ]]; then
    echo ""
    echo -e "${YELLOW}⚠ WARNING: AllowedIPs field is empty!${NC}"
    echo "Specify IP addresses to route through VPN:"
    read -p "Enter IP addresses (comma-separated): " ALLOWED_IPS
    if [ -n "$ALLOWED_IPS" ]; then
        sed -i.bak "s|AllowedIPs =.*|AllowedIPs = $ALLOWED_IPS|" "$CONFIG_FILE" 2>/dev/null || \
        sed -i '' "s|AllowedIPs =.*|AllowedIPs = $ALLOWED_IPS|" "$CONFIG_FILE" 2>/dev/null || true
        echo -e "${GREEN}✓ AllowedIPs updated${NC}"
    fi
fi

# ============================================================================
# macOS INSTALLATION
# ============================================================================
if [ "$OS" = "macos" ]; then
    echo -e "${CYAN}Installing for macOS...${NC}"
    
    # Check for Homebrew
    if ! command -v brew &> /dev/null; then
        echo -e "${CYAN}Installing Homebrew...${NC}"
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
    
    # Install WireGuard tools
    echo -e "${CYAN}Installing WireGuard tools...${NC}"
    if ! command -v wg &> /dev/null; then
        echo -e "${YELLOW}This may take a few minutes...${NC}"
        
        # Fix potential gettext conflicts
        if brew list gettext &>/dev/null; then
            echo -e "${CYAN}Resolving gettext conflicts...${NC}"
            brew unlink gettext 2>/dev/null || true
        fi
        
        # Install wireguard-tools with automatic conflict resolution
        brew install wireguard-tools || {
            # If installation failed due to conflicts, try to fix and retry
            echo -e "${YELLOW}Resolving conflicts and retrying...${NC}"
            brew link --overwrite gettext 2>/dev/null || true
            brew install wireguard-tools
        }
        
        if [ $? -ne 0 ]; then
            echo -e "${RED}Error: Failed to install wireguard-tools${NC}"
            echo -e "${YELLOW}Try running manually: brew install wireguard-tools${NC}"
            exit 1
        fi
    else
        echo -e "${GREEN}✓ WireGuard tools already installed${NC}"
    fi
    echo -e "${GREEN}✓ WireGuard tools ready${NC}"
    
    # Check for WireGuard GUI
    echo -e "${CYAN}Checking WireGuard GUI...${NC}"
    if [ ! -d "/Applications/WireGuard.app" ]; then
        echo -e "${YELLOW}WireGuard GUI not found. Installing...${NC}"
        
        # Try to install via mas (Mac App Store CLI) if available
        if command -v mas &> /dev/null; then
            echo -e "${CYAN}Installing WireGuard GUI via Mac App Store...${NC}"
            mas install 1451685025 || {
                echo -e "${YELLOW}Failed to install via mas. Please install manually:${NC}"
                echo -e "${CYAN}1. Open Mac App Store${NC}"
                echo -e "${CYAN}2. Search for 'WireGuard'${NC}"
                echo -e "${CYAN}3. Install WireGuard${NC}"
                echo ""
                read -p "Press Enter after installing WireGuard GUI..."
            }
        else
            # Download from official site
            echo -e "${CYAN}Downloading WireGuard GUI from official site...${NC}"
            WG_DMG="/tmp/wireguard.dmg"
            curl -L -o "$WG_DMG" "https://github.com/WireGuard/wireguard-apple/releases/latest/download/WireGuard.dmg" || {
                echo -e "${YELLOW}Failed to download. Please install manually:${NC}"
                echo -e "${CYAN}1. Visit: https://www.wireguard.com/install/${NC}"
                echo -e "${CYAN}2. Download WireGuard for macOS${NC}"
                echo -e "${CYAN}3. Install WireGuard${NC}"
                echo ""
                read -p "Press Enter after installing WireGuard GUI..."
            }
            
            if [ -f "$WG_DMG" ]; then
                hdiutil attach "$WG_DMG" -quiet -nobrowse >/dev/null 2>&1
                cp -R /Volumes/WireGuard/WireGuard.app /Applications/ 2>/dev/null || true
                hdiutil detach /Volumes/WireGuard -quiet >/dev/null 2>&1
                rm -f "$WG_DMG"
            fi
        fi
    fi
    
    if [ -d "/Applications/WireGuard.app" ]; then
        echo -e "${GREEN}✓ WireGuard GUI found${NC}"
    else
        echo -e "${YELLOW}⚠ WireGuard GUI not installed. You can install it later from Mac App Store.${NC}"
    fi
    
    # Copy config to WireGuard directory (GUI automatically detects it)
    WG_CONFIG_DIR="$HOME/Library/Application Support/WireGuard"
    mkdir -p "$WG_CONFIG_DIR"
    CONFIG_NAME=$(basename "$CONFIG_FILE" .conf)
    TARGET_CONFIG="$WG_CONFIG_DIR/${CONFIG_NAME}.conf"
    cp "$CONFIG_FILE" "$TARGET_CONFIG"
    echo -e "${GREEN}✓ Config copied${NC}"
    
    # WireGuard GUI automatically detects configs in its directory
    # Just open the GUI and the config will appear automatically
    if [ -d "/Applications/WireGuard.app" ]; then
        echo ""
        echo -e "${CYAN}Opening WireGuard GUI...${NC}"
        echo -e "${GREEN}✓ Config is ready at: $TARGET_CONFIG${NC}"
        echo -e "${CYAN}The tunnel '$CONFIG_NAME' will appear in WireGuard GUI${NC}"
        
        # Open WireGuard GUI (it will automatically detect the config)
        open -a WireGuard
        
        # Give GUI time to load and detect the config
        sleep 2
        
        echo -e "${GREEN}✓ WireGuard GUI opened${NC}"
        echo -e "${YELLOW}Look for '$CONFIG_NAME' in the tunnel list and click 'Activate'${NC}"
    fi
    
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║              Client installed successfully!              ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Config: $WG_CONFIG_DIR/${CONFIG_NAME}.conf"
    if [ -d "/Applications/WireGuard.app" ]; then
        echo "In WireGuard GUI, click 'Activate' to connect"
    else
        echo ""
        echo -e "${YELLOW}To use WireGuard GUI:${NC}"
        echo "1. Install WireGuard from Mac App Store: https://apps.apple.com/app/wireguard/id1451685025"
        echo "2. Or download from: https://www.wireguard.com/install/"
        echo "3. Open WireGuard and import config from: $WG_CONFIG_DIR/${CONFIG_NAME}.conf"
        echo ""
        echo -e "${CYAN}Or use CLI:${NC}"
        echo "  sudo wg-quick up $CONFIG_NAME"
    fi
    exit 0
fi

# ============================================================================
# LINUX INSTALLATION
# ============================================================================
if [ "$OS" = "linux" ]; then
    echo -e "${CYAN}Installing for Linux...${NC}"
    
    # Check root
    if [ "$EUID" -ne 0 ]; then 
        echo -e "${RED}Error: Run script with sudo${NC}"
        echo "  sudo ./install.sh [config.conf]"
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
