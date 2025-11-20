#!/bin/bash
# WireGuard client installation for macOS

set -e

[ "$OSTYPE" != "darwin"* ] && { echo "Error: macOS only"; exit 1; }

# Install Homebrew if needed
command -v brew &>/dev/null || /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install WireGuard
echo "Installing WireGuard..."
brew list --cask wireguard 2>/dev/null || brew install --cask wireguard >/dev/null 2>&1
command -v wg &>/dev/null || brew install wireguard-tools >/dev/null 2>&1

# Find config file
CONFIG_FILE=${1:-$(find . .. -name "client.conf" -o -name "*.conf" 2>/dev/null | head -1)}
[ -z "$CONFIG_FILE" ] && read -p "Enter config path: " CONFIG_FILE
[ ! -f "$CONFIG_FILE" ] && { echo "Error: Config not found: $CONFIG_FILE"; exit 1; }

# Copy config
WG_CONFIG_DIR="$HOME/Library/Application Support/WireGuard"
mkdir -p "$WG_CONFIG_DIR"
CONFIG_NAME=$(basename "$CONFIG_FILE" .conf)
cp "$CONFIG_FILE" "$WG_CONFIG_DIR/${CONFIG_NAME}.conf"

# Check AllowedIPs
ALLOWED_IPS=$(grep "^AllowedIPs" "$WG_CONFIG_DIR/${CONFIG_NAME}.conf" | cut -d'=' -f2 | xargs)
[ -z "$ALLOWED_IPS" ] || [[ "$ALLOWED_IPS" == *"#"* ]] && {
    echo "⚠ WARNING: AllowedIPs is empty!"
    echo "Edit: open -a TextEdit \"$WG_CONFIG_DIR/${CONFIG_NAME}.conf\""
    read -p "Press Enter after editing..."
}

# Open GUI
open -a WireGuard

echo ""
echo "=== Installation Complete ==="
echo "Config: $WG_CONFIG_DIR/${CONFIG_NAME}.conf"
echo "Click 'Activate' in WireGuard GUI"
