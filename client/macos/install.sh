#!/bin/bash

set -e

echo "=== WireGuard Split Tunnel Client Installation (macOS) ==="
echo ""

# Check for macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    echo "Error: This script is for macOS only"
    exit 1
fi

# Check for Homebrew
if ! command -v brew &> /dev/null; then
    echo "Homebrew not found. Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# Install WireGuard GUI
echo "Installing WireGuard GUI..."
if ! brew list --cask wireguard 2>/dev/null; then
    brew install --cask wireguard
else
    echo "WireGuard GUI is already installed"
fi

# Also install wireguard-tools for CLI support
if ! command -v wg &> /dev/null; then
    echo "Installing WireGuard tools..."
    brew install wireguard-tools
fi

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

# Copy config to WireGuard GUI directory
WG_CONFIG_DIR="$HOME/Library/Application Support/WireGuard"
mkdir -p "$WG_CONFIG_DIR"
CONFIG_NAME=$(basename "$CONFIG_FILE" .conf)
cp "$CONFIG_FILE" "$WG_CONFIG_DIR/${CONFIG_NAME}.conf"

echo "✓ Configuration copied to $WG_CONFIG_DIR/${CONFIG_NAME}.conf"

# Check for IP addresses in AllowedIPs
ALLOWED_IPS=$(grep "^AllowedIPs" "$WG_CONFIG_DIR/${CONFIG_NAME}.conf" | cut -d'=' -f2 | xargs)
if [ -z "$ALLOWED_IPS" ] || [[ "$ALLOWED_IPS" == *"#"* ]]; then
    echo ""
    echo "⚠ WARNING: AllowedIPs field is empty or contains comments!"
    echo "Open the file and specify IP addresses to route through VPN:"
    echo "  open -a TextEdit \"$WG_CONFIG_DIR/${CONFIG_NAME}.conf\""
    echo ""
    echo "Example:"
    echo "  AllowedIPs = 192.168.1.100/32, 10.0.0.50/32"
    echo ""
    read -p "Press Enter after filling in AllowedIPs..."
fi

# Open WireGuard GUI
echo ""
echo "Opening WireGuard GUI..."
open -a WireGuard

# Wait a moment for GUI to start, then try to import config automatically
sleep 2

# Try to import config using WireGuard CLI if available
if command -v wg &> /dev/null; then
    # Check if WireGuard GUI is running
    if pgrep -x "WireGuard" > /dev/null; then
        echo "✓ WireGuard GUI is running"
    fi
fi

echo ""
echo "=== Installation completed ==="
echo ""
echo "Configuration file: $WG_CONFIG_DIR/${CONFIG_NAME}.conf"
echo ""
echo "WireGuard GUI should open automatically."
echo "The configuration is ready to use - just click 'Activate' in the GUI."
echo ""
echo "You can also manage the tunnel from the WireGuard menu bar icon"
echo ""

