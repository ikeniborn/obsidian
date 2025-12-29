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
            if [[ -z "$container_name" ]]; then
                error "No nginx container found"
                return 1
            fi

            # Try to find mount for /etc/nginx/conf.d first (most common)
            local config_dir=$(docker inspect "$container_name" --format '{{range .Mounts}}{{if eq .Destination "/etc/nginx/conf.d"}}{{.Source}}{{end}}{{end}}' 2>/dev/null)

            # If not found, try /etc/nginx
            if [[ -z "$config_dir" ]]; then
                config_dir=$(docker inspect "$container_name" --format '{{range .Mounts}}{{if eq .Destination "/etc/nginx"}}{{.Source}}{{end}}{{end}}' 2>/dev/null)
                if [[ -n "$config_dir" ]]; then
                    config_dir="${config_dir}/conf.d"
                fi
            fi

            # If still not found, return empty (caller should handle)
            if [[ -z "$config_dir" ]]; then
                warning "No volume mount found for nginx config directory"
                warning "Container $container_name does not have /etc/nginx or /etc/nginx/conf.d mounted"
                return 1
            fi

            echo "$config_dir"
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

    local sync_backend="${SYNC_BACKEND:-couchdb}"

    if [[ "$sync_backend" == "both" ]]; then
        # Unified configuration for both backends
        local template_file="${PROJECT_ROOT}/templates/unified.conf.template"

        if [[ ! -f "$template_file" ]]; then
            error "Unified nginx template not found at $template_file"
        fi

        # Set upstreams for both backends
        if [ "$nginx_mode" = "docker" ]; then
            export COUCHDB_UPSTREAM="${COUCHDB_CONTAINER_NAME:-couchdb-notes}"
            export SERVERPEER_UPSTREAM="${SERVERPEER_CONTAINER_NAME:-serverpeer-notes}"
        else
            export COUCHDB_UPSTREAM="127.0.0.1"
            export SERVERPEER_UPSTREAM="127.0.0.1"
        fi

        # Export location paths
        export COUCHDB_LOCATION="${COUCHDB_LOCATION:-/couchdb}"
        export SERVERPEER_LOCATION="${SERVERPEER_LOCATION:-/serverpeer}"

        local output_file="${PROJECT_ROOT}/unified.conf"
        export NOTES_DOMAIN
        envsubst '$COUCHDB_UPSTREAM,$SERVERPEER_UPSTREAM,$COUCHDB_LOCATION,$SERVERPEER_LOCATION,$NOTES_DOMAIN' < "$template_file" > "$output_file"

        info "Generated unified nginx config: $output_file" >&2
        info "  CouchDB upstream: ${COUCHDB_UPSTREAM}, location: ${COUCHDB_LOCATION}" >&2
        info "  ServerPeer upstream: ${SERVERPEER_UPSTREAM}, location: ${SERVERPEER_LOCATION}" >&2
        echo "$output_file"
    elif [[ "$sync_backend" == "serverpeer" ]]; then
        # ServerPeer WebSocket proxy
        local template_file="${PROJECT_ROOT}/templates/serverpeer.conf.template"

        if [[ ! -f "$template_file" ]]; then
            error "ServerPeer nginx template not found at $template_file"
        fi

        if [ "$nginx_mode" = "docker" ]; then
            export SERVERPEER_UPSTREAM="${SERVERPEER_CONTAINER_NAME:-serverpeer-notes}"
        else
            export SERVERPEER_UPSTREAM="127.0.0.1"
        fi

        export SERVERPEER_LOCATION="${SERVERPEER_LOCATION:-/}"

        local output_file="${PROJECT_ROOT}/serverpeer.conf"
        export NOTES_DOMAIN
        envsubst '$SERVERPEER_UPSTREAM,$SERVERPEER_LOCATION,$NOTES_DOMAIN' < "$template_file" > "$output_file"

        info "Generated serverpeer nginx config: $output_file (upstream: ${SERVERPEER_UPSTREAM}, location: ${SERVERPEER_LOCATION})" >&2
        echo "$output_file"
    else
        # CouchDB HTTP proxy
        local template_file="${PROJECT_ROOT}/templates/couchdb.conf.template"

        if [[ ! -f "$template_file" ]]; then
            error "CouchDB nginx template not found at $template_file"
        fi

        if [ "$nginx_mode" = "docker" ]; then
            export COUCHDB_UPSTREAM="${COUCHDB_CONTAINER_NAME:-couchdb-notes}"
        else
            export COUCHDB_UPSTREAM="127.0.0.1"
        fi

        export COUCHDB_LOCATION="${COUCHDB_LOCATION:-/}"

        local output_file="${PROJECT_ROOT}/couchdb.conf"
        export NOTES_DOMAIN
        export COUCHDB_UPSTREAM
        envsubst '$COUCHDB_UPSTREAM,$COUCHDB_LOCATION,$NOTES_DOMAIN' < "$template_file" > "$output_file"

        info "Generated CouchDB nginx config: $output_file (upstream: ${COUCHDB_UPSTREAM}, location: ${COUCHDB_LOCATION})" >&2
        echo "$output_file"
    fi
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
    local use_docker_cp=false

    # Try auto-detection if not set in .env
    if [ -z "$config_dir" ]; then
        warning "NGINX_CONFIG_DIR not set in .env, using auto-detection"
        if ! config_dir=$(get_nginx_config_dir "$nginx_type" 2>&1); then
            # get_nginx_config_dir failed - no volume mount found
            if [[ "$nginx_type" == "docker" ]]; then
                warning "No volume mount found for nginx config"
                info "Will use 'docker cp' to copy config directly into container"
                use_docker_cp=true
                config_dir="/etc/nginx/conf.d"  # Path inside container
            else
                error "Failed to detect nginx config directory"
                return 1
            fi
        fi
    fi

    # Validate config_dir from .env (if it was set)
    # For Docker nginx, if path doesn't exist on host, use docker cp
    if [[ "$nginx_type" == "docker" ]] && [[ ! -d "$config_dir" ]] && [[ "$use_docker_cp" == "false" ]]; then
        warning "Config directory from .env not found on host: $config_dir"
        warning "This is normal for Docker nginx without volume mounts"
        info "Will use 'docker cp' to copy config directly into container"
        use_docker_cp=true
        # config_dir is already set (from .env), use it as container path
    fi

    local config_file=$(generate_nginx_config "$nginx_type")

    info "Integrating with existing nginx ($nginx_type)"
    info "Config destination: $config_dir"

    if [[ "$use_docker_cp" == "true" ]]; then
        # Use docker cp to copy config directly into container
        local container_name=$(docker ps --format '{{.Names}}' | grep nginx | head -1)
        local dest_file="${config_dir}/notes.conf"

        info "Copying config into container using 'docker cp'..."
        # docker cp may show "mounted volume is marked read-only" warning after successful copy
        # This warning is harmless - the file is copied successfully before the warning
        local cp_output=$(docker cp "$config_file" "${container_name}:${dest_file}" 2>&1)
        local cp_status=$?

        if [[ $cp_status -eq 0 ]] || echo "$cp_output" | grep -q "Successfully copied"; then
            success "Config copied to container: ${container_name}:${dest_file}"
            # Suppress read-only volume warning (cosmetic issue, doesn't affect functionality)
            [[ "$cp_output" =~ "read-only" ]] && info "Note: read-only volume warning is harmless"
        else
            error "Failed to copy config into container"
            echo "$cp_output"
            return 1
        fi
    else
        # Use regular file copy for volume-mounted configs
        if [[ ! -d "$config_dir" ]]; then
            error "Nginx config directory not found: $config_dir"
            return 1
        fi

        local dest_file="${config_dir}/notes.conf"
        sudo cp "$config_file" "$dest_file"
        sudo chmod 644 "$dest_file"

        info "Copied config to $dest_file"
    fi

    case "$nginx_type" in
        docker)
            local container_name=$(docker ps --format '{{.Names}}' | grep nginx | head -1)

            if [[ -z "$container_name" ]]; then
                error "Nginx container not found or not running"
                error "Cannot test configuration without running nginx container"
                return 1
            fi

            # Wait for container to stabilize if it's restarting
            local max_wait=30
            local waited=0
            while docker ps --filter "name=$container_name" --format '{{.Status}}' | grep -q "Restarting"; do
                if [[ $waited -ge $max_wait ]]; then
                    error "Nginx container stuck in restart loop"
                    error "Check logs: docker logs $container_name"
                    return 1
                fi
                info "Waiting for nginx container to stabilize... ($waited/$max_wait)"
                sleep 2
                ((waited+=2))
            done

            # Check if container is running
            if ! docker ps --filter "name=$container_name" --format '{{.Status}}' | grep -q "Up"; then
                error "Nginx container is not running"
                error "Status: $(docker ps -a --filter "name=$container_name" --format '{{.Status}}')"
                error "Check logs: docker logs $container_name"
                return 1
            fi

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

    # Pre-pull nginx image (respects Docker daemon proxy)
    info "Pre-pulling nginx image..."
    info "This ensures proxy settings are used for image download"
    if docker pull nginx:alpine; then
        success "Pulled: nginx:alpine"
    else
        warning "Failed to pull nginx:alpine - deployment may fail"
        warning "If you're behind a proxy, ensure Docker daemon proxy is configured"
    fi

    info "Starting nginx container..."
    docker compose -f /opt/notes/docker-compose.nginx.yml up -d

    sleep 3

    source "$ENV_FILE"
    local sync_backend="${SYNC_BACKEND:-couchdb}"
    local nginx_container="${NGINX_CONTAINER_NAME:-notes-nginx}"

    # Determine which backend container(s) to check based on SYNC_BACKEND
    info "Validating network connectivity..."
    local connectivity_ok=true

    case "$sync_backend" in
        couchdb)
            local backend_container="${COUCHDB_CONTAINER_NAME:-couchdb-notes}"
            if docker ps --format '{{.Names}}' | grep -q "^${backend_container}$"; then
                if validate_network_connectivity "${network_name}" "$nginx_container" "$backend_container"; then
                    success "Network connectivity validated (CouchDB)"
                else
                    connectivity_ok=false
                fi
            else
                info "CouchDB container not yet created, skipping connectivity check"
            fi
            ;;
        serverpeer)
            local backend_container="${SERVERPEER_CONTAINER_NAME:-serverpeer-notes}"
            if docker ps --format '{{.Names}}' | grep -q "^${backend_container}$"; then
                if validate_network_connectivity "${network_name}" "$nginx_container" "$backend_container"; then
                    success "Network connectivity validated (ServerPeer)"
                else
                    connectivity_ok=false
                fi
            else
                info "ServerPeer container not yet created, skipping connectivity check"
            fi
            ;;
        both)
            local couchdb_container="${COUCHDB_CONTAINER_NAME:-couchdb-notes}"
            local serverpeer_container="${SERVERPEER_CONTAINER_NAME:-serverpeer-notes}"

            if docker ps --format '{{.Names}}' | grep -q "^${couchdb_container}$"; then
                if validate_network_connectivity "${network_name}" "$nginx_container" "$couchdb_container"; then
                    success "Network connectivity validated (CouchDB)"
                else
                    connectivity_ok=false
                fi
            else
                info "CouchDB container not yet created, skipping connectivity check"
            fi

            if docker ps --format '{{.Names}}' | grep -q "^${serverpeer_container}$"; then
                if validate_network_connectivity "${network_name}" "$nginx_container" "$serverpeer_container"; then
                    success "Network connectivity validated (ServerPeer)"
                else
                    connectivity_ok=false
                fi
            else
                info "ServerPeer container not yet created, skipping connectivity check"
            fi
            ;;
    esac

    if [ "$connectivity_ok" = false ]; then
        error "Network connectivity check failed"
        error "Nginx and backend containers may not be able to communicate"
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
