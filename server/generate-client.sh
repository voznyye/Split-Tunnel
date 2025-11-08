#!/bin/bash

set -e

# Load environment variables from .env file if exists
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/../.env" ]; then
    set +a
    source "$SCRIPT_DIR/../.env" 2>/dev/null || true
    set -a
fi

if [ "$#" -lt 1 ]; then
    echo "Usage: $0 <client_name> [IP_addresses_for_routing] [--auto-server-control]"
    echo ""
    echo "Example:"
    echo "  $0 client1 192.168.1.100/32,10.0.0.50/32"
    echo "  $0 client1 192.168.1.100/32,10.0.0.50/32 --auto-server-control"
    echo ""
    echo "Options:"
    echo "  --auto-server-control  Enable automatic VDS start/stop via Selectel API"
    echo ""
    echo "If IP addresses are not specified, a template with comments will be created"
    exit 1
fi

CLIENT_NAME=$1
ALLOWED_IPS=${2:-""}
ENABLE_AUTO_SERVER_CONTROL=false

# Check for auto-server-control flag
for arg in "$@"; do
    if [ "$arg" = "--auto-server-control" ]; then
        ENABLE_AUTO_SERVER_CONTROL=true
        break
    fi
done

WG_DIR="/etc/wireguard"
CLIENTS_DIR="$WG_DIR/clients"

# Check for root privileges
if [ "$EUID" -ne 0 ]; then 
    echo "Error: This script must be run as root (use sudo)"
    exit 1
fi

# Check if server config exists
if [ ! -f "$WG_DIR/wg0.conf" ]; then
    echo "Error: Server configuration not found. Please run install.sh first"
    exit 1
fi

mkdir -p $CLIENTS_DIR
cd $CLIENTS_DIR

# Generate client keys
echo "Generating keys for client: $CLIENT_NAME"
CLIENT_PRIVATE_KEY=$(wg genkey)
CLIENT_PUBLIC_KEY=$(echo $CLIENT_PRIVATE_KEY | wg pubkey)

# Get server data
SERVER_PUBLIC_KEY=$(cat $WG_DIR/server_public.key)

# Get SERVER_IP from env, config, or detect
if [ -z "$SERVER_IP" ]; then
    SERVER_IP=$(grep Endpoint $WG_DIR/wg0.conf 2>/dev/null | head -1 | grep -oP '\d+\.\d+\.\d+\.\d+' | head -1 || echo "")
fi
if [ -z "$SERVER_IP" ]; then
    SERVER_IP=$(curl -s ifconfig.me || curl -s icanhazip.com || echo "")
fi
if [ -z "$SERVER_IP" ]; then
    read -p "Enter server IP address: " SERVER_IP
fi

# Get WG_PORT from env, config, or use default
if [ -z "$WG_PORT" ]; then
    WG_PORT=$(grep ListenPort $WG_DIR/wg0.conf 2>/dev/null | awk '{print $3}' | head -1)
fi
WG_PORT=${WG_PORT:-51820}

CLIENT_DNS=${CLIENT_DNS:-"8.8.8.8"}

# Determine next client IP
LAST_IP=$(grep -oP '10\.0\.0\.\d+' $WG_DIR/wg0.conf | sort -t. -k4 -n | tail -1 | cut -d. -f4)
if [ -z "$LAST_IP" ]; then
    CLIENT_VPN_IP="10.0.0.2"
else
    NEXT_IP=$((LAST_IP + 1))
    CLIENT_VPN_IP="10.0.0.$NEXT_IP"
fi

# Create client config
CLIENT_CONF="$CLIENTS_DIR/${CLIENT_NAME}.conf"
cat > $CLIENT_CONF <<EOF
[Interface]
PrivateKey = $CLIENT_PRIVATE_KEY
Address = $CLIENT_VPN_IP/24
DNS = $CLIENT_DNS

[Peer]
PublicKey = $SERVER_PUBLIC_KEY
Endpoint = $SERVER_IP:$WG_PORT
AllowedIPs = 
EOF

# Add IP addresses for routing
if [ -n "$ALLOWED_IPS" ]; then
    # Replace AllowedIPs with specified addresses
    sed -i "s|AllowedIPs =|AllowedIPs = $ALLOWED_IPS|" $CLIENT_CONF
    echo "✓ IP addresses added: $ALLOWED_IPS"
else
    # Add comment for manual filling
    cat >> $CLIENT_CONF <<EOF
# Specify IP addresses to route through VPN (split tunnel)
# Example: AllowedIPs = 192.168.1.100/32, 10.0.0.50/32
# To route all traffic, use: AllowedIPs = 0.0.0.0/0, ::/0
EOF
    echo "⚠ Template created. Don't forget to specify IP addresses in the AllowedIPs field"
fi

# Add server control hooks if enabled
if [ "$ENABLE_AUTO_SERVER_CONTROL" = true ]; then
    echo ""
    echo "Adding automatic server control hooks..."
    # Note: Client needs to configure the script path after copying config
    # We'll add placeholders that need to be replaced on client side
    sed -i '/^\[Interface\]/a # Auto server control hooks (configure path on client)' "$CLIENT_CONF"
    sed -i '/^# Auto server control hooks/a PreUp = SELECTEL_CONTROL_SCRIPT start' "$CLIENT_CONF"
    sed -i '/^PreUp = SELECTEL_CONTROL_SCRIPT start/a PostDown = SELECTEL_CONTROL_SCRIPT stop' "$CLIENT_CONF"
    echo "✓ Server control hooks added (configure script path on client)"
fi

# Add client to server config
echo ""
echo "Adding client to server configuration..."
cat >> $WG_DIR/wg0.conf <<EOF

# Client: $CLIENT_NAME
[Peer]
PublicKey = $CLIENT_PUBLIC_KEY
AllowedIPs = $CLIENT_VPN_IP/32
EOF

# Reload WireGuard
echo "Reloading WireGuard..."
wg syncconf wg0 <(wg-quick strip wg0)

echo ""
echo "=== Client config created ==="
echo ""
echo "File: $CLIENT_CONF"
echo ""
echo "QR code for mobile devices:"
qrencode -t ANSI < $CLIENT_CONF
echo ""
echo "To transfer the config, use:"
echo "  cat $CLIENT_CONF"
echo ""

