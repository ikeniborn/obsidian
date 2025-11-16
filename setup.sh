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

    mapfile -t available_networks < <(list_available_networks)

    if [ ${#available_networks[@]} -eq 0 ]; then
        info "No existing Docker networks found"
        info "Will create new isolated network: obsidian_network"
        NETWORK_MODE="isolated"
        NETWORK_NAME="obsidian_network"
    else
        info "Available Docker networks:"
        echo ""
        local i=1
        for network in "${available_networks[@]}"; do
            local subnet=$(docker network inspect "$network" --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}' 2>/dev/null || echo "N/A")
            echo "  $i. Use existing: $network ($subnet)"
            ((i++))
        done
        echo "  $i. Create new isolated network"
        echo ""

        read -p "Select option [1-$i]: " choice

        if [ "$choice" -eq "$i" ]; then
            NETWORK_MODE="isolated"
            read -p "Enter new network name [obsidian_network]: " NETWORK_NAME
            NETWORK_NAME=${NETWORK_NAME:-obsidian_network}

            read -p "Enter custom subnet (leave empty for auto-selection): " NETWORK_SUBNET
        else
            NETWORK_MODE="shared"
            NETWORK_NAME="${available_networks[$((choice-1))]}"
            success "Selected existing network: $NETWORK_NAME"
        fi
    fi
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

        read -p "S3 Backup Prefix [couchdb-backups/]: " S3_BACKUP_PREFIX
        S3_BACKUP_PREFIX=${S3_BACKUP_PREFIX:-couchdb-backups/}

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
NETWORK_EXTERNAL=true
${NETWORK_SUBNET:+NETWORK_SUBNET=$NETWORK_SUBNET}

COUCHDB_PORT=5984
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

    chmod 600 "$ENV_FILE"

    success "Configuration file created: $ENV_FILE"
}

setup_backup_cron() {
    info "Setting up automatic backups..."

    echo ""
    echo "Automatic backups configuration:"
    echo "  Schedule: Daily at 3:00 AM"
    echo "  Target: S3 (if configured) + local /opt/notes/backups/"
    echo ""
    read -p "Enable automatic backups? (Y/n): " -n 1 -r
    echo ""

    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        CRON_JOB="0 3 * * * cd /opt/notes && bash couchdb-backup.sh >> /opt/notes/logs/backup.log 2>&1"

        if crontab -l 2>/dev/null | grep -q "couchdb-backup.sh"; then
            warning "Backup cron job already exists, skipping"
        else
            (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
            success "Backup cron job created (daily at 3:00 AM)"
        fi

        touch /opt/notes/logs/backup.log
        chmod 644 /opt/notes/logs/backup.log
    else
        info "Automatic backups not configured"
        info "You can run backups manually: bash /opt/notes/couchdb-backup.sh"
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

    prompt_certbot_email
    prompt_notes_domain
    configure_network
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

    success "Setup completed successfully!"
    echo ""
    info "Next steps:"
    echo "  1. Review configuration: cat $ENV_FILE"
    echo "  2. Deploy notes:         ./deploy.sh"
    echo ""
}

main "$@"
