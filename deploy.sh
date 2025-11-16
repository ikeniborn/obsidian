#!/bin/bash
#
# Notes CouchDB - Deployment Script
#
# This script deploys Notes application:
# - Checks Family Budget nginx is running (dependency)
# - Checks external network exists
# - Syncs notes/ to /opt/notes/
# - Deploys CouchDB via docker compose
# - Updates nginx configuration
# - Reloads nginx
#
# Usage:
#   ./deploy.sh
#
# Requirements:
#   - notes/install.sh and notes/setup.sh must be run first
#   - Family Budget nginx must be running
#   - /opt/notes/.env must exist
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
REPO_DIR="$(dirname "$SCRIPT_DIR")"  # Parent directory (familyBudget)
NOTES_DEPLOY_DIR="/opt/notes"

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

check_family_budget_nginx() {
    info "Checking Family Budget nginx..."

    if ! docker ps --format '{{.Names}}' | grep -q '^familybudget-nginx$'; then
        error "Family Budget nginx is NOT running.

Notes requires Family Budget nginx for reverse proxy.

Please start Family Budget first:
  cd ~/familyBudget && ./deploy.sh --profile full

Or start just nginx:
  cd ~/familyBudget && docker compose up -d nginx"
    fi

    success "Family Budget nginx is running"
}

check_external_network() {
    info "Checking external network..."

    if ! docker network ls --format '{{.Name}}' | grep -q '^familybudget_familybudget$'; then
        error "Docker network 'familybudget_familybudget' NOT found.

This network is created by Family Budget deployment.

Please deploy Family Budget first:
  cd ~/familyBudget && ./deploy.sh --profile full"
    fi

    success "External network 'familybudget_familybudget' exists"
}

check_env_file() {
    info "Checking configuration file..."

    if [[ ! -f "$NOTES_DEPLOY_DIR/.env" ]]; then
        error "Configuration file not found: $NOTES_DEPLOY_DIR/.env

Please run setup first:
  ./setup.sh"
    fi

    success "Configuration file exists"
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

sync_files() {
    info "Syncing notes files to $NOTES_DEPLOY_DIR..."

    check_rsync

    # Sync notes/ directory to /opt/notes/
    # Exclude: data/, .env (runtime files), dev-setup.sh (dev only)
    rsync -av --delete \
        --exclude 'data/' \
        --exclude '.env' \
        --exclude 'dev-setup.sh' \
        --exclude '.git/' \
        "$SCRIPT_DIR/" "$NOTES_DEPLOY_DIR/"

    success "Files synced successfully"
}

deploy_couchdb() {
    info "Deploying CouchDB..."

    cd "$NOTES_DEPLOY_DIR"

    # Pull latest images
    docker compose -f docker-compose.notes.yml pull

    # Start CouchDB
    docker compose -f docker-compose.notes.yml up -d --remove-orphans

    success "CouchDB deployed"
}

wait_for_couchdb_healthy() {
    info "Waiting for CouchDB to become healthy..."

    local max_attempts=30
    local attempt=1

    while [[ $attempt -le $max_attempts ]]; do
        if docker inspect familybudget-couchdb-notes | grep -q '"Health".*"healthy"'; then
            success "CouchDB is healthy"
            return 0
        fi

        echo -n "."
        sleep 2
        ((attempt++))
    done

    echo ""
    warning "CouchDB health check timeout (not critical)"
    warning "Check logs: docker logs familybudget-couchdb-notes"
}

update_nginx_config() {
    info "Updating nginx configuration..."

    # Check if couchdb.sh module exists
    if [[ -f "/opt/budget/scripts/lib/couchdb.sh" ]]; then
        # Use existing couchdb.sh to generate nginx config
        source "/opt/budget/scripts/lib/couchdb.sh"

        if declare -f generate_nginx_notes_config >/dev/null 2>&1; then
            generate_nginx_notes_config
        else
            warning "generate_nginx_notes_config function not found in couchdb.sh"
            warning "Nginx config must be updated manually"
            return 0
        fi
    else
        warning "scripts/lib/couchdb.sh not found"
        warning "Nginx config must be updated manually"
        return 0
    fi

    success "Nginx configuration updated"
}

reload_nginx() {
    info "Reloading nginx..."

    if docker exec familybudget-nginx nginx -t >/dev/null 2>&1; then
        docker exec familybudget-nginx nginx -s reload
        success "Nginx reloaded successfully"
    else
        error "Nginx configuration test failed. Please check nginx config:
    docker exec familybudget-nginx nginx -t"
    fi
}

display_summary() {
    echo ""
    success "========================================"
    success "Notes Deployment Summary"
    success "========================================"
    echo ""

    # Get CouchDB container status
    local couchdb_status=$(docker ps --filter name=familybudget-couchdb-notes --format "{{.Status}}")

    echo "  CouchDB Status:     $couchdb_status"
    echo "  Configuration:      /opt/notes/.env"
    echo "  Data Directory:     /opt/notes/data"
    echo ""

    # Get NOTES_DOMAIN from .env
    if [[ -f "$NOTES_DEPLOY_DIR/.env" ]]; then
        local notes_domain=$(grep NOTES_DOMAIN "$NOTES_DEPLOY_DIR/.env" | cut -d'=' -f2)
        echo "  Access URL:         http://$notes_domain"
        echo "  CouchDB Direct:     http://localhost:5984 (localhost only)"
    fi

    echo ""
    info "Useful commands:"
    echo "  Logs:     docker logs familybudget-couchdb-notes"
    echo "  Restart:  cd /opt/notes && docker compose -f docker-compose.notes.yml restart"
    echo "  Stop:     cd /opt/notes && docker compose -f docker-compose.notes.yml down"
    echo ""
}

# =============================================================================
# MAIN DEPLOYMENT
# =============================================================================

main() {
    info "========================================"
    info "Notes CouchDB - Deployment"
    info "========================================"
    echo ""

    # Validation
    check_family_budget_nginx
    check_external_network
    check_env_file

    # Deployment
    sync_files
    deploy_couchdb
    wait_for_couchdb_healthy
    update_nginx_config
    reload_nginx

    # Summary
    display_summary

    success "Deployment completed successfully!"
    echo ""
}

main "$@"
