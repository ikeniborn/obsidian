#!/bin/bash
#
# Notes CouchDB - Setup Script
#
# This script configures Notes application:
# - Creates /opt/notes/.env configuration file
# - Generates secure COUCHDB_PASSWORD
# - Prompts for NOTES_DOMAIN
#
# Usage:
#   ./setup.sh
#
# Requirements:
#   - notes/install.sh must be run first
#   - /opt/notes directory must exist
#
# Author: Family Budget Team
# Version: 1.0.0
# Date: 2025-11-16
#

set -e  # Exit on error
set -u  # Exit on undefined variable

# =============================================================================
# CONFIGURATION
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NOTES_DIR="/opt/notes"
ENV_FILE="$NOTES_DIR/.env"
ENV_EXAMPLE="$SCRIPT_DIR/.env.example"

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

# =============================================================================
# VALIDATION FUNCTIONS
# =============================================================================

check_notes_directory() {
    if [[ ! -d "$NOTES_DIR" ]]; then
        error "/opt/notes directory not found. Please run install.sh first:
    sudo ./install.sh"
    fi
}

check_existing_env() {
    if [[ -f "$ENV_FILE" ]]; then
        warning "Configuration file already exists: $ENV_FILE"
        echo ""
        read -p "Do you want to overwrite it? (y/N): " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            info "Setup cancelled. Existing configuration preserved."
            exit 0
        fi

        local backup_file="$ENV_FILE.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$ENV_FILE" "$backup_file"
        success "Backed up existing configuration to: $backup_file"
    fi
}

validate_network_config() {
    if [ "$NETWORK_MODE" = "custom" ] && [ -z "$NETWORK_NAME" ]; then
        error "NETWORK_NAME required for custom mode"
        exit 1
    fi

    if [ -n "${NETWORK_SUBNET:-}" ]; then
        if ! echo "$NETWORK_SUBNET" | grep -qE '^172\.(2[4-9]|3[0-1])\.0\.0/16$'; then
            error "Invalid subnet format. Use 172.24-31.0.0/16"
            exit 1
        fi
    fi

    success "Network configuration validated"
}

validate_config() {
    info "Validating configuration..."

    local has_errors=false

    if [[ -z "${CERTBOT_EMAIL:-}" ]]; then
        error "CERTBOT_EMAIL is required"
        has_errors=true
    fi

    if [[ -z "${NOTES_DOMAIN:-}" ]]; then
        error "NOTES_DOMAIN is required"
        has_errors=true
    fi

    if [[ -n "${S3_ACCESS_KEY_ID:-}" ]]; then
        if [[ -z "${S3_SECRET_ACCESS_KEY:-}" ]]; then
            warning "S3_ACCESS_KEY_ID is set but S3_SECRET_ACCESS_KEY is missing"
            has_errors=true
        fi

        if [[ -z "${S3_BUCKET_NAME:-}" ]]; then
            warning "S3_ACCESS_KEY_ID is set but S3_BUCKET_NAME is missing"
            has_errors=true
        fi
    fi

    if [[ "$has_errors" == true ]]; then
        error "Configuration validation failed"
    fi

    validate_network_config

    success "Configuration validation passed"
}

test_dns_resolution() {
    info "Testing DNS resolution for $NOTES_DOMAIN..."

    if [[ "$NOTES_DOMAIN" == "notes.localhost" ]]; then
        info "Development domain detected, skipping DNS check"
        return 0
    fi

    if ! command_exists host && ! command_exists dig && ! command_exists nslookup; then
        warning "DNS tools not available, skipping DNS check"
        return 0
    fi

    local resolved_ip=""

    if command_exists host; then
        resolved_ip=$(host "$NOTES_DOMAIN" 2>/dev/null | grep "has address" | awk '{print $4}' | head -1)
    elif command_exists dig; then
        resolved_ip=$(dig +short "$NOTES_DOMAIN" 2>/dev/null | head -1)
    elif command_exists nslookup; then
        resolved_ip=$(nslookup "$NOTES_DOMAIN" 2>/dev/null | grep -A1 "Name:" | tail -1 | awk '{print $2}')
    fi

    if [[ -z "$resolved_ip" ]]; then
        warning "DNS resolution failed for $NOTES_DOMAIN"
        warning "Make sure the domain is configured in DNS before deploying"
        echo ""
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            info "Setup cancelled. Configure DNS first."
            exit 0
        fi
    else
        success "Domain resolves to: $resolved_ip"

        local server_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
        if [[ -n "$server_ip" && "$resolved_ip" != "$server_ip" ]]; then
            warning "Domain resolves to $resolved_ip, but server IP is $server_ip"
            warning "Make sure DNS points to this server"
        fi
    fi
}

# =============================================================================
# GENERATION FUNCTIONS
# =============================================================================

generate_password() {
    local length=${1:-32}

    if command_exists openssl; then
        openssl rand -hex "$length"
    else
        tr -dc 'a-f0-9' < /dev/urandom | head -c $((length * 2))
    fi
}

validate_email() {
    local email=$1
    local email_regex='^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'

    if [[ $email =~ $email_regex ]]; then
        return 0
    else
        return 1
    fi
}

# =============================================================================
# CONFIGURATION FUNCTIONS
# =============================================================================

prompt_certbot_email() {
    echo ""
    info "Let's Encrypt Email Configuration"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Email for Let's Encrypt SSL certificate notifications:"
    echo "(Required for production HTTPS certificates)"
    echo ""

    while true; do
        read -p "Email: " CERTBOT_EMAIL

        if [[ -z "$CERTBOT_EMAIL" ]]; then
            warning "Email is required for SSL certificates"
            continue
        fi

        if validate_email "$CERTBOT_EMAIL"; then
            success "Email set to: $CERTBOT_EMAIL"
            break
        else
            warning "Invalid email format. Please try again."
        fi
    done
}

prompt_notes_domain() {
    echo ""
    info "Notes Domain Configuration"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Enter the domain for Obsidian Sync access:"
    echo ""
    echo "  Development:  notes.localhost"
    echo "  Production:   notes.example.com"
    echo ""
    warning "IMPORTANT: Domain must be configured in DNS and point to this server"
    echo ""

    while true; do
        read -p "Domain: " NOTES_DOMAIN

        if [[ -z "$NOTES_DOMAIN" ]]; then
            NOTES_DOMAIN="notes.localhost"
            warning "Using default: notes.localhost (development mode)"
            break
        fi

        if [[ "$NOTES_DOMAIN" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]] || [[ "$NOTES_DOMAIN" == "notes.localhost" ]]; then
            success "Domain set to: $NOTES_DOMAIN"
            break
        else
            warning "Invalid domain format. Please try again."
        fi
    done
}

configure_network() {
    echo ""
    info "Docker Network Configuration"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Configure Docker network for CouchDB container"
    echo ""

    source "${SCRIPT_DIR}/scripts/network-manager.sh"

    local result=$(prompt_network_selection)
    NETWORK_MODE=$(echo "$result" | cut -d'|' -f1)
    NETWORK_NAME=$(echo "$result" | cut -d'|' -f2)

    if [ "$NETWORK_MODE" = "shared" ]; then
        NETWORK_EXTERNAL="true"
        NETWORK_SUBNET=""
    else
        NETWORK_EXTERNAL="false"
        NETWORK_SUBNET=$(find_free_subnet)
    fi

    echo ""
    info "Network configuration:"
    echo "  Mode: $NETWORK_MODE"
    echo "  Name: $NETWORK_NAME"
    echo "  External: $NETWORK_EXTERNAL"
    [ -n "$NETWORK_SUBNET" ] && echo "  Subnet: $NETWORK_SUBNET"
    echo ""
}

configure_nginx() {
    echo ""
    info "Nginx Configuration"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Configure nginx for reverse proxy"
    echo ""

    source "${SCRIPT_DIR}/scripts/nginx-setup.sh"

    local nginx_result=$(prompt_nginx_selection)
    local nginx_container=$(echo "$nginx_result" | cut -d'|' -f1)
    local nginx_config_dir=$(echo "$nginx_result" | cut -d'|' -f2)
    local nginx_create_flag=$(echo "$nginx_result" | cut -d'|' -f3)

    if [ "$nginx_container" = "none" ]; then
        info "Will deploy own nginx container"
        NGINX_CONTAINER_NAME="notes-nginx"
        NGINX_CONFIG_DIR="/etc/nginx/conf.d"
        DEPLOY_OWN_NGINX="true"
    else
        info "Will use existing nginx: $nginx_container"
        NGINX_CONTAINER_NAME="$nginx_container"
        NGINX_CONFIG_DIR="$nginx_config_dir"
        DEPLOY_OWN_NGINX="false"

        if [ "$nginx_create_flag" = "CREATE" ]; then
            info "Creating nginx config directory: $nginx_config_dir"
            if docker exec "$nginx_container" mkdir -p "$nginx_config_dir" 2>/dev/null; then
                success "Directory created in container: $nginx_config_dir"
            elif sudo mkdir -p "$nginx_config_dir" 2>/dev/null; then
                success "Directory created on host: $nginx_config_dir"
            else
                error "Failed to create directory: $nginx_config_dir"
                exit 1
            fi
        fi
    fi

    echo ""
    info "Nginx configuration:"
    echo "  Container: $NGINX_CONTAINER_NAME"
    echo "  Config dir: $NGINX_CONFIG_DIR"
    echo "  Deploy own: $DEPLOY_OWN_NGINX"
    echo ""
}

configure_couchdb() {
    echo ""
    info "CouchDB Configuration"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    read -p "CouchDB container name [couchdb-notes]: " couchdb_name
    COUCHDB_CONTAINER_NAME="${couchdb_name:-couchdb-notes}"
    success "CouchDB container name: $COUCHDB_CONTAINER_NAME"
}

prompt_sync_backend() {
    echo ""
    info "Sync Backend Selection"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "1) CouchDB only - Client-Server (HTTP REST API)"
    echo "2) ServerPeer only - P2P (WebSocket relay)"
    echo "3) Both - Run both backends simultaneously"
    echo ""

    while true; do
        read -p "Select backend [1-3] (default: 1): " choice
        choice=${choice:-1}

        case "$choice" in
            1)
                SYNC_BACKEND="couchdb"
                S3_BACKUP_PREFIX="couchdb-backups/"
                COUCHDB_LOCATION="/"
                success "Selected: CouchDB only"
                break
                ;;
            2)
                SYNC_BACKEND="serverpeer"
                S3_BACKUP_PREFIX="serverpeer-backups/"
                SERVERPEER_LOCATION="/"
                success "Selected: ServerPeer only (Docker-based)"
                info "All dependencies (Deno, Node.js) are containerized - no host installation needed"
                break
                ;;
            3)
                SYNC_BACKEND="both"
                S3_BACKUP_PREFIX="backups/"
                success "Selected: Both backends (dual mode)"
                info "All dependencies (Deno, Node.js) are containerized - no host installation needed"

                # Prompt for location paths
                echo ""
                info "Nginx Location Paths Configuration"
                echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                echo "Configure URL paths for each backend on ${NOTES_DOMAIN:-your-domain}"
                echo ""

                read -p "CouchDB location path (default: /couchdb): " COUCHDB_LOCATION
                COUCHDB_LOCATION=${COUCHDB_LOCATION:-/couchdb}
                # Ensure leading slash
                [[ "$COUCHDB_LOCATION" != /* ]] && COUCHDB_LOCATION="/$COUCHDB_LOCATION"

                read -p "ServerPeer location path (default: /serverpeer): " SERVERPEER_LOCATION
                SERVERPEER_LOCATION=${SERVERPEER_LOCATION:-/serverpeer}
                # Ensure leading slash
                [[ "$SERVERPEER_LOCATION" != /* ]] && SERVERPEER_LOCATION="/$SERVERPEER_LOCATION"

                success "CouchDB will be available at: https://${NOTES_DOMAIN:-domain}${COUCHDB_LOCATION}"
                success "ServerPeer will be available at: https://${NOTES_DOMAIN:-domain}${SERVERPEER_LOCATION}"
                break
                ;;
            *)
                warning "Invalid choice"
                ;;
        esac
    done
}

configure_serverpeer() {
    [[ "$SYNC_BACKEND" != "serverpeer" && "$SYNC_BACKEND" != "both" ]] && return 0

    echo ""
    info "ServerPeer Configuration"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Generate secure passphrase (16 bytes = 32 hex chars)
    local passphrase=$(openssl rand -hex 16)

    # Generate room ID (12 bytes = UUID-like format)
    local room_id=$(openssl rand -hex 6 | sed 's/\(..\)/\1-/g;s/-$//')

    SERVERPEER_APPID=self-hosted-livesync
    SERVERPEER_ROOMID=$room_id
    SERVERPEER_PASSPHRASE=$passphrase
    SERVERPEER_RELAYS=wss://exp-relay.vrtmrz.net/
    SERVERPEER_NAME=${NOTES_DOMAIN}-peer
    SERVERPEER_VAULT_NAME=headless-vault
    SERVERPEER_AUTOBROADCAST=true
    SERVERPEER_AUTOSTART=true
    SERVERPEER_PORT=3000
    SERVERPEER_VAULT_DIR=/opt/notes/serverpeer-vault
    SERVERPEER_CONTAINER_NAME=serverpeer-notes

    success "ServerPeer configured"
    echo "  Room ID: $room_id"
    echo "  Passphrase: [hidden - saved in .env]"
}

prompt_s3_credentials() {
    echo ""
    info "S3 Backup Configuration (Optional)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Configure S3-compatible storage for automatic backups"
    echo "(Supports: AWS S3, Yandex Object Storage, MinIO, etc.)"
    echo ""
    echo "Press Enter to skip S3 configuration"
    echo ""

    read -p "S3 Access Key ID [skip]: " S3_ACCESS_KEY_ID

    if [[ -n "$S3_ACCESS_KEY_ID" ]]; then
        read -p "S3 Secret Access Key: " S3_SECRET_ACCESS_KEY

        if [[ -z "$S3_SECRET_ACCESS_KEY" ]]; then
            warning "S3 Secret Access Key is required. Skipping S3 configuration."
            S3_ACCESS_KEY_ID=""
            return
        fi

        read -p "S3 Bucket Name: " S3_BUCKET_NAME
        if [[ -z "$S3_BUCKET_NAME" ]]; then
            warning "S3 Bucket Name is required. Skipping S3 configuration."
            S3_ACCESS_KEY_ID=""
            return
        fi

        read -p "S3 Endpoint URL [https://storage.yandexcloud.net]: " S3_ENDPOINT_URL
        S3_ENDPOINT_URL=${S3_ENDPOINT_URL:-https://storage.yandexcloud.net}

        read -p "S3 Region [ru-central1]: " S3_REGION
        S3_REGION=${S3_REGION:-ru-central1}

        # Use backend-specific default prefix (set in prompt_sync_backend)
        read -p "S3 Backup Prefix [${S3_BACKUP_PREFIX}]: " user_prefix
        S3_BACKUP_PREFIX=${user_prefix:-${S3_BACKUP_PREFIX}}

        success "S3 configuration saved"
    else
        info "Skipping S3 configuration. Backups will be stored locally."
    fi
}

create_env_file() {
    info "Creating configuration file: $ENV_FILE"

    local couchdb_password
    couchdb_password=$(generate_password 32)

    cat > "$ENV_FILE" << EOF
# =============================================================================
# Notes CouchDB Environment Configuration
# =============================================================================
# Generated by notes/setup.sh at $(date +'%Y-%m-%d %H:%M:%S')
# DO NOT commit this file to git

# =============================================================================
# CouchDB Credentials
# =============================================================================

COUCHDB_USER=admin
COUCHDB_PASSWORD=$couchdb_password

# =============================================================================
# Notes Domain Configuration
# =============================================================================

NOTES_DOMAIN=$NOTES_DOMAIN

# =============================================================================
# SSL/TLS Configuration (Let's Encrypt)
# =============================================================================

CERTBOT_EMAIL=$CERTBOT_EMAIL
CERTBOT_STAGING=false

# =============================================================================
# Data Directories
# =============================================================================

NOTES_DATA_DIR=/opt/notes/data
NOTES_BACKUP_DIR=/opt/notes/backups
NOTES_LOG_DIR=/opt/notes/logs

# =============================================================================
# Network Configuration
# =============================================================================

NETWORK_MODE=$NETWORK_MODE
NETWORK_NAME=$NETWORK_NAME
NETWORK_EXTERNAL=$NETWORK_EXTERNAL
${NETWORK_SUBNET:+NETWORK_SUBNET=$NETWORK_SUBNET}

# =============================================================================
# Nginx Configuration
# =============================================================================

NGINX_CONTAINER_NAME=$NGINX_CONTAINER_NAME
NGINX_CONFIG_DIR=$NGINX_CONFIG_DIR
DEPLOY_OWN_NGINX=$DEPLOY_OWN_NGINX
EOF

    if [[ -n "${S3_ACCESS_KEY_ID:-}" ]]; then
        cat >> "$ENV_FILE" << EOF

# =============================================================================
# S3 Backup Configuration
# =============================================================================

S3_ACCESS_KEY_ID=$S3_ACCESS_KEY_ID
S3_SECRET_ACCESS_KEY=$S3_SECRET_ACCESS_KEY
S3_BUCKET_NAME=$S3_BUCKET_NAME
S3_ENDPOINT_URL=$S3_ENDPOINT_URL
S3_REGION=$S3_REGION
S3_BACKUP_PREFIX=$S3_BACKUP_PREFIX
EOF
    fi

    # Backend-specific configuration
    cat >> "$ENV_FILE" << EOF

# =============================================================================
# Sync Backend Configuration
# =============================================================================

SYNC_BACKEND=$SYNC_BACKEND
EOF

    # CouchDB configuration (if enabled)
    if [[ "$SYNC_BACKEND" == "couchdb" || "$SYNC_BACKEND" == "both" ]]; then
        cat >> "$ENV_FILE" << EOF

# =============================================================================
# CouchDB Configuration
# =============================================================================

COUCHDB_CONTAINER_NAME=$COUCHDB_CONTAINER_NAME
COUCHDB_PORT=5984
COUCHDB_LOCATION=${COUCHDB_LOCATION:-/}
EOF
    fi

    # ServerPeer configuration (if enabled)
    if [[ "$SYNC_BACKEND" == "serverpeer" || "$SYNC_BACKEND" == "both" ]]; then
        cat >> "$ENV_FILE" << EOF

# =============================================================================
# ServerPeer Configuration
# =============================================================================

SERVERPEER_APPID=$SERVERPEER_APPID
SERVERPEER_ROOMID=$SERVERPEER_ROOMID
SERVERPEER_PASSPHRASE=$SERVERPEER_PASSPHRASE
SERVERPEER_RELAYS=$SERVERPEER_RELAYS
SERVERPEER_NAME=$SERVERPEER_NAME
SERVERPEER_AUTOBROADCAST=$SERVERPEER_AUTOBROADCAST
SERVERPEER_AUTOSTART=$SERVERPEER_AUTOSTART
SERVERPEER_PORT=$SERVERPEER_PORT
SERVERPEER_VAULT_NAME=$SERVERPEER_VAULT_NAME
SERVERPEER_VAULT_DIR=$SERVERPEER_VAULT_DIR
SERVERPEER_CONTAINER_NAME=$SERVERPEER_CONTAINER_NAME
SERVERPEER_LOCATION=${SERVERPEER_LOCATION:-/}
EOF
    fi

    chmod 600 "$ENV_FILE"

    success "Configuration file created: $ENV_FILE"
}

setup_backup_cron() {
    info "Setting up automatic backups..."

    echo ""
    echo "Automatic backups configuration:"
    echo "  Backend: ${SYNC_BACKEND:-couchdb}"
    echo "  Schedule: Daily at 3:00 AM"
    echo "  Target: S3 (if configured) + local /opt/notes/backups/"
    echo ""
    read -p "Enable automatic backups? (Y/n): " -n 1 -r
    echo ""

    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        # Remove old backup cron jobs (both couchdb and serverpeer)
        if crontab -l 2>/dev/null | grep -qE "couchdb-backup.sh|serverpeer-backup.sh"; then
            info "Removing old backup cron jobs..."
            crontab -l 2>/dev/null | grep -vE "couchdb-backup.sh|serverpeer-backup.sh" | crontab -
        fi

        # Add cron jobs based on backend
        if [[ "${SYNC_BACKEND}" == "both" ]]; then
            info "Installing backup cron jobs for both backends..."
            COUCHDB_CRON="0 3 * * * /bin/bash /opt/notes/scripts/couchdb-backup.sh >> /opt/notes/logs/backup.log 2>&1"
            SERVERPEER_CRON="5 3 * * * /bin/bash /opt/notes/scripts/serverpeer-backup.sh >> /opt/notes/logs/backup.log 2>&1"
            (crontab -l 2>/dev/null; echo "$COUCHDB_CRON"; echo "$SERVERPEER_CRON") | crontab -
            success "Backup cron jobs created:"
            echo "  - CouchDB: daily at 3:00 AM"
            echo "  - ServerPeer: daily at 3:05 AM"
        elif [[ "${SYNC_BACKEND}" == "serverpeer" ]]; then
            CRON_JOB="0 3 * * * /bin/bash /opt/notes/scripts/serverpeer-backup.sh >> /opt/notes/logs/backup.log 2>&1"
            (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
            success "Backup cron job created (ServerPeer, daily at 3:00 AM)"
        else
            CRON_JOB="0 3 * * * /bin/bash /opt/notes/scripts/couchdb-backup.sh >> /opt/notes/logs/backup.log 2>&1"
            (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
            success "Backup cron job created (CouchDB, daily at 3:00 AM)"
        fi

        touch /opt/notes/logs/backup.log
        chmod 644 /opt/notes/logs/backup.log
    else
        info "Automatic backups not configured"
        if [[ "${SYNC_BACKEND}" == "both" ]]; then
            info "You can run backups manually:"
            info "  bash /opt/notes/scripts/couchdb-backup.sh"
            info "  bash /opt/notes/scripts/serverpeer-backup.sh"
        elif [[ "${SYNC_BACKEND}" == "serverpeer" ]]; then
            info "You can run backups manually: bash /opt/notes/scripts/serverpeer-backup.sh"
        else
            info "You can run backups manually: bash /opt/notes/scripts/couchdb-backup.sh"
        fi
    fi
}

setup_systemd_timer() {
    info "Setting up systemd timer for backups..."

    if [[ ! -f "$SCRIPT_DIR/systemd/couchdb-backup.service" ]]; then
        warning "Systemd service file not found, skipping"
        return 1
    fi

    sudo cp "$SCRIPT_DIR/systemd/couchdb-backup.service" /etc/systemd/system/
    sudo cp "$SCRIPT_DIR/systemd/couchdb-backup.timer" /etc/systemd/system/

    sudo systemctl daemon-reload
    sudo systemctl enable couchdb-backup.timer
    sudo systemctl start couchdb-backup.timer

    success "Systemd timer configured (daily at 3:00 AM)"
    info "Check status: systemctl status couchdb-backup.timer"
}

display_summary() {
    echo ""
    success "========================================"
    success "Notes Configuration Summary"
    success "========================================"
    echo ""
    echo "  Configuration file: $ENV_FILE"
    echo "  CouchDB user:       admin"
    echo "  CouchDB password:   [generated - 64 chars]"
    echo "  Notes domain:       $NOTES_DOMAIN"
    echo "  Certbot email:      $CERTBOT_EMAIL"
    echo "  Data directory:     /opt/notes/data"

    if [[ -n "${S3_ACCESS_KEY_ID:-}" ]]; then
        echo ""
        echo "  S3 Backup:"
        echo "    Bucket:           $S3_BUCKET_NAME"
        echo "    Endpoint:         $S3_ENDPOINT_URL"
        echo "    Region:           $S3_REGION"
    else
        echo ""
        echo "  S3 Backup:          Not configured (local backups only)"
    fi

    echo ""
    info "IMPORTANT: Keep $ENV_FILE secure!"
    info "           This file contains sensitive credentials."
    echo ""
}

# =============================================================================
# MAIN SETUP
# =============================================================================

main() {
    info "========================================"
    info "Notes CouchDB - Setup"
    info "========================================"
    echo ""

    check_notes_directory
    check_existing_env

    configure_network
    configure_nginx

    # Domain and email configuration (needed before backend setup)
    prompt_notes_domain
    prompt_certbot_email

    # Backend selection
    prompt_sync_backend

    # Conditional backend configuration
    if [[ "${SYNC_BACKEND:-couchdb}" == "both" ]]; then
        configure_couchdb
        configure_serverpeer
    elif [[ "${SYNC_BACKEND}" == "serverpeer" ]]; then
        configure_serverpeer
    else
        configure_couchdb
    fi

    prompt_s3_credentials

    echo ""
    validate_config
    test_dns_resolution

    echo ""
    create_env_file
    display_summary

    echo ""
    info "Backup scheduler:"
    echo "  1) Cron (traditional)"
    echo "  2) Systemd timer (modern)"
    read -p "Choose [1]: " SCHEDULER_CHOICE
    SCHEDULER_CHOICE=${SCHEDULER_CHOICE:-1}

    if [[ "$SCHEDULER_CHOICE" == "2" ]]; then
        setup_systemd_timer
    else
        setup_backup_cron
    fi

    echo ""
    echo ""
    success "╔════════════════════════════════════════════════════════════════════╗"
    success "║                 ✅ УСТАНОВКА ЗАВЕРШЕНА УСПЕШНО                    ║"
    success "╚════════════════════════════════════════════════════════════════════╝"
    echo ""

    echo "📋 ИТОГОВЫЕ ПАРАМЕТРЫ:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "  🌐 Network:"
    echo "     Mode:     $NETWORK_MODE"
    echo "     Name:     $NETWORK_NAME"
    [ -n "$NETWORK_SUBNET" ] && echo "     Subnet:   $NETWORK_SUBNET"
    echo ""
    echo "  🔧 Nginx:"
    echo "     Container:  $NGINX_CONTAINER_NAME"
    echo "     Config dir: $NGINX_CONFIG_DIR"
    echo "     Deploy own: $DEPLOY_OWN_NGINX"
    echo ""

    # Backend-specific summary
    if [[ "$SYNC_BACKEND" == "couchdb" || "$SYNC_BACKEND" == "both" ]]; then
        echo "  💾 CouchDB:"
        echo "     Container:  $COUCHDB_CONTAINER_NAME"
        echo "     User:       admin"
        echo "     Password:   [generated - 64 chars]"
        echo "     Port:       5984 (localhost only)"
        [[ "$SYNC_BACKEND" == "both" ]] && echo "     Location:   $COUCHDB_LOCATION"
        echo ""
    fi

    if [[ "$SYNC_BACKEND" == "serverpeer" || "$SYNC_BACKEND" == "both" ]]; then
        echo "  🔄 ServerPeer:"
        echo "     Container:  $SERVERPEER_CONTAINER_NAME"
        echo "     App ID:     $SERVERPEER_APPID"
        echo "     Room ID:    $SERVERPEER_ROOMID"
        echo "     Port:       3000 (localhost only)"
        [[ "$SYNC_BACKEND" == "both" ]] && echo "     Location:   $SERVERPEER_LOCATION"
        echo ""
    fi

    echo "  🌍 Domain & SSL:"
    echo "     Domain:     $NOTES_DOMAIN"
    echo "     Email:      $CERTBOT_EMAIL"
    echo "     SSL:        Let's Encrypt (автообновление каждые 60 дней)"
    echo ""

    if [[ -n "${S3_ACCESS_KEY_ID:-}" ]]; then
        echo "  ☁️  S3 Backup:"
        echo "     Bucket:     $S3_BUCKET_NAME"
        echo "     Endpoint:   $S3_ENDPOINT_URL"
        echo "     Region:     $S3_REGION"
        echo ""
    fi

    if [[ "$SCHEDULER_CHOICE" == "2" ]]; then
        echo "  🕐 Backup Schedule:"
        echo "     Type:       Systemd timer"
        echo "     Schedule:   Daily at 3:00 AM"
        echo ""
    else
        echo "  🕐 Backup Schedule:"
        echo "     Type:       Cron"
        echo "     Schedule:   Daily at 3:00 AM"
        echo ""
    fi

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "📁 КОНФИГУРАЦИЯ СОХРАНЕНА:"
    echo "   $ENV_FILE"
    echo ""
    warning "⚠️  ВАЖНО: Храните $ENV_FILE в безопасности!"
    warning "⚠️  Файл содержит пароли и секретные ключи."
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    info "🚀 СЛЕДУЮЩИЕ ШАГИ:"
    echo ""
    echo "   1. Проверьте конфигурацию:"
    echo "      cat $ENV_FILE"
    echo ""
    echo "   2. Запустите deploy:"
    echo "      sudo ./deploy.sh"
    echo ""
    echo "   3. После успешного deploy:"
    echo "      - Откройте https://$NOTES_DOMAIN"
    echo "      - Настройте Obsidian Self-hosted LiveSync plugin"
    echo "      - Используйте credentials из $ENV_FILE"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

main "$@"
