# Design: CouchDB useRequestAPI Verification + Backup Fix

**Date:** 2026-05-21  
**Status:** Approved

## Context

Two production issues in the Obsidian sync server:

1. **Broken backups**: S3 backups contain only `{"error":"unauthorized"}` responses instead of actual data.
2. **useRequestAPI=true verification**: Obsidian LiveSync on proxy-enabled workstations appends `?useRequestAPI=true` to CouchDB requests. Need to confirm the nginx→CouchDB chain handles this correctly.
3. **HTTP 500 in Obsidian**: Intermittent 500 errors during sync — root cause unknown, requires log-based diagnosis.

---

## Issue 1: Backup Credential Bug

### Root Cause

`scripts/couchdb-backup.sh` lines 64–65 contain literal placeholder text instead of variable interpolation:

```
COUCHDB_URL="http://[CREDENTIALS]@localhost:5984"      ← bug: literal string
COUCHDB_HOST_URL="http://[CREDENTIALS]@localhost:5984" ← bug: literal string
```

`COUCHDB_USER` and `COUCHDB_PASSWORD` are declared above (lines 62–63) but never used in the URL. All curl requests authenticate as `[CREDENTIALS]` → CouchDB returns 401 → error JSON written to backup files → uploaded to S3.

### Fix

Replace both lines:

```bash
COUCHDB_URL="http://${COUCHDB_USER}:${COUCHDB_PASSWORD}@localhost:5984"
COUCHDB_HOST_URL="http://${COUCHDB_USER}:${COUCHDB_PASSWORD}@localhost:5984"
```

Add pre-flight auth check immediately after URL variables are set:

```bash
if ! curl -sf "${COUCHDB_HOST_URL}/_up" >/dev/null 2>&1; then
    error_exit "CouchDB auth failed — check COUCHDB_USER/COUCHDB_PASSWORD in .env"
fi
```

**Fail-fast benefit**: Script exits with clear error instead of silently uploading corrupt data to S3.

---

## Issue 2: useRequestAPI=true Verification

### Static Analysis

Nginx config (`templates/couchdb.conf.template`):
- Rewrite: `rewrite ^${COUCHDB_LOCATION}(.*)$ /$1 break;` — regex matches URI path only; query string preserved automatically. `useRequestAPI=true` passes through unchanged.
- CouchDB receives unknown query parameter → ignored per CouchDB 3.x behavior.
- CORS (`local.ini`): `origins = app://obsidian.md,capacitor://localhost,http://localhost` — covers Obsidian desktop origin.

**Static conclusion**: configuration appears correct. Verification script confirms at runtime.

### Verification Script

Run on the server after sourcing env:

```bash
source /opt/notes/.env

# Step 1: Direct CouchDB (bypass nginx)
echo "=== Direct CouchDB ==="
curl -sv "http://${COUCHDB_USER}:${COUCHDB_PASSWORD}@localhost:5984/_up?useRequestAPI=true" 2>&1 \
  | grep -E "< HTTP|error"

# Step 2: Full chain through nginx (with Obsidian Origin header)
echo "=== nginx -> CouchDB ==="
curl -sv "https://${NOTES_DOMAIN}${COUCHDB_LOCATION}/_up?useRequestAPI=true" \
  -H "Origin: app://obsidian.md" \
  -u "${COUCHDB_USER}:${COUCHDB_PASSWORD}" 2>&1 \
  | grep -E "< HTTP|< Access-Control|error"
```

**Expected**: both return `HTTP/... 200`. If nginx leg fails and direct leg passes → nginx issue. If both fail → CouchDB config issue.

---

## Issue 3: HTTP 500 Diagnosis

### Diagnosis Commands

```bash
# nginx error log (docker)
docker exec notes-nginx tail -100 /var/log/nginx/error.log 2>/dev/null \
  || sudo tail -100 /var/log/nginx/error.log

# nginx access log — isolate 500 requests
docker exec notes-nginx grep " 500 " /var/log/nginx/access.log 2>/dev/null \
  || sudo grep " 500 " /var/log/nginx/access.log

# CouchDB errors
docker logs notes-couchdb --tail 100 2>&1 | grep -iE "error|500|fail|exception"
```

### Confirmed Error

Obsidian LiveSync worker log (2026-05-21):
```
Work-e303cab92c8b0cdb: The request may have failed. The reason sent by the server: 500: 500
```

Server returning actual HTTP 500, not a timeout or network drop.

### Probable Causes (by likelihood)

1. **`Connection: upgrade` on all requests** — nginx template hardcodes `Connection "upgrade"` for every request, not just WebSocket. When `$http_upgrade` is empty (regular HTTP), nginx sends `Upgrade: ` (empty) + `Connection: upgrade`. CouchDB/cowboy may return 500 on malformed upgrade headers.

   Fix: use a map variable so `Connection` is `keep-alive` for regular requests and `upgrade` only for actual WebSocket:
   ```nginx
   map $http_upgrade $connection_upgrade {
       default   keep-alive;
       websocket upgrade;
   }
   # in location block:
   proxy_set_header Connection $connection_upgrade;
   ```

2. **CouchDB 500 on endpoint with `?useRequestAPI=true`** — some endpoints may reject unknown params. Diagnosis: check if 500s correlate with specific paths in access log.
3. **nginx upstream connection reset** — `proxy_buffering off` + large payload. Check nginx error log for `upstream prematurely closed connection`.
4. **CORS rejection** — Origin not in whitelist → 500 on OPTIONS.

### Fix Decision Tree

- `Connection: upgrade` mismatch (most likely) → fix nginx template with `$connection_upgrade` map.
- 500 on specific endpoints with `?useRequestAPI=true` → strip unknown param in nginx.
- nginx upstream reset → increase `proxy_read_timeout`.
- 500 on OPTIONS → fix CORS origins in `local.ini`.

---

## Scope

In scope:
- Fix credential interpolation bug in `scripts/couchdb-backup.sh` (2 lines)
- Add pre-flight auth check to `scripts/couchdb-backup.sh`
- Fix `Connection: upgrade` header in nginx template (`couchdb.conf.template`, `unified.conf.template`) using map variable
- Verification commands for useRequestAPI=true chain
- Diagnosis commands for 500 errors; apply remaining fixes based on log findings

Out of scope:
- Backup format or S3 structure changes
- Backup script refactoring beyond the credential fix
