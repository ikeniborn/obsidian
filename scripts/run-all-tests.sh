#!/bin/bash
# Комплексное тестирование Obsidian Sync Server

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_RESULTS="/tmp/obsidian-sync-test-results.txt"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { echo -e "${GREEN}✓ PASS${NC}: $*" | tee -a "$TEST_RESULTS"; }
fail() { echo -e "${RED}✗ FAIL${NC}: $*" | tee -a "$TEST_RESULTS"; }
info() { echo -e "${YELLOW}ℹ INFO${NC}: $*"; }

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

run_test() {
    local test_name="$1"
    local test_command="$2"

    ((TOTAL_TESTS++))
    info "Running: $test_name"

    if eval "$test_command"; then
        pass "$test_name"
        ((PASSED_TESTS++))
    else
        fail "$test_name"
        ((FAILED_TESTS++))
    fi
}

info "Starting comprehensive tests..."
echo "" > "$TEST_RESULTS"

# === SECURITY TESTS ===
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "SECURITY TESTS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# UFW status
run_test "UFW is enabled" "sudo ufw status | grep -q 'Status: active'"

# SSH port allowed
run_test "SSH port 22 is allowed" "sudo ufw status | grep -q '22/tcp.*ALLOW'"

# HTTPS port allowed
run_test "HTTPS port 443 is allowed" "sudo ufw status | grep -q '443/tcp.*ALLOW'"

# Port 80 closed
run_test "HTTP port 80 is closed" "! sudo ufw status | grep -q '^80/tcp.*ALLOW'"

# === SSL TESTS ===
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "SSL/TLS TESTS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

source /opt/notes/.env

# SSL certificate exists
run_test "SSL certificate exists" "test -f /etc/letsencrypt/live/${NOTES_DOMAIN}/fullchain.pem"

# SSL certificate valid
run_test "SSL certificate is valid" "openssl x509 -in /etc/letsencrypt/live/${NOTES_DOMAIN}/fullchain.pem -noout -checkend 86400"

# Certbot renewal hooks exist
run_test "Certbot pre-hook exists" "test -x /etc/letsencrypt/renewal-hooks/pre/ufw-open-80.sh"
run_test "Certbot post-hook exists" "test -x /etc/letsencrypt/renewal-hooks/post/ufw-close-80.sh"

# === NGINX TESTS ===
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "NGINX TESTS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Nginx running
run_test "Nginx is running" "docker ps | grep -q nginx || systemctl is-active nginx"

# Nginx config valid
run_test "Nginx config is valid" "docker exec -it \$(docker ps --format '{{.Names}}' | grep nginx | head -1) nginx -t 2>&1 | grep -q 'successful' || nginx -t 2>&1 | grep -q 'successful'"

# HTTP redirect test
run_test "HTTP redirects to HTTPS" "curl -sI http://${NOTES_DOMAIN} 2>/dev/null | grep -q 'HTTP.*30[12]'"

# HTTPS accessible
run_test "HTTPS is accessible" "curl -sk https://${NOTES_DOMAIN}/_up 2>/dev/null | grep -q 'ok'"

# === COUCHDB TESTS ===
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "COUCHDB TESTS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# CouchDB container running (load name from .env)
source /opt/notes/.env 2>/dev/null || true
COUCHDB_CONTAINER="${COUCHDB_CONTAINER_NAME:-notes-couchdb}"
run_test "CouchDB container is running" "docker ps | grep -q ${COUCHDB_CONTAINER}"

# CouchDB health check
run_test "CouchDB is healthy" "curl -s http://localhost:5984/_up | grep -q 'ok'"

# CouchDB port bound to localhost only
run_test "CouchDB port 5984 bound to 127.0.0.1" "netstat -tuln | grep 5984 | grep -q '127.0.0.1:5984'"

# === BACKUP TESTS ===
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "BACKUP TESTS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Backup script exists
run_test "Backup script exists" "test -x /opt/notes/scripts/couchdb-backup.sh"

# Cron job exists
run_test "Backup cron job exists" "crontab -l | grep -q couchdb-backup"

# S3 upload script exists
run_test "S3 upload script exists" "test -x /opt/notes/scripts/s3_upload.py"

# boto3 installed
run_test "boto3 is installed" "python3 -c 'import boto3' 2>/dev/null"

# === NETWORK TESTS ===
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "NETWORK TESTS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

info "Running network modes tests..."
if bash "$SCRIPT_DIR/test-network-modes.sh"; then
    pass "Network modes tests"
    ((PASSED_TESTS++))
else
    fail "Network modes tests"
    ((FAILED_TESTS++))
fi
((TOTAL_TESTS++))

# === SUMMARY ===
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "TEST SUMMARY"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Total:  $TOTAL_TESTS"
echo "Passed: $PASSED_TESTS"
echo "Failed: $FAILED_TESTS"

if [[ $FAILED_TESTS -eq 0 ]]; then
    echo -e "${GREEN}✓ ALL TESTS PASSED${NC}"
    exit 0
else
    echo -e "${RED}✗ SOME TESTS FAILED${NC}"
    echo "See detailed results: $TEST_RESULTS"
    exit 1
fi
