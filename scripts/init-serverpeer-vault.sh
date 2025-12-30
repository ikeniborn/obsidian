#!/bin/bash
#
# Initialize ServerPeer vault with P2P enabled
#
# This script creates the obsidian-livesync plugin configuration
# with P2P sync enabled for headless vault.
#
# Usage:
#   bash scripts/init-serverpeer-vault.sh <vault_number>
#
# Example:
#   bash scripts/init-serverpeer-vault.sh 1  # Initialize VAULT_1
#
# Author: Obsidian Sync Server Team
# Version: 1.0.0
# Date: 2025-12-30
#

set -e
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ENV_FILE="/opt/notes/.env"
TEMPLATE_FILE="$PROJECT_ROOT/templates/serverpeer-data.json.template"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*"
    exit 1
}

# Check arguments
if [[ $# -lt 1 ]]; then
    error "Usage: $0 <vault_number>
Example: $0 1  # Initialize VAULT_1"
fi

VAULT_NUM="$1"

# Load environment variables
if [[ ! -f "$ENV_FILE" ]]; then
    error "Environment file not found: $ENV_FILE
Run setup.sh first to create configuration."
fi

source "$ENV_FILE"

# Get vault-specific variables
VAULT_NAME_VAR="VAULT_${VAULT_NUM}_NAME"
VAULT_ROOMID_VAR="VAULT_${VAULT_NUM}_ROOMID"
VAULT_PASSPHRASE_VAR="VAULT_${VAULT_NUM}_PASSPHRASE"
VAULT_DIR_VAR="VAULT_${VAULT_NUM}_VAULT_DIR"

VAULT_NAME="${!VAULT_NAME_VAR:-}"
VAULT_ROOMID="${!VAULT_ROOMID_VAR:-}"
VAULT_PASSPHRASE="${!VAULT_PASSPHRASE_VAR:-}"
VAULT_DIR="${!VAULT_DIR_VAR:-}"

# Validate variables
if [[ -z "$VAULT_NAME" ]]; then
    error "VAULT_${VAULT_NUM}_NAME not found in $ENV_FILE"
fi

if [[ -z "$VAULT_ROOMID" ]]; then
    error "VAULT_${VAULT_NUM}_ROOMID not found in $ENV_FILE"
fi

if [[ -z "$VAULT_PASSPHRASE" ]]; then
    error "VAULT_${VAULT_NUM}_PASSPHRASE not found in $ENV_FILE"
fi

if [[ -z "$VAULT_DIR" ]]; then
    error "VAULT_${VAULT_NUM}_VAULT_DIR not found in $ENV_FILE"
fi

# Check common variables
if [[ -z "${SERVERPEER_APPID:-}" ]]; then
    error "SERVERPEER_APPID not found in $ENV_FILE"
fi

if [[ -z "${SERVERPEER_RELAYS:-}" ]]; then
    error "SERVERPEER_RELAYS not found in $ENV_FILE"
fi

info "Initializing vault: $VAULT_NAME (VAULT_$VAULT_NUM)"
info "Vault directory: $VAULT_DIR"

# Create vault directory if not exists
if [[ ! -d "$VAULT_DIR" ]]; then
    info "Creating vault directory..."
    sudo mkdir -p "$VAULT_DIR"
    sudo chown $(whoami):$(whoami) "$VAULT_DIR"
fi

# Create .obsidian structure
OBSIDIAN_DIR="$VAULT_DIR/.obsidian"
PLUGIN_DIR="$OBSIDIAN_DIR/plugins/obsidian-livesync"

if [[ ! -d "$PLUGIN_DIR" ]]; then
    info "Creating .obsidian plugin structure..."
    sudo mkdir -p "$PLUGIN_DIR"
    sudo chown -R $(whoami):$(whoami) "$OBSIDIAN_DIR"
fi

# Check if data.json already exists
DATA_JSON="$PLUGIN_DIR/data.json"

if [[ -f "$DATA_JSON" ]]; then
    # Backup existing data.json
    BACKUP_FILE="$DATA_JSON.backup.$(date +%Y%m%d_%H%M%S)"
    warning "data.json already exists, creating backup: $BACKUP_FILE"
    sudo cp "$DATA_JSON" "$BACKUP_FILE"

    # Check if P2P is already enabled
    if grep -q '"P2P_Enabled": true' "$DATA_JSON" 2>/dev/null; then
        success "P2P already enabled in $DATA_JSON"
        exit 0
    else
        info "P2P is disabled, updating configuration..."
    fi
fi

# Check template exists
if [[ ! -f "$TEMPLATE_FILE" ]]; then
    error "Template file not found: $TEMPLATE_FILE"
fi

# Generate data.json from template
info "Generating data.json from template..."

sudo cp "$TEMPLATE_FILE" "$DATA_JSON"

# Substitute variables
sudo sed -i "s|__SERVERPEER_APPID__|$SERVERPEER_APPID|g" "$DATA_JSON"
sudo sed -i "s|__VAULT_ROOMID__|$VAULT_ROOMID|g" "$DATA_JSON"
sudo sed -i "s|__VAULT_PASSPHRASE__|$VAULT_PASSPHRASE|g" "$DATA_JSON"
sudo sed -i "s|__SERVERPEER_RELAYS__|$SERVERPEER_RELAYS|g" "$DATA_JSON"
sudo sed -i "s|__VAULT_NAME__|$VAULT_NAME|g" "$DATA_JSON"

# Set permissions
sudo chown $(whoami):$(whoami) "$DATA_JSON"
sudo chmod 644 "$DATA_JSON"

success "✅ Vault initialized: $VAULT_NAME"
success "   P2P Enabled: true"
success "   Room ID: $VAULT_ROOMID"
success "   Device Name: ${VAULT_NAME}-peer"
success "   Relay: $SERVERPEER_RELAYS"
success "   Config: $DATA_JSON"

echo ""
info "To apply changes, restart ServerPeer container:"
echo "  docker restart notes-serverpeer-$(echo "$VAULT_NAME" | tr '[:upper:]' '[:lower:]')"
