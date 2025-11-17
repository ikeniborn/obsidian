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

validate_deployment() {
    info "Validating deployment..."

    source /opt/notes/.env

    local network_name="${NETWORK_NAME:-familybudget_familybudget}"
    local network_mode="${NETWORK_MODE:-shared}"

    info "Checking network: ${network_name}"
    if ! docker network ls --format '{{.Name}}' | grep -q "^${network_name}$"; then
        error "Network ${network_name} does not exist"
        return 1
    fi
    success "Network ${network_name} exists"

    info "Checking CouchDB container..."
    if ! docker ps --format '{{.Names}}' | grep -q "^familybudget-couchdb-notes$"; then
        error "CouchDB container not running"
        return 1
    fi
    success "CouchDB container running"

    info "Checking CouchDB network connection..."
    if ! docker network inspect "${network_name}" --format '{{range .Containers}}{{.Name}} {{end}}' | grep -q "familybudget-couchdb-notes"; then
        error "CouchDB not connected to ${network_name}"
        return 1
    fi
    success "CouchDB connected to ${network_name}"

    if docker ps --format '{{.Names}}' | grep -q "^notes-nginx$"; then
        info "Checking nginx container..."

        if ! docker network inspect "${network_name}" --format '{{range .Containers}}{{.Name}} {{end}}' | grep -q "notes-nginx"; then
            error "Nginx not connected to ${network_name}"
            return 1
        fi
        success "Nginx connected to ${network_name}"

        info "Testing network connectivity nginx → CouchDB..."
        if validate_network_connectivity "${network_name}" "notes-nginx" "familybudget-couchdb-notes"; then
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
        if curl -sf http://127.0.0.1:5984/_up >/dev/null 2>&1; then
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
    echo "=========================================="
    echo "Deploying Obsidian Sync Server"
    echo "=========================================="

    check_env_file
    check_ufw_configured

    prepare_network

    setup_nginx

    setup_ssl
    verify_ssl

    apply_nginx_config

    deploy_couchdb

    wait_for_couchdb_healthy

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
