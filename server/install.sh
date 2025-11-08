#!/bin/bash

set -e

# Load environment variables from .env file if exists
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/../.env" ]; then
    set +a
    source "$SCRIPT_DIR/../.env" 2>/dev/null || true
    set -a
fi

echo "=== WireGuard Split Tunnel Server Installation ==="
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
        apt-get install -y wireguard wireguard-tools qrencode
        ;;
    centos|rhel|fedora)
        if [ "$OS" = "fedora" ]; then
            dnf install -y wireguard-tools qrencode
        else
            yum install -y epel-release
            yum install -y wireguard-tools qrencode
        fi
        ;;
    arch|manjaro)
        pacman -S --noconfirm wireguard-tools qrencode
        ;;
    *)
        echo "Error: Unsupported distribution. Please install WireGuard manually."
        exit 1
        ;;
esac

# Enable IP forwarding
ENABLE_IP_FORWARDING=${ENABLE_IP_FORWARDING:-true}
if [ "$ENABLE_IP_FORWARDING" = "true" ]; then
    echo "Configuring IP forwarding..."
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.conf
    sysctl -p
fi

# Create directory for configs
WG_DIR="/etc/wireguard"
mkdir -p $WG_DIR
cd $WG_DIR

# Generate server keys
echo "Generating server keys..."
if [ ! -f server_private.key ]; then
    wg genkey | tee server_private.key | wg pubkey > server_public.key
    chmod 600 server_private.key
    chmod 644 server_public.key
    echo "Server keys created"
else
    echo "Server keys already exist"
fi

SERVER_PRIVATE_KEY=$(cat server_private.key)
SERVER_PUBLIC_KEY=$(cat server_public.key)

# Detect server IP address
echo ""
echo "Detecting server IP address..."
if [ -z "$SERVER_IP" ]; then
    SERVER_IP=$(curl -s ifconfig.me || curl -s icanhazip.com || echo "")
fi
if [ -z "$SERVER_IP" ]; then
    read -p "Unable to detect public IP. Enter server IP address: " SERVER_IP
fi

# Detect network interface
if [ -z "$SERVER_INTERFACE" ]; then
    INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
else
    INTERFACE="$SERVER_INTERFACE"
fi
if [ -z "$INTERFACE" ]; then
    read -p "Enter network interface name (e.g., eth0): " INTERFACE
fi

# VPN network configuration (from env or defaults)
VPN_NETWORK=${VPN_NETWORK:-"10.0.0.0/24"}
SERVER_VPN_IP=${SERVER_VPN_IP:-"10.0.0.1"}
WG_PORT=${WG_PORT:-51820}

# Create server config
echo ""
echo "Creating server configuration..."
cat > wg0.conf <<EOF
[Interface]
Address = $SERVER_VPN_IP/24
ListenPort = $WG_PORT
PrivateKey = $SERVER_PRIVATE_KEY
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o $INTERFACE -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o $INTERFACE -j MASQUERADE

# Clients will be added via generate-client.sh
EOF

chmod 600 wg0.conf

# Configure firewall
ENABLE_FIREWALL=${ENABLE_FIREWALL:-true}
if [ "$ENABLE_FIREWALL" = "true" ]; then
    echo "Configuring firewall..."
    if command -v ufw &> /dev/null; then
        ufw allow $WG_PORT/udp
        echo "UFW configured"
    elif command -v firewall-cmd &> /dev/null; then
        firewall-cmd --permanent --add-port=$WG_PORT/udp
        firewall-cmd --reload
        echo "Firewalld configured"
    elif command -v iptables &> /dev/null; then
        iptables -A INPUT -p udp --dport $WG_PORT -j ACCEPT
        echo "IPTables configured"
    fi
fi

# Secure SSH access
ENABLE_SSH_SECURITY=${ENABLE_SSH_SECURITY:-true}
if [ "$ENABLE_SSH_SECURITY" = "true" ]; then
    echo ""
    echo "Securing SSH access..."
    SSH_CONFIG="/etc/ssh/sshd_config"
    SSH_CONFIG_BACKUP="/etc/ssh/sshd_config.backup.$(date +%Y%m%d_%H%M%S)"
    SSH_PORT=${SSH_PORT:-22}
    SSH_MAX_AUTH_TRIES=${SSH_MAX_AUTH_TRIES:-3}
    SSH_LOGIN_GRACE_TIME=${SSH_LOGIN_GRACE_TIME:-30}

# Backup SSH config
if [ -f "$SSH_CONFIG" ]; then
    cp "$SSH_CONFIG" "$SSH_CONFIG_BACKUP"
    echo "SSH config backed up to: $SSH_CONFIG_BACKUP"
fi

# Check if SSH keys exist for root or any user
HAS_SSH_KEYS=false
if [ -f /root/.ssh/authorized_keys ] && [ -s /root/.ssh/authorized_keys ]; then
    HAS_SSH_KEYS=true
    echo "✓ SSH keys found for root"
elif find /home -name authorized_keys -type f 2>/dev/null | grep -q .; then
    HAS_SSH_KEYS=true
    echo "✓ SSH keys found for users"
fi

# Configure SSH security settings
if [ -f "$SSH_CONFIG" ]; then
    # Disable root login with password (keep key-based login)
    if grep -q "^PermitRootLogin" "$SSH_CONFIG"; then
        sed -i 's/^PermitRootLogin.*/PermitRootLogin prohibit-password/' "$SSH_CONFIG"
    else
        echo "PermitRootLogin prohibit-password" >> "$SSH_CONFIG"
    fi
    
    # Disable password authentication (only if SSH keys exist)
    if [ "$HAS_SSH_KEYS" = true ]; then
        if grep -q "^PasswordAuthentication" "$SSH_CONFIG"; then
            sed -i 's/^PasswordAuthentication.*/PasswordAuthentication no/' "$SSH_CONFIG"
        else
            echo "PasswordAuthentication no" >> "$SSH_CONFIG"
        fi
        echo "✓ Password authentication disabled (using SSH keys only)"
    else
        echo "⚠ Warning: No SSH keys found. Keeping password authentication enabled."
        echo "  Please add SSH keys before disabling password authentication."
        if grep -q "^PasswordAuthentication" "$SSH_CONFIG"; then
            sed -i 's/^PasswordAuthentication.*/PasswordAuthentication yes/' "$SSH_CONFIG"
        else
            echo "PasswordAuthentication yes" >> "$SSH_CONFIG"
        fi
    fi
    
    # Enable public key authentication
    if grep -q "^PubkeyAuthentication" "$SSH_CONFIG"; then
        sed -i 's/^PubkeyAuthentication.*/PubkeyAuthentication yes/' "$SSH_CONFIG"
    else
        echo "PubkeyAuthentication yes" >> "$SSH_CONFIG"
    fi
    
    # Disable empty passwords
    if grep -q "^PermitEmptyPasswords" "$SSH_CONFIG"; then
        sed -i 's/^PermitEmptyPasswords.*/PermitEmptyPasswords no/' "$SSH_CONFIG"
    else
        echo "PermitEmptyPasswords no" >> "$SSH_CONFIG"
    fi
    
    # Disable X11 forwarding (security best practice)
    if grep -q "^X11Forwarding" "$SSH_CONFIG"; then
        sed -i 's/^X11Forwarding.*/X11Forwarding no/' "$SSH_CONFIG"
    else
        echo "X11Forwarding no" >> "$SSH_CONFIG"
    fi
    
    # Set maximum authentication attempts
    if grep -q "^MaxAuthTries" "$SSH_CONFIG"; then
        sed -i "s/^MaxAuthTries.*/MaxAuthTries $SSH_MAX_AUTH_TRIES/" "$SSH_CONFIG"
    else
        echo "MaxAuthTries $SSH_MAX_AUTH_TRIES" >> "$SSH_CONFIG"
    fi
    
    # Set login grace time
    if grep -q "^LoginGraceTime" "$SSH_CONFIG"; then
        sed -i "s/^LoginGraceTime.*/LoginGraceTime $SSH_LOGIN_GRACE_TIME/" "$SSH_CONFIG"
    else
        echo "LoginGraceTime $SSH_LOGIN_GRACE_TIME" >> "$SSH_CONFIG"
    fi
    
    # Disable root login via password (prohibit-password allows only keys)
    echo "✓ SSH security settings configured"
    
    # Test SSH config before applying
    if sshd -t -f "$SSH_CONFIG" 2>/dev/null; then
        systemctl restart sshd
        echo "✓ SSH configuration applied successfully"
    else
        echo "⚠ Warning: SSH config test failed. Restoring backup..."
        cp "$SSH_CONFIG_BACKUP" "$SSH_CONFIG"
        echo "Original SSH config restored. Please check manually."
    fi
    
    # Configure SSH rate limiting with iptables
    if command -v iptables &> /dev/null; then
        echo "Configuring SSH rate limiting..."
        # Allow established connections
        iptables -A INPUT -p tcp --dport $SSH_PORT -m state --state ESTABLISHED,RELATED -j ACCEPT
        # Rate limit new SSH connections
        iptables -A INPUT -p tcp --dport $SSH_PORT -m state --state NEW -m recent --set --name SSH
        iptables -A INPUT -p tcp --dport $SSH_PORT -m state --state NEW -m recent --update --seconds 60 --hitcount 4 --name SSH -j DROP
        iptables -A INPUT -p tcp --dport $SSH_PORT -j ACCEPT
        echo "✓ SSH rate limiting configured (max 4 connections per minute)"
    fi
fi

# Start WireGuard
echo ""
echo "Starting WireGuard..."
systemctl enable wg-quick@wg0
systemctl start wg-quick@wg0

# Check status
if systemctl is-active --quiet wg-quick@wg0; then
    echo "✓ WireGuard started successfully"
else
    echo "⚠ Warning: WireGuard may not be running. Check status: systemctl status wg-quick@wg0"
fi

echo ""
echo "=== Installation completed ==="
echo ""
echo "Server public key: $SERVER_PUBLIC_KEY"
echo "Server IP address: $SERVER_IP"
echo "Port: $WG_PORT"
echo "VPN network: $VPN_NETWORK"
echo ""
echo "To create a client config, use:"
echo "  ./generate-client.sh <client_name>"
echo ""

