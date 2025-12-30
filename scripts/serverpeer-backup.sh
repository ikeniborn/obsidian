#!/bin/bash
set -uo pipefail

# =============================================================================
# ServerPeer Vault Backup Script
# =============================================================================
# Backs up headless vault directory and uploads to S3
#
# NO DEPENDENCY ON COUCHDB - works with file-based storage
#
# Uses: SHARED s3_upload.py (backend-agnostic)
# =============================================================================

ENV_FILE="/opt/notes/.env"

if [[ -f "$ENV_FILE" ]]; then
    set -a
    source "$ENV_FILE" 2>/dev/null || true
    set +a
else
    echo "ERROR: .env file not found: $ENV_FILE"
    exit 1
fi

# Configuration
BACKUP_DIR="${NOTES_BACKUP_DIR:-/opt/notes/backups}"
LOG_FILE="${NOTES_LOG_DIR:-/opt/notes/logs}/backup.log"
RETENTION_DAYS=7
DATE_FORMAT="+%Y%m%d"
BACKUP_NAME="serverpeer-$(date -u ${DATE_FORMAT}).tar.gz"

VAULT_DIR="${SERVERPEER_VAULT_DIR:-/opt/notes/serverpeer-vault}"
CONTAINER_NAME="${SERVERPEER_CONTAINER_NAME:-notes-serverpeer}"

# S3 configuration (SHARED with CouchDB backups)
S3_ACCESS_KEY_ID="${S3_ACCESS_KEY_ID:-}"
S3_SECRET_ACCESS_KEY="${S3_SECRET_ACCESS_KEY:-}"
S3_BUCKET_NAME="${S3_BUCKET_NAME:-}"
S3_ENDPOINT_URL="${S3_ENDPOINT_URL:-https://storage.yandexcloud.net}"
S3_REGION="${S3_REGION:-ru-central1}"

# Backend-specific S3 prefix with fallback chain
# Priority: SERVERPEER_S3_BACKUP_PREFIX > S3_BACKUP_PREFIX > default
S3_BACKUP_PREFIX="${SERVERPEER_S3_BACKUP_PREFIX:-${S3_BACKUP_PREFIX:-serverpeer-backups/}}"

# SHARED s3_upload.py script (works with ANY file)
S3_UPLOAD_SCRIPT="/opt/notes/scripts/s3_upload.py"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "${LOG_FILE}"
}

error_exit() {
    log "ERROR: $1"
    exit 1
}

# Prerequisites
[[ -d "${BACKUP_DIR}" ]] || error_exit "Backup directory not found"
[[ -d "${VAULT_DIR}" ]] || error_exit "Vault directory not found: ${VAULT_DIR}"

# Check S3 availability
if [[ -z "$S3_ACCESS_KEY_ID" ]] || [[ -z "$S3_SECRET_ACCESS_KEY" ]]; then
    log "WARNING: S3 credentials not configured. Local backup only."
    S3_UPLOAD_ENABLED=false
elif [[ ! -f "${S3_UPLOAD_SCRIPT}" ]]; then
    log "WARNING: s3_upload.py not found. Local backup only."
    S3_UPLOAD_ENABLED=false
else
    S3_UPLOAD_ENABLED=true
fi

log "Starting ServerPeer vault backup"
log "Vault: ${VAULT_DIR}"

# Remove existing backup
[[ -f "${BACKUP_DIR}/${BACKUP_NAME}" ]] && rm -f "${BACKUP_DIR}/${BACKUP_NAME}"

# Create tar.gz archive
log "Creating backup: ${BACKUP_NAME}"
cd "${BACKUP_DIR}" || error_exit "Failed to cd to backup dir"

if tar czf "${BACKUP_NAME}" -C "$(dirname "${VAULT_DIR}")" "$(basename "${VAULT_DIR}")"; then
    log "Backup created: $(du -h "${BACKUP_NAME}" | cut -f1)"
else
    error_exit "Failed to create backup"
fi

# Verify integrity
log "Verifying backup integrity..."
if gzip -t "${BACKUP_NAME}" 2>/dev/null; then
    log "Integrity check: PASSED"
else
    error_exit "Backup corrupted"
fi

# Upload to S3 (using SHARED s3_upload.py)
if [[ "${S3_UPLOAD_ENABLED}" == "true" ]]; then
    log "Uploading to S3..."
    log "S3 prefix: ${S3_BACKUP_PREFIX}"

    if python3 "${S3_UPLOAD_SCRIPT}" "${BACKUP_DIR}/${BACKUP_NAME}" "${S3_BACKUP_PREFIX}" 2>&1 | tee -a "${LOG_FILE}"; then
        log "S3 upload: SUCCESS"
        log "Location: s3://${S3_BUCKET_NAME}/${S3_BACKUP_PREFIX}${BACKUP_NAME}"
    else
        log "S3 upload: FAILED (local backup available)"
    fi
fi

# Cleanup old backups
OLD_BACKUP="serverpeer-$(date -d "${RETENTION_DAYS} days ago" ${DATE_FORMAT}).tar.gz"
[[ -f "${BACKUP_DIR}/${OLD_BACKUP}" ]] && rm -f "${BACKUP_DIR}/${OLD_BACKUP}"
find "${BACKUP_DIR}" -name "serverpeer-*.tar.gz" -type f -mtime +${RETENTION_DAYS} -delete

log "Backup completed"
log "Local: ${BACKUP_DIR}/${BACKUP_NAME}"
[[ "${S3_UPLOAD_ENABLED}" == "true" ]] && log "Remote: s3://${S3_BUCKET_NAME}/${S3_BACKUP_PREFIX}${BACKUP_NAME}"
