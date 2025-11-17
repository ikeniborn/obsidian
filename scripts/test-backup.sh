#!/bin/bash

set -e

info() { echo "[INFO] $*"; }
success() { echo "[SUCCESS] $*"; }
error() { echo "[ERROR] $*"; exit 1; }

info "Testing CouchDB backup process..."

if [[ ! -f "/opt/notes/.env" ]]; then
    error ".env file not found"
fi

source /opt/notes/.env
if [[ -n "$S3_ACCESS_KEY_ID" ]]; then
    info "S3 credentials found, testing connection..."
    python3 /opt/notes/scripts/s3_upload.py --test || error "S3 connection failed"
else
    info "S3 credentials not configured, backup will be local only"
fi

info "Running backup..."
bash /opt/notes/scripts/couchdb-backup.sh

BACKUP_FILE=$(ls -t /opt/notes/backups/couchdb-*.tar.gz 2>/dev/null | head -1)
if [[ -z "$BACKUP_FILE" ]]; then
    error "Backup file not created"
fi

success "Backup created: $BACKUP_FILE"
info "Backup size: $(du -h "$BACKUP_FILE" | cut -f1)"

info "Checking backup integrity..."
if gzip -t "$BACKUP_FILE"; then
    success "Backup integrity OK"
else
    error "Backup file is corrupted"
fi

success "Backup test PASSED"
