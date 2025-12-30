#!/bin/bash
# Validation script for serverpeer patch file
# This script tests that the updated patch applies correctly to current upstream

set -e

echo "=== ServerPeer Patch Validation ==="
echo

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Step 1: Clone upstream
echo "Step 1: Cloning upstream livesync-serverpeer..."
rm -rf /tmp/test-serverpeer-validation
git clone --depth=1 https://github.com/vrtmrz/livesync-serverpeer.git /tmp/test-serverpeer-validation
cd /tmp/test-serverpeer-validation

# Step 2: Show current code
echo
echo "Step 2: Current upstream code (BEFORE patch):"
echo "---"
head -15 src/ServerPeer.ts | tail -10
echo "---"

# Step 3: Apply patch
echo
echo "Step 3: Applying patch..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
patch -p1 < "$SCRIPT_DIR/fix-p2p-enabled.patch"

# Step 4: Show patched code
echo
echo "Step 4: Patched code (AFTER patch):"
echo "---"
head -15 src/ServerPeer.ts | tail -11
echo "---"

# Step 5: Verify critical fix
echo
echo "Step 5: Verifying P2P fix..."
if grep -q "// Set P2P_Enabled BEFORE saving to globalVariables" src/ServerPeer.ts; then
    echo -e "${GREEN}✓ Comment added${NC}"
else
    echo -e "${RED}✗ Comment missing${NC}"
    exit 1
fi

# Check that globalVariables.set comes AFTER P2P settings
LINE_P2P=$(grep -n "conf.P2P_Enabled = true" src/ServerPeer.ts | cut -d: -f1)
LINE_GLOBAL=$(grep -n "globalVariables.set" src/ServerPeer.ts | cut -d: -f1)

if [ "$LINE_GLOBAL" -gt "$LINE_P2P" ]; then
    echo -e "${GREEN}✓ globalVariables.set comes AFTER P2P settings (line $LINE_GLOBAL > line $LINE_P2P)${NC}"
else
    echo -e "${RED}✗ globalVariables.set comes BEFORE P2P settings (line $LINE_GLOBAL <= line $LINE_P2P)${NC}"
    exit 1
fi

echo
echo -e "${GREEN}=== Patch validation PASSED ===${NC}"
echo
echo "You can now rebuild Docker images:"
echo "  docker compose -f docker-compose.serverpeer.yml build --no-cache"
echo "  docker compose -f docker-compose.serverpeer-personal.yml build --no-cache"
