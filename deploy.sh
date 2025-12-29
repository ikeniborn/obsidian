#!/bin/bash
#
# Obsidian Sync Server - Deployment Script
#
# This script deploys Obsidian Sync Server:
# - Validates .env configuration
# - Sets up Nginx (detects existing or deploys own)
# - Obtains SSL certificates via Let's Encrypt
# - Deploys CouchDB via docker compose
# - Applies Nginx configuration with SSL
# - Verifies deployment
#
# Usage:
#   ./deploy.sh
#
# Requirements:
#   - install.sh and setup.sh must be run first
#   - /opt/notes/.env must exist
#   - UFW configured (ports 22, 443 open)
#
# Author: Obsidian Sync Server Team
# Version: 2.0.0
# Date: 2025-11-16
#

set -e  # Exit on error
set -u  # Exit on undefined variable

# =============================================================================
# CONFIGURATION
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NOTES_DEPLOY_DIR="/opt/notes"
SCRIPTS_DIR="${SCRIPT_DIR}/scripts"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

print_message() {
    local color=$1
    shift
    echo -e "${color}$*${NC}"
}

info() {
    print_message "$BLUE" "[INFO] $*"
}

success() {
    print_message "$GREEN" "[SUCCESS] $*"
}

warning() {
    print_message "$YELLOW" "[WARNING] $*"
}

error() {
    print_message "$RED" "[ERROR] $*"
    exit 1
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Source network manager
source "${SCRIPT_DIR}/scripts/network-manager.sh"

# Source fail2ban setup (optional, non-blocking)
source "${SCRIPT_DIR}/scripts/fail2ban-setup.sh" 2>/dev/null || true

# =============================================================================
# VALIDATION FUNCTIONS
# =============================================================================

check_env_file() {
    info "Checking configuration file..."

    if [[ ! -f "$NOTES_DEPLOY_DIR/.env" ]]; then
        error "Configuration file not found: $NOTES_DEPLOY_DIR/.env

Please run setup first:
  sudo bash setup.sh"
    fi

    source "$NOTES_DEPLOY_DIR/.env"

    local required_vars=("NOTES_DOMAIN" "COUCHDB_PORT" "COUCHDB_USER" "COUCHDB_PASSWORD" "CERTBOT_EMAIL" "NETWORK_NAME" "NETWORK_MODE")
    local missing_vars=()

    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            missing_vars+=("$var")
        fi
    done

    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        error "Missing required variables in .env: ${missing_vars[*]}

Configuration file: $NOTES_DEPLOY_DIR/.env

Please run setup to generate complete configuration:
  bash setup.sh

If you already ran setup.sh, check that all prompts were completed successfully."
    fi

    success "Configuration file valid"
}

check_ufw_configured() {
    info "Checking UFW firewall configuration..."

    if ! command -v ufw >/dev/null 2>&1; then
        error "UFW not found. Please run install.sh first"
    fi

    if ! sudo ufw status | grep -q "Status: active"; then
        error "UFW is not active. Please run install.sh first"
    fi

    if ! sudo ufw status | grep -q "443/tcp.*ALLOW"; then
        warning "Port 443 not open in UFW. This may cause SSL verification issues"
    fi

    success "UFW is configured"
}

setup_fail2ban() {
    info "Setting up fail2ban intrusion prevention..."

    # Check if script exists
    if [[ ! -f "$NOTES_DEPLOY_DIR/scripts/fail2ban-setup.sh" ]]; then
        warning "fail2ban-setup.sh not found - skipping intrusion prevention"
        warning "Server will use UFW firewall only (static rules)"
        return 0
    fi

    # Run fail2ban setup (non-blocking)
    if sudo bash "$NOTES_DEPLOY_DIR/scripts/fail2ban-setup.sh"; then
        success "fail2ban intrusion prevention enabled"
    else
        warning "fail2ban setup failed - continuing without intrusion prevention"
        warning "Server will use UFW firewall only (static rules)"
        warning "You can run manually: sudo bash /opt/notes/scripts/fail2ban-setup.sh"
    fi
}

check_rsync() {
    if ! command_exists rsync; then
        warning "rsync not found, installing..."
        sudo apt-get update -qq
        sudo apt-get install -y rsync
    fi
}

# =============================================================================
# DEPLOYMENT FUNCTIONS
# =============================================================================

prepare_network() {
    info "Preparing network configuration..."

    if [ ! -f /opt/notes/.env ]; then
        error ".env file not found. Run setup.sh first."
        exit 1
    fi
    source /opt/notes/.env

    if [ -z "$NETWORK_NAME" ]; then
        error "NETWORK_NAME not configured in .env"
        error "Please run setup.sh to configure network"
        exit 1
    fi

    if [ -z "$NETWORK_MODE" ]; then
        if docker network ls --format '{{.Name}}' | grep -q "^${NETWORK_NAME}$"; then
            export NETWORK_MODE="shared"
            info "Network ${NETWORK_NAME} exists - using shared mode"
        else
            export NETWORK_MODE="isolated"
            info "Network ${NETWORK_NAME} will be created - using isolated mode"
        fi

        echo "NETWORK_MODE=${NETWORK_MODE}" >> /opt/notes/.env
    else
        info "Using configured network mode: ${NETWORK_MODE}"
        info "Using configured network: ${NETWORK_NAME}"
    fi

    if [ "$NETWORK_MODE" = "shared" ]; then
        if ! docker network ls --format '{{.Name}}' | grep -q "^${NETWORK_NAME}$"; then
            error "Configured network ${NETWORK_NAME} does not exist"
            error "Either create it or run setup.sh to reconfigure"
            exit 1
        fi
        success "Found existing network: ${NETWORK_NAME}"
    fi

    success "Network configuration prepared: mode=${NETWORK_MODE}, name=${NETWORK_NAME}"
}

setup_nginx() {
    info "Setting up Nginx..."

    if [[ ! -f "$SCRIPTS_DIR/nginx-setup.sh" ]]; then
        error "nginx-setup.sh not found at $SCRIPTS_DIR/nginx-setup.sh"
    fi

    bash "$SCRIPTS_DIR/nginx-setup.sh" || error "Nginx setup failed"

    success "Nginx setup completed"
}

setup_ssl() {
    info "Setting up SSL certificates..."

    if [[ ! -f "$SCRIPTS_DIR/ssl-setup.sh" ]]; then
        error "ssl-setup.sh not found at $SCRIPTS_DIR/ssl-setup.sh"
    fi

    bash "$SCRIPTS_DIR/ssl-setup.sh" || error "SSL setup failed"

    success "SSL setup completed"
}

verify_ssl() {
    info "Verifying SSL certificate..."

    source "$NOTES_DEPLOY_DIR/.env"

    local cert_file="/etc/letsencrypt/live/${NOTES_DOMAIN}/fullchain.pem"

    if [[ ! -f "$cert_file" ]]; then
        error "SSL certificate not found at $cert_file"
    fi

    if sudo openssl x509 -in "$cert_file" -noout -checkend 86400; then
        success "SSL certificate is valid"
    else
        warning "SSL certificate expires in less than 24 hours"
    fi
}

apply_nginx_config() {
    info "Applying Nginx configuration with SSL..."

    if [[ ! -f "$SCRIPTS_DIR/nginx-setup.sh" ]]; then
        error "nginx-setup.sh not found"
    fi

    bash "$SCRIPTS_DIR/nginx-setup.sh" --apply-config || error "Failed to apply Nginx config"

    success "Nginx configuration applied"
}

copy_scripts_to_workdir() {
    info "Copying scripts to working directory..."

    # Create scripts directory in /opt/notes if not exists
    sudo mkdir -p "$NOTES_DEPLOY_DIR/scripts"

    # Copy all scripts from repository to working directory
    sudo cp -r "$SCRIPTS_DIR"/* "$NOTES_DEPLOY_DIR/scripts/"

    # Set executable permissions
    sudo chmod +x "$NOTES_DEPLOY_DIR/scripts"/*.sh
    sudo chmod +x "$NOTES_DEPLOY_DIR/scripts"/*.py 2>/dev/null || true

    # Set ownership
    sudo chown -R root:root "$NOTES_DEPLOY_DIR/scripts"

    success "Scripts copied to $NOTES_DEPLOY_DIR/scripts/"
}

prepull_serverpeer_images() {
    info "Pre-pulling base images for ServerPeer build..."
    info "This ensures proxy settings are used for image downloads"

    local images=(
        "denoland/deno:bin"
        "node:22.14-bookworm-slim"
    )

    for image in "${images[@]}"; do
        info "Pulling $image..."
        if docker pull "$image"; then
            success "Pulled: $image"
        else
            warning "Failed to pull $image - build may fail"
            warning "If you're behind a proxy, ensure Docker daemon proxy is configured"
            warning "Run: sudo systemctl show --property=Environment docker | grep -i proxy"
        fi
    done

    success "Base images pre-pulled"
}

deploy_serverpeer() {
    info "Building and starting ServerPeer containers..."

    # Generate docker-compose file for multiple vaults
    info "Generating docker-compose.serverpeers.yml for $VAULT_COUNT vault(s)..."
    bash "$SCRIPT_DIR/scripts/generate-serverpeer-compose.sh"

    local compose_file="$SCRIPT_DIR/docker-compose.serverpeers.yml"

    if [[ ! -f "$compose_file" ]]; then
        error "docker-compose.serverpeers.yml not found at $compose_file"
        error "Generation script may have failed"
        return 1
    fi

    # Create vault directories for all vaults
    for ((i=1; i<=VAULT_COUNT; i++)); do
        local vault_dir_var="VAULT_${i}_VAULT_DIR"
        local vault_name_var="VAULT_${i}_NAME"
        local vault_dir="${!vault_dir_var}"
        local vault_name="${!vault_name_var}"

        sudo mkdir -p "$vault_dir"
        sudo chown -R $(whoami):$(whoami) "$vault_dir"
        info "Created vault directory: $vault_dir (${vault_name})"
    done

    # Pre-pull base images (respects Docker daemon proxy)
    prepull_serverpeer_images

    # Export common variables
    export NETWORK_NAME NETWORK_EXTERNAL
    export SERVERPEER_APPID SERVERPEER_RELAYS
    export SERVERPEER_AUTOBROADCAST SERVERPEER_AUTOSTART
    export VAULT_COUNT

    # Export vault-specific variables
    for ((i=1; i<=VAULT_COUNT; i++)); do
        eval "export VAULT_${i}_NAME VAULT_${i}_ROOMID VAULT_${i}_PASSPHRASE"
        eval "export VAULT_${i}_PORT VAULT_${i}_CONTAINER VAULT_${i}_VAULT_DIR"
    done

    docker compose -f "$compose_file" build
    # Note: Don't use --remove-orphans when using multiple compose files
    docker compose -f "$compose_file" up -d

    success "ServerPeer deployed ($VAULT_COUNT vault(s))"
}

wait_for_serverpeer_healthy() {
    info "Waiting for ServerPeer health checks (${VAULT_COUNT} vault(s))..."

    local max_attempts=30

    # Wait for each ServerPeer container
    for ((i=1; i<=VAULT_COUNT; i++)); do
        local container_var="VAULT_${i}_CONTAINER"
        local vault_name_var="VAULT_${i}_NAME"
        local container="${!container_var}"
        local vault_name="${!vault_name_var}"
        local attempt=1

        info "Checking vault: $vault_name ($container)"

        while [[ $attempt -le $max_attempts ]]; do
            if docker ps --filter "name=$container" --filter "health=healthy" | grep -q "$container"; then
                success "ServerPeer '$vault_name' is healthy"
                break
            fi
            echo -n "."
            sleep 2
            ((attempt++))
        done

        if [[ $attempt -gt $max_attempts ]]; then
            warning "Health check timeout for '$vault_name' (container may still be starting)"
        fi
    done

    success "All ServerPeer containers checked"
}

prepull_nostr_relay_images() {
    info "Pre-pulling Nostr Relay image..."
    info "This ensures proxy settings are used for image download"

    local image="scsibug/nostr-rs-relay:latest"

    info "Pulling $image..."
    if docker pull "$image"; then
        success "Pulled: $image"
    else
        warning "Failed to pull $image - deployment may fail"
        warning "If you're behind a proxy, ensure Docker daemon proxy is configured"
        warning "Run: sudo systemctl show --property=Environment docker | grep -i proxy"
    fi
}

deploy_nostr_relay() {
    info "Deploying Nostr Relay (WebSocket signaling server)..."

    local compose_file="$SCRIPT_DIR/docker-compose.nostr-relay.yml"

    if [[ ! -f "$compose_file" ]]; then
        error "docker-compose.nostr-relay.yml not found at $compose_file"
    fi

    # Create relay data directory
    sudo mkdir -p "${NOSTR_RELAY_DATA_DIR:-/opt/notes/nostr-relay-data}"
    sudo chown -R $(whoami):$(whoami) "${NOSTR_RELAY_DATA_DIR}"

    # Copy config to deployment directory
    sudo mkdir -p /opt/notes/nostr-relay
    sudo cp "$SCRIPT_DIR/nostr-relay/config.toml" /opt/notes/nostr-relay/config.toml
    sudo chown root:root /opt/notes/nostr-relay/config.toml

    # Pre-pull Nostr Relay image (respects Docker daemon proxy)
    prepull_nostr_relay_images

    # Export variables for docker compose interpolation
    export NETWORK_NAME NETWORK_EXTERNAL
    export NOSTR_RELAY_CONTAINER_NAME NOSTR_RELAY_DATA_DIR NOSTR_RELAY_PORT

    docker compose -f "$compose_file" up -d

    success "Nostr Relay deployed"
}

wait_for_nostr_relay_healthy() {
    info "Waiting for Nostr Relay health check..."

    local container="${NOSTR_RELAY_CONTAINER_NAME:-notes-nostr-relay}"
    local max_attempts=30
    local attempt=1

    while [[ $attempt -le $max_attempts ]]; do
        if docker ps --filter "name=$container" --filter "health=healthy" | grep -q "$container"; then
            success "Nostr Relay is healthy"
            return 0
        fi
        echo -n "."
        sleep 2
        ((attempt++))
    done

    warning "Health check timeout (container may still be starting)"
}

prepull_couchdb_images() {
    info "Pre-pulling CouchDB image..."
    info "This ensures proxy settings are used for image download"

    local image="couchdb:3.3"

    info "Pulling $image..."
    if docker pull "$image"; then
        success "Pulled: $image"
    else
        warning "Failed to pull $image - deployment may fail"
        warning "If you're behind a proxy, ensure Docker daemon proxy is configured"
        warning "Run: sudo systemctl show --property=Environment docker | grep -i proxy"
    fi
}

deploy_couchdb() {
    info "Deploying CouchDB..."

    local compose_file="$SCRIPT_DIR/docker-compose.notes.yml"

    if [[ ! -f "$compose_file" ]]; then
        error "docker-compose.notes.yml not found at $compose_file"
    fi

    # Pre-pull CouchDB image (respects Docker daemon proxy)
    prepull_couchdb_images

    # Export variables for docker compose interpolation
    export NETWORK_NAME
    export NETWORK_EXTERNAL
    export NETWORK_MODE
    export NETWORK_SUBNET
    export COUCHDB_CONTAINER_NAME
    export COUCHDB_USER
    export COUCHDB_PASSWORD
    export NOTES_DATA_DIR
    export COUCHDB_PORT

    # Note: Image already pulled by prepull_couchdb_images(), no need for docker compose pull
    # Note: Don't use --remove-orphans when using multiple compose files
    docker compose -f "$compose_file" up -d

    success "CouchDB deployed"
}

wait_for_couchdb_healthy() {
    info "Waiting for CouchDB to become healthy..."

    source "$NOTES_DEPLOY_DIR/.env"

    local max_attempts=30
    local attempt=1
    local container_name="${COUCHDB_CONTAINER_NAME:-notes-couchdb}"

    while [[ $attempt -le $max_attempts ]]; do
        if docker ps --filter "name=$container_name" --filter "health=healthy" | grep -q "$container_name"; then
            success "CouchDB is healthy"
            return 0
        fi

        echo -n "."
        sleep 2
        ((attempt++))
    done

    echo ""
    warning "CouchDB health check timeout (not critical)"
    warning "Check logs: docker logs $container_name"
}

validate_env_variables() {
    local required_vars=(
        "NETWORK_NAME"
        "NETWORK_MODE"
        "COUCHDB_CONTAINER_NAME"
        "NOTES_DOMAIN"
        "COUCHDB_PASSWORD"
    )

    local missing=()
    for var in "${required_vars[@]}"; do
        if [ -z "${!var:-}" ]; then
            missing+=("$var")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        error "Missing required variables in .env:"
        printf '  - %s\n' "${missing[@]}"
        error "Run 'setup.sh' to configure these variables"
        return 1
    fi

    success "All required .env variables are set"
    return 0
}

validate_deployment() {
    info "Validating deployment..."

    source /opt/notes/.env

    if ! validate_env_variables; then
        return 1
    fi

    local network_name="${NETWORK_NAME}"
    local network_mode="${NETWORK_MODE}"
    local couchdb_container="${COUCHDB_CONTAINER_NAME:-notes-couchdb}"

    info "Checking network: ${network_name}"
    if ! docker network ls --format '{{.Name}}' | grep -q "^${network_name}$"; then
        error "Network ${network_name} does not exist"
        return 1
    fi
    success "Network ${network_name} exists"

    info "Checking CouchDB container..."
    if ! docker ps --format '{{.Names}}' | grep -q "^${couchdb_container}$"; then
        error "CouchDB container not running"
        return 1
    fi
    success "CouchDB container running"

    info "Checking CouchDB network connection..."
    if ! docker network inspect "${network_name}" --format '{{range .Containers}}{{.Name}} {{end}}' | grep -q "${couchdb_container}"; then
        error "CouchDB not connected to ${network_name}"
        return 1
    fi
    success "CouchDB connected to ${network_name}"

    local nginx_container="${NGINX_CONTAINER_NAME:-notes-nginx}"

    if docker ps --format '{{.Names}}' | grep -q "^${nginx_container}$"; then
        info "Checking nginx container..."

        if ! docker network inspect "${network_name}" --format '{{range .Containers}}{{.Name}} {{end}}' | grep -q "${nginx_container}"; then
            error "Nginx not connected to ${network_name}"
            return 1
        fi
        success "Nginx connected to ${network_name}"

        info "Testing network connectivity nginx → CouchDB..."
        if validate_network_connectivity "${network_name}" "${nginx_container}" "${couchdb_container}"; then
            success "Network connectivity validated"
        else
            warning "Network connectivity test failed (containers may not be fully started)"
        fi
    else
        info "No Docker nginx found (using systemd/standalone nginx - OK)"
    fi

    info "Testing CouchDB health endpoint..."
    local max_attempts=10
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        if curl -sf -u "$COUCHDB_USER:$COUCHDB_PASSWORD" http://0.0.0.0:5984/_up >/dev/null 2>&1; then
            success "CouchDB health check passed"
            break
        fi

        if [ $attempt -eq $max_attempts ]; then
            error "CouchDB health check failed after ${max_attempts} attempts"
            return 1
        fi

        info "Waiting for CouchDB... (attempt $attempt/$max_attempts)"
        sleep 2
        ((attempt++))
    done

    success "Deployment validation completed"
    return 0
}

display_summary() {
    echo ""
    success "========================================"
    success "Obsidian Sync Server Deployment Summary"
    success "========================================"
    echo ""

    source "$NOTES_DEPLOY_DIR/.env"

    local container_name="${COUCHDB_CONTAINER_NAME:-notes-couchdb}"
    local couchdb_status=$(docker ps --filter name="$container_name" --format "{{.Status}}")
    local nginx_type=$(bash "$SCRIPTS_DIR/nginx-setup.sh" --detect-only)

    echo "  Domain:             https://${NOTES_DOMAIN}"
    echo "  CouchDB Status:     $couchdb_status"
    echo "  Nginx:              $nginx_type"
    echo "  SSL Certificate:    /etc/letsencrypt/live/${NOTES_DOMAIN}/"
    echo "  Configuration:      $NOTES_DEPLOY_DIR/.env"
    echo ""

    info "Useful commands:"
    echo "  CouchDB logs:       docker logs $container_name"
    echo "  Check SSL:          bash scripts/check-ssl-expiration.sh"
    echo "  Test SSL renewal:   bash scripts/test-ssl-renewal.sh"
    echo "  Restart CouchDB:    docker compose -f docker-compose.notes.yml restart"
    echo "  Stop:               docker compose -f docker-compose.notes.yml down"
    echo ""
}

# =============================================================================
# MAIN DEPLOYMENT
# =============================================================================

main() {
    echo "=========================================="
    echo "Deploying Obsidian Sync Server"
    echo "=========================================="

    check_env_file
    check_ufw_configured

    prepare_network
    copy_scripts_to_workdir

    # Setup fail2ban AFTER copying scripts to /opt/notes/scripts/
    setup_fail2ban

    # Conditional deployment based on backend
    # Deploy backends BEFORE nginx to ensure DNS resolution works
    source "$NOTES_DEPLOY_DIR/.env"

    if [[ "${SYNC_BACKEND:-couchdb}" == "both" ]]; then
        info "Deploying both backends (dual mode)..."
        deploy_couchdb
        deploy_nostr_relay
        deploy_serverpeer
        wait_for_couchdb_healthy
        wait_for_nostr_relay_healthy
        wait_for_serverpeer_healthy
        success "Both backends deployed successfully"
    elif [[ "${SYNC_BACKEND}" == "serverpeer" ]]; then
        info "Deploying ServerPeer backend..."
        deploy_nostr_relay
        deploy_serverpeer
        wait_for_nostr_relay_healthy
        wait_for_serverpeer_healthy
    else
        info "Deploying CouchDB backend..."
        deploy_couchdb
        wait_for_couchdb_healthy
    fi

    # Setup nginx AFTER backends are running (for DNS resolution)
    setup_nginx

    setup_ssl
    verify_ssl

    apply_nginx_config

    if ! validate_deployment; then
        error "Deployment validation failed"
        error "Please check logs and fix issues before continuing"
        exit 1
    fi

    display_summary

    echo "=========================================="
    success "Deployment completed successfully!"
    echo "=========================================="
}

main "$@"
