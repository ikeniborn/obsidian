# CouchDB Backup Fix + nginx 500 Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix CouchDB backup credential bug (empty S3 backups), fix nginx `Connection: upgrade` header causing HTTP 500 in Obsidian LiveSync, and apply both fixes to the production server `ikenibornsync`.

**Architecture:** Two independent code fixes in the repo (`scripts/couchdb-backup.sh` and `templates/couchdb.conf.template`), then SSH to `ikenibornsync` to apply changes to `/opt/notes/` (deployment dir) and reload nginx.

**Tech Stack:** Bash, nginx, CouchDB 3.x, Docker, SSH (`ikenibornsync`)

---

## File Map

| File | Change |
|------|--------|
| `scripts/couchdb-backup.sh` | Lines 64–65: interpolate `${COUCHDB_USER}:${COUCHDB_PASSWORD}` into URL; add pre-flight auth check after |
| `templates/couchdb.conf.template` | Add `map` directive; replace `Connection "upgrade"` with `$connection_upgrade` |

Server deployment dir: `/opt/notes/` mirrors repo structure (`/opt/notes/scripts/`, `/opt/notes/templates/`).

---

## Task 1: Fix backup credential interpolation

**Files:**
- Modify: `scripts/couchdb-backup.sh:64-65`

Lines 62–65 currently read:
```bash
COUCHDB_USER="${COUCHDB_USER:-admin}"
COUCHDB_PASSWORD="${COUCHDB_PASSWORD:?ERROR: COUCHDB_PASSWORD not set in .env}"
COUCHDB_URL="http://[CREDENTIALS]@localhost:5984"        # bug: literal string
COUCHDB_HOST_URL="http://[CREDENTIALS]@localhost:5984"   # bug: literal string
```

- [ ] **Step 1: Replace lines 64–65 with correct variable interpolation**

In `scripts/couchdb-backup.sh`, replace the two broken URL lines:

Old (lines 64–65):
```bash
COUCHDB_URL="http://[CREDENTIALS]@localhost:5984"
COUCHDB_HOST_URL="http://[CREDENTIALS]@localhost:5984"
```

New:
```bash
COUCHDB_URL="http://${COUCHDB_USER}:${COUCHDB_PASSWORD}@localhost:5984"
COUCHDB_HOST_URL="http://${COUCHDB_USER}:${COUCHDB_PASSWORD}@localhost:5984"
```

- [ ] **Step 2: Add pre-flight auth check after line 65**

After the two URL lines, insert:
```bash
# Verify credentials before attempting backup
if ! curl -sf "${COUCHDB_HOST_URL}/_up" >/dev/null 2>&1; then
    error_exit "CouchDB auth check failed — verify COUCHDB_USER/COUCHDB_PASSWORD in .env and CouchDB is reachable at localhost:5984"
fi
```

- [ ] **Step 3: Verify the fix**

```bash
sed -n '62,72p' scripts/couchdb-backup.sh
```

Expected output (line numbers approx):
```
COUCHDB_USER="${COUCHDB_USER:-admin}"
COUCHDB_PASSWORD="${COUCHDB_PASSWORD:?ERROR: COUCHDB_PASSWORD not set in .env}"
COUCHDB_URL="http://[CREDENTIALS]@localhost:5984"
COUCHDB_HOST_URL="http://[CREDENTIALS]@localhost:5984"
# Verify credentials before attempting backup
if ! curl -sf "${COUCHDB_HOST_URL}/_up" >/dev/null 2>&1; then
    error_exit "CouchDB auth check failed — verify COUCHDB_USER/COUCHDB_PASSWORD in .env and CouchDB is reachable at localhost:5984"
fi
```

- [ ] **Step 4: Commit**

```bash
git add scripts/couchdb-backup.sh
git commit -m "fix(backup): interpolate credentials into CouchDB URL; add pre-flight auth check"
```

---

## Task 2: Fix nginx Connection header (prevents HTTP 500)

**Files:**
- Modify: `templates/couchdb.conf.template`

`couchdb.conf.template` currently hardcodes `Connection "upgrade"` for all requests. For non-WebSocket requests (most LiveSync HTTP calls), `$http_upgrade` is empty — nginx sends `Upgrade: ` (empty) + `Connection: upgrade`, which causes CouchDB/cowboy to return HTTP 500.

Fix: `map` variable returns `keep-alive` for regular HTTP, `upgrade` only for actual WebSocket.

- [ ] **Step 1: Add map directive after upstream block**

In `templates/couchdb.conf.template`, insert the `map` block between the `upstream` block and the first `server {`. The file currently starts:

```nginx
upstream couchdb_backend {
    server ${COUCHDB_UPSTREAM}:5984 max_fails=0;
    keepalive 32;
}

# HTTP - redirect to HTTPS
server {
```

Change to:
```nginx
upstream couchdb_backend {
    server ${COUCHDB_UPSTREAM}:5984 max_fails=0;
    keepalive 32;
}

map $http_upgrade $connection_upgrade {
    default   keep-alive;
    websocket upgrade;
}

# HTTP - redirect to HTTPS
server {
```

- [ ] **Step 2: Replace hardcoded Connection header in location block**

In the `location ${COUCHDB_LOCATION}` block, find:
```nginx
        proxy_set_header Connection "upgrade";
```

Replace with:
```nginx
        proxy_set_header Connection $connection_upgrade;
```

The full location block should now read:
```nginx
    location ${COUCHDB_LOCATION} {
        # Strip location prefix before proxying to backend
        rewrite ^${COUCHDB_LOCATION}(.*)$ /$1 break;

        proxy_pass http://couchdb_backend;
        proxy_redirect off;
        proxy_buffering off;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;

        client_max_body_size 50M;
    }
```

- [ ] **Step 3: Verify template**

```bash
grep -n "map\|connection_upgrade\|Connection" templates/couchdb.conf.template
```

Expected:
```
6:map $http_upgrade $connection_upgrade {
7:    default   keep-alive;
8:    websocket upgrade;
9:}
55:        proxy_set_header Connection $connection_upgrade;
```

- [ ] **Step 4: Commit**

```bash
git add templates/couchdb.conf.template
git commit -m "fix(nginx): use map variable for Connection header — prevent 500 on non-WebSocket requests"
```

---

## Task 3: Apply fixes to production server

**Prerequisites:** Tasks 1 and 2 committed.

- [ ] **Step 1: Push to remote**

```bash
git push origin dev
```

- [ ] **Step 2: SSH to server, pull, copy fixed files to /opt/notes/**

```bash
ssh ikenibornsync
```

On server:
```bash
# Pull updated files (if repo is on server)
cd /opt/notes && git pull origin dev 2>/dev/null

# OR copy directly from where repo lives on server:
# If repo is not present, the scp in Step 3 covers it
```

- [ ] **Step 3: If repo not present on server — copy from local machine**

Run this from your LOCAL machine (not inside ssh):
```bash
scp scripts/couchdb-backup.sh ikenibornsync:/opt/notes/scripts/couchdb-backup.sh
scp templates/couchdb.conf.template ikenibornsync:/opt/notes/templates/couchdb.conf.template
```

- [ ] **Step 4: On server — verify backup script has real credentials**

```bash
grep -n "COUCHDB_URL\|COUCHDB_HOST_URL" /opt/notes/scripts/couchdb-backup.sh | head -4
```

Expected: lines show `${COUCHDB_USER}:${COUCHDB_PASSWORD}`, not `[CREDENTIALS]`.

- [ ] **Step 5: On server — regenerate and apply nginx config**

```bash
source /opt/notes/.env
bash /opt/notes/scripts/nginx-setup.sh
```

If nginx-setup.sh is not available or fails, apply manually:
```bash
source /opt/notes/.env

# Determine backend type from .env
echo "SYNC_BACKEND=${SYNC_BACKEND:-couchdb}"

# For CouchDB-only backend:
envsubst '$COUCHDB_UPSTREAM,$COUCHDB_LOCATION,$NOTES_DOMAIN' \
  < /opt/notes/templates/couchdb.conf.template \
  > /tmp/notes-nginx-new.conf

# Find active nginx config location
docker inspect notes-nginx --format \
  '{{range .Mounts}}{{.Source}} -> {{.Destination}}{{"\n"}}{{end}}' 2>/dev/null \
  | grep "conf.d\|nginx.conf"

# Copy to active location (adjust path from inspect output):
cp /tmp/notes-nginx-new.conf /REPLACE_WITH_ACTUAL_PATH/notes.conf

# Test and reload
docker exec notes-nginx nginx -t
docker exec notes-nginx nginx -s reload
```

- [ ] **Step 6: On server — verify active nginx config has the map**

```bash
# Find active notes nginx conf
find /etc/nginx /opt/notes /var -name "*.conf" 2>/dev/null \
  | xargs grep -l "couchdb_backend" 2>/dev/null

# Check it has the fix (replace path with result above)
grep -n "map\|connection_upgrade\|Connection" /PATH/TO/ACTIVE/notes.conf
```

Expected: `map $http_upgrade $connection_upgrade` and `proxy_set_header Connection $connection_upgrade`.

---

## Task 4: Verify useRequestAPI=true chain

Run on server (`ssh ikenibornsync`).

- [ ] **Step 1: Load env**

```bash
source /opt/notes/.env
```

- [ ] **Step 2: Test direct CouchDB (bypass nginx)**

```bash
echo "=== Direct CouchDB ==="
curl -sv "http://${COUCHDB_USER}:${COUCHDB_PASSWORD}@localhost:5984/_up?useRequestAPI=true" 2>&1 \
  | grep -E "< HTTP|error"
```

Expected: `< HTTP/1.1 200 OK`

- [ ] **Step 3: Test full nginx chain with Obsidian origin**

```bash
echo "=== nginx -> CouchDB ==="
curl -sv "https://${NOTES_DOMAIN}${COUCHDB_LOCATION}/_up?useRequestAPI=true" \
  -H "Origin: app://obsidian.md" \
  -u "${COUCHDB_USER}:${COUCHDB_PASSWORD}" 2>&1 \
  | grep -E "< HTTP|< Access-Control|error"
```

Expected: `< HTTP/1.1 200 OK` and `< Access-Control-Allow-Origin: app://obsidian.md`

- [ ] **Step 4: Test session endpoint (simulates LiveSync auth with useRequestAPI)**

```bash
curl -sv -X POST \
  "https://${NOTES_DOMAIN}${COUCHDB_LOCATION}/_session?useRequestAPI=true" \
  -H "Origin: app://obsidian.md" \
  -H "Content-Type: application/json" \
  -d "{\"name\":\"${COUCHDB_USER}\",\"password\":\"${COUCHDB_PASSWORD}\"}" 2>&1 \
  | grep -E "< HTTP|error"
```

Expected: `< HTTP/1.1 200 OK`

If any step returns 500 after nginx reload:
```bash
docker exec notes-nginx tail -20 /var/log/nginx/error.log
```

---

## Task 5: Verify backup produces real data

Run on server (`ssh ikenibornsync`).

- [ ] **Step 1: Run backup manually**

```bash
bash /opt/notes/scripts/couchdb-backup.sh 2>&1 | tail -20
```

Expected: output shows database names, ends with `BACKUP PROCESS COMPLETED SUCCESSFULLY`. No `unauthorized` in output.

- [ ] **Step 2: Check backup file is non-trivially sized**

```bash
ls -lh /opt/notes/backups/couchdb-*.tar.gz | tail -3
```

Expected: file size significantly > 1KB (401 error JSON archives are ~200 bytes).

- [ ] **Step 3: Confirm content is real data**

```bash
LATEST=$(ls -t /opt/notes/backups/couchdb-*.tar.gz | head -1)
tar -tzf "${LATEST}"
```

Expected: lists JSON files named after your databases (e.g., `couchdb/obsidian.json`).

```bash
tar -xOzf "${LATEST}" --wildcards "*/obsidian.json" 2>/dev/null | python3 -c "
import sys, json
data = json.load(sys.stdin)
print('total_rows:', data.get('total_rows', 'N/A'))
print('first_key:', data['rows'][0]['id'] if data.get('rows') else 'empty')
"
```

Expected: `total_rows: N` (some positive number), `first_key: <document id>`.

- [ ] **Step 4: Check S3 upload in logs**

```bash
grep "Upload successful\|S3 upload failed\|auth check failed" /opt/notes/logs/backup.log | tail -5
```

Expected: `Upload successful: s3://...`

---

## Task 6: Check nginx logs for remaining 500s

Run on server after nginx reload.

- [ ] **Step 1: Check access log for 500s**

```bash
docker exec notes-nginx grep " 500 " /var/log/nginx/access.log 2>/dev/null \
  | tail -20 \
  || sudo grep " 500 " /var/log/nginx/access.log 2>/dev/null | tail -20 \
  || echo "No 500s in access log"
```

If 500s present: check timestamps — are they before or after the nginx reload time?

- [ ] **Step 2: If 500s persist after reload — identify endpoint**

```bash
docker exec notes-nginx grep " 500 " /var/log/nginx/access.log 2>/dev/null \
  | awk '{print $7}' | sort | uniq -c | sort -rn | head -10
```

This shows which URL paths are failing. Report output — further fix depends on specific endpoint.

- [ ] **Step 3: Check CouchDB logs**

```bash
docker logs notes-couchdb --tail 50 2>&1 | grep -iE "error|500|exception" | tail -20
```

---

## Verification Checklist

- [ ] `grep "COUCHDB_URL" /opt/notes/scripts/couchdb-backup.sh` → `${COUCHDB_USER}:${COUCHDB_PASSWORD}`, not `[CREDENTIALS]`
- [ ] Active nginx conf: `grep "Connection" notes.conf` → `$connection_upgrade`, not `"upgrade"`
- [ ] Direct CouchDB curl `?useRequestAPI=true` → HTTP 200
- [ ] nginx chain curl `?useRequestAPI=true` + Origin header → HTTP 200 + CORS header
- [ ] Manual backup run → no `unauthorized`, file > 1KB, S3 upload successful
- [ ] No new 500s in nginx access log after reload
