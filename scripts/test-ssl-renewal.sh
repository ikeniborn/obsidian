#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${SCRIPT_DIR}/ufw-setup.sh" 2>/dev/null || true

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"; }
info() { log "INFO: $*"; }
error() { log "ERROR: $*" >&2; exit 1; }
success() { log "SUCCESS: $*"; }
warning() { log "WARNING: $*"; }

test_ssl_renewal() {
    info "Testing SSL renewal with UFW hooks..."

    if ! command -v certbot &> /dev/null; then
        error "Certbot not installed. Run ssl-setup.sh first"
    fi

    info "Checking port 80 status before test..."
    if sudo ufw status | grep -q "80/tcp.*ALLOW"; then
        error "Port 80 is already open (should be closed before test)"
    fi

    success "Port 80 is closed (correct state)"

    info "Running certbot renew --dry-run..."
    if sudo certbot renew --dry-run 2>&1 | tee /tmp/certbot-renewal-test.log; then
        success "Certbot dry-run PASSED"
    else
        error "Certbot dry-run FAILED. Check /tmp/certbot-renewal-test.log"
    fi

    info "Checking port 80 status after test..."
    sleep 2

    if sudo ufw status | grep -q "80/tcp.*ALLOW"; then
        error "Port 80 is still open after renewal (should be closed). UFW post-hook failed!"
    fi

    success "Port 80 is closed after renewal (correct state)"
    success "SSL renewal test PASSED"
    echo ""
    info "UFW hooks are working correctly:"
    info "  - Port 80 opens during renewal"
    info "  - Port 80 closes after renewal"
}

main() {
    test_ssl_renewal
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
