#!/bin/bash

set -e

info() { echo -e "\033[0;36m[TEST]\033[0m $*"; }
success() { echo -e "\033[0;32m[PASS]\033[0m $*"; }
error() { echo -e "\033[0;31m[FAIL]\033[0m $*"; }

cleanup() {
    info "Cleaning up..."
    docker compose -f /opt/notes/docker-compose.notes.yml down 2>/dev/null || true
    docker compose -f /opt/notes/docker-compose.nginx.yml down 2>/dev/null || true
    docker network rm obsidian_network 2>/dev/null || true
    rm -f /opt/notes/.env
}

test_isolated_mode() {
    info "=== Testing ISOLATED mode ==="

    docker network rm familybudget_familybudget 2>/dev/null || true

    info "Running setup.sh (simulated)..."
    cat > /opt/notes/.env <<EOF
COUCHDB_USER=admin
COUCHDB_PASSWORD=$(openssl rand -hex 32)
NOTES_DOMAIN=notes.test.local
CERTBOT_EMAIL=test@example.com
NETWORK_MODE=isolated
NETWORK_NAME=obsidian_network
NETWORK_EXTERNAL=true
EOF

    info "Running deploy.sh..."
    if bash deploy.sh; then
        success "Isolated mode deployment succeeded"
    else
        error "Isolated mode deployment failed"
        return 1
    fi

    if docker network ls | grep -q obsidian_network; then
        success "obsidian_network created"
    else
        error "obsidian_network not found"
        return 1
    fi

    if docker ps | grep -q familybudget-couchdb-notes; then
        success "CouchDB container running"
    else
        error "CouchDB container not running"
        return 1
    fi

    cleanup
}

test_shared_mode() {
    info "=== Testing SHARED mode ==="

    docker network create familybudget_familybudget || true

    info "Running setup.sh (simulated)..."
    cat > /opt/notes/.env <<EOF
COUCHDB_USER=admin
COUCHDB_PASSWORD=$(openssl rand -hex 32)
NOTES_DOMAIN=notes.test.local
CERTBOT_EMAIL=test@example.com
NETWORK_MODE=shared
NETWORK_NAME=familybudget_familybudget
NETWORK_EXTERNAL=true
EOF

    info "Running deploy.sh..."
    if bash deploy.sh; then
        success "Shared mode deployment succeeded"
    else
        error "Shared mode deployment failed"
        return 1
    fi

    if docker network inspect familybudget_familybudget | grep -q familybudget-couchdb-notes; then
        success "CouchDB connected to familybudget_familybudget"
    else
        error "CouchDB not connected to shared network"
        return 1
    fi

    cleanup
}

main() {
    info "Starting network modes testing..."

    test_isolated_mode
    test_shared_mode

    success "All tests passed!"
}

main
