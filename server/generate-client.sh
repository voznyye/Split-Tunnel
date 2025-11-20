#!/bin/bash
# Generate WireGuard client configuration
# Usage: ./generate-client.sh <client_name> [IP_addresses]

set -e

# Load .env if exists
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$SCRIPT_DIR/../.env" ] && source "$SCRIPT_DIR/../.env" 2>/dev/null || true

[ "$#" -lt 1 ] && { echo "Usage: $0 <client_name> [IP_addresses]"; exit 1; }

CLIENT_NAME=$1
ALLOWED_IPS=${2:-""}
WG_DIR="/etc/wireguard"
CLIENTS_DIR="$WG_DIR/clients"

# Check root
[ "$EUID" -ne 0 ] && { echo "Error: Run with sudo"; exit 1; }
[ ! -f "$WG_DIR/wg0.conf" ] && { echo "Error: Server config not found. Run install.sh first"; exit 1; }

mkdir -p $CLIENTS_DIR
cd $CLIENTS_DIR

# Generate client keys
CLIENT_PRIVATE_KEY=$(wg genkey)
CLIENT_PUBLIC_KEY=$(echo $CLIENT_PRIVATE_KEY | wg pubkey)

# Get server data
SERVER_PUBLIC_KEY=$(cat $WG_DIR/server_public.key)
SERVER_IP=${SERVER_IP:-$(grep Endpoint $WG_DIR/wg0.conf 2>/dev/null | grep -oP '\d+\.\d+\.\d+\.\d+' | head -1 || curl -s ifconfig.me 2>/dev/null || echo "")}
[ -z "$SERVER_IP" ] && read -p "Enter server IP: " SERVER_IP
WG_PORT=${WG_PORT:-$(grep ListenPort $WG_DIR/wg0.conf 2>/dev/null | awk '{print $3}' || echo "51820")}
CLIENT_DNS=${CLIENT_DNS:-"8.8.8.8"}

# Determine client VPN IP
LAST_IP=$(grep -oP '10\.0\.0\.\d+' $WG_DIR/wg0.conf | sort -t. -k4 -n | tail -1 | cut -d. -f4 || echo "1")
CLIENT_VPN_IP="10.0.0.$((LAST_IP + 1))"

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
AllowedIPs = ${ALLOWED_IPS:-# Specify IPs to route through VPN (split tunnel)
# Example: AllowedIPs = 192.168.1.100/32, 10.0.0.50/32
# Full tunnel: AllowedIPs = 0.0.0.0/0, ::/0}
EOF

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
echo "=== Client Config Created ==="
echo "File: $CLIENT_CONF"
echo ""
qrencode -t ANSI < $CLIENT_CONF
echo ""
echo "Transfer: cat $CLIENT_CONF"
