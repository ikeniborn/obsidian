#!/bin/bash
set -e
set -u

# Network Manager for Obsidian Sync Server
# Manages Docker networks with support for shared, isolated, and custom modes

# Color output functions
info() { echo -e "\033[0;36m[INFO]\033[0m $*"; }
success() { echo -e "\033[0;32m[SUCCESS]\033[0m $*"; }
warning() { echo -e "\033[0;33m[WARNING]\033[0m $*"; }
error() { echo -e "\033[0;31m[ERROR]\033[0m $*"; }

usage() {
    cat << EOF
Usage: $0 <command>

Commands:
    detect_mode                 - Auto-detect network mode (shared/isolated)
    list_networks               - List available Docker networks
    prompt_network_selection    - Interactive network selection (returns: mode|name)
    find_free_subnet            - Find free subnet in 172.24-31.0.0/16 range
    validate_subnet <subnet>    - Check if subnet is available
    create_network <name> [subnet] - Create Docker network
    validate_connectivity <network> <container1> <container2> - Test network connectivity

Examples:
    $0 detect_mode
    $0 list_networks
    $0 prompt_network_selection
    $0 find_free_subnet
    $0 validate_subnet 172.25.0.0/16
    $0 create_network obsidian_network
    $0 create_network obsidian_network 172.25.0.0/16
    $0 validate_connectivity obsidian_network couchdb nginx

EOF
}

detect_network_mode() {
    info "Detecting network mode..."

    local networks=$(docker network ls --format '{{.Name}}' | grep -v '^bridge$\|^host$\|^none$' || true)

    if [ -z "$networks" ]; then
        info "No existing custom networks found"
        success "Detected mode: ISOLATED"
        echo "isolated"
        return 0
    fi

    info "Found existing networks, defaulting to isolated mode"
    info "Run 'setup.sh' to configure shared mode with existing network"
    success "Detected mode: ISOLATED"
    echo "isolated"
    return 0
}

list_available_networks() {
    info "Listing available Docker networks..." >&2

    local networks=$(docker network ls --format '{{.Name}}' | grep -v '^bridge$\|^host$\|^none$' || true)

    if [ -z "$networks" ]; then
        warning "No custom Docker networks found" >&2
        echo "0. Create new isolated network" >&2
        echo "0"
        return 0
    fi

    local count=0
    while IFS= read -r network; do
        count=$((count + 1))
        local subnet=$(docker network inspect "$network" --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}' 2>/dev/null || echo "N/A")
        local driver=$(docker network inspect "$network" --format '{{.Driver}}' 2>/dev/null || echo "N/A")
        echo "$count. $network ($subnet, $driver)" >&2
    done <<< "$networks"

    echo "$((count + 1)). Create new isolated network" >&2

    success "Found $count existing network(s)" >&2
    echo "$count"
}

prompt_network_selection() {
    info "Select network mode:" >&2
    echo "" >&2

    local count=$(list_available_networks)
    local networks=$(docker network ls --format '{{.Name}}' | grep -v '^bridge$\|^host$\|^none$' || true)

    echo "" >&2
    echo "Options:" >&2
    if [ "$count" -gt 0 ]; then
        echo "  1-${count}. Use existing network" >&2
        echo "  $((count + 1)). Create new isolated network" >&2
    else
        echo "  1. Create new isolated network" >&2
    fi
    echo "" >&2

    local max_choice=$((count + 1))
    read -p "Your choice [1-${max_choice}]: " choice

    if [ -z "$choice" ]; then
        error "Choice cannot be empty"
        return 1
    fi

    if ! [[ "$choice" =~ ^[0-9]+$ ]]; then
        error "Invalid choice: must be a number"
        return 1
    fi

    if [ "$choice" -lt 1 ] || [ "$choice" -gt "$max_choice" ]; then
        error "Invalid choice: must be between 1 and $max_choice"
        return 1
    fi

    if [ "$choice" -le "$count" ] && [ "$count" -gt 0 ]; then
        local selected=$(echo "$networks" | sed -n "${choice}p")
        echo "shared|$selected"
    else
        echo "isolated|obsidian_network"
    fi
}

validate_subnet() {
    local subnet="$1"

    info "Validating subnet: $subnet" >&2

    local used_subnets=$(docker network inspect $(docker network ls -q) --format '{{range .IPAM.Config}}{{.Subnet}}{{"\n"}}{{end}}' 2>/dev/null | grep -v '^$' || true)

    if echo "$used_subnets" | grep -q "^${subnet}$"; then
        error "Subnet $subnet is already in use" >&2
        return 1
    fi

    success "Subnet $subnet is available" >&2
    return 0
}

find_free_subnet() {
    info "Searching for free subnet in range 172.24-31.0.0/16..." >&2

    for i in {24..31}; do
        local subnet="172.${i}.0.0/16"
        if validate_subnet "$subnet" &>/dev/null; then
            success "Found free subnet: $subnet" >&2
            echo "$subnet"
            return 0
        fi
    done

    error "No free subnets available in range 172.24-31.0.0/16" >&2
    return 1
}

create_network() {
    local network_name="$1"
    local subnet="${2:-}"

    if [ -z "$subnet" ]; then
        info "Subnet not specified, auto-detecting..." >&2
        subnet=$(find_free_subnet)
        if [ $? -ne 0 ]; then
            error "Failed to find free subnet" >&2
            return 1
        fi
    fi

    local gateway=$(echo "$subnet" | sed 's|0/16|1|')

    info "Creating Docker network: $network_name" >&2
    info "  Subnet: $subnet" >&2
    info "  Gateway: $gateway" >&2

    if docker network create \
        --driver bridge \
        --subnet "$subnet" \
        --gateway "$gateway" \
        "$network_name" &> /dev/null; then
        success "Network created successfully" >&2
        echo "Network: $network_name"
        echo "Subnet: $subnet"
        echo "Gateway: $gateway"
        return 0
    else
        error "Failed to create network $network_name" >&2
        return 1
    fi
}

validate_network_connectivity() {
    local network_name="$1"
    local container1="$2"
    local container2="$3"

    info "Validating connectivity: $container1 -> $container2 on network $network_name"

    local connected_containers=$(docker network inspect "$network_name" --format '{{range .Containers}}{{.Name}} {{end}}' 2>/dev/null || echo "")

    if ! echo "$connected_containers" | grep -q "$container1"; then
        error "Container $container1 is not connected to network $network_name"
        return 1
    fi

    if ! echo "$connected_containers" | grep -q "$container2"; then
        error "Container $container2 is not connected to network $network_name"
        return 1
    fi

    success "Both containers are connected to network $network_name"

    if docker exec "$container1" ping -c 1 "$container2" &> /dev/null; then
        success "Connectivity test PASSED: $container1 can reach $container2"
        return 0
    else
        warning "Connectivity test FAILED: $container1 cannot reach $container2"
        return 1
    fi
}

main() {
    if [ $# -eq 0 ]; then
        usage
        exit 1
    fi

    local command="$1"
    shift

    case "$command" in
        detect_mode)
            detect_network_mode
            ;;
        list_networks)
            list_available_networks
            ;;
        prompt_network_selection)
            prompt_network_selection
            ;;
        find_free_subnet)
            find_free_subnet
            ;;
        validate_subnet)
            if [ $# -lt 1 ]; then
                error "Usage: $0 validate_subnet <subnet>"
                exit 1
            fi
            validate_subnet "$1"
            ;;
        create_network)
            if [ $# -lt 1 ]; then
                error "Usage: $0 create_network <name> [subnet]"
                exit 1
            fi
            create_network "$@"
            ;;
        validate_connectivity)
            if [ $# -lt 3 ]; then
                error "Usage: $0 validate_connectivity <network> <container1> <container2>"
                exit 1
            fi
            validate_network_connectivity "$@"
            ;;
        -h|--help)
            usage
            ;;
        *)
            error "Unknown command: $command"
            usage
            exit 1
            ;;
    esac
}

# Execute main only when script is run directly (not when sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
