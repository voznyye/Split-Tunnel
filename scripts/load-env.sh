#!/bin/bash
# Load environment variables from .env file
# Usage: source load-env.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

# Function to load .env file
load_env() {
    local env_file="$1"
    
    if [ ! -f "$env_file" ]; then
        return 1
    fi
    
    # Read .env file and export variables
    # Ignore comments and empty lines
    while IFS= read -r line || [ -n "$line" ]; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue
        
        # Export variable if it contains =
        if [[ "$line" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
            local var_name="${BASH_REMATCH[1]}"
            local var_value="${BASH_REMATCH[2]}"
            
            # Remove quotes if present
            var_value="${var_value#\"}"
            var_value="${var_value%\"}"
            var_value="${var_value#\'}"
            var_value="${var_value%\'}"
            
            # Export variable
            export "$var_name=$var_value"
        fi
    done < "$env_file"
    
    return 0
}

# Try to load .env file
if load_env "$ENV_FILE"; then
    return 0
else
    # Try parent directory
    if load_env "$SCRIPT_DIR/../.env"; then
        return 0
    fi
fi

return 1

