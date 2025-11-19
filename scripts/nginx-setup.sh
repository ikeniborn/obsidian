#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ENV_FILE="/opt/notes/.env"
TEMPLATE_FILE="${PROJECT_ROOT}/templates/notes.conf.template"
NGINX_CONTAINER_NAME="notes-nginx"

source "${SCRIPT_DIR}/ufw-setup.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/network-manager.sh"

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
    local nginx_mode="${1:-systemd}"

    if [[ ! -f "$ENV_FILE" ]]; then
        error ".env file not found at $ENV_FILE"
    fi

    source "$ENV_FILE"

    if [[ -z "${NOTES_DOMAIN:-}" ]]; then
        error "NOTES_DOMAIN not set in .env"
    fi

    if [[ ! -f "$TEMPLATE_FILE" ]]; then
        error "Nginx template not found at $TEMPLATE_FILE"
    fi

    source "$ENV_FILE"

    if [ "$nginx_mode" = "docker" ]; then
        export COUCHDB_UPSTREAM="${COUCHDB_CONTAINER_NAME:-couchdb-notes}"
    else
        export COUCHDB_UPSTREAM="127.0.0.1"
    fi

    local output_file="${PROJECT_ROOT}/notes.conf"

    envsubst < "$TEMPLATE_FILE" > "$output_file"

    info "Generated nginx config: $output_file (upstream: ${COUCHDB_UPSTREAM})" >&2
    echo "$output_file"
}

detect_nginx_containers() {
    info "Detecting nginx containers..." >&2

    local nginx_containers=$(docker ps --format '{{.Names}}' | grep -i nginx || true)

    if [ -z "$nginx_containers" ]; then
        info "No nginx containers found" >&2
        return 1
    fi

    info "Found nginx containers:" >&2
    local count=0
    while IFS= read -r container; do
        count=$((count + 1))
        local network=$(docker inspect "$container" --format '{{range $net, $conf := .NetworkSettings.Networks}}{{$net}} {{end}}' 2>/dev/null | awk '{print $1}')
        echo "$count. $container (network: $network)" >&2
    done <<< "$nginx_containers"

    return 0
}

prompt_nginx_selection() {
    if ! detect_nginx_containers; then
        echo "none||"
        return 0
    fi

    echo "" >&2
    read -p "Use existing nginx container? [y/N]: " use_existing

    if [[ "$use_existing" =~ ^[Yy]$ ]]; then
        local nginx_containers=$(docker ps --format '{{.Names}}' | grep -i nginx)
        local count=$(echo "$nginx_containers" | wc -l)

        local selected_nginx
        if [ "$count" -eq 1 ]; then
            selected_nginx="$nginx_containers"
        else
            read -p "Enter nginx container name: " selected_nginx
        fi

        echo "" >&2
        info "Detecting nginx config directory for: $selected_nginx" >&2

        local detected_config_dir=$(docker inspect "$selected_nginx" \
            --format '{{range .Mounts}}{{if eq .Destination "/etc/nginx"}}{{.Source}}{{end}}{{end}}' \
            2>/dev/null || echo "")

        if [ -n "$detected_config_dir" ]; then
            info "Auto-detected config directory: $detected_config_dir" >&2
            read -p "Use this directory? [Y/n]: " use_detected
            if [[ ! "$use_detected" =~ ^[Nn]$ ]]; then
                echo "${selected_nginx}|${detected_config_dir}"
                return 0
            fi
        fi

        echo "" >&2
        warning "Cannot auto-detect nginx config directory" >&2
        echo "Please specify the directory where nginx configs should be placed:" >&2
        echo "  - For Docker nginx: volume mount path (e.g., /opt/nginx/conf.d)" >&2
        echo "  - For systemd nginx: /etc/nginx/sites-available or /etc/nginx/conf.d" >&2
        echo "" >&2
        read -p "Nginx config directory: " config_dir

        if [ -z "$config_dir" ]; then
            error "Config directory cannot be empty" >&2
            echo "none||"
            return 1
        fi

        if docker exec "$selected_nginx" test -d "$config_dir" 2>/dev/null; then
            success "Directory verified: $config_dir" >&2
            echo "${selected_nginx}|${config_dir}"
        elif [ -d "$config_dir" ]; then
            success "Directory verified: $config_dir" >&2
            echo "${selected_nginx}|${config_dir}"
        else
            warning "Directory not found: $config_dir" >&2
            read -p "Create this directory? [y/N]: " create_dir
            if [[ "$create_dir" =~ ^[Yy]$ ]]; then
                echo "${selected_nginx}|${config_dir}|CREATE"
            else
                error "Cannot proceed without valid config directory" >&2
                echo "none||"
                return 1
            fi
        fi
    else
        echo "none||"
    fi
}

integrate_with_existing_nginx() {
    local nginx_type="$1"

    source "$ENV_FILE"

    local config_dir="${NGINX_CONFIG_DIR}"
    if [ -z "$config_dir" ]; then
        warning "NGINX_CONFIG_DIR not set in .env, using auto-detection"
        config_dir=$(get_nginx_config_dir "$nginx_type")
    fi

    local config_file=$(generate_nginx_config "$nginx_type")

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

    source /opt/notes/.env

    local network_mode=$(detect_network_mode)
    info "Network mode: ${network_mode}"

    local network_name="${NETWORK_NAME}"
    local network_external="${NETWORK_EXTERNAL:-true}"

    if [ "$network_mode" = "isolated" ]; then
        if ! docker network ls --format '{{.Name}}' | grep -q "^${network_name}$"; then
            info "Creating isolated network: ${network_name}"

            local subnet="${NETWORK_SUBNET}"
            if [ -z "$subnet" ]; then
                subnet=$(find_free_subnet)
                info "Auto-selected subnet: ${subnet}"
            fi

            create_network "${network_name}" "${subnet}"

            if [ -z "$NETWORK_SUBNET" ]; then
                echo "NETWORK_SUBNET=${subnet}" >> /opt/notes/.env
            fi
        else
            success "Network ${network_name} already exists"
        fi
    fi

    info "Generating docker-compose.nginx.yml..."
    export NETWORK_NAME NETWORK_EXTERNAL
    envsubst < templates/docker-compose.nginx.template > /opt/notes/docker-compose.nginx.yml

    info "Starting nginx container..."
    docker compose -f /opt/notes/docker-compose.nginx.yml up -d

    sleep 3

    source "$ENV_FILE"
    local couchdb_container="${COUCHDB_CONTAINER_NAME:-couchdb-notes}"
    local nginx_container="${NGINX_CONTAINER_NAME:-notes-nginx}"

    info "Validating network connectivity..."
    if validate_network_connectivity "${network_name}" "$nginx_container" "$couchdb_container"; then
        success "Network connectivity validated"
    else
        error "Network connectivity check failed"
        error "Nginx and CouchDB may not be able to communicate"
        exit 1
    fi

    success "Own nginx deployed in ${network_mode} mode (network: ${network_name})"
}

main() {
    info "Setting up nginx for Obsidian Sync Server..."

    if [ ! -f /opt/notes/.env ]; then
        error ".env file not found. Run setup.sh first."
        exit 1
    fi

    source /opt/notes/.env

    NGINX_MODE=$(detect_existing_nginx)
    info "Detected nginx mode: ${NGINX_MODE}"

    case "$NGINX_MODE" in
        docker)
            info "Using existing Docker nginx from Family Budget"
            integrate_with_existing_nginx "docker"
            ;;
        systemd)
            info "Using existing systemd nginx"
            integrate_with_existing_nginx "systemd"
            ;;
        standalone)
            info "Using existing standalone nginx"
            integrate_with_existing_nginx "standalone"
            ;;
        none)
            info "No existing nginx found"
            deploy_own_nginx
            ;;
        *)
            error "Unknown nginx mode: ${NGINX_MODE}"
            exit 1
            ;;
    esac

    success "Nginx setup completed"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
