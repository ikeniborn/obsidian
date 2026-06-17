# Troubleshooting

Operational playbook for the production Obsidian Sync (CouchDB) server. Each
section: symptom → root cause → diagnosis → fix. Commands assume the deploy
dir `/opt/notes` and CouchDB credentials in `/opt/notes/.env`.

Quick credential helper used below:

```bash
set -a; source /opt/notes/.env; set +a
AUTH="$COUCHDB_USER:$COUCHDB_PASSWORD"
H="http://localhost:5984"
```

---

## HTTP 500 — disk full / CouchDB cannot write

**Symptom:** Client/sync returns 500; CouchDB writes fail.

**Root cause:** The root filesystem is 100% full, so CouchDB cannot write
data or metadata. A frequent amplifier is an **orphaned compaction file**:
auto-compaction (smoosh) writes a temporary `*.couch.compact.data` up to the
size of the live data; if the disk fills mid-compaction the compaction dies
and leaves the partial file, and on the next cycle it tries again — a
**disk-full compaction loop**.

**Diagnosis:**
```bash
df -h /
sudo du -sh /opt/notes/* | sort -rh | head
sudo find /opt/notes/data -name "*.compact*" -exec ls -lah {} \;
curl -s -u "$AUTH" "$H/_active_tasks"   # [] means no compaction is actually running
```

**Fix:**
1. If `_active_tasks` is empty, the leftover `*.compact.data` / `*.compact.meta`
   are orphans — delete them to reclaim space immediately (safe, regenerated):
   ```bash
   sudo rm -fv /opt/notes/data/shards/*/<db>.*.couch.compact.*
   ```
2. Stop the loop by disabling auto-compaction (smoosh) until disk is healthy:
   ```bash
   B="$H/_node/_local/_config"
   curl -s -u "$AUTH" -X PUT "$B/smoosh/db_channels"   -d '""'
   curl -s -u "$AUTH" -X PUT "$B/smoosh/view_channels" -d '""'
   ```
3. Once free space is restored, re-enable it:
   ```bash
   curl -s -u "$AUTH" -X PUT "$B/smoosh/db_channels"   -d '"ratio_dbs,slack_dbs"'
   curl -s -u "$AUTH" -X PUT "$B/smoosh/view_channels" -d '"ratio_views,slack_views"'
   ```

> ⚠️ Never run a manual compaction while the disk is nearly full — the temp
> `.compact` file needs roughly the live size of the largest shard.

---

## HTTP 413 — Request Entity Too Large (nginx)

**Symptom:** Obsidian shows `Failed to fetch by API. 413` with an nginx HTML
error page (`<center>nginx/x.y.z</center>`). Usually on initial sync / rebuild.

**Root cause:** LiveSync sends large `_bulk_docs` batches that exceed a body-size
limit. There are **two layers**, and the 413 must be fixed at both — otherwise it
just moves from one to the other:
1. **nginx** `client_max_body_size` (template default was `50M`). nginx 413 →
   an HTML error page (`<center>nginx/x.y.z</center>`).
2. **CouchDB** `[chttpd] max_http_request_size` (`local.ini`, was `100MB`).
   CouchDB 413 → a tiny JSON body (~65 bytes,
   `the request entity is too large`). After raising nginx, the limiter moved
   here.

Tell them apart by the response: large HTML = nginx; ~65-byte JSON = CouchDB.

**Diagnosis:**
```bash
sudo docker exec notes-nginx grep -n client_max_body_size /etc/nginx/conf.d/notes.conf
curl -s -u "$AUTH" "$H/_node/_local/_config/chttpd/max_http_request_size"
# True status histogram (don't confuse the body_bytes column with the status!):
sudo docker exec notes-nginx sh -c 'tail -4000 /var/log/nginx/access.log \
  | grep -oE "HTTP/[12]\.[0-9]\" [0-9]{3}" | awk "{print \$2}" | sort | uniq -c | sort -rn'
```

**Fix:** raise BOTH to `1024M`/`1GB`.
- nginx (template default is already `1024M` — `templates/couchdb.conf.template`).
  On a deployed server: `sed -i 's/client_max_body_size .*/client_max_body_size 1024M;/'`
  `/opt/notes/nginx/notes.conf` then **restart** `notes-nginx` (bind-mounted single
  file → `sed -i` changes the inode, so a reload keeps the old content).
- CouchDB — `local.ini` `[chttpd] max_http_request_size = 1073741824`, and apply
  at runtime without a restart:
  ```bash
  curl -s -u "$AUTH" -X PUT \
    "$H/_node/_local/_config/chttpd/max_http_request_size" -d '"1073741824"'
  ```

> **Durable alternative:** raising CouchDB's request limit weakens DoS/memory
> protection on a small host. The better long-term fix is to **reduce the
> LiveSync client batch size** so `_bulk_docs` stays small — then both limits can
> be kept low. A 413 storm also drives a client retry loop (high load, nginx CPU);
> fixing the 413 stops it.

> A separate, per-document limit also exists: CouchDB `max_document_size`
> (`local.ini`, 50MB). A single file/attachment larger than that is rejected by
> CouchDB (JSON 413), independent of nginx. LiveSync chunks files, so normal
> notes never hit it; keep the LiveSync "Maximum file size" aligned.

---

## HTTP 502 — CouchDB OOM crash loop

**Symptom:** Intermittent 502 Bad Gateway. nginx error log shows
`connect() failed (111: Connection refused) ... upstream :5984`. CouchDB
container `RestartCount` keeps climbing.

**Root cause:** The CouchDB container memory limit was too low (`384M`). Under
heavy sync load the Erlang VM (`beam.smp`) exceeds the cgroup limit and the
kernel OOM-kills it; Docker restarts it; the client retries and kills it
again — a crash loop. On a low-RAM host with **no swap**, kills are hard.

**Diagnosis:**
```bash
sudo docker inspect notes-couchdb \
  --format 'RestartCount={{.RestartCount}} Memory={{.HostConfig.Memory}} MemorySwap={{.HostConfig.MemorySwap}}'
sudo dmesg | grep -iE 'out of memory|killed process|oom' | tail
free -h; swapon --show
sudo docker stats --no-stream notes-couchdb
```

**Fix (two parts):**
1. **Add a swap file** as an OOM cushion (host had none). `install.sh`
   now does this automatically on low-RAM hosts (`ensure_swap`). Manually:
   ```bash
   sudo fallocate -l 2G /swapfile && sudo chmod 600 /swapfile
   sudo mkswap /swapfile && sudo swapon /swapfile
   grep -q /swapfile /etc/fstab || echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
   ```
2. **Raise the container memory limit** to `512M` (now the default in
   `docker-compose.notes.yml`). For an already-deployed server:
   ```bash
   sudo sed -i 's/memory: 384M/memory: 512M/' /opt/notes/docker-compose.notes.yml
   sudo docker compose -f /opt/notes/docker-compose.notes.yml up -d   # recreates couchdb
   ```

After the fix, `RestartCount` stops climbing and CouchDB memory sits well below
the limit (it was thrashing at ~98% before, ~30% after).

---

## Database bloat / huge document count

**Symptom:** CouchDB databases grow to many GB with hundreds of thousands of
documents (e.g. work/family DBs at ~17G / ~178K docs each).

**Root cause:** LiveSync stores each content **chunk** as one CouchDB document.
Every edit produces new chunks; old chunks become **orphaned chunks** that are
not garbage-collected, accumulating over months. `active ≈ file` size means the
data is "live" from CouchDB's view, so **compaction reclaims little** — the
orphans are the bulk.

**Confirm it is genuinely orphan-heavy vs. real data:**
```bash
for db in work family; do
  curl -s -u "$AUTH" "$H/$db" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d.get("doc_count"),round(d["sizes"]["active"]/1e9,2),"GB active",round(d["sizes"]["file"]/1e9,2),"GB file")'
done
```

**Fix — clean reset (what was done in the incident):**
1. Verify an S3 backup exists and is valid (`gunzip -t` streamed from S3).
2. Drop and recreate the remote DBs:
   ```bash
   curl -s -u "$AUTH" -X DELETE "$H/work";   curl -s -u "$AUTH" -X PUT "$H/work"
   curl -s -u "$AUTH" -X DELETE "$H/family"; curl -s -u "$AUTH" -X PUT "$H/family"
   ```
   (If the disk is at 0 the DELETE may return `internal_server_error` while the
   shard files are still removed — once space is freed, re-issue DELETE to clear
   the metadata, then PUT to recreate.)
3. On the reference client (full local vault) run **Rebuild everything →
   Overwrite remote**. Other devices: **Fetch everything from remote**.

**Prevention (reduce future chunk/document growth):** see
[reducing CouchDB documents](#reducing-couchdb-document-count).

---

## Reducing CouchDB document count

LiveSync stores 1 chunk = 1 document. To keep the count down:

- **Enable Eden** ("Incubate Chunks in Document", `useEden`, Power-User pane).
  Keeps volatile chunks inside the note document until stable, avoiding a
  separate document per churned chunk. Defaults: `maxChunksInEden=10`,
  `maxTotalLengthInEden=1024`, `maxAgeInEden=10`. Best lever — keeps small
  chunks (fast incremental sync) **and** few documents.
- **Larger chunk size** ("Enhance chunk size", `customChunkSize`): fewer chunks
  per file. Trade-off: a small edit re-sends the whole chunk (more bandwidth /
  latency), weaker dedup. Not a data-loss risk. Don't crank to extremes.
- **Exclude attachments** (images/PDF) from sync or lower the LiveSync max file
  size — attachments are the biggest document multiplier.
- **Maintenance:** periodic `Perform cleanup` (drops non-latest revisions) and
  occasional `Rebuild everything` to shed orphans (the sanctioned GC; the
  author deprecated server-side "remove unused chunks" as unreliable).

Changing chunk/Eden settings is a "tweak" → run **Rebuild everything**, then
**Fetch everything** on other devices, or they hit a tweak mismatch.

---

## Backups (S3 streaming)

`scripts/couchdb-backup.sh` streams each DB straight to S3
(`curl _all_docs | gzip | s3_upload.py --stdin`) — no local temp file, so it
works even with very little free disk. S3 is required (no local-archive path).

```bash
sudo bash /opt/notes/scripts/couchdb-backup.sh
tail -f /opt/notes/logs/backup.log
```

**Verify a backup** (stream from S3 through gunzip, no local download):
list objects with boto3 (creds from `.env`) and decompress each with
`zlib.decompressobj(16+zlib.MAX_WBITS)` to confirm it is a complete gzip.

**Retention (fixed):** S3 retention is now **count-based** — `couchdb-backup.sh`
keeps the `BACKUP_KEEP_SETS` (default 2) most-recent dated set-folders via
`s3_upload.py --prune-sets`, pruned only after a complete run. (The old
age-based cleanup let two overlapping sets coexist; the leftover local
`couchdb-*.tar.gz` glob was dead code — streaming writes no local archive — and
has been removed.)

> **Capacity caveat (`BucketMaxSizeExceeded`):** a size-capped bucket must hold
> two full sets during the window when a new set is written before the old one
> is pruned. If one set is ~23G, the bucket needs ≥ ~50G. Options: raise the
> bucket size limit (recommended, keeps `BACKUP_KEEP_SETS=2` safe), or set
> `BACKUP_KEEP_SETS=1` + `BACKUP_PRUNE_BEFORE=true` to prune old sets *before*
> upload (fits a small bucket, but briefly leaves no previous set if the new
> upload fails).

---

## Capacity note

The production host (`ikenibornsync`) is **891MB RAM / 39G disk** — undersized
for a ~30G, ~300K-document sync workload. The fixes above stabilise it, but the
durable remedies are **reducing data** (Eden + excluding attachments + rebuild)
or **upgrading the VPS** (more RAM and disk).
