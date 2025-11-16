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

    local required_vars=("NOTES_DOMAIN" "COUCHDB_PORT" "COUCHDB_USER" "COUCHDB_PASSWORD" "CERTBOT_EMAIL")
    local missing_vars=()

    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            missing_vars+=("$var")
        fi
    done

    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        error "Missing required variables in .env: ${missing_vars[*]}

Please run setup.sh again"
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

deploy_couchdb() {
    info "Deploying CouchDB..."

    local compose_file="$SCRIPT_DIR/docker-compose.notes.yml"

    if [[ ! -f "$compose_file" ]]; then
        error "docker-compose.notes.yml not found at $compose_file"
    fi

    docker compose -f "$compose_file" pull
    docker compose -f "$compose_file" up -d --remove-orphans

    success "CouchDB deployed"
}

wait_for_couchdb_healthy() {
    info "Waiting for CouchDB to become healthy..."

    local max_attempts=30
    local attempt=1
    local container_name="obsidian-couchdb"

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

display_summary() {
    echo ""
    success "========================================"
    success "Obsidian Sync Server Deployment Summary"
    success "========================================"
    echo ""

    source "$NOTES_DEPLOY_DIR/.env"

    local couchdb_status=$(docker ps --filter name=obsidian-couchdb --format "{{.Status}}")
    local nginx_type=$(bash "$SCRIPTS_DIR/nginx-setup.sh" --detect-only)

    echo "  Domain:             https://${NOTES_DOMAIN}"
    echo "  CouchDB Status:     $couchdb_status"
    echo "  Nginx:              $nginx_type"
    echo "  SSL Certificate:    /etc/letsencrypt/live/${NOTES_DOMAIN}/"
    echo "  Configuration:      $NOTES_DEPLOY_DIR/.env"
    echo ""

    info "Useful commands:"
    echo "  CouchDB logs:       docker logs obsidian-couchdb"
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
    info "========================================"
    info "Obsidian Sync Server - Deployment"
    info "========================================"
    echo ""

    check_env_file
    check_ufw_configured

    setup_nginx
    setup_ssl
    verify_ssl
    apply_nginx_config

    deploy_couchdb
    wait_for_couchdb_healthy

    display_summary

    success "Deployment completed successfully!"
    echo ""
}

main "$@"
