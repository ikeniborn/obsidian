#!/bin/bash
#
# UFW Firewall Setup Script
#
# Configures UFW for Obsidian Sync Server with minimal attack surface:
# - Allow SSH (auto-detect port from sshd_config)
# - Allow HTTPS (443)
# - Block all other incoming traffic (including port 80)
#
# Usage:
#   sudo bash scripts/ufw-setup.sh
#   sudo bash scripts/ufw-setup.sh --dry-run
#
# Requirements:
#   - Root/sudo access
#
# Author: Obsidian Sync Server Team
# Version: 1.0.0
# Date: 2025-11-16
#

set -e
set -u

# =============================================================================
# CONFIGURATION
# =============================================================================

DRY_RUN=false
SSH_CONFIG="/etc/ssh/sshd_config"
DEFAULT_SSH_PORT=22

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root (use sudo)"
    fi
}

# =============================================================================
# UFW FUNCTIONS
# =============================================================================

check_ufw_installed() {
    info "Checking UFW installation..."

    if command_exists ufw; then
        success "UFW is already installed"
        return 0
    fi

    warning "UFW is not installed"
    return 1
}

install_ufw() {
    info "Installing UFW..."

    if [[ "$DRY_RUN" == true ]]; then
        info "[DRY-RUN] Would install: apt-get install -y ufw"
        return 0
    fi

    apt-get update -qq
    apt-get install -y ufw

    success "UFW installed successfully"
}

detect_ssh_port() {
    local ssh_port=$DEFAULT_SSH_PORT

    if [[ -f "$SSH_CONFIG" ]]; then
        local config_port=$(grep -E "^Port " "$SSH_CONFIG" | awk '{print $2}')
        if [[ -n "$config_port" ]]; then
            ssh_port=$config_port
        fi
    fi

    echo "$ssh_port"
}

reset_ufw_rules() {
    info "Resetting UFW rules..."

    if [[ "$DRY_RUN" == true ]]; then
        info "[DRY-RUN] Would reset UFW rules"
        return 0
    fi

    ufw --force reset
    success "UFW rules reset"
}

configure_ufw_defaults() {
    info "Configuring UFW default policies..."

    if [[ "$DRY_RUN" == true ]]; then
        info "[DRY-RUN] Would set: default deny incoming"
        info "[DRY-RUN] Would set: default allow outgoing"
        return 0
    fi

    ufw default deny incoming
    ufw default allow outgoing

    success "Default policies configured"
}

add_ssh_rule() {
    local ssh_port=$1

    info "Checking SSH rule for port $ssh_port..."

    if check_rule_exists "$ssh_port" "tcp"; then
        success "SSH rule for port $ssh_port already exists - skipping"
        return 0
    fi

    info "Adding SSH rule for port $ssh_port..."

    if [[ "$DRY_RUN" == true ]]; then
        info "[DRY-RUN] Would allow: $ssh_port/tcp (SSH access)"
        return 0
    fi

    ufw allow "$ssh_port/tcp" comment 'SSH access'
    success "SSH access allowed on port $ssh_port"
}

add_https_rule() {
    info "Checking HTTPS rule..."

    if check_rule_exists "443" "tcp"; then
        success "HTTPS rule for port 443 already exists - skipping"
        return 0
    fi

    info "Adding HTTPS rule..."

    if [[ "$DRY_RUN" == true ]]; then
        info "[DRY-RUN] Would allow: 443/tcp (HTTPS for Obsidian Sync)"
        return 0
    fi

    ufw allow 443/tcp comment 'HTTPS for Obsidian Sync'
    success "HTTPS access allowed on port 443"
}

verify_ssh_rule_exists() {
    local ssh_port=$1

    if [[ "$DRY_RUN" == true ]]; then
        return 0
    fi

    if ufw status | grep -q "Status: active"; then
        if ufw status | grep -q "$ssh_port/tcp"; then
            return 0
        fi
    else
        if ufw show added | grep -q "allow $ssh_port/tcp"; then
            return 0
        fi
    fi

    error "SSH rule not found! This would block your SSH access. Aborting."
}

check_rule_exists() {
    local port=$1
    local protocol="${2:-tcp}"

    if [[ "$DRY_RUN" == true ]]; then
        return 1
    fi

    if ufw status | grep -q "Status: active"; then
        if ufw status | grep -q "$port/$protocol"; then
            return 0
        fi
    else
        if ufw show added | grep -q "allow $port/$protocol"; then
            return 0
        fi
    fi

    return 1
}

enable_ufw() {
    info "Enabling UFW..."

    if [[ "$DRY_RUN" == true ]]; then
        info "[DRY-RUN] Would enable UFW"
        return 0
    fi

    ufw --force enable
    success "UFW enabled and active"
}

display_ufw_status() {
    info "UFW Status:"
    echo ""

    if [[ "$DRY_RUN" == true ]]; then
        info "[DRY-RUN] Final configuration would be:"
        echo "  Status: active"
        echo "  Default: deny (incoming), allow (outgoing)"
        echo ""
        echo "  Rules:"
        echo "    - ${SSH_PORT}/tcp    ALLOW    SSH access"
        echo "    - 443/tcp            ALLOW    HTTPS for Obsidian Sync"
        echo "    - 80/tcp             DENY     (blocked by default)"
        return 0
    fi

    ufw status verbose
}

confirm_reset() {
    echo ""
    warning "WARNING: This will reset all existing UFW rules"
    warning "All current firewall rules will be removed"
    echo ""
    read -p "Reset UFW rules? (yes/no): " -r
    echo ""

    if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        return 0
    else
        return 1
    fi
}

confirm_enable() {
    echo ""
    warning "WARNING: UFW will block all incoming traffic except SSH and HTTPS"
    warning "Make sure you can access this server via SSH on port ${SSH_PORT}"
    echo ""
    read -p "Continue and enable UFW? (yes/no): " -r
    echo ""

    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        info "UFW setup cancelled by user"
        exit 0
    fi
}

# =============================================================================
# MAIN SETUP
# =============================================================================

main() {
    if [[ "${1:-}" == "--dry-run" ]]; then
        DRY_RUN=true
        warning "DRY-RUN MODE: No changes will be applied"
        echo ""
    fi

    info "========================================"
    info "UFW Firewall Setup"
    info "========================================"
    echo ""

    check_root

    if ! check_ufw_installed; then
        install_ufw
    fi

    SSH_PORT=$(detect_ssh_port)
    info "Detected SSH port: $SSH_PORT"
    echo ""

    if [[ "$DRY_RUN" == false ]]; then
        local ufw_active=false
        if ufw status | grep -q "Status: active"; then
            ufw_active=true
            info "UFW is currently active"
        else
            info "UFW is currently inactive"
        fi

        if [[ "$ufw_active" == true ]]; then
            info "Checking existing rules..."
            local ssh_exists=false
            local https_exists=false

            if check_rule_exists "$SSH_PORT" "tcp"; then
                ssh_exists=true
            fi
            if check_rule_exists "443" "tcp"; then
                https_exists=true
            fi

            if [[ "$ssh_exists" == true && "$https_exists" == true ]]; then
                success "Required rules (SSH:$SSH_PORT, HTTPS:443) already exist"
                info "No reset needed - will add missing rules only"
            else
                warning "Some required rules are missing"
                if confirm_reset; then
                    reset_ufw_rules
                    configure_ufw_defaults
                fi
            fi
        else
            info "UFW not active - configuring from scratch"
            configure_ufw_defaults
        fi
    fi

    echo ""
    add_ssh_rule "$SSH_PORT"
    add_https_rule

    echo ""
    info "Port 80 (HTTP) will remain BLOCKED (not added to rules)"
    success "This ensures maximum security for HTTPS-only access"

    if [[ "$DRY_RUN" == false ]]; then
        echo ""
        verify_ssh_rule_exists "$SSH_PORT"
        confirm_enable
        enable_ufw
    fi

    echo ""
    display_ufw_status

    echo ""
    success "========================================"
    success "UFW Firewall Setup Complete!"
    success "========================================"
    echo ""

    if [[ "$DRY_RUN" == false ]]; then
        info "Security Status:"
        echo "  ✓ SSH access:   Allowed on port $SSH_PORT"
        echo "  ✓ HTTPS access: Allowed on port 443"
        echo "  ✓ HTTP access:  BLOCKED (port 80 closed)"
        echo "  ✓ Other ports:  BLOCKED (default deny)"
        echo ""
    fi
}

# Execute main only when script is run directly (not when sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
