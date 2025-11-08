#!/bin/bash
# Selectel VDS Server Control Script
# Manages VDS by Selectel via API (start/stop/status)
# Usage: ./selectel-server-control.sh start|stop|status

# Don't exit on error in hooks - WireGuard should continue even if server control fails
set +e

ACTION=$1
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${HOME}/.selectel-vpn-config"

# Check if curl is available
if ! command -v curl &> /dev/null; then
    echo "[Selectel] Error: curl is not installed" >&2
    exit 1
fi

# Load environment variables from .env file if exists (project root)
if [ -f "$SCRIPT_DIR/../../.env" ]; then
    set +a
    source "$SCRIPT_DIR/../../.env" 2>/dev/null || true
    set -a
fi

# Load configuration if exists (user config)
if [ -f "$CONFIG_FILE" ]; then
    # Source config file, but don't fail if it doesn't export variables
    set +e
    source "$CONFIG_FILE" 2>/dev/null || true
    set -e
fi

# Environment variables take precedence over config file

# Check if required variables are set
if [ -z "$SELECTEL_API_TOKEN" ] || [ -z "$SELECTEL_SERVER_ID" ]; then
    echo "Error: SELECTEL_API_TOKEN and SELECTEL_SERVER_ID must be set" >&2
    echo "Run setup script: selectel-config.sh setup" >&2
    exit 1
fi

SELECTEL_API_URL="https://api.selvpc.ru/v2/servers"

# Function to get server status
get_server_status() {
    curl -s -X GET \
        -H "X-Token: $SELECTEL_API_TOKEN" \
        "$SELECTEL_API_URL/$SELECTEL_SERVER_ID" 2>/dev/null | \
        grep -o '"status":"[^"]*"' | cut -d'"' -f4 || echo "UNKNOWN"
}

# Function to wait for server to be ready
wait_for_server() {
    local max_attempts=30
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        STATUS=$(get_server_status)
        if [ "$STATUS" = "ACTIVE" ]; then
            return 0
        fi
        attempt=$((attempt + 1))
        sleep 2
    done
    return 1
}

case "$ACTION" in
    start)
        echo "[Selectel] Starting server..."
        
        # Check current status
        CURRENT_STATUS=$(get_server_status)
        if [ "$CURRENT_STATUS" = "ACTIVE" ]; then
            echo "[Selectel] Server is already running"
            exit 0
        fi
        
        # Start server
        RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
            -H "X-Token: $SELECTEL_API_TOKEN" \
            -H "Content-Type: application/json" \
            "$SELECTEL_API_URL/$SELECTEL_SERVER_ID/start" 2>/dev/null)
        
        HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
        BODY=$(echo "$RESPONSE" | head -n-1)
        
        if [ "$HTTP_CODE" != "200" ] && [ "$HTTP_CODE" != "202" ]; then
            echo "[Selectel] Error starting server (HTTP $HTTP_CODE): $BODY" >&2
            exit 1
        fi
        
        echo "[Selectel] Server start command sent. Waiting for server to be ready..."
        
        # Wait for server to start
        if wait_for_server; then
            echo "[Selectel] ✓ Server started successfully"
            # Additional wait for services to initialize
            sleep 5
        else
            echo "[Selectel] ⚠ Server may still be starting. Current status: $(get_server_status)"
        fi
        ;;
        
    stop)
        echo "[Selectel] Stopping server..."
        
        # Check current status
        CURRENT_STATUS=$(get_server_status)
        if [ "$CURRENT_STATUS" = "STOPPED" ] || [ "$CURRENT_STATUS" = "SHUTOFF" ]; then
            echo "[Selectel] Server is already stopped"
            exit 0
        fi
        
        # Stop server
        RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
            -H "X-Token: $SELECTEL_API_TOKEN" \
            -H "Content-Type: application/json" \
            "$SELECTEL_API_URL/$SELECTEL_SERVER_ID/stop" 2>/dev/null)
        
        HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
        BODY=$(echo "$RESPONSE" | head -n-1)
        
        if [ "$HTTP_CODE" != "200" ] && [ "$HTTP_CODE" != "202" ]; then
            echo "[Selectel] Error stopping server (HTTP $HTTP_CODE): $BODY" >&2
            exit 1
        fi
        
        echo "[Selectel] ✓ Server stop command sent"
        ;;
        
    status)
        STATUS=$(get_server_status)
        echo "[Selectel] Server status: $STATUS"
        exit 0
        ;;
        
    *)
        echo "Usage: $0 {start|stop|status}" >&2
        exit 1
        ;;
esac

