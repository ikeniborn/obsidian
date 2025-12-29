#!/bin/bash
#
# fail2ban Intrusion Prevention Setup Script
#
# Configures fail2ban for Obsidian Sync Server with dynamic IP banning:
# - SSH brute-force protection (5 failures → 1h ban)
# - Nginx HTTP scanning/DoS protection (10 failures → 1h ban)
# - CouchDB API abuse protection (3 failures → 2h ban)
# - ServerPeer WebSocket abuse protection (3 failures → 2h ban)
#
# Usage:
#   sudo bash scripts/fail2ban-setup.sh
#   sudo bash scripts/fail2ban-setup.sh --dry-run
#
# Requirements:
#   - Root/sudo access
#   - UFW must be active (dependency)
#   - /opt/notes/.env must exist
#
# Author: Obsidian Sync Server Team
# Version: 1.0.0
# Date: 2025-12-29
#

set -e
set -u

# =============================================================================
# CONFIGURATION
# =============================================================================

DRY_RUN=false
ENV_FILE="/opt/notes/.env"
FAIL2BAN_CONF_DIR="/etc/fail2ban"
NGINX_LOG_ACCESS="/var/log/nginx/access.log"
NGINX_LOG_ERROR="/var/log/nginx/error.log"

# Ban parameters (default)
BANTIME_DEFAULT=3600        # 1 hour
FINDTIME_DEFAULT=600        # 10 minutes
MAXRETRY_DEFAULT=5

# API-specific parameters
API_BANTIME=7200           # 2 hours
API_FINDTIME=300           # 5 minutes
API_MAXRETRY=3

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
# VALIDATION FUNCTIONS
# =============================================================================

check_ufw_active() {
    info "Checking UFW firewall status..."

    if ! command_exists ufw; then
        error "UFW is not installed. Please run ufw-setup.sh first"
    fi

    if ! ufw status | grep -q "Status: active"; then
        error "UFW is not active. Please run ufw-setup.sh first"
    fi

    success "UFW is active"
}

check_env_file() {
    info "Checking configuration file..."

    if [[ ! -f "$ENV_FILE" ]]; then
        error "Configuration file not found: $ENV_FILE

Please run setup.sh first:
  sudo bash setup.sh"
    fi

    success "Configuration file found"
}

detect_nginx_logs() {
    info "Detecting nginx log files..."

    # Check if nginx is running in Docker
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q nginx; then
        local nginx_container=$(docker ps --format '{{.Names}}' | grep nginx | head -n1)
        info "Detected Docker nginx container: $nginx_container"

        # Check for volume mount
        local log_mount=$(docker inspect "$nginx_container" --format '{{range .Mounts}}{{if eq .Destination "/var/log/nginx"}}{{.Source}}{{end}}{{end}}' 2>/dev/null)

        if [[ -z "$log_mount" ]]; then
            warning "Nginx logs not mounted to host filesystem"
            warning "fail2ban cannot monitor Docker container logs"
            warning "Add volume mount to docker-compose: /opt/notes/logs/nginx:/var/log/nginx"
            return 1
        fi

        # Update log paths to mounted location
        NGINX_LOG_ACCESS="$log_mount/access.log"
        NGINX_LOG_ERROR="$log_mount/error.log"
        success "Found nginx logs at: $log_mount"
        return 0
    fi

    # Check for systemd nginx logs
    if [[ -f "$NGINX_LOG_ACCESS" ]]; then
        success "Found nginx logs at: /var/log/nginx/"
        return 0
    fi

    warning "Nginx logs not found"
    warning "Nginx jails will be skipped"
    return 1
}

# =============================================================================
# INSTALLATION FUNCTIONS
# =============================================================================

check_fail2ban_installed() {
    info "Checking fail2ban installation..."

    if command_exists fail2ban-client; then
        success "fail2ban is already installed"
        return 0
    fi

    warning "fail2ban is not installed"
    return 1
}

install_fail2ban() {
    if check_fail2ban_installed; then
        return 0
    fi

    info "Installing fail2ban..."

    if [[ "$DRY_RUN" == true ]]; then
        info "[DRY-RUN] Would install: apt-get install -y fail2ban"
        return 0
    fi

    apt-get update -qq
    apt-get install -y fail2ban

    success "fail2ban installed successfully"
}

# =============================================================================
# FILTER CREATION FUNCTIONS
# =============================================================================

create_couchdb_filter() {
    local filter_file="$FAIL2BAN_CONF_DIR/filter.d/notes-couchdb.conf"

    info "Creating CouchDB API filter..."

    if [[ "$DRY_RUN" == true ]]; then
        info "[DRY-RUN] Would create: $filter_file"
        return 0
    fi

    cat > "$filter_file" << 'EOF'
# Fail2Ban filter for CouchDB API authentication failures
#
# Matches HTTP 401 responses on /couchdb location
# Ignores health check endpoints (/_up, /_session)

[Definition]

# Match 401 Unauthorized on CouchDB endpoints
failregex = ^<HOST> .* "(GET|POST|PUT|DELETE) /couchdb.* HTTP/.*" 401 .*$

# Ignore health checks and session endpoints
ignoreregex = ^<HOST> .* "(GET|HEAD) /couchdb/_up .*$
              ^<HOST> .* "(GET|POST) /couchdb/_session .*$

datepattern = %%d/%%b/%%Y:%%H:%%M:%%S
EOF

    success "Created CouchDB API filter: $filter_file"
}

create_serverpeer_filter() {
    local filter_file="$FAIL2BAN_CONF_DIR/filter.d/notes-serverpeer.conf"

    info "Creating ServerPeer WebSocket filter..."

    if [[ "$DRY_RUN" == true ]]; then
        info "[DRY-RUN] Would create: $filter_file"
        return 0
    fi

    cat > "$filter_file" << 'EOF'
# Fail2Ban filter for ServerPeer WebSocket authentication failures
#
# ServerPeer uses WebSocket Secure (WSS) protocol over HTTPS (port 443)
# Matches HTTP 401/403 responses on /serverpeer location
# Ignores successful WebSocket upgrades (HTTP 101 Switching Protocols)

[Definition]

# Match authentication failures (401/403) on ServerPeer WebSocket endpoints
# This catches failed auth attempts before WebSocket upgrade
failregex = ^<HOST> .* "(GET|POST) /serverpeer.* HTTP/.*" (401|403) .*$

# Ignore successful WebSocket upgrades (HTTP 101 Switching Protocols)
# This is normal WSS connection establishment
ignoreregex = ^<HOST> .* "GET /serverpeer.* HTTP/.*" 101 .*$
              ^<HOST> .* "GET /serverpeer.* HTTP/.*" 200 .*$

datepattern = %%d/%%b/%%Y:%%H:%%M:%%S
EOF

    success "Created ServerPeer WebSocket filter: $filter_file"
}

create_custom_filters() {
    info "Creating custom fail2ban filters..."

    # Always create filters (they don't hurt if not used)
    create_couchdb_filter
    create_serverpeer_filter

    success "Custom filters created"
}

# =============================================================================
# JAIL CREATION FUNCTIONS
# =============================================================================

create_jail_local() {
    local jail_file="$FAIL2BAN_CONF_DIR/jail.local"

    info "Creating main jail configuration..."

    if [[ "$DRY_RUN" == true ]]; then
        info "[DRY-RUN] Would create: $jail_file"
        return 0
    fi

    cat > "$jail_file" << EOF
# fail2ban jail configuration for Obsidian Sync Server
#
# CRITICAL: Uses UFW backend for firewall integration
#

[DEFAULT]
# Ban IP using UFW (inserts rules: ufw insert 1 deny from <IP>)
banaction = ufw

# Default ban parameters
bantime = $BANTIME_DEFAULT
findtime = $FINDTIME_DEFAULT
maxretry = $MAXRETRY_DEFAULT

# Whitelist localhost
ignoreip = 127.0.0.1/8 ::1

# Email notifications (optional - configure if needed)
# destemail = admin@example.com
# sendername = Fail2Ban
# action = %(action_mwl)s
EOF

    success "Created jail.local: $jail_file"
}

create_sshd_jail() {
    local jail_file="$FAIL2BAN_CONF_DIR/jail.d/sshd.local"

    info "Creating SSH brute-force protection jail..."

    if [[ "$DRY_RUN" == true ]]; then
        info "[DRY-RUN] Would create: $jail_file"
        return 0
    fi

    # Detect SSH port from sshd_config
    local ssh_port=22
    if [[ -f /etc/ssh/sshd_config ]]; then
        local config_port=$(grep -E "^Port " /etc/ssh/sshd_config | awk '{print $2}')
        if [[ -n "$config_port" ]]; then
            ssh_port=$config_port
        fi
    fi

    cat > "$jail_file" << EOF
# SSH brute-force protection
#
# Protects SSH from password guessing attacks
# 5 failures in 10 minutes → 1 hour ban

[sshd]
enabled = true
port = $ssh_port
filter = sshd
logpath = /var/log/auth.log
maxretry = 5
findtime = 600
bantime = 3600
EOF

    success "Created SSH jail (port $ssh_port)"
}

create_nginx_jails() {
    local jail_file="$FAIL2BAN_CONF_DIR/jail.d/nginx.local"

    # Check if nginx logs are accessible
    if ! detect_nginx_logs; then
        warning "Skipping nginx jails (logs not accessible)"
        return 0
    fi

    info "Creating nginx HTTP protection jails..."

    if [[ "$DRY_RUN" == true ]]; then
        info "[DRY-RUN] Would create: $jail_file"
        return 0
    fi

    cat > "$jail_file" << EOF
# Nginx HTTP protection jails
#
# Protects against HTTP scanning, DoS, and authentication abuse
# 10 failures in 10 minutes → 1 hour ban

[nginx-http-auth]
enabled = true
port = http,https
filter = nginx-http-auth
logpath = $NGINX_LOG_ACCESS
maxretry = 10
findtime = 600
bantime = 3600

[nginx-noscript]
enabled = true
port = http,https
filter = nginx-noscript
logpath = $NGINX_LOG_ACCESS
maxretry = 10
findtime = 600
bantime = 3600

[nginx-badbots]
enabled = true
port = http,https
filter = nginx-badbots
logpath = $NGINX_LOG_ACCESS
maxretry = 10
findtime = 600
bantime = 3600

[nginx-noproxy]
enabled = true
port = http,https
filter = nginx-noproxy
logpath = $NGINX_LOG_ACCESS
maxretry = 10
findtime = 600
bantime = 3600
EOF

    success "Created nginx jails"
}

create_couchdb_jail() {
    local jail_file="$FAIL2BAN_CONF_DIR/jail.d/notes-couchdb.local"

    info "Creating CouchDB API protection jail..."

    if [[ "$DRY_RUN" == true ]]; then
        info "[DRY-RUN] Would create: $jail_file"
        return 0
    fi

    # Check if nginx logs are accessible
    if [[ ! -f "$NGINX_LOG_ACCESS" ]]; then
        warning "Skipping CouchDB jail (nginx logs not accessible)"
        return 0
    fi

    cat > "$jail_file" << EOF
# CouchDB API abuse protection
#
# Protects CouchDB from authentication abuse and API hammering
# 3 failures in 5 minutes → 2 hour ban

[notes-couchdb]
enabled = true
port = http,https
filter = notes-couchdb
logpath = $NGINX_LOG_ACCESS
maxretry = $API_MAXRETRY
findtime = $API_FINDTIME
bantime = $API_BANTIME
EOF

    success "Created CouchDB API jail"
}

create_serverpeer_jail() {
    local jail_file="$FAIL2BAN_CONF_DIR/jail.d/notes-serverpeer.local"

    info "Creating ServerPeer WebSocket protection jail..."

    if [[ "$DRY_RUN" == true ]]; then
        info "[DRY-RUN] Would create: $jail_file"
        return 0
    fi

    # Check if nginx logs are accessible
    if [[ ! -f "$NGINX_LOG_ACCESS" ]]; then
        warning "Skipping ServerPeer jail (nginx logs not accessible)"
        return 0
    fi

    cat > "$jail_file" << EOF
# ServerPeer WebSocket abuse protection
#
# Protects ServerPeer from authentication abuse
# 3 failures in 5 minutes → 2 hour ban

[notes-serverpeer]
enabled = true
port = http,https
filter = notes-serverpeer
logpath = $NGINX_LOG_ACCESS
maxretry = $API_MAXRETRY
findtime = $API_FINDTIME
bantime = $API_BANTIME
EOF

    success "Created ServerPeer WebSocket jail"
}

create_backend_aware_jails() {
    info "Creating backend-aware jails..."

    # Source .env to get SYNC_BACKEND
    if [[ -f "$ENV_FILE" ]]; then
        source "$ENV_FILE"
    fi

    local sync_backend="${SYNC_BACKEND:-couchdb}"

    case "$sync_backend" in
        both)
            info "Detected backend: both (CouchDB + ServerPeer)"
            create_couchdb_jail
            create_serverpeer_jail
            ;;
        serverpeer)
            info "Detected backend: ServerPeer only"
            create_serverpeer_jail
            ;;
        couchdb|*)
            info "Detected backend: CouchDB only"
            create_couchdb_jail
            ;;
    esac

    success "Backend-aware jails created"
}

create_jails() {
    info "Creating fail2ban jails..."

    create_jail_local
    create_sshd_jail
    create_nginx_jails
    create_backend_aware_jails

    success "All jails created"
}

# =============================================================================
# SERVICE MANAGEMENT FUNCTIONS
# =============================================================================

enable_fail2ban() {
    info "Enabling fail2ban service..."

    if [[ "$DRY_RUN" == true ]]; then
        info "[DRY-RUN] Would enable and start fail2ban"
        return 0
    fi

    systemctl enable fail2ban
    systemctl restart fail2ban

    # Wait for service to start
    sleep 2

    if systemctl is-active --quiet fail2ban; then
        success "fail2ban service is active"
    else
        error "fail2ban service failed to start"
    fi
}

validate_fail2ban() {
    info "Validating fail2ban configuration..."

    if [[ "$DRY_RUN" == true ]]; then
        info "[DRY-RUN] Would validate fail2ban configuration"
        return 0
    fi

    # Check service status
    if ! systemctl is-active --quiet fail2ban; then
        error "fail2ban service is not running"
    fi

    # Check jails are loaded
    local jail_count=$(fail2ban-client status 2>/dev/null | grep "Jail list:" | sed 's/.*Jail list://' | tr ',' '\n' | wc -l)
    if [[ $jail_count -lt 1 ]]; then
        warning "No jails loaded - check configuration"
    else
        success "Loaded $jail_count jail(s)"
    fi

    # Verify UFW integration
    local sshd_banaction=$(fail2ban-client get sshd banaction 2>/dev/null || echo "")
    if [[ "$sshd_banaction" == "ufw" ]]; then
        success "UFW integration verified (banaction = ufw)"
    else
        warning "UFW integration may not be working (banaction = $sshd_banaction)"
    fi

    success "fail2ban configuration validated"
}

test_fail2ban_filters() {
    info "Testing fail2ban filters..."

    if [[ "$DRY_RUN" == true ]]; then
        info "[DRY-RUN] Would test filters with fail2ban-regex"
        return 0
    fi

    # Test CouchDB filter syntax
    if [[ -f "$FAIL2BAN_CONF_DIR/filter.d/notes-couchdb.conf" ]]; then
        if fail2ban-regex /dev/null "$FAIL2BAN_CONF_DIR/filter.d/notes-couchdb.conf" >/dev/null 2>&1; then
            success "CouchDB filter syntax valid"
        else
            warning "CouchDB filter syntax may have issues"
        fi
    fi

    # Test ServerPeer filter syntax
    if [[ -f "$FAIL2BAN_CONF_DIR/filter.d/notes-serverpeer.conf" ]]; then
        if fail2ban-regex /dev/null "$FAIL2BAN_CONF_DIR/filter.d/notes-serverpeer.conf" >/dev/null 2>&1; then
            success "ServerPeer filter syntax valid"
        else
            warning "ServerPeer filter syntax may have issues"
        fi
    fi
}

# =============================================================================
# MONITORING FUNCTIONS
# =============================================================================

display_fail2ban_status() {
    info "fail2ban Status:"
    echo ""

    if [[ "$DRY_RUN" == true ]]; then
        info "[DRY-RUN] Final configuration would include:"
        echo "  Service: active (enabled)"
        echo "  Jails: sshd, nginx-*, notes-couchdb OR notes-serverpeer"
        echo "  Integration: UFW (banaction = ufw)"
        return 0
    fi

    # Service status
    if systemctl is-active --quiet fail2ban; then
        echo -e "  ${GREEN}✓${NC} Service: active"
    else
        echo -e "  ${RED}✗${NC} Service: inactive"
    fi

    # Jail list
    echo ""
    echo "  Active Jails:"
    fail2ban-client status 2>/dev/null | grep "Jail list:" | sed 's/.*Jail list://' | tr ',' '\n' | while read -r jail; do
        jail=$(echo "$jail" | xargs)  # Trim whitespace
        if [[ -n "$jail" ]]; then
            echo "    - $jail"
        fi
    done

    echo ""
}

show_banned_ips() {
    info "Currently banned IP addresses:"
    echo ""

    if [[ "$DRY_RUN" == true ]]; then
        info "[DRY-RUN] Would show banned IPs"
        return 0
    fi

    # Get list of active jails
    local jails=$(fail2ban-client status 2>/dev/null | grep "Jail list:" | sed 's/.*Jail list://' | tr ',' ' ')

    for jail in $jails; do
        jail=$(echo "$jail" | xargs)  # Trim whitespace
        if [[ -n "$jail" ]]; then
            local banned=$(fail2ban-client status "$jail" 2>/dev/null | grep "Banned IP list:" | sed 's/.*Banned IP list://' | xargs)
            if [[ -n "$banned" ]]; then
                echo "  $jail: $banned"
            fi
        fi
    done

    echo ""
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
    info "fail2ban Intrusion Prevention Setup"
    info "========================================"
    echo ""

    check_root
    check_ufw_active
    check_env_file

    echo ""
    install_fail2ban

    echo ""
    create_custom_filters

    echo ""
    create_jails

    if [[ "$DRY_RUN" == false ]]; then
        echo ""
        enable_fail2ban

        echo ""
        validate_fail2ban

        echo ""
        test_fail2ban_filters
    fi

    echo ""
    display_fail2ban_status

    if [[ "$DRY_RUN" == false ]]; then
        echo ""
        show_banned_ips
    fi

    echo ""
    success "========================================"
    success "fail2ban Setup Complete!"
    success "========================================"
    echo ""

    if [[ "$DRY_RUN" == false ]]; then
        info "Protection Status:"
        echo "  ✓ SSH:        5 failures → 1h ban"
        echo "  ✓ HTTP:       10 failures → 1h ban"
        echo "  ✓ API abuse:  3 failures → 2h ban"
        echo ""
        info "Useful commands:"
        echo "  fail2ban-client status                    # View all jails"
        echo "  fail2ban-client status notes-couchdb      # View specific jail"
        echo "  fail2ban-client set <jail> unbanip <IP>   # Unban IP"
        echo "  tail -f /var/log/fail2ban/fail2ban.log    # View logs"
        echo ""
    fi
}

# Execute main only when script is run directly (not when sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
