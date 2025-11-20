#!/bin/bash
# WireGuard server installation script

set -e

# Load .env if exists
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$SCRIPT_DIR/../.env" ] && source "$SCRIPT_DIR/../.env" 2>/dev/null || true

echo "=== WireGuard Server Installation ==="

# Check root
[ "$EUID" -ne 0 ] && { echo "Error: Run with sudo"; exit 1; }

# Detect OS
[ -f /etc/os-release ] && . /etc/os-release || { echo "Error: Cannot detect OS"; exit 1; }
OS=$ID
echo "OS: $OS"

# Install WireGuard
echo "Installing WireGuard..."
case $OS in
    ubuntu|debian) apt-get update -qq && apt-get install -y wireguard wireguard-tools qrencode curl ;;
    centos|rhel) yum install -y epel-release && yum install -y wireguard-tools qrencode curl ;;
    fedora) dnf install -y wireguard-tools qrencode curl ;;
    arch|manjaro) pacman -S --noconfirm wireguard-tools qrencode curl ;;
    *) echo "Error: Unsupported OS"; exit 1 ;;
esac

# Enable IP forwarding
[ "${ENABLE_IP_FORWARDING:-true}" = "true" ] && {
    grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf || echo -e "net.ipv4.ip_forward=1\nnet.ipv6.conf.all.forwarding=1" >> /etc/sysctl.conf
    sysctl -p >/dev/null 2>&1
}

# Setup WireGuard directory
WG_DIR="/etc/wireguard"
mkdir -p $WG_DIR
cd $WG_DIR

# Generate server keys
[ ! -f server_private.key ] && {
    wg genkey | tee server_private.key | wg pubkey > server_public.key
    chmod 600 server_private.key && chmod 644 server_public.key
}
SERVER_PRIVATE_KEY=$(cat server_private.key)
SERVER_PUBLIC_KEY=$(cat server_public.key)

# Detect server IP
SERVER_IP=${SERVER_IP:-$(curl -s ifconfig.me 2>/dev/null || curl -s icanhazip.com 2>/dev/null || echo "")}
[ -z "$SERVER_IP" ] && read -p "Enter server IP: " SERVER_IP

# Detect interface
INTERFACE=${SERVER_INTERFACE:-$(ip route | grep default | awk '{print $5}' | head -n1)}
[ -z "$INTERFACE" ] && read -p "Enter interface (e.g., eth0): " INTERFACE

# Config vars
SERVER_VPN_IP=${SERVER_VPN_IP:-"10.0.0.1"}
WG_PORT=${WG_PORT:-51820}

# Create server config
cat > wg0.conf <<EOF
[Interface]
Address = $SERVER_VPN_IP/24
ListenPort = $WG_PORT
PrivateKey = $SERVER_PRIVATE_KEY
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o $INTERFACE -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o $INTERFACE -j MASQUERADE
EOF
chmod 600 wg0.conf

# Configure firewall
[ "${ENABLE_FIREWALL:-true}" = "true" ] && {
    command -v ufw &>/dev/null && ufw allow $WG_PORT/udp >/dev/null 2>&1 || \
    command -v firewall-cmd &>/dev/null && firewall-cmd --permanent --add-port=$WG_PORT/udp && firewall-cmd --reload >/dev/null 2>&1 || \
    command -v iptables &>/dev/null && iptables -A INPUT -p udp --dport $WG_PORT -j ACCEPT 2>/dev/null || true
}

# Secure SSH
[ "${ENABLE_SSH_SECURITY:-true}" = "true" ] && {
    SSH_CONFIG="/etc/ssh/sshd_config"
    [ -f "$SSH_CONFIG" ] && cp "$SSH_CONFIG" "$SSH_CONFIG.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Check for SSH keys
    HAS_KEYS=$([ -f /root/.ssh/authorized_keys ] && [ -s /root/.ssh/authorized_keys ] || find /home -name authorized_keys -type f 2>/dev/null | grep -q .)
    
    # Configure SSH settings
    [ -f "$SSH_CONFIG" ] && {
        for setting in \
            "PermitRootLogin prohibit-password" \
            "PasswordAuthentication $([ "$HAS_KEYS" ] && echo no || echo yes)" \
            "PubkeyAuthentication yes" \
            "PermitEmptyPasswords no" \
            "X11Forwarding no" \
            "MaxAuthTries ${SSH_MAX_AUTH_TRIES:-3}" \
            "LoginGraceTime ${SSH_LOGIN_GRACE_TIME:-30}"; do
            key="${setting%% *}"
            grep -q "^$key" "$SSH_CONFIG" && sed -i "s|^$key.*|$setting|" "$SSH_CONFIG" || echo "$setting" >> "$SSH_CONFIG"
        done
        
        # Test and restart
        sshd -t -f "$SSH_CONFIG" 2>/dev/null && systemctl restart sshd || cp "$SSH_CONFIG.backup."* "$SSH_CONFIG" 2>/dev/null || true
        
        # Rate limiting
        command -v iptables &>/dev/null && {
            iptables -A INPUT -p tcp --dport ${SSH_PORT:-22} -m state --state ESTABLISHED,RELATED -j ACCEPT
            iptables -A INPUT -p tcp --dport ${SSH_PORT:-22} -m state --state NEW -m recent --set --name SSH
            iptables -A INPUT -p tcp --dport ${SSH_PORT:-22} -m state --state NEW -m recent --update --seconds 60 --hitcount 4 --name SSH -j DROP
            iptables -A INPUT -p tcp --dport ${SSH_PORT:-22} -j ACCEPT
        }
    }
}

# Start WireGuard
systemctl enable wg-quick@wg0 >/dev/null 2>&1
systemctl start wg-quick@wg0 >/dev/null 2>&1
systemctl is-active --quiet wg-quick@wg0 && echo "✓ WireGuard started" || echo "⚠ Check status: systemctl status wg-quick@wg0"

echo ""
echo "=== Installation Complete ==="
echo "Public Key: $SERVER_PUBLIC_KEY"
echo "IP: $SERVER_IP"
echo "Port: $WG_PORT"
echo ""
echo "Create client: ./generate-client.sh <name> [IPs]"
