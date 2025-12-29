#!/bin/bash
#
# Configure multiple vaults interactively
# This script is called from setup.sh to configure P2P vaults
#

# Helper functions
info() { echo -e "\033[0;34m[INFO]\033[0m $*"; }
success() { echo -e "\033[0;32m[SUCCESS]\033[0m $*"; }
warning() { echo -e "\033[1;33m[WARNING]\033[0m $*"; }
error() { echo -e "\033[0;31m[ERROR]\033[0m $*"; }

# Ask how many vaults
echo ""
info "P2P ServerPeer Configuration - Multiple Vaults"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "You can configure multiple independent vaults with ServerPeer."
echo "Each vault will have:"
echo "  - Unique Room ID and Passphrase"
echo "  - Own ServerPeer container (always-on buffer)"
echo "  - Dedicated port and storage"
echo ""
read -p "How many vaults do you want to configure? [1]: " vault_count
VAULT_COUNT=${vault_count:-1}

if [[ ! "$VAULT_COUNT" =~ ^[1-9][0-9]*$ ]]; then
    error "Invalid number. Using 1 vault."
    VAULT_COUNT=1
fi

success "Configuring $VAULT_COUNT vault(s)"
echo ""

# Configure each vault
for ((i=1; i<=VAULT_COUNT; i++)); do
    echo ""
    info "Vault #$i Configuration"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Vault name
    read -p "Vault #$i name (e.g., Work, Personal, Projects) [Vault$i]: " vault_name
    vault_name=${vault_name:-"Vault$i"}

    # Auto-generate Room ID and Passphrase
    room_id=$(openssl rand -hex 3 | sed 's/\(..\)/\1-/g;s/-$//')
    passphrase=$(openssl rand -hex 16)

    # Calculate port (3001, 3002, 3003, ...)
    port=$((3000 + i))

    # Generate container name and vault dir
    vault_name_lower=$(echo "$vault_name" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
    container="notes-serverpeer-$vault_name_lower"
    vault_dir="/opt/notes/serverpeer-vault-$vault_name_lower"

    # Save variables
    eval "export VAULT_${i}_NAME='$vault_name'"
    eval "export VAULT_${i}_ROOMID='$room_id'"
    eval "export VAULT_${i}_PASSPHRASE='$passphrase'"
    eval "export VAULT_${i}_PORT='$port'"
    eval "export VAULT_${i}_CONTAINER='$container'"
    eval "export VAULT_${i}_VAULT_DIR='$vault_dir'"

    success "Vault '$vault_name' configured"
    echo "  Room ID:    $room_id"
    echo "  Passphrase: $passphrase"
    echo "  Port:       127.0.0.1:$port"
    echo "  Container:  $container"
    echo ""
done

# Configure WebSocket Relay (shared for all vaults)
echo ""
info "WebSocket Relay Configuration (Shared)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "All vaults will use the same Nostr Relay for WebSocket signaling."
echo "Relay URL: wss://${NOTES_DOMAIN:-sync.example.com}${SERVERPEER_LOCATION:-/serverpeer}"
echo ""

export SERVERPEER_RELAYS="wss://${NOTES_DOMAIN:-sync.example.com}${SERVERPEER_LOCATION:-/serverpeer}"
export SERVERPEER_APPID="self-hosted-livesync"
export SERVERPEER_AUTOBROADCAST=true
export SERVERPEER_AUTOSTART=true

# Nostr Relay configuration
export NOSTR_RELAY_PORT=7000
export NOSTR_RELAY_DATA_DIR=/opt/notes/nostr-relay-data
export NOSTR_RELAY_CONTAINER_NAME=notes-nostr-relay
export NOSTR_RELAY_UPSTREAM=notes-nostr-relay

export VAULT_COUNT

success "All vaults configured"
echo ""
echo "Summary:"
echo "  Total vaults: $VAULT_COUNT"
echo "  Relay:        $SERVERPEER_RELAYS"
echo ""

# Print all vault variables for debugging
if [[ "${DEBUG:-}" == "true" ]]; then
    echo "Exported variables:"
    for ((i=1; i<=VAULT_COUNT; i++)); do
        echo "  VAULT_${i}_NAME=$(eval echo \$VAULT_${i}_NAME)"
        echo "  VAULT_${i}_ROOMID=$(eval echo \$VAULT_${i}_ROOMID)"
        echo "  VAULT_${i}_PORT=$(eval echo \$VAULT_${i}_PORT)"
    done
fi
