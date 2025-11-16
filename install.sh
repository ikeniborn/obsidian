#!/bin/bash
#
# Notes CouchDB - Installation Script
#
# This script installs dependencies for Notes application:
# - Checks Docker and Docker Compose are installed
# - Creates /opt/notes directory structure
# - Sets proper permissions
#
# Usage:
#   sudo ./install.sh
#
# Requirements:
#   - Docker 20.10+ (installed by Family Budget install.sh)
#   - Docker Compose v2+
#   - Root/sudo access
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
LOG_FILE="/var/log/notes_install.log"

# Deployment directory for notes
NOTES_DIR="/opt/notes"

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
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [INFO] $*" >> "$LOG_FILE" 2>&1 || true
}

success() {
    print_message "$GREEN" "[SUCCESS] $*"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [SUCCESS] $*" >> "$LOG_FILE" 2>&1 || true
}

warning() {
    print_message "$YELLOW" "[WARNING] $*"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [WARNING] $*" >> "$LOG_FILE" 2>&1 || true
}

error() {
    print_message "$RED" "[ERROR] $*"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR] $*" >> "$LOG_FILE" 2>&1 || true
    exit 1
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root (use sudo)"
    fi
}

# =============================================================================
# VALIDATION FUNCTIONS
# =============================================================================

check_docker() {
    info "Checking Docker installation..."

    if ! command_exists docker; then
        error "Docker is not installed. Please install Family Budget first:
    cd ~/familyBudget && sudo ./install.sh"
    fi

    # Check Docker is running
    if ! docker ps >/dev/null 2>&1; then
        error "Docker is not running. Please start Docker:
    sudo systemctl start docker"
    fi

    local docker_version=$(docker --version | grep -oP '\d+\.\d+' | head -1)
    success "Docker $docker_version is installed and running"
}

check_docker_compose() {
    info "Checking Docker Compose installation..."

    if ! command_exists docker compose version; then
        error "Docker Compose is not installed. Please install Family Budget first:
    cd ~/familyBudget && sudo ./install.sh"
    fi

    local compose_version=$(docker compose version --short)
    success "Docker Compose $compose_version is installed"
}

check_family_budget() {
    info "Checking Family Budget installation..."

    if [[ ! -d "/opt/budget" ]]; then
        warning "Family Budget is not installed at /opt/budget"
        warning "Notes can work independently, but requires Family Budget nginx"
        warning "Install Family Budget first for best experience"
    else
        success "Family Budget found at /opt/budget"
    fi
}

# =============================================================================
# INSTALLATION FUNCTIONS
# =============================================================================

create_directories() {
    info "Creating /opt/notes directory structure..."

    # Create main directories
    mkdir -p "$NOTES_DIR"/{data,backups,logs}

    # Set ownership to current user (who invoked sudo)
    local actual_user="${SUDO_USER:-$USER}"
    chown -R "$actual_user:$actual_user" "$NOTES_DIR"

    # Set permissions
    chmod 755 "$NOTES_DIR"
    chmod 755 "$NOTES_DIR"/{data,backups,logs}

    success "Created directory structure:
    $NOTES_DIR/
    ├── data/     (CouchDB persistent storage)
    ├── backups/  (Backup files)
    └── logs/     (Application logs)"
}

# =============================================================================
# MAIN INSTALLATION
# =============================================================================

main() {
    info "========================================"
    info "Notes CouchDB - Installation"
    info "========================================"
    echo ""

    check_root
    check_docker
    check_docker_compose
    check_family_budget

    echo ""
    create_directories

    echo ""
    success "========================================"
    success "Notes installation completed!"
    success "========================================"
    echo ""
    info "Next steps:"
    echo "  1. Configure notes:  ./setup.sh"
    echo "  2. Deploy notes:     ./deploy.sh"
    echo ""
    info "For development:"
    echo "  ./dev-setup.sh"
    echo ""
}

main "$@"
