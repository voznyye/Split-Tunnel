#!/bin/bash
# Load environment variables from .env file
# Usage: source load-env.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load .env file
load_env() {
    [ ! -f "$1" ] && return 1
    while IFS= read -r line || [ -n "$line" ]; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue
        if [[ "$line" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
            local var="${BASH_REMATCH[2]}"
            var="${var#\"}"; var="${var%\"}"; var="${var#\'}"; var="${var%\'}"
            export "${BASH_REMATCH[1]}=$var"
        fi
    done < "$1"
    return 0
}

# Try current and parent directory
load_env "$SCRIPT_DIR/.env" || load_env "$SCRIPT_DIR/../.env" || return 1
