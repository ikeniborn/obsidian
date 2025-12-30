#!/bin/bash
#
# Deployment Helper Functions
# Provides rsync synchronization and Docker image version checking
#
# Author: Obsidian Sync Server Team
# Version: 1.0.0
# Date: 2025-12-30
#

set -e
set -u

# =============================================================================
# RSYNC DEPLOYMENT
# =============================================================================

rsync_deployment_files() {
    local source_dir="$1"
    local target_dir="$2"
    local dry_run="${3:-false}"

    echo "🔄 Synchronizing files from $source_dir to $target_dir..."

    # Files and directories to EXCLUDE from sync (preserve user data)
    local exclude_patterns=(
        # User configuration and secrets
        ".env"
        ".env.backup.*"
        ".credentials.json"

        # Persistent data directories
        "data/"
        "backups/"
        "logs/"
        "nostr-relay-data/"
        "serverpeer-vault*/"

        # SSL certificates (managed by certbot)
        "nginx/ssl/"
        "nginx/letsencrypt/"

        # Git metadata
        ".git/"
        ".github/"
        ".gitignore"

        # Temporary files
        "tmp/"
        "*.swp"
        "*.tmp"
        ".DS_Store"

        # Version control
        "deployment.lock"
    )

    # Build rsync exclude arguments
    local exclude_args=()
    for pattern in "${exclude_patterns[@]}"; do
        exclude_args+=("--exclude=$pattern")
    done

    # Rsync options:
    # -a: archive mode (preserves permissions, timestamps, etc.)
    # -v: verbose
    # -h: human-readable
    # -P: show progress and keep partial files
    # --delete: delete files in target that don't exist in source (mirror mode)
    # --backup: backup files before overwriting
    # --backup-dir: where to store backups
    local rsync_opts=(
        -avhP
        --delete
        --backup
        "--backup-dir=$target_dir/.rsync-backups/$(date +%Y%m%d_%H%M%S)"
    )

    if [[ "$dry_run" == "true" ]]; then
        rsync_opts+=(--dry-run)
        echo "🧪 DRY RUN MODE - No changes will be made"
    fi

    # Execute rsync
    if sudo rsync "${rsync_opts[@]}" "${exclude_args[@]}" \
        "$source_dir/" "$target_dir/"; then
        echo "✅ Files synchronized successfully"

        if [[ "$dry_run" != "true" ]]; then
            # Set correct permissions on synced scripts
            sudo find "$target_dir/scripts" -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
            sudo find "$target_dir/scripts" -name "*.py" -exec chmod +x {} \; 2>/dev/null || true
            echo "✅ Script permissions updated"
        fi

        return 0
    else
        echo "❌ Rsync synchronization failed"
        return 1
    fi
}

show_rsync_changes() {
    local source_dir="$1"
    local target_dir="$2"

    echo "📋 Changes that will be applied:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    rsync_deployment_files "$source_dir" "$target_dir" true | \
        grep -E "^(deleting|<f|>f|\*deleting)" || echo "No changes detected"

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# =============================================================================
# DOCKER IMAGE VERSION CHECKING
# =============================================================================

get_local_image_id() {
    local image="$1"

    # Get Image ID (Config.Digest) - same as what docker pull checks
    docker inspect --format='{{.Id}}' "$image" 2>/dev/null || echo ""
}

get_remote_image_id() {
    local image="$1"

    # Get remote Image ID by inspecting manifest config
    # This returns the same Image ID that docker pull would compare
    local manifest

    if manifest=$(docker manifest inspect "$image" 2>/dev/null); then
        # Extract config.digest which is the Image ID
        echo "$manifest" | grep -oP '"config":\s*\{[^}]*"digest":\s*"\K[^"]+' | head -1
    else
        # Fallback: cannot determine remote Image ID
        echo ""
    fi
}

check_image_needs_update() {
    local image="$1"

    echo "🔍 Checking if image needs update: $image"

    # Check if image exists locally
    if ! docker image inspect "$image" &>/dev/null; then
        echo "📥 Image not found locally, pull required"
        return 0  # Needs pull
    fi

    # Get local Image ID
    local local_image_id=$(get_local_image_id "$image")
    if [[ -z "$local_image_id" ]]; then
        echo "⚠️  Cannot determine local image ID, pulling to be safe"
        return 0  # Needs pull
    fi

    # Get remote Image ID
    local remote_image_id=$(get_remote_image_id "$image")
    if [[ -z "$remote_image_id" ]]; then
        echo "⚠️  Cannot determine remote image ID, skipping pull"
        echo "💡 Using cached local image"
        return 1  # Skip pull
    fi

    # Compare Image IDs (same logic as docker pull)
    if [[ "$local_image_id" == "$remote_image_id" ]]; then
        echo "✅ Image is up-to-date (ID: ${local_image_id:0:19}...)"
        return 1  # Skip pull
    else
        echo "📥 Update available"
        echo "   Local:  ${local_image_id:0:19}..."
        echo "   Remote: ${remote_image_id:0:19}..."
        return 0  # Needs pull
    fi
}

smart_docker_pull() {
    local image="$1"
    local force_pull="${2:-false}"

    if [[ "$force_pull" == "true" ]]; then
        echo "🔄 Force pulling image: $image"
        docker pull "$image"
        return $?
    fi

    if check_image_needs_update "$image"; then
        echo "🔄 Pulling updated image: $image"
        docker pull "$image"
        return $?
    else
        echo "⏭️  Skipping pull (image up-to-date): $image"
        return 0
    fi
}

# =============================================================================
# DEPLOYMENT LOCKFILE
# =============================================================================

save_deployment_lockfile() {
    local lockfile="$1"

    echo "💾 Saving deployment lockfile..."

    # Collect image versions
    local couchdb_digest=$(get_local_image_digest "couchdb:3.3" || echo "unknown")
    local nostr_digest=$(get_local_image_digest "scsibug/nostr-rs-relay:latest" || echo "unknown")
    local deno_digest=$(get_local_image_digest "denoland/deno:bin" || echo "unknown")
    local node_digest=$(get_local_image_digest "node:22.14-bookworm-slim" || echo "unknown")

    # Get git commit hash
    local git_commit=$(git -C "$(dirname "$lockfile")" rev-parse HEAD 2>/dev/null || echo "unknown")

    # Create lockfile
    cat > "$lockfile" << EOF
{
  "deployment": {
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "git_commit": "$git_commit",
    "deployed_by": "$(whoami)@$(hostname)"
  },
  "docker_images": {
    "couchdb": {
      "image": "couchdb:3.3",
      "digest": "$couchdb_digest"
    },
    "nostr_relay": {
      "image": "scsibug/nostr-rs-relay:latest",
      "digest": "$nostr_digest"
    },
    "deno": {
      "image": "denoland/deno:bin",
      "digest": "$deno_digest"
    },
    "node": {
      "image": "node:22.14-bookworm-slim",
      "digest": "$node_digest"
    }
  },
  "config_checksums": {
    "env_file": "$(md5sum /opt/notes/.env 2>/dev/null | awk '{print $1}' || echo 'not_found')",
    "nostr_config": "$(md5sum /opt/notes/nostr-relay/config.toml 2>/dev/null | awk '{print $1}' || echo 'not_found')",
    "couchdb_config": "$(md5sum /opt/notes/local.ini 2>/dev/null | awk '{print $1}' || echo 'not_found')"
  }
}
EOF

    echo "✅ Lockfile saved: $lockfile"
}

show_deployment_diff() {
    local old_lockfile="$1"
    local new_lockfile="$2"

    if [[ ! -f "$old_lockfile" ]]; then
        echo "📝 First deployment - no previous lockfile found"
        return 0
    fi

    echo "📊 Deployment changes since last deployment:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Compare git commits
    local old_commit=$(grep -oP '"git_commit":\s*"\K[^"]+' "$old_lockfile" 2>/dev/null || echo "unknown")
    local new_commit=$(grep -oP '"git_commit":\s*"\K[^"]+' "$new_lockfile" 2>/dev/null || echo "unknown")

    if [[ "$old_commit" != "$new_commit" ]]; then
        echo "🔄 Git commit: $old_commit → $new_commit"
    else
        echo "✅ Git commit: unchanged ($old_commit)"
    fi

    # Compare image digests
    for image_key in couchdb nostr_relay deno node; do
        local old_digest=$(grep -A 2 "\"$image_key\"" "$old_lockfile" | grep -oP '"digest":\s*"\K[^"]+' || echo "unknown")
        local new_digest=$(grep -A 2 "\"$image_key\"" "$new_lockfile" | grep -oP '"digest":\s*"\K[^"]+' || echo "unknown")

        if [[ "$old_digest" != "$new_digest" ]]; then
            echo "🔄 Image $image_key: updated"
        fi
    done

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# =============================================================================
# EXPORTS
# =============================================================================

# Make functions available to sourcing scripts
export -f rsync_deployment_files
export -f show_rsync_changes
export -f check_image_needs_update
export -f smart_docker_pull
export -f save_deployment_lockfile
export -f show_deployment_diff
