#!/bin/bash
set -uo pipefail

# =============================================================================
# CouchDB Notes Backup Script
# =============================================================================
# Backs up CouchDB databases and uploads to S3-compatible storage
# Uses environment variables from /opt/budget/.env
#
# Requirements:
#   - Docker container running (name from .env: COUCHDB_CONTAINER_NAME)
#   - Python 3 with boto3: pip3 install boto3
#   - S3 credentials in .env: S3_ACCESS_KEY_ID, S3_SECRET_ACCESS_KEY, S3_BUCKET_NAME
#
# Usage:
#   bash /opt/budget/notes/couchdb-backup.sh
#
# Cron (daily at 3 AM):
#   0 3 * * * cd /opt/budget && bash notes/couchdb-backup.sh >> /opt/notes/logs/backup.log 2>&1
#

# Load environment variables from .env
ENV_FILE="/opt/notes/.env"

# Fallback на /opt/budget/.env для обратной совместимости
if [[ ! -f "$ENV_FILE" ]] && [[ -f "/opt/budget/.env" ]]; then
    ENV_FILE="/opt/budget/.env"
    echo "WARNING: Using fallback .env from /opt/budget/"
fi

if [[ -f "$ENV_FILE" ]]; then
    # Export variables from .env (excluding comments and empty lines)
    set -a
    source "$ENV_FILE" 2>/dev/null || true
    set +a
else
    echo "WARNING: .env file not found: $ENV_FILE"
    echo "Using default configuration"
fi

# Configuration (with .env fallback to defaults)
BACKUP_DIR="${NOTES_BACKUP_DIR:-/opt/notes/backups}"
LOG_FILE="${NOTES_LOG_DIR:-/opt/notes/logs}/backup.log"
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-7}"
DATE_FORMAT="+%Y%m%d"
# Per-DB streaming layout: each database is a separate object under a dated
# "set" folder, e.g. couchdb-backups/couchdb-20260616/work.json.gz
BACKUP_SET="couchdb-$(date -u ${DATE_FORMAT})"
# Legacy single-archive names kept only for stray local cleanup globs
BACKUP_NAME="couchdb-$(date -u ${DATE_FORMAT}).tar.gz"
OLD_BACKUP_NAME="couchdb-$(date -d "${RETENTION_DAYS} days ago" ${DATE_FORMAT}).tar.gz"

# Docker configuration
# Use container name from .env (default: notes-couchdb)
COUCHDB_CONTAINER="${COUCHDB_CONTAINER_NAME:-notes-couchdb}"

# Validate container exists
if ! docker ps --format '{{.Names}}' | grep -q "^${COUCHDB_CONTAINER}$"; then
    echo "ERROR: CouchDB container '${COUCHDB_CONTAINER}' not found"
    echo "Available containers:"
    docker ps --format '{{.Names}}'
    exit 1
fi

# CouchDB credentials (from .env)
COUCHDB_USER="${COUCHDB_USER:-admin}"
COUCHDB_PASSWORD="${COUCHDB_PASSWORD:?ERROR: COUCHDB_PASSWORD not set in .env}"
COUCHDB_URL="http://${COUCHDB_USER}:${COUCHDB_PASSWORD}@localhost:5984"
COUCHDB_HOST_URL="http://${COUCHDB_USER}:${COUCHDB_PASSWORD}@localhost:5984"
# Verify credentials before attempting backup
if ! curl -sf "${COUCHDB_HOST_URL}/_up" >/dev/null 2>&1; then
    error_exit "CouchDB auth check failed -- verify COUCHDB_USER/COUCHDB_PASSWORD in .env"
fi

# S3 configuration (from .env)
S3_ACCESS_KEY_ID="${S3_ACCESS_KEY_ID:-}"
S3_SECRET_ACCESS_KEY="${S3_SECRET_ACCESS_KEY:-}"
S3_BUCKET_NAME="${S3_BUCKET_NAME:-}"
S3_ENDPOINT_URL="${S3_ENDPOINT_URL:-https://storage.yandexcloud.net}"
S3_REGION="${S3_REGION:-ru-central1}"

# Backend-specific S3 prefix with fallback chain
# Priority: COUCHDB_S3_BACKUP_PREFIX > S3_BACKUP_PREFIX > default
S3_BACKUP_PREFIX="${COUCHDB_S3_BACKUP_PREFIX:-${S3_BACKUP_PREFIX:-couchdb-backups/}}"

S3_UPLOAD_SCRIPT="/opt/notes/scripts/s3_upload.py"

# Fallback
if [[ ! -f "$S3_UPLOAD_SCRIPT" ]] && [[ -f "/opt/budget/scripts/s3_upload.py" ]]; then
    S3_UPLOAD_SCRIPT="/opt/budget/scripts/s3_upload.py"
fi

S3_PREFIX="${S3_BACKUP_PREFIX}"

# Standalone system cleanup script (journal/apt/logs)
CLEANUP_SCRIPT="$(dirname "${BASH_SOURCE[0]}")/cleanup-system.sh"

# Tracks whether the local archive was removed after a successful S3 upload
LOCAL_BACKUP_REMOVED=false

# Resource limits
CPU_LIMIT="0.5"  # 50% of one CPU
MEMORY_LIMIT="512m"  # 512MB RAM
COMPRESSION_LEVEL="6"  # gzip compression level (1-9)
UPLOAD_BANDWIDTH="1MB"  # Bandwidth limit for S3 upload
NICE_LEVEL="19"  # Lowest priority
IONICE_CLASS="3"  # Idle I/O priority
BACKUP_BATCH_SIZE="10"  # Number of databases to backup before checking container health

# Timeout settings
BASE_TIMEOUT=60       # Base timeout for small databases (seconds)
# Streaming upload of a multi-GB DB to S3 is bandwidth-bound and holds curl
# open for the whole upload; 1800s was too low for ~9GB over a slow link.
MAX_TIMEOUT=7200      # Maximum timeout for very large databases (2 hours)
TIMEOUT_PER_MB=2      # Additional seconds per MB of database size

# Progress tracking variables
TOTAL_STEPS=9
CURRENT_STEP=0
PROGRESS_WIDTH=50

# Function to calculate timeout based on database size and report fragmentation
calculate_timeout() {
    local db_name="$1"
    local use_host_api="$2"
    local db_info
    local timeout

    if [[ "${use_host_api}" == "true" ]]; then
        db_info=$(curl -s --connect-timeout 10 "${COUCHDB_HOST_URL}/${db_name}" 2>/dev/null)
    else
        db_info=$(docker exec "${COUCHDB_CONTAINER}" curl -s "${COUCHDB_URL}/${db_name}" 2>/dev/null)
    fi

    if [[ -n "$db_info" ]]; then
        # Use active size (actual data) for timeout — not file size (includes dead revisions)
        local active_bytes file_bytes
        active_bytes=$(echo "$db_info" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('sizes',{}).get('active', d.get('data_size', 0)))" 2>/dev/null)
        file_bytes=$(echo "$db_info" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('sizes',{}).get('file', d.get('disk_size', 0)))" 2>/dev/null)

        if [[ -n "$active_bytes" && "$active_bytes" -gt 0 ]]; then
            local active_mb=$((active_bytes / 1024 / 1024))
            timeout=$((BASE_TIMEOUT + active_mb * TIMEOUT_PER_MB))
            if [[ $timeout -gt $MAX_TIMEOUT ]]; then
                timeout=$MAX_TIMEOUT
            fi

            # Report fragmentation
            if [[ -n "$file_bytes" && "$file_bytes" -gt 0 ]]; then
                local frag_pct=$(( (file_bytes - active_bytes) * 100 / file_bytes ))
                local file_mb=$((file_bytes / 1024 / 1024))
                if [[ $frag_pct -gt 30 ]]; then
                    echo "WARNING: DB ${db_name}: ${frag_pct}% fragmentation (${active_mb}MB active / ${file_mb}MB on disk) — run manual compaction" >&2
                else
                    echo "DB ${db_name}: ${active_mb}MB active, ${frag_pct}% fragmentation, timeout: ${timeout}s" >&2
                fi
            else
                echo "DB ${db_name}: ${active_mb}MB, timeout: ${timeout}s" >&2
            fi
            echo $timeout
        else
            echo "DB ${db_name}: size unknown, using base timeout ${BASE_TIMEOUT}s" >&2
            echo $BASE_TIMEOUT
        fi
    else
        echo "DB ${db_name}: info unavailable, using base timeout ${BASE_TIMEOUT}s" >&2
        echo $BASE_TIMEOUT
    fi
}

# Progress bar function
show_progress() {
    local step=$1
    local description="$2"
    local percent=$((step * 100 / TOTAL_STEPS))
    local filled=$((percent * PROGRESS_WIDTH / 100))
    local empty=$((PROGRESS_WIDTH - filled))
    
    # Create progress bar
    local bar=""
    for ((i=0; i<filled; i++)); do bar+="█"; done
    for ((i=0; i<empty; i++)); do bar+="░"; done
    
    # Clear current line and show progress
    printf "\r\033[K[%s] %3d%% - %s" "$bar" "$percent" "$description"
    
    # Log to file as well
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] PROGRESS: ${percent}% - ${description}" >> "${LOG_FILE}"
    
    # Add newline for intermediate steps to avoid conflicts with other output
    if [[ $step -lt $TOTAL_STEPS ]]; then
        echo ""
    else
        echo ""
    fi
}

# Update progress function
update_progress() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    show_progress $CURRENT_STEP "$1"
    
    # Also show simplified progress line for better visibility
    local percent=$((CURRENT_STEP * 100 / TOTAL_STEPS))
    log "🔄 Progress: Step ${CURRENT_STEP}/${TOTAL_STEPS} (${percent}%) - $1"
}

# Logging function
log() {
    # File-only: the systemd/cron runner already captures stdout into the same
    # log file, so teeing to stdout here would duplicate every line.
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "${LOG_FILE}"
}

# Error handling
error_exit() {
    log "ERROR: $1"
    exit 1
}

# Check prerequisites
if [[ ! -d "${BACKUP_DIR}" ]]; then
    error_exit "Backup directory ${BACKUP_DIR} does not exist"
fi

# Check if Python 3 is available for S3 upload
if ! command -v python3 >/dev/null 2>&1; then
    error_exit "python3 is not installed (required for S3 upload)"
fi

# Check disk space before starting backup
check_disk_space() {
    local dir="$1"
    local free_kb
    free_kb=$(df -k "$dir" | awk 'NR==2 {print $4}')
    local free_gb=$((free_kb / 1024 / 1024))
    local used_pct
    used_pct=$(df -k "$dir" | awk 'NR==2 {print $5}' | tr -d '%')

    log "Disk space: ${free_gb}GB free (${used_pct}% used) on $(df -k "$dir" | awk 'NR==2 {print $1}')"

    # Per-DB streaming writes nothing but log lines to local disk, so a full
    # disk no longer blocks the backup — warn only. (The old hard-abort would
    # have prevented a backup precisely when it was most needed.)
    if [[ $free_kb -lt 524288 ]]; then  # < 512MB — only logs need space
        log "WARNING: Very low disk space: ${free_gb}GB free — streaming backup will still run"
    elif [[ $used_pct -gt 90 ]]; then
        log "WARNING: Disk usage critical: ${used_pct}% used — backup streams to S3, but free space soon"
    elif [[ $used_pct -gt 80 ]]; then
        log "WARNING: Disk usage high: ${used_pct}% used"
    fi
}

check_disk_space "${BACKUP_DIR}"

# Проверка что S3 credentials заданы
if [[ -z "$S3_ACCESS_KEY_ID" ]] || [[ -z "$S3_SECRET_ACCESS_KEY" ]]; then
    log "WARNING: S3 credentials not configured"
    log "Backup will be local only (no S3 upload)"
    S3_UPLOAD_ENABLED=false
elif [[ ! -f "${S3_UPLOAD_SCRIPT}" ]]; then
    log "WARNING: S3 upload script not found: ${S3_UPLOAD_SCRIPT}"
    log "S3 upload will be skipped. Backup will be local only."
    S3_UPLOAD_ENABLED=false
else
    S3_UPLOAD_ENABLED=true
fi

update_progress "Prerequisites checked"

# Change to backup directory
cd "${BACKUP_DIR}" || error_exit "Failed to change to backup directory"

log "Starting CouchDB backup process"
update_progress "Initializing backup process"

# Remove existing backup if present
if [[ -f "${BACKUP_NAME}" ]]; then
    log "Removing existing backup: ${BACKUP_NAME}"
    rm -f "${BACKUP_NAME}" || error_exit "Failed to remove existing backup"
fi

# Check if CouchDB is running (initial check)
log "Checking if CouchDB container is running..."
if ! docker ps --format "{{.Names}}" | grep -q "^${COUCHDB_CONTAINER}$" && \
   ! [[ "$(docker inspect -f '{{.State.Running}}' "${COUCHDB_CONTAINER}" 2>/dev/null)" == "true" ]] && \
   ! curl -s --connect-timeout 2 "${COUCHDB_HOST_URL}/_up" >/dev/null 2>&1; then
    error_exit "CouchDB container '${COUCHDB_CONTAINER}' is not running"
fi
log "CouchDB container is running"
update_progress "Container status verified"

# Create backup using CouchDB _all_docs API, streamed per-database to S3
log "Creating backup set: ${BACKUP_SET}"
log "Streaming each database directly to S3 (no local temp/archive)"

# Function to check if container is running
check_container_health() {
    # Try multiple methods to check container status
    local container_running=false
    
    # Method 1: Check by name format
    if docker ps --format "{{.Names}}" | grep -q "^${COUCHDB_CONTAINER}$"; then
        container_running=true
    # Method 2: Check by container inspection
    elif docker inspect "${COUCHDB_CONTAINER}" >/dev/null 2>&1 && \
         [[ "$(docker inspect -f '{{.State.Running}}' "${COUCHDB_CONTAINER}" 2>/dev/null)" == "true" ]]; then
        container_running=true
    # Method 3: Try to connect to CouchDB API
    elif curl -s --connect-timeout 2 "${COUCHDB_HOST_URL}/_up" >/dev/null 2>&1; then
        container_running=true
    fi
    
    if [[ "${container_running}" == "false" ]]; then
        log "WARNING: CouchDB container is not running, waiting for restart..."
        sleep 10
        
        # Retry check after waiting
        if docker ps --format "{{.Names}}" | grep -q "^${COUCHDB_CONTAINER}$" || \
           [[ "$(docker inspect -f '{{.State.Running}}' "${COUCHDB_CONTAINER}" 2>/dev/null)" == "true" ]] || \
           curl -s --connect-timeout 2 "${COUCHDB_HOST_URL}/_up" >/dev/null 2>&1; then
            log "CouchDB container is now running"
        else
            error_exit "CouchDB container failed to restart"
        fi
    fi
}

# Get list of all databases (excluding system databases)
log "Fetching database list..."
check_container_health
update_progress "Fetching database list"

# Try to use direct host access first, fall back to docker exec if needed
if curl -s --connect-timeout 5 "${COUCHDB_HOST_URL}/_all_dbs" >/dev/null 2>&1; then
    log "Using direct host access to CouchDB API"
    DBS=$(curl -s "${COUCHDB_HOST_URL}/_all_dbs" | \
        sed 's/\[//;s/\]//;s/"//g' | \
        tr ',' '\n' | \
        grep -v '^_')
    USE_HOST_API=true
else
    log "Using docker exec to access CouchDB API"
    DBS=$(docker exec "${COUCHDB_CONTAINER}" curl -s "${COUCHDB_URL}/_all_dbs" | \
        sed 's/\[//;s/\]//;s/"//g' | \
        tr ',' '\n' | \
        grep -v '^_')
    USE_HOST_API=false
fi

# Per-DB streaming requires S3 — there is no local-archive path (by design,
# the dataset is too large to stage on the local disk).
if [[ "${S3_UPLOAD_ENABLED}" != "true" ]]; then
    error_exit "S3 must be configured — per-DB streaming backup writes no local archive. Set S3 credentials in .env."
fi

S3_SET_PREFIX="${S3_PREFIX}${BACKUP_SET}/"

# Stream one database straight to S3: curl | gzip | upload. No temp file, so
# peak local disk stays ~0 regardless of DB size (a 16GB DB does not touch the
# disk). pipefail (set at top) + PIPESTATUS report which stage failed.
stream_db_to_s3() {
    local db="$1" timeout_s="$2" key="$3"
    if [[ "${USE_HOST_API}" == "true" ]]; then
        timeout "${timeout_s}" curl -fsS "${COUCHDB_HOST_URL}/${db}/_all_docs?include_docs=true" \
            | gzip -${COMPRESSION_LEVEL} \
            | nice -n ${NICE_LEVEL} ionice -c ${IONICE_CLASS} python3 "${S3_UPLOAD_SCRIPT}" --stdin "${key}"
    else
        timeout "${timeout_s}" docker exec "${COUCHDB_CONTAINER}" curl -fsS "${COUCHDB_URL}/${db}/_all_docs?include_docs=true" \
            | gzip -${COMPRESSION_LEVEL} \
            | nice -n ${NICE_LEVEL} ionice -c ${IONICE_CLASS} python3 "${S3_UPLOAD_SCRIPT}" --stdin "${key}"
    fi
    PIPE_RESULT=("${PIPESTATUS[@]}")
}

if [[ -z "${DBS}" ]]; then
    log "No user databases found to backup"
else
    DB_COUNT=0
    UPLOADED_DBS=0
    FAILED_DBS=0
    TOTAL_DBS=$(echo "${DBS}" | wc -w)
    log "Found ${TOTAL_DBS} databases to backup"
    log "Streaming to s3://${S3_BUCKET_NAME}/${S3_SET_PREFIX}"

    for db in ${DBS}; do
        log "Backing up database: ${db}"

        # Check container health periodically
        if (( DB_COUNT % BACKUP_BATCH_SIZE == 0 )); then
            check_container_health
        fi

        sleep 0.5

        DB_TIMEOUT=$(calculate_timeout "${db}" "${USE_HOST_API}")
        if ! [[ "$DB_TIMEOUT" =~ ^[0-9]+$ ]]; then
            log "WARNING: Invalid timeout calculated for ${db} (got: '$DB_TIMEOUT'), using default"
            DB_TIMEOUT=$BASE_TIMEOUT
        fi

        db_key="${S3_SET_PREFIX}${db}.json.gz"
        log "Streaming ${db} → s3://${S3_BUCKET_NAME}/${db_key} (timeout: ${DB_TIMEOUT}s)..."
        stream_db_to_s3 "${db}" "${DB_TIMEOUT}" "${db_key}"

        if [[ "${PIPE_RESULT[0]}" -eq 0 && "${PIPE_RESULT[1]}" -eq 0 && "${PIPE_RESULT[2]}" -eq 0 ]]; then
            log "✓ Database ${db} streamed to S3"
            ((UPLOADED_DBS++))
        else
            if [[ "${PIPE_RESULT[0]}" -eq 124 ]]; then
                log "ERROR: Database ${db} timed out after ${DB_TIMEOUT}s"
            else
                log "ERROR: Database ${db} stream failed (curl=${PIPE_RESULT[0]} gzip=${PIPE_RESULT[1]} upload=${PIPE_RESULT[2]})"
            fi
            # Remove any partial/incomplete object left in S3
            python3 "${S3_UPLOAD_SCRIPT}" --delete "${db_key}" >> "${LOG_FILE}" 2>&1 || true
            ((FAILED_DBS++))
            log "Continuing with other databases..."
        fi

        ((DB_COUNT++))
        log "  └── Database progress: ${DB_COUNT}/${TOTAL_DBS} - ${db}"
    done

    update_progress "Database streaming completed (${UPLOADED_DBS}/${TOTAL_DBS} uploaded)"

    # Stream global configuration as its own object
    log "Backing up CouchDB configuration..."
    check_container_health
    sleep 0.5
    config_key="${S3_SET_PREFIX}_config.json.gz"
    if [[ "${USE_HOST_API}" == "true" ]]; then
        timeout 30 curl -fsS "${COUCHDB_HOST_URL}/_node/_local/_config" \
            | gzip -${COMPRESSION_LEVEL} | python3 "${S3_UPLOAD_SCRIPT}" --stdin "${config_key}"
    else
        timeout 30 docker exec "${COUCHDB_CONTAINER}" curl -fsS "${COUCHDB_URL}/_node/_local/_config" \
            | gzip -${COMPRESSION_LEVEL} | python3 "${S3_UPLOAD_SCRIPT}" --stdin "${config_key}"
    fi
    cfg_status=("${PIPESTATUS[@]}")
    if [[ "${cfg_status[0]}" -eq 0 && "${cfg_status[1]}" -eq 0 && "${cfg_status[2]}" -eq 0 ]]; then
        log "Configuration backed up successfully"
    else
        log "WARNING: Failed to backup configuration, but continuing"
        python3 "${S3_UPLOAD_SCRIPT}" --delete "${config_key}" 2>/dev/null || true
    fi

    update_progress "Configuration backup completed"

    # Require at least one database to have made it to S3
    if [[ "${UPLOADED_DBS}" -eq 0 ]]; then
        error_exit "No databases uploaded to S3 — backup failed"
    fi
    if [[ "${FAILED_DBS}" -gt 0 ]]; then
        log "WARNING: ${FAILED_DBS} database(s) failed to upload (set is incomplete)"
    fi

    LOCAL_BACKUP_REMOVED=true
    log "✅ Backup set ${BACKUP_SET} streamed to S3 (${UPLOADED_DBS}/${TOTAL_DBS} databases)"
    update_progress "Backup streamed to S3"

    # Prune old S3 objects ONLY when this set is complete. Pruning on an
    # incomplete set could delete the previous good backup while the current
    # one is missing a database — leaving no valid copy at all.
    if [[ "${FAILED_DBS}" -eq 0 ]]; then
        log "Cleaning up S3 objects older than ${RETENTION_DAYS} days..."
        if python3 "${S3_UPLOAD_SCRIPT}" --cleanup "${S3_PREFIX}" --days "${RETENTION_DAYS}" >> "${LOG_FILE}" 2>&1; then
            log "S3 cleanup completed"
        else
            log "WARNING: S3 cleanup failed (backup upload was successful)"
        fi
    else
        log "Skipping S3 retention cleanup — set incomplete (${FAILED_DBS} failed), keeping older backups"
    fi
fi

# Clean up local old backups
if [[ -f "${OLD_BACKUP_NAME}" ]]; then
    log "Removing old local backup: ${OLD_BACKUP_NAME}"
    rm -f "${OLD_BACKUP_NAME}" || log "WARNING: Failed to remove old local backup"
fi

# Clean up any backups older than retention period
log "Cleaning up backups older than ${RETENTION_DAYS} days"
find "${BACKUP_DIR}" -name "couchdb-*.tar.gz" -type f -mtime +$((RETENTION_DAYS-1)) -delete

# Remove failed/empty backup archives (0-byte leftovers from aborted runs)
find "${BACKUP_DIR}" -name "couchdb-*.tar.gz" -type f -size 0 -delete 2>/dev/null

# System cleanup (journal/apt/logs) — reclaim OS-level disk after backup
if [[ -x "${CLEANUP_SCRIPT}" ]] || [[ -f "${CLEANUP_SCRIPT}" ]]; then
    log "Running system cleanup..."
    bash "${CLEANUP_SCRIPT}" || log "WARNING: System cleanup reported errors"
else
    log "WARNING: Cleanup script not found: ${CLEANUP_SCRIPT}"
fi

update_progress "Cleanup completed - Backup process finished"

echo ""
echo "=========================================="
log "🎉 BACKUP PROCESS COMPLETED SUCCESSFULLY 🎉"
log "Backup set: ${BACKUP_SET} (${UPLOADED_DBS:-0}/${TOTAL_DBS:-0} databases)"
log "Local copy: none (streamed directly to S3)"
log "S3 location: s3://${S3_BUCKET_NAME:-[bucket]}/${S3_SET_PREFIX:-${S3_PREFIX}}"
log "Restore: download <db>.json.gz from the set prefix, gunzip, POST docs via _bulk_docs"
echo "=========================================="

# Final container health check
check_container_health
log "CouchDB container is running normally after backup"

# Return to home directory
