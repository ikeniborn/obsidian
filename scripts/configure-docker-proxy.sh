#!/bin/bash
# =============================================================================
# Docker Proxy Configuration Helper
# =============================================================================
# Configures Docker daemon to use HTTP/HTTPS/SOCKS5 proxy for image pulls
#
# Usage: sudo bash scripts/configure-docker-proxy.sh [proxy_url]
#
# Examples:
#   sudo bash scripts/configure-docker-proxy.sh https://user:pass@proxy:8080
#   sudo bash scripts/configure-docker-proxy.sh socks5://proxy:1080
# =============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root (use sudo)"
        exit 1
    fi
}

configure_docker_daemon_proxy() {
    local proxy_url="$1"

    info "Configuring Docker daemon proxy..."

    # Create systemd override directory
    mkdir -p /etc/systemd/system/docker.service.d

    # Create proxy configuration
    cat > /etc/systemd/system/docker.service.d/http-proxy.conf << EOF
[Service]
Environment="HTTP_PROXY=${proxy_url}"
Environment="HTTPS_PROXY=${proxy_url}"
Environment="NO_PROXY=localhost,127.0.0.1,docker-registry.somecorporation.com"
EOF

    success "Docker daemon proxy configuration created"

    # Reload systemd and restart Docker
    info "Reloading systemd daemon..."
    systemctl daemon-reload

    info "Restarting Docker service..."
    systemctl restart docker

    success "Docker service restarted with proxy configuration"
}

verify_docker_proxy() {
    info "Verifying Docker proxy configuration..."

    systemctl show --property=Environment docker | grep -i proxy

    info "Testing Docker pull through proxy..."
    if docker pull hello-world:latest; then
        success "Docker can pull images through proxy"
        docker rmi hello-world:latest 2>/dev/null || true
        return 0
    else
        error "Docker pull test failed"
        return 1
    fi
}

remove_docker_proxy() {
    info "Removing Docker proxy configuration..."

    if [[ -f /etc/systemd/system/docker.service.d/http-proxy.conf ]]; then
        rm -f /etc/systemd/system/docker.service.d/http-proxy.conf
        systemctl daemon-reload
        systemctl restart docker
        success "Docker proxy configuration removed"
    else
        info "No proxy configuration found"
    fi
}

show_usage() {
    cat << EOF
Usage: sudo bash $0 [OPTIONS] [proxy_url]

Options:
  --remove      Remove Docker proxy configuration
  --verify      Verify current proxy configuration
  --help        Show this help message

Examples:
  # Configure HTTPS proxy
  sudo bash $0 https://user:pass@proxy.example.com:8080

  # Configure SOCKS5 proxy
  sudo bash $0 socks5://proxy.example.com:1080

  # Remove proxy configuration
  sudo bash $0 --remove

  # Verify current configuration
  sudo bash $0 --verify
EOF
}

main() {
    check_root

    if [[ $# -eq 0 ]]; then
        error "No arguments provided"
        show_usage
        exit 1
    fi

    case "$1" in
        --remove)
            remove_docker_proxy
            ;;
        --verify)
            verify_docker_proxy
            ;;
        --help)
            show_usage
            ;;
        *)
            local proxy_url="$1"

            if [[ ! "$proxy_url" =~ ^(https?|socks5):// ]]; then
                error "Invalid proxy URL format. Must start with http://, https://, or socks5://"
                exit 1
            fi

            configure_docker_daemon_proxy "$proxy_url"
            verify_docker_proxy
            ;;
    esac
}

main "$@"
