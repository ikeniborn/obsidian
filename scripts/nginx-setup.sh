#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ENV_FILE="/opt/notes/.env"
TEMPLATE_FILE="${PROJECT_ROOT}/templates/notes.conf.template"
NGINX_CONTAINER_NAME="notes-nginx"

source "${SCRIPT_DIR}/ufw-setup.sh" 2>/dev/null || true

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"; }
info() { log "INFO: $*"; }
error() { log "ERROR: $*" >&2; exit 1; }
success() { log "SUCCESS: $*"; }
warning() { log "WARNING: $*"; }

detect_existing_nginx() {
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q nginx; then
        echo "docker"
        return 0
    fi

    if systemctl is-active nginx >/dev/null 2>&1; then
        echo "systemd"
        return 0
    fi

    if pgrep nginx >/dev/null 2>&1; then
        echo "standalone"
        return 0
    fi

    echo "none"
}

get_nginx_config_dir() {
    local nginx_type="$1"

    case "$nginx_type" in
        docker)
            local container_name=$(docker ps --format '{{.Names}}' | grep nginx | head -1)
            docker inspect "$container_name" --format '{{range .Mounts}}{{if eq .Destination "/etc/nginx"}}{{.Source}}{{end}}{{end}}' 2>/dev/null || echo "/etc/nginx"
            ;;
        systemd)
            if [[ -d "/etc/nginx/sites-available" ]]; then
                echo "/etc/nginx/sites-available"
            else
                echo "/etc/nginx/conf.d"
            fi
            ;;
        standalone)
            echo "/etc/nginx/conf.d"
            ;;
        *)
            error "Unknown nginx type: $nginx_type"
            ;;
    esac
}

generate_nginx_config() {
    if [[ ! -f "$ENV_FILE" ]]; then
        error ".env file not found at $ENV_FILE"
    fi

    source "$ENV_FILE"

    if [[ -z "${NOTES_DOMAIN:-}" ]]; then
        error "NOTES_DOMAIN not set in .env"
    fi

    if [[ -z "${COUCHDB_PORT:-}" ]]; then
        error "COUCHDB_PORT not set in .env"
    fi

    if [[ ! -f "$TEMPLATE_FILE" ]]; then
        error "Nginx template not found at $TEMPLATE_FILE"
    fi

    local output_file="${PROJECT_ROOT}/notes.conf"

    sed -e "s/\${NOTES_DOMAIN}/${NOTES_DOMAIN}/g" \
        -e "s/\${COUCHDB_PORT}/${COUCHDB_PORT}/g" \
        "$TEMPLATE_FILE" > "$output_file"

    info "Generated nginx config: $output_file"
    echo "$output_file"
}

integrate_with_existing_nginx() {
    local nginx_type="$1"
    local config_dir=$(get_nginx_config_dir "$nginx_type")
    local config_file=$(generate_nginx_config)

    info "Integrating with existing nginx ($nginx_type)"
    info "Config directory: $config_dir"

    if [[ ! -d "$config_dir" ]]; then
        error "Nginx config directory not found: $config_dir"
    fi

    local dest_file="${config_dir}/notes.conf"
    sudo cp "$config_file" "$dest_file"
    sudo chmod 644 "$dest_file"

    info "Copied config to $dest_file"

    case "$nginx_type" in
        docker)
            local container_name=$(docker ps --format '{{.Names}}' | grep nginx | head -1)
            info "Testing nginx configuration..."
            if docker exec "$container_name" nginx -t 2>&1 | tee /tmp/nginx-test.log; then
                info "Reloading nginx container..."
                docker exec "$container_name" nginx -s reload
                success "Nginx configuration applied"
            else
                cat /tmp/nginx-test.log
                error "Nginx configuration test failed"
            fi
            ;;
        systemd|standalone)
            info "Testing nginx configuration..."
            if sudo nginx -t 2>&1 | tee /tmp/nginx-test.log; then
                info "Reloading nginx..."
                sudo systemctl reload nginx
                success "Nginx configuration applied"
            else
                cat /tmp/nginx-test.log
                error "Nginx configuration test failed"
            fi
            ;;
    esac

    if [[ "$nginx_type" == "systemd" ]] && [[ -d "/etc/nginx/sites-available" ]]; then
        local sites_enabled="/etc/nginx/sites-enabled/notes.conf"
        if [[ ! -L "$sites_enabled" ]]; then
            sudo ln -s "$dest_file" "$sites_enabled"
            info "Created symlink: $sites_enabled"
        fi
    fi
}

deploy_own_nginx() {
    info "Deploying own nginx container..."

    local config_file=$(generate_nginx_config)
    local compose_file="${PROJECT_ROOT}/docker-compose.nginx.yml"

    cat > "$compose_file" <<EOF
version: '3.8'

services:
  nginx:
    image: nginx:alpine
    container_name: ${NGINX_CONTAINER_NAME}
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ${config_file}:/etc/nginx/conf.d/notes.conf:ro
      - /etc/letsencrypt:/etc/letsencrypt:ro
      - /var/log/nginx:/var/log/nginx
    networks:
      - notes-network

networks:
  notes-network:
    external: true
EOF

    info "Created docker-compose.nginx.yml"

    if ! docker network ls | grep -q notes-network; then
        docker network create notes-network
        info "Created notes-network"
    fi

    docker-compose -f "$compose_file" up -d

    success "Nginx container deployed: ${NGINX_CONTAINER_NAME}"
    echo "${NGINX_CONTAINER_NAME}"
}

main() {
    local detect_only=false
    local apply_config=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            --detect-only)
                detect_only=true
                shift
                ;;
            --apply-config)
                apply_config=true
                shift
                ;;
            *)
                error "Unknown option: $1"
                ;;
        esac
    done

    if [[ "$detect_only" == true ]]; then
        detect_existing_nginx
        exit 0
    fi

    NGINX_TYPE=$(detect_existing_nginx)

    if [[ "$apply_config" == true ]]; then
        if [[ "$NGINX_TYPE" != "none" ]]; then
            integrate_with_existing_nginx "$NGINX_TYPE"
        else
            error "No nginx found. Run without --apply-config first."
        fi
        exit 0
    fi

    if [[ "$NGINX_TYPE" != "none" ]]; then
        info "Found existing nginx ($NGINX_TYPE), integrating..."
        integrate_with_existing_nginx "$NGINX_TYPE"
    else
        info "No nginx found, deploying own nginx container..."
        deploy_own_nginx
    fi

    success "Nginx setup completed"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
