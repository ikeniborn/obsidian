#!/bin/bash
#
# Generate docker-compose.serverpeers.yml for multiple vaults
#
# Reads VAULT_COUNT from .env and generates compose file with N ServerPeer services
#
# Usage:
#   bash scripts/generate-serverpeer-compose.sh
#

set -e
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ENV_FILE="/opt/notes/.env"
OUTPUT_FILE="$PROJECT_ROOT/docker-compose.serverpeers.yml"

# Source .env to get VAULT_COUNT
if [[ ! -f "$ENV_FILE" ]]; then
    echo "ERROR: $ENV_FILE not found. Run setup.sh first."
    exit 1
fi

source "$ENV_FILE"

# Default to 1 if VAULT_COUNT not set
VAULT_COUNT=${VAULT_COUNT:-1}

echo "Generating docker-compose.serverpeers.yml for $VAULT_COUNT vault(s)..."

# Write compose file header
cat > "$OUTPUT_FILE" << 'EOF'
# Auto-generated docker-compose for multiple ServerPeer instances
# DO NOT EDIT MANUALLY - regenerate with scripts/generate-serverpeer-compose.sh

services:
EOF

# Generate service for each vault
for ((i=1; i<=VAULT_COUNT; i++)); do
    # Get vault-specific variables
    vault_name_var="VAULT_${i}_NAME"
    vault_roomid_var="VAULT_${i}_ROOMID"
    vault_passphrase_var="VAULT_${i}_PASSPHRASE"
    vault_port_var="VAULT_${i}_PORT"
    vault_container_var="VAULT_${i}_CONTAINER"
    vault_dir_var="VAULT_${i}_VAULT_DIR"

    vault_name="${!vault_name_var:-vault$i}"
    vault_port="${!vault_port_var:-$((3000 + i - 1))}"
    vault_container="${!vault_container_var:-notes-serverpeer-$vault_name}"
    vault_dir="${!vault_dir_var:-/opt/notes/serverpeer-vault-$vault_name}"

    # Convert vault name to lowercase for service name
    service_name=$(echo "$vault_name" | tr '[:upper:]' '[:lower:]')

    cat >> "$OUTPUT_FILE" << EOF

  serverpeer-$service_name:
    build:
      context: ./serverpeer
      dockerfile: Dockerfile
    container_name: \${VAULT_${i}_CONTAINER}
    restart: unless-stopped

    env_file:
      - /opt/notes/.env

    environment:
      SLS_SERVER_PEER_APPID: \${SERVERPEER_APPID}
      SLS_SERVER_PEER_ROOMID: \${VAULT_${i}_ROOMID}
      SLS_SERVER_PEER_PASSPHRASE: \${VAULT_${i}_PASSPHRASE}
      SLS_SERVER_PEER_RELAYS: \${SERVERPEER_RELAYS}
      SLS_SERVER_PEER_NAME: \${VAULT_${i}_NAME}-peer
      SLS_SERVER_PEER_AUTOBROADCAST: \${SERVERPEER_AUTOBROADCAST}
      SLS_SERVER_PEER_AUTOSTART: \${SERVERPEER_AUTOSTART}
      SLS_SERVER_PEER_VAULT_NAME: \${VAULT_${i}_NAME}

    volumes:
      - \${VAULT_${i}_VAULT_DIR}:/app/vault

    ports:
      - "127.0.0.1:\${VAULT_${i}_PORT}:3000"

    networks:
      - notes-network

    # ServerPeer is a P2P client, not an HTTP server
    # Check if deno process is running instead of HTTP endpoint
    healthcheck:
      test: ["CMD", "sh", "-c", "pgrep -f 'deno.*main.ts' > /dev/null"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s

    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 512M
        reservations:
          cpus: '0.1'
          memory: 128M

EOF
done

# Write networks section
cat >> "$OUTPUT_FILE" << 'EOF'

networks:
  notes-network:
    external: ${NETWORK_EXTERNAL:-false}
    name: ${NETWORK_NAME}
EOF

echo "✓ Generated: $OUTPUT_FILE"
echo "  Services: $VAULT_COUNT ServerPeer instance(s)"
