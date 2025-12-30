#!/bin/bash
set -e

echo "=== ServerPeer Deployment Test ==="

# Load config
source /opt/notes/.env

# Test 1: Container
echo "✓ Test 1: Container status"
docker ps | grep notes-serverpeer || exit 1

# Test 2: Health
echo "✓ Test 2: Health endpoint"
docker exec notes-serverpeer curl -sf http://localhost:3000/health || exit 1

# Test 3: Vault
echo "✓ Test 3: Vault directory"
[[ -d /opt/notes/serverpeer-vault ]] || exit 1

# Test 4: Backup
echo "✓ Test 4: Backup script"
bash /opt/notes/scripts/serverpeer-backup.sh || exit 1

# Test 5: S3 upload (if configured)
if [[ -n "$S3_ACCESS_KEY_ID" ]]; then
    echo "✓ Test 5: S3 connection"
    python3 /opt/notes/scripts/s3_upload.py --test || exit 1
fi

echo ""
echo "=== All Tests PASSED ==="
