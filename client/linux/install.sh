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
        echo "Checking for WireGuard GUI..."
        if apt-cache search wireguard-gui 2>/dev/null | grep -q wireguard-gui; then
            echo "Installing WireGuard GUI..."
            apt-get install -y wireguard-gui || echo "⚠ GUI not available in repositories, using CLI only"
        else
            echo "⚠ WireGuard GUI not found in repositories, using CLI only"
            echo "  You can install GUI manually or use systemctl commands"
        fi
        ;;
    centos|rhel|fedora)
        if [ "$OS" = "fedora" ]; then
            dnf install -y wireguard-tools
            # Try to install GUI
            if dnf search wireguard-gui 2>/dev/null | grep -q wireguard-gui; then
                echo "Installing WireGuard GUI..."
                dnf install -y wireguard-gui || echo "⚠ GUI not available"
            fi
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
            pacman -S --noconfirm wireguard-gui || echo "⚠ GUI not available"
        else
            echo "⚠ WireGuard GUI not found, using CLI only"
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
    echo "=== Installation completed ==="
    echo ""
    echo "Management commands:"
    echo "  Status: systemctl status wg-quick@${CONFIG_NAME}"
    echo "  Stop:   systemctl stop wg-quick@${CONFIG_NAME}"
    echo "  Start:  systemctl start wg-quick@${CONFIG_NAME}"
    echo ""
    # Try to launch GUI if available
    if command -v wireguard-gui &> /dev/null; then
        echo "Launching WireGuard GUI..."
        wireguard-gui &
        echo "✓ GUI launched"
    elif command -v wg-quick &> /dev/null && [ -n "$DISPLAY" ]; then
        echo "Note: If you have a GUI installed, you can manage tunnels through it"
    fi
else
    echo "⚠ Error starting tunnel. Check configuration:"
    systemctl status wg-quick@${CONFIG_NAME}
    exit 1
fi

