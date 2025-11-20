#!/bin/bash
# WireGuard client installation for Linux

set -e

[ "$EUID" -ne 0 ] && { echo "Error: Run with sudo"; exit 1; }

# Detect OS
[ -f /etc/os-release ] && . /etc/os-release || { echo "Error: Cannot detect OS"; exit 1; }
OS=$ID

# Install WireGuard
echo "Installing WireGuard..."
case $OS in
    ubuntu|debian) apt-get update -qq && apt-get install -y wireguard wireguard-tools ;;
    centos|rhel) yum install -y epel-release && yum install -y wireguard-tools ;;
    fedora) dnf install -y wireguard-tools ;;
    arch|manjaro) pacman -S --noconfirm wireguard-tools ;;
    *) echo "Error: Unsupported OS"; exit 1 ;;
esac

# Find config file
CONFIG_FILE=${1:-$(find . .. -name "client.conf" -o -name "*.conf" 2>/dev/null | head -1)}
[ -z "$CONFIG_FILE" ] && read -p "Enter config path: " CONFIG_FILE
[ ! -f "$CONFIG_FILE" ] && { echo "Error: Config not found: $CONFIG_FILE"; exit 1; }

# Copy config
CONFIG_NAME=$(basename "$CONFIG_FILE" .conf)
[ "$CONFIG_NAME" = "client" ] && CONFIG_NAME="wg0"
cp "$CONFIG_FILE" "/etc/wireguard/${CONFIG_NAME}.conf"
chmod 600 "/etc/wireguard/${CONFIG_NAME}.conf"

# Check AllowedIPs
ALLOWED_IPS=$(grep "^AllowedIPs" "/etc/wireguard/${CONFIG_NAME}.conf" | cut -d'=' -f2 | xargs)
[ -z "$ALLOWED_IPS" ] || [[ "$ALLOWED_IPS" == *"#"* ]] && {
    echo "⚠ WARNING: AllowedIPs is empty!"
    echo "Edit: nano /etc/wireguard/${CONFIG_NAME}.conf"
    read -p "Press Enter after editing..."
}

# Start service
systemctl enable wg-quick@${CONFIG_NAME} >/dev/null 2>&1
systemctl start wg-quick@${CONFIG_NAME} >/dev/null 2>&1

sleep 2
systemctl is-active --quiet wg-quick@${CONFIG_NAME} && {
    echo "✓ Tunnel started"
    wg show ${CONFIG_NAME}
} || {
    echo "⚠ Error starting tunnel"
    systemctl status wg-quick@${CONFIG_NAME}
    exit 1
}

echo ""
echo "=== Installation Complete ==="
echo "Status: systemctl status wg-quick@${CONFIG_NAME}"
echo "Stop: systemctl stop wg-quick@${CONFIG_NAME}"
