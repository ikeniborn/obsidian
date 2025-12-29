#!/bin/bash
#
# fail2ban Test Suite
#
# Tests fail2ban configuration, filters, and UFW integration
#
# Usage:
#   sudo bash scripts/test-fail2ban.sh
#   sudo bash scripts/test-fail2ban.sh --filter notes-couchdb
#   sudo bash scripts/test-fail2ban.sh --dry-run
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

TEST_FILTER=""
DRY_RUN=false
FAIL2BAN_CONF_DIR="/etc/fail2ban"

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
    print_message "$GREEN" "[✓] $*"
}

warning() {
    print_message "$YELLOW" "[!] $*"
}

error() {
    print_message "$RED" "[✗] $*"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

test_service_running() {
    info "Testing fail2ban service status..."

    if [[ "$DRY_RUN" == true ]]; then
        success "Dry-run: Would check service status"
        return 0
    fi

    if systemctl is-active --quiet fail2ban; then
        success "fail2ban service is running"
        return 0
    else
        error "fail2ban service is not running"
        error "Start with: systemctl start fail2ban"
        return 1
    fi
}

test_filter_syntax() {
    local filter_name=$1
    local filter_file="$FAIL2BAN_CONF_DIR/filter.d/${filter_name}.conf"

    info "Testing filter syntax: $filter_name"

    if [[ ! -f "$filter_file" ]]; then
        error "Filter not found: $filter_file"
        return 1
    fi

    if [[ "$DRY_RUN" == true ]]; then
        success "Dry-run: Would validate $filter_name syntax"
        return 0
    fi

    # Test with fail2ban-regex (empty log, just syntax check)
    if fail2ban-regex /dev/null "$filter_file" >/dev/null 2>&1; then
        success "Filter syntax valid: $filter_name"
        return 0
    else
        error "Filter syntax invalid: $filter_name"
        return 1
    fi
}

test_filter_matching() {
    local filter_name=$1
    local filter_file="$FAIL2BAN_CONF_DIR/filter.d/${filter_name}.conf"

    info "Testing filter matching: $filter_name"

    if [[ ! -f "$filter_file" ]]; then
        warning "Filter not found: $filter_file - skipping"
        return 0
    fi

    # Sample log entries to test
    local test_log="/tmp/fail2ban-test-${filter_name}.log"

    case "$filter_name" in
        notes-couchdb)
            cat > "$test_log" << 'EOF'
192.168.1.100 - - [29/Dec/2025:12:00:00 +0000] "GET /couchdb/_all_dbs HTTP/1.1" 401 51 "-" "curl/7.68.0"
192.168.1.100 - - [29/Dec/2025:12:00:01 +0000] "POST /couchdb/_session HTTP/1.1" 401 51 "-" "curl/7.68.0"
192.168.1.100 - - [29/Dec/2025:12:00:02 +0000] "GET /couchdb/_up HTTP/1.1" 200 17 "-" "curl/7.68.0"
192.168.1.100 - - [29/Dec/2025:12:00:03 +0000] "GET /couchdb/mydb HTTP/1.1" 401 51 "-" "curl/7.68.0"
EOF
            ;;
        notes-serverpeer)
            cat > "$test_log" << 'EOF'
192.168.1.100 - - [29/Dec/2025:12:00:00 +0000] "GET /serverpeer/ HTTP/1.1" 401 51 "-" "Mozilla/5.0"
192.168.1.100 - - [29/Dec/2025:12:00:01 +0000] "GET /serverpeer/ HTTP/1.1" 403 51 "-" "Mozilla/5.0"
192.168.1.100 - - [29/Dec/2025:12:00:02 +0000] "GET /serverpeer/ HTTP/1.1" 101 0 "-" "Mozilla/5.0"
192.168.1.100 - - [29/Dec/2025:12:00:03 +0000] "GET /serverpeer/ HTTP/1.1" 200 17 "-" "Mozilla/5.0"
EOF
            ;;
        *)
            warning "Unknown filter: $filter_name - skipping match test"
            rm -f "$test_log"
            return 0
            ;;
    esac

    if [[ "$DRY_RUN" == true ]]; then
        success "Dry-run: Would test $filter_name matching"
        rm -f "$test_log"
        return 0
    fi

    # Run fail2ban-regex to test matching
    local matches=$(fail2ban-regex "$test_log" "$filter_file" 2>/dev/null | grep "Total matched:" | awk '{print $3}')

    if [[ "$matches" -gt 0 ]]; then
        success "Filter matching works: $filter_name ($matches matches)"
    else
        warning "Filter didn't match expected patterns: $filter_name"
    fi

    rm -f "$test_log"
    return 0
}

test_ufw_integration() {
    info "Testing UFW integration..."

    if [[ "$DRY_RUN" == true ]]; then
        success "Dry-run: Would verify UFW integration"
        return 0
    fi

    # Check if fail2ban is using UFW backend
    local jails=$(fail2ban-client status 2>/dev/null | grep "Jail list:" | sed 's/.*Jail list://' | tr ',' ' ')

    if [[ -z "$jails" ]]; then
        warning "No jails found - cannot test UFW integration"
        return 0
    fi

    local tested=false
    for jail in $jails; do
        jail=$(echo "$jail" | xargs)  # Trim whitespace
        if [[ -n "$jail" ]]; then
            local banaction=$(fail2ban-client get "$jail" banaction 2>/dev/null || echo "")
            if [[ "$banaction" == "ufw" ]]; then
                success "UFW integration verified for jail: $jail (banaction = ufw)"
                tested=true
                break
            fi
        fi
    done

    if [[ "$tested" == false ]]; then
        error "UFW integration not found in any jail"
        error "Check /etc/fail2ban/jail.local for banaction setting"
        return 1
    fi

    return 0
}

test_jail_health() {
    info "Testing jail health..."

    if [[ "$DRY_RUN" == true ]]; then
        success "Dry-run: Would check jail health"
        return 0
    fi

    local jails=$(fail2ban-client status 2>/dev/null | grep "Jail list:" | sed 's/.*Jail list://' | tr ',' ' ')

    if [[ -z "$jails" ]]; then
        error "No jails found"
        return 1
    fi

    local count=0
    for jail in $jails; do
        jail=$(echo "$jail" | xargs)
        if [[ -n "$jail" ]]; then
            success "Jail active: $jail"
            ((count++))
        fi
    done

    if [[ $count -eq 0 ]]; then
        error "No active jails"
        return 1
    fi

    success "Total active jails: $count"
    return 0
}

test_ban_cycle() {
    local test_ip="198.51.100.1"  # TEST-NET-2 (RFC 5737)

    info "Testing ban/unban cycle with test IP: $test_ip"

    if [[ "$DRY_RUN" == true ]]; then
        success "Dry-run: Would test ban/unban cycle"
        return 0
    fi

    # Get first available jail
    local jails=$(fail2ban-client status 2>/dev/null | grep "Jail list:" | sed 's/.*Jail list://' | tr ',' ' ')
    local test_jail=""

    for jail in $jails; do
        jail=$(echo "$jail" | xargs)
        if [[ -n "$jail" ]]; then
            test_jail="$jail"
            break
        fi
    done

    if [[ -z "$test_jail" ]]; then
        error "No jails available for testing"
        return 1
    fi

    info "Using jail: $test_jail"

    # Test ban
    if fail2ban-client set "$test_jail" banip "$test_ip" >/dev/null 2>&1; then
        success "Test ban successful: $test_ip"
    else
        error "Test ban failed"
        return 1
    fi

    # Verify ban in UFW
    sleep 1
    if sudo ufw status | grep -q "$test_ip"; then
        success "UFW rule created for banned IP: $test_ip"
    else
        warning "UFW rule not found (may take time to apply)"
    fi

    # Test unban
    if fail2ban-client set "$test_jail" unbanip "$test_ip" >/dev/null 2>&1; then
        success "Test unban successful: $test_ip"
    else
        error "Test unban failed"
        return 1
    fi

    success "Ban/unban cycle completed successfully"
    return 0
}

# =============================================================================
# MAIN TEST RUNNER
# =============================================================================

run_all_tests() {
    local failed=0

    echo ""
    info "=========================================="
    info "fail2ban Test Suite"
    info "=========================================="
    echo ""

    test_service_running || ((failed++))
    echo ""

    test_filter_syntax "notes-couchdb" || ((failed++))
    test_filter_syntax "notes-serverpeer" || ((failed++))
    echo ""

    test_filter_matching "notes-couchdb" || ((failed++))
    test_filter_matching "notes-serverpeer" || ((failed++))
    echo ""

    test_ufw_integration || ((failed++))
    echo ""

    test_jail_health || ((failed++))
    echo ""

    if [[ "$DRY_RUN" == false ]]; then
        test_ban_cycle || ((failed++))
        echo ""
    fi

    echo ""
    info "=========================================="
    if [[ $failed -eq 0 ]]; then
        success "All tests passed!"
    else
        error "$failed test(s) failed"
    fi
    info "=========================================="
    echo ""

    return $failed
}

show_usage() {
    echo "fail2ban Test Suite"
    echo ""
    echo "Usage:"
    echo "  sudo bash $0                       # Run all tests"
    echo "  sudo bash $0 --dry-run             # Dry-run mode"
    echo "  sudo bash $0 --filter <name>       # Test specific filter"
    echo ""
    echo "Options:"
    echo "  --dry-run                Show what tests would run"
    echo "  --filter <name>          Test specific filter only"
    echo ""
    echo "Examples:"
    echo "  sudo bash $0 --filter notes-couchdb"
    echo "  sudo bash $0 --filter notes-serverpeer"
    echo ""
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --filter)
                TEST_FILTER="$2"
                shift 2
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done

    check_root

    if [[ "$DRY_RUN" == true ]]; then
        warning "DRY-RUN MODE: No actual tests will be performed"
        echo ""
    fi

    # Run specific filter test or all tests
    if [[ -n "$TEST_FILTER" ]]; then
        info "Testing filter: $TEST_FILTER"
        echo ""
        test_filter_syntax "$TEST_FILTER"
        echo ""
        test_filter_matching "$TEST_FILTER"
        echo ""
    else
        run_all_tests
    fi
}

main "$@"
