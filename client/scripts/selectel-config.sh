#!/bin/bash
# Selectel API Configuration Setup
# Sets up API token and server ID for automatic server control

set -e

# Load environment variables from .env file if exists
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/../../.env" ]; then
    set +a
    source "$SCRIPT_DIR/../../.env" 2>/dev/null || true
    set -a
fi

CONFIG_FILE="${HOME}/.selectel-vpn-config"

echo "=== Selectel VDS API Configuration ==="
echo ""
echo "This script will configure automatic VDS start/stop when connecting to VPN."
echo "This saves money by only paying when VPN is in use!"
echo ""
echo "To get your API token:"
echo "1. Go to Selectel Control Panel: https://panel.selectel.com/"
echo "2. Navigate to: API → Tokens"
echo "3. Click 'Create Token'"
echo "4. Give it a name (e.g., 'VPN Auto Control')"
echo "5. Select permissions: 'Servers' (read and write)"
echo "6. Copy the token immediately (you won't see it again!)"
echo ""
echo "To find your VDS Server ID:"
echo "1. Go to your VDS server in Selectel panel"
echo "2. Server ID is in the URL: .../servers/12345/..."
echo "   Or check server details page (ID field)"
echo ""

# Try to get from environment first
if [ -z "$SELECTEL_API_TOKEN" ]; then
    read -p "Enter Selectel API Token: " API_TOKEN
else
    echo "Using SELECTEL_API_TOKEN from environment"
    API_TOKEN="$SELECTEL_API_TOKEN"
fi

if [ -z "$SELECTEL_SERVER_ID" ]; then
    read -p "Enter Server ID: " SERVER_ID
else
    echo "Using SELECTEL_SERVER_ID from environment"
    SERVER_ID="$SELECTEL_SERVER_ID"
fi

if [ -z "$API_TOKEN" ] || [ -z "$SERVER_ID" ]; then
    echo "Error: Both API token and Server ID are required" >&2
    exit 1
fi

# Save configuration
cat > "$CONFIG_FILE" <<EOF
# Selectel API Configuration
# Generated on $(date)
export SELECTEL_API_TOKEN="$API_TOKEN"
export SELECTEL_SERVER_ID="$SERVER_ID"
EOF

chmod 600 "$CONFIG_FILE"

echo ""
echo "✓ Configuration saved to $CONFIG_FILE"
echo ""
echo "Testing connection..."

# Test connection
export SELECTEL_API_TOKEN="$API_TOKEN"
export SELECTEL_SERVER_ID="$SERVER_ID"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if "$SCRIPT_DIR/selectel-server-control.sh" status >/dev/null 2>&1; then
    echo "✓ Connection test successful!"
    echo ""
    echo "Configuration is ready. The server will automatically:"
    echo "  - Start when you connect to VPN"
    echo "  - Stop when you disconnect from VPN"
else
    echo "⚠ Warning: Could not verify connection. Please check your credentials."
    echo "  You can test manually: $SCRIPT_DIR/selectel-server-control.sh status"
fi

echo ""

