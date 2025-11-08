#!/bin/bash

set -e

echo "=== WireGuard Split Tunnel Client Installation (Linux) ==="
echo ""

# Check for root privileges
if [ "$EUID" -ne 0 ]; then 
    echo "Error: This script must be run as root (use sudo)"
    exit 1
fi

# Detect Linux distribution
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    echo "Error: Unable to detect Linux distribution"
    exit 1
fi

echo "Detected distribution: $OS"
echo ""

# Install WireGuard
echo "Installing WireGuard..."
case $OS in
    ubuntu|debian)
        apt-get update
        apt-get install -y wireguard wireguard-tools
        # Try to install GUI if available
        if apt-cache search wireguard-gui 2>/dev/null | grep -q wireguard-gui; then
            echo "Installing WireGuard GUI..."
            apt-get install -y wireguard-gui || echo "GUI not available in repositories"
        fi
        ;;
    centos|rhel|fedora)
        if [ "$OS" = "fedora" ]; then
            dnf install -y wireguard-tools
        else
            yum install -y epel-release
            yum install -y wireguard-tools
        fi
        ;;
    arch|manjaro)
        pacman -S --noconfirm wireguard-tools
        # Install GUI if available
        if pacman -Ss wireguard-gui 2>/dev/null | grep -q wireguard-gui; then
            echo "Installing WireGuard GUI..."
            pacman -S --noconfirm wireguard-gui || echo "GUI not available"
        fi
        ;;
    *)
        echo "Error: Unsupported distribution. Please install WireGuard manually."
        exit 1
        ;;
esac

# Check for config file
CONFIG_FILE=""
if [ -n "$1" ]; then
    CONFIG_FILE="$1"
elif [ -f "client.conf" ]; then
    CONFIG_FILE="client.conf"
elif [ -f "../config/client.conf" ]; then
    CONFIG_FILE="../config/client.conf"
else
    echo ""
    echo "Configuration file not found."
    read -p "Enter path to WireGuard config: " CONFIG_FILE
fi

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Configuration file not found: $CONFIG_FILE"
    exit 1
fi

# Determine interface name from config
CONFIG_NAME=$(basename "$CONFIG_FILE" .conf)
if [ "$CONFIG_NAME" = "client" ]; then
    CONFIG_NAME="wg0"
fi

# Copy config
WG_CONFIG_DIR="/etc/wireguard"
cp "$CONFIG_FILE" "$WG_CONFIG_DIR/${CONFIG_NAME}.conf"
chmod 600 "$WG_CONFIG_DIR/${CONFIG_NAME}.conf"

echo "✓ Configuration copied to $WG_CONFIG_DIR/${CONFIG_NAME}.conf"

# Check if config has server control hooks
if grep -q "SELECTEL_CONTROL_SCRIPT" "$WG_CONFIG_DIR/${CONFIG_NAME}.conf"; then
    echo ""
    echo "Detected automatic server control hooks in config..."
    
    # Copy server control scripts
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    SCRIPTS_DIR="/usr/local/bin"
    
    if [ -f "$SCRIPT_DIR/../scripts/selectel-server-control.sh" ]; then
        cp "$SCRIPT_DIR/../scripts/selectel-server-control.sh" "$SCRIPTS_DIR/"
        cp "$SCRIPT_DIR/../scripts/selectel-config.sh" "$SCRIPTS_DIR/"
        chmod +x "$SCRIPTS_DIR/selectel-server-control.sh"
        chmod +x "$SCRIPTS_DIR/selectel-config.sh"
        
        # Update config with script path
        CONTROL_SCRIPT="$SCRIPTS_DIR/selectel-server-control.sh"
        sed -i "s|SELECTEL_CONTROL_SCRIPT|$CONTROL_SCRIPT|g" "$WG_CONFIG_DIR/${CONFIG_NAME}.conf"
        
        echo "✓ Server control scripts installed to $SCRIPTS_DIR"
        echo ""
        echo "⚠ IMPORTANT: Configure Selectel API credentials:"
        echo "  $SCRIPTS_DIR/selectel-config.sh setup"
        echo ""
        read -p "Do you want to configure Selectel API now? (y/n): " CONFIGURE_NOW
        if [ "$CONFIGURE_NOW" = "y" ] || [ "$CONFIGURE_NOW" = "Y" ]; then
            "$SCRIPTS_DIR/selectel-config.sh" setup
        else
            echo "Remember to configure it before using the tunnel!"
        fi
    else
        echo "⚠ Warning: Server control scripts not found. Please install them manually."
    fi
fi

# Check for IP addresses in AllowedIPs
ALLOWED_IPS=$(grep "^AllowedIPs" "$WG_CONFIG_DIR/${CONFIG_NAME}.conf" | cut -d'=' -f2 | xargs)
if [ -z "$ALLOWED_IPS" ] || [[ "$ALLOWED_IPS" == *"#"* ]]; then
    echo ""
    echo "⚠ WARNING: AllowedIPs field is empty or contains comments!"
    echo "Open the file and specify IP addresses to route through VPN:"
    echo "  nano $WG_CONFIG_DIR/${CONFIG_NAME}.conf"
    echo ""
    echo "Example:"
    echo "  AllowedIPs = 192.168.1.100/32, 10.0.0.50/32"
    echo ""
    read -p "Press Enter after filling in AllowedIPs..."
fi

# Enable and start service
echo ""
echo "Configuring autostart..."
systemctl enable wg-quick@${CONFIG_NAME}

echo "Starting WireGuard tunnel..."
systemctl start wg-quick@${CONFIG_NAME}

# Check status
sleep 2
if systemctl is-active --quiet wg-quick@${CONFIG_NAME}; then
    echo "✓ WireGuard tunnel started successfully"
    echo ""
    echo "Current status:"
    wg show ${CONFIG_NAME}
    echo ""
    echo "To stop the tunnel, use:"
    echo "  systemctl stop wg-quick@${CONFIG_NAME}"
    echo ""
    echo "To check status:"
    echo "  systemctl status wg-quick@${CONFIG_NAME}"
    echo ""
    echo "Note: If you have a GUI installed, you can also manage tunnels through it"
else
    echo "⚠ Error starting tunnel. Check configuration:"
    systemctl status wg-quick@${CONFIG_NAME}
    exit 1
fi

