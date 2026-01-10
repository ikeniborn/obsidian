#!/bin/bash
# CouchDB Health Monitoring Script
# Purpose: Check database fragmentation, disk space, and performance metrics
# Schedule: Run daily via cron (e.g., 0 6 * * *)

set -euo pipefail

# Color output for better readability
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Configuration
NOTES_DIR="/opt/notes"
ENV_FILE="$NOTES_DIR/.env"
LOG_DIR="$NOTES_DIR/logs"
LOG_FILE="$LOG_DIR/health.log"

# Functions for colored output
info() {
    echo -e "${GREEN}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

# Load credentials from .env
if [[ ! -f "$ENV_FILE" ]]; then
    error "Environment file not found: $ENV_FILE"
    exit 1
fi

ADMIN_USER="admin"
ADMIN_PASS=$(grep "^COUCHDB_PASSWORD=" "$ENV_FILE" | cut -d'=' -f2)
COUCHDB_PORT=$(grep "^COUCHDB_PORT=" "$ENV_FILE" | cut -d'=' -f2 || echo "5984")

if [[ -z "$ADMIN_PASS" ]]; then
    error "COUCHDB_PASSWORD not found in $ENV_FILE"
    exit 1
fi

# Create log directory if not exists
mkdir -p "$LOG_DIR"

# Timestamp
echo "========================================" | tee -a "$LOG_FILE"
info "CouchDB Health Check - $(date '+%Y-%m-%d %H:%M:%S')"

# Check CouchDB availability
info "Checking CouchDB availability..."
if ! curl -s -f -u "$ADMIN_USER:$ADMIN_PASS" "http://localhost:$COUCHDB_PORT/_up" > /dev/null 2>&1; then
    error "CouchDB is not responding at http://localhost:$COUCHDB_PORT"
    exit 1
fi
info "✓ CouchDB is running"

# Get list of databases (exclude system databases)
DATABASES=$(curl -s -u "$ADMIN_USER:$ADMIN_PASS" "http://localhost:$COUCHDB_PORT/_all_dbs" | \
    python3 -c "import sys, json; dbs = json.load(sys.stdin); print(' '.join([db for db in dbs if not db.startswith('_')]))")

if [[ -z "$DATABASES" ]]; then
    warning "No user databases found"
    exit 0
fi

info "Found databases: $DATABASES"

# Check fragmentation for each database
for DB in $DATABASES; do
    info "Analyzing database: $DB"

    # Get database stats
    DB_STATS=$(curl -s -u "$ADMIN_USER:$ADMIN_PASS" "http://localhost:$COUCHDB_PORT/$DB")

    # Extract sizes using Python
    FRAGMENTATION=$(echo "$DB_STATS" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    file_size = data['sizes']['file']
    active = data['sizes']['active']

    # Calculate fragmentation percentage
    if file_size > 0:
        frag = ((file_size - active) / file_size) * 100
        print(f'{frag:.2f}')
    else:
        print('0.00')
except Exception as e:
    print('ERROR', file=sys.stderr)
    print('0.00')
")

    FILE_SIZE=$(echo "$DB_STATS" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    size_mb = data['sizes']['file'] / (1024 * 1024)
    print(f'{size_mb:.2f}')
except:
    print('0.00')
")

    DOC_COUNT=$(echo "$DB_STATS" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data['doc_count'])
except:
    print('0')
")

    info "  Size: ${FILE_SIZE} MB | Documents: ${DOC_COUNT} | Fragmentation: ${FRAGMENTATION}%"

    # Warning thresholds
    if (( $(echo "$FRAGMENTATION > 30" | bc -l) )); then
        warning "  HIGH FRAGMENTATION ($FRAGMENTATION%) - Consider running compaction"
        info "  To compact manually: curl -X POST -u admin:PASSWORD http://localhost:$COUCHDB_PORT/$DB/_compact"
    elif (( $(echo "$FRAGMENTATION > 20" | bc -l) )); then
        warning "  Moderate fragmentation ($FRAGMENTATION%) - Automatic compaction should trigger soon"
    else
        info "  ✓ Fragmentation is healthy ($FRAGMENTATION%)"
    fi
done

# Check disk space
info "Checking disk space..."
DISK_USAGE=$(df -h "$NOTES_DIR/data" | tail -1 | awk '{print $5}' | sed 's/%//')
DISK_AVAIL=$(df -h "$NOTES_DIR/data" | tail -1 | awk '{print $4}')

info "Disk usage: ${DISK_USAGE}% (${DISK_AVAIL} available)"

if (( DISK_USAGE > 90 )); then
    error "CRITICAL: Disk usage is very high (${DISK_USAGE}%)"
elif (( DISK_USAGE > 80 )); then
    warning "Disk usage is high (${DISK_USAGE}%)"
else
    info "✓ Disk usage is healthy (${DISK_USAGE}%)"
fi

# Check compaction daemon status
info "Checking compaction daemon configuration..."
COMPACTION_CONFIG=$(curl -s -u "$ADMIN_USER:$ADMIN_PASS" "http://localhost:$COUCHDB_PORT/_node/_local/_config/compaction_daemon")

if echo "$COMPACTION_CONFIG" | grep -q "check_interval"; then
    info "✓ Compaction daemon is configured"
else
    warning "Compaction daemon is not configured - database may grow indefinitely"
fi

# Check for running compactions
info "Checking active compactions..."
ACTIVE_TASKS=$(curl -s -u "$ADMIN_USER:$ADMIN_PASS" "http://localhost:$COUCHDB_PORT/_active_tasks")

if echo "$ACTIVE_TASKS" | grep -q '"type":"database_compaction"'; then
    COMPACTING_DB=$(echo "$ACTIVE_TASKS" | python3 -c "
import sys, json
tasks = json.load(sys.stdin)
for task in tasks:
    if task.get('type') == 'database_compaction':
        print(task.get('database', 'unknown'))
")
    info "Compaction in progress for database: $COMPACTING_DB"
else
    info "No active compactions"
fi

# Check memory usage (Docker stats)
info "Checking Docker container resource usage..."
CONTAINER_NAME=$(grep "^COUCHDB_CONTAINER_NAME=" "$ENV_FILE" | cut -d'=' -f2 || echo "notes-couchdb")

if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    STATS=$(docker stats "$CONTAINER_NAME" --no-stream --format "table {{.CPUPerc}}\t{{.MemUsage}}")
    info "Container stats ($CONTAINER_NAME):"
    echo "$STATS" | tee -a "$LOG_FILE"
else
    warning "Container $CONTAINER_NAME is not running"
fi

# Summary
info "Health check completed successfully"
echo "========================================" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
