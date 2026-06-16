#!/bin/bash
set -uo pipefail

# =============================================================================
# System Disk Cleanup Script
# =============================================================================
# Reclaims disk space by trimming OS-level junk that accumulates over time:
#   - systemd journal (vacuumed to a size cap)
#   - apt package cache
#   - oversized log files (btmp, fail2ban, project nginx logs)
#
# Runs independently of the backup so a disk-full condition cannot deadlock
# cleanup: couchdb-backup.sh aborts early when the disk is critically full,
# which previously left no path to reclaim space (ENOSPC -> CouchDB 500).
#
# Usage:
#   sudo bash /opt/notes/scripts/cleanup-system.sh
#
# Scheduled via notes-cleanup.timer (daily at 03:30, after the backup).

ENV_FILE="/opt/notes/.env"
if [[ -f "$ENV_FILE" ]]; then
    set -a
    source "$ENV_FILE" 2>/dev/null || true
    set +a
fi

LOG_FILE="${NOTES_LOG_DIR:-/opt/notes/logs}/backup.log"
JOURNAL_MAX_SIZE="${CLEANUP_JOURNAL_MAX_SIZE:-200M}"
NGINX_LOG_DIR="${NOTES_LOG_DIR:-/opt/notes/logs}/nginx"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] CLEANUP: $1" | tee -a "${LOG_FILE}"
}

disk_free_gb() {
    df -k / | awk 'NR==2 {printf "%.1f", $4/1024/1024}'
}

log "Starting system cleanup (free before: $(disk_free_gb)GB)"

# 1. Vacuum systemd journal to a size cap
if command -v journalctl >/dev/null 2>&1; then
    result=$(journalctl --vacuum-size="${JOURNAL_MAX_SIZE}" 2>&1 | tail -1)
    log "journal vacuum -> ${result:-done}"
fi

# 2. Clear apt package cache
if command -v apt-get >/dev/null 2>&1; then
    apt-get clean 2>/dev/null && log "apt cache cleared" || log "WARNING: apt clean failed"
fi

# 3. Truncate oversized system logs (records, not data)
for f in /var/log/btmp /var/log/wtmp /var/log/fail2ban.log; do
    if [[ -f "$f" ]]; then
        truncate -s 0 "$f" 2>/dev/null && log "truncated $f" || true
    fi
done

# 4. Truncate project nginx logs (volume-mounted, monitored by fail2ban)
if [[ -d "${NGINX_LOG_DIR}" ]]; then
    find "${NGINX_LOG_DIR}" -type f -name '*.log' -exec truncate -s 0 {} \; 2>/dev/null \
        && log "nginx logs truncated" || true
fi

log "System cleanup completed (free after: $(disk_free_gb)GB)"
