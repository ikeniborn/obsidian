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

check_ufw() {
    info "Checking UFW firewall..."

    if ! command_exists ufw; then
        warning "UFW is not installed"
        warning "Run scripts/ufw-setup.sh after installation for security"
        return 1
    fi

    local ufw_status=$(ufw status 2>/dev/null | grep -i "Status:" | awk '{print $2}')
    if [[ "$ufw_status" == "active" ]]; then
        success "UFW is installed and active"
    else
        warning "UFW is installed but not active"
        warning "Run scripts/ufw-setup.sh to configure firewall"
    fi
}

detect_nginx() {
    info "Detecting nginx instances..."

    local nginx_found=false
    local nginx_type=""

    if docker ps 2>/dev/null | grep -q nginx; then
        nginx_found=true
        nginx_type="docker"
        success "Found nginx running in Docker"
    fi

    if systemctl is-active --quiet nginx 2>/dev/null; then
        nginx_found=true
        nginx_type="${nginx_type:+$nginx_type, }systemd"
        success "Found nginx running via systemd"
    fi

    if pgrep -x nginx >/dev/null 2>&1; then
        if [[ "$nginx_found" == false ]]; then
            nginx_found=true
            nginx_type="process"
            success "Found nginx running as process"
        fi
    fi

    if [[ "$nginx_found" == false ]]; then
        warning "No nginx instance detected"
        warning "Notes requires nginx reverse proxy for HTTPS"
    fi

    echo "$nginx_found" > /tmp/nginx_detected
    echo "$nginx_type" > /tmp/nginx_type
}

check_ports() {
    info "Checking port availability..."

    local port_80_used=false
    local port_443_used=false

    if command_exists netstat; then
        if netstat -tuln 2>/dev/null | grep -q ':80 '; then
            port_80_used=true
            warning "Port 80 is already in use"
        fi

        if netstat -tuln 2>/dev/null | grep -q ':443 '; then
            port_443_used=true
            warning "Port 443 is already in use"
        fi
    elif command_exists ss; then
        if ss -tuln 2>/dev/null | grep -q ':80 '; then
            port_80_used=true
            warning "Port 80 is already in use"
        fi

        if ss -tuln 2>/dev/null | grep -q ':443 '; then
            port_443_used=true
            warning "Port 443 is already in use"
        fi
    fi

    if [[ "$port_80_used" == false && "$port_443_used" == false ]]; then
        success "Ports 80 and 443 are available"
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
    check_ufw
    detect_nginx
    check_ports

    echo ""
    create_directories

    echo ""
    if [[ ! -f "$SCRIPT_DIR/scripts/ufw-setup.sh" ]]; then
        warning "UFW setup script not found at scripts/ufw-setup.sh"
    else
        echo ""
        info "Security: UFW Firewall Setup"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "For production security, configure UFW firewall:"
        echo "  sudo bash scripts/ufw-setup.sh"
        echo ""
        echo "This will:"
        echo "  - Allow SSH (port 22)"
        echo "  - Allow HTTPS (port 443)"
        echo "  - Block all other incoming traffic"
        echo ""
        read -p "Configure UFW now? (y/N): " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            bash "$SCRIPT_DIR/scripts/ufw-setup.sh"
        else
            warning "Skipping UFW setup. Run manually later for security."
        fi
    fi

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
