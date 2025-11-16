#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="/opt/notes/.env"
PRE_HOOK_FILE="/etc/letsencrypt/renewal-hooks/pre/ufw-open-80.sh"
POST_HOOK_FILE="/etc/letsencrypt/renewal-hooks/post/ufw-close-80.sh"

source "${SCRIPT_DIR}/ufw-setup.sh" 2>/dev/null || true

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"; }
info() { log "INFO: $*"; }
error() { log "ERROR: $*" >&2; exit 1; }
success() { log "SUCCESS: $*"; }
warning() { log "WARNING: $*"; }

install_certbot() {
    if command -v certbot &> /dev/null; then
        info "Certbot already installed: $(certbot --version)"
        return 0
    fi

    info "Installing certbot..."
    sudo apt-get update
    sudo apt-get install -y certbot

    if command -v certbot &> /dev/null; then
        success "Certbot installed: $(certbot --version)"
    else
        error "Failed to install certbot"
    fi
}

create_ufw_hooks() {
    info "Creating UFW renewal hooks..."

    sudo mkdir -p /etc/letsencrypt/renewal-hooks/pre
    sudo mkdir -p /etc/letsencrypt/renewal-hooks/post

    cat <<'EOF' | sudo tee "$PRE_HOOK_FILE" > /dev/null
#!/bin/bash
ufw allow 80/tcp comment 'Certbot renewal (temporary)'
sleep 2
EOF

    cat <<'EOF' | sudo tee "$POST_HOOK_FILE" > /dev/null
#!/bin/bash
ufw delete allow 80/tcp
EOF

    sudo chmod +x "$PRE_HOOK_FILE"
    sudo chmod +x "$POST_HOOK_FILE"

    if [[ -x "$PRE_HOOK_FILE" ]] && [[ -x "$POST_HOOK_FILE" ]]; then
        success "UFW hooks created and executable"
    else
        error "Failed to create executable UFW hooks"
    fi
}

obtain_certificate() {
    if [[ ! -f "$ENV_FILE" ]]; then
        error ".env file not found at $ENV_FILE"
    fi

    source "$ENV_FILE"

    if [[ -z "${CERTBOT_EMAIL:-}" ]]; then
        error "CERTBOT_EMAIL not set in .env"
    fi

    if [[ -z "${NOTES_DOMAIN:-}" ]]; then
        error "NOTES_DOMAIN not set in .env"
    fi

    local cert_dir="/etc/letsencrypt/live/${NOTES_DOMAIN}"
    if [[ -d "$cert_dir" ]]; then
        info "Certificate already exists for ${NOTES_DOMAIN}"

        if sudo openssl x509 -in "${cert_dir}/fullchain.pem" -noout -checkend 2592000; then
            info "Certificate is valid for at least 30 days"
            return 0
        else
            warning "Certificate expires soon, will renew"
        fi
    fi

    info "Obtaining SSL certificate for ${NOTES_DOMAIN}..."
    info "Email: ${CERTBOT_EMAIL}"

    local staging_flag=""
    if [[ "${CERTBOT_STAGING:-false}" == "true" ]]; then
        staging_flag="--staging"
        warning "Using Let's Encrypt STAGING environment (test certificates)"
    fi

    info "Temporarily opening port 80 for certbot..."
    sudo ufw allow 80/tcp comment 'Certbot initial setup'
    sleep 2

    local cert_exit_code=0
    sudo certbot certonly \
        --standalone \
        --non-interactive \
        --agree-tos \
        --email "${CERTBOT_EMAIL}" \
        --domain "${NOTES_DOMAIN}" \
        ${staging_flag} || cert_exit_code=$?

    info "Closing port 80..."
    sudo ufw delete allow 80/tcp

    if [[ $cert_exit_code -ne 0 ]]; then
        error "Failed to obtain SSL certificate (exit code: $cert_exit_code)"
    fi

    success "SSL certificate obtained successfully"
}

verify_certificate() {
    source "$ENV_FILE"

    local cert_file="/etc/letsencrypt/live/${NOTES_DOMAIN}/fullchain.pem"

    if [[ ! -f "$cert_file" ]]; then
        error "Certificate file not found: $cert_file"
    fi

    info "Verifying certificate..."

    if sudo openssl x509 -in "$cert_file" -noout -checkend 86400; then
        local expiry_date=$(sudo openssl x509 -in "$cert_file" -noout -enddate | cut -d= -f2)
        success "Certificate is valid. Expires: $expiry_date"
    else
        warning "Certificate expires in less than 24 hours"
        return 1
    fi
}

test_renewal_dry_run() {
    info "Testing SSL renewal (dry-run)..."

    if sudo certbot renew --dry-run; then
        success "SSL renewal test PASSED"
    else
        error "SSL renewal test FAILED"
    fi
}

setup_auto_renewal() {
    info "Checking auto-renewal setup..."

    if systemctl is-active certbot.timer >/dev/null 2>&1; then
        success "Certbot timer is active (systemd)"
        sudo systemctl status certbot.timer --no-pager | head -5
        return 0
    fi

    if [[ -f /etc/cron.d/certbot ]] || crontab -l 2>/dev/null | grep -q certbot; then
        success "Certbot cron job found"
        return 0
    fi

    warning "Auto-renewal not detected. Certbot should have set it up automatically."
    info "You can manually verify with: sudo certbot renew --dry-run"
}

main() {
    info "Starting SSL setup..."

    install_certbot
    create_ufw_hooks
    obtain_certificate
    verify_certificate
    setup_auto_renewal

    success "SSL setup completed successfully"
    info ""
    info "Next steps:"
    info "  1. Apply nginx configuration: bash scripts/nginx-setup.sh --apply-config"
    info "  2. Test SSL renewal: bash scripts/test-ssl-renewal.sh"
    info "  3. Monitor certificate: bash scripts/check-ssl-expiration.sh"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
