# Backup System

The backup system protects sync data independent of the chosen backend. CouchDB backups stream every database directly to S3 (no local archive); ServerPeer uses a legacy local-tar.gz design. A shared `s3_upload.py` (boto3) handles all object-storage transfers, and systemd timers schedule runs.

## CouchDB Backup

Primary backup path. `scripts/couchdb-backup.sh` enumerates all user databases via the CouchDB API and streams each one — `curl | gzip | s3_upload.py --stdin` — straight to S3 under a dated "set" prefix. Nothing is staged on local disk, so peak disk stays ~0 even for multi-GB databases.

`scripts/couchdb-backup.sh` (512 lines) loads `/opt/notes/.env` (falling back to `/opt/budget/.env` for legacy installs), then:

- **Pre-flight checks**: validates the container `${COUCHDB_CONTAINER_NAME:-notes-couchdb}` exists, runs an auth check against `/_up`, requires `python3`, and logs disk space (warn-only — streaming needs no local space).
- **Per-DB streaming layout**: each DB becomes its own object, e.g. `couchdb-backups/couchdb-20260616/<db>.json.gz`. The set prefix is `${S3_PREFIX}${BACKUP_SET}/` where `BACKUP_SET="couchdb-$(date -u +%Y%m%d)"`. System databases (names starting `_`) are excluded.
- **Source**: `/<db>/_all_docs?include_docs=true`, gzipped at level 6, piped to `s3_upload.py --stdin <key>` (see [[backup-system#S3 Upload]]).
- **API access**: prefers direct host access (`http://...@localhost:5984`); falls back to `docker exec <container> curl` when the host port is unreachable.
- **Per-DB timeout**: `calculate_timeout()` reads `sizes.active` and computes `BASE_TIMEOUT(60s) + active_MB * 2`, capped at `MAX_TIMEOUT(7200s)`. It also reports fragmentation (warns >30%).
- **Container health**: re-checked every `BACKUP_BATCH_SIZE(10)` databases; waits/retries if the container restarts mid-run.
- **Config object**: global config from `/_node/_local/_config` is streamed as `_config.json.gz`.
- **Failure handling**: a failed DB stream deletes its partial S3 object (`--delete`) and continues; the run errors out only if **zero** databases uploaded. `pipefail` + `PIPESTATUS` identify which pipeline stage (curl/gzip/upload) failed.

S3 is mandatory for this path — there is no local-archive fallback by design (the dataset is too large to stage). Per-DB layout supports restore by downloading a `<db>.json.gz`, gunzipping, and POSTing to `_bulk_docs`. Backend config it reads lives in [[architecture#Configuration & Secrets]]; the database it backs up is described in [[couchdb-backend#Container Definition]].

## ServerPeer Backup

**LEGACY / FROZEN.** `scripts/serverpeer-backup.sh` (126 lines) archives the headless vault directory to a local `tar.gz`, verifies it with `gzip -t`, then uploads via the shared `s3_upload.py`. It has **no CouchDB dependency** — it works purely on file-based storage.

This script still uses the old "stage a local tar.gz, then upload" design and was **not** migrated to the per-DB direct-streaming model used by [[backup-system#CouchDB Backup]]. Because it writes the full archive to local disk first, it can fill the disk on a large vault. ServerPeer is a frozen project and production runs CouchDB; see [[serverpeer-backend#Legacy Status]]. Do not extend it — if ServerPeer is revived, port it to streaming first.

Behavior:

- Archives `${SERVERPEER_VAULT_DIR:-/opt/notes/serverpeer-vault}` as `serverpeer-$(date -u +%Y%m%d).tar.gz` in `${NOTES_BACKUP_DIR:-/opt/notes/backups}`.
- Integrity check via `gzip -t`; aborts on corruption.
- Uploads with `s3_upload.py <file> <prefix>` (positional file path, not `--stdin`).
- Local retention via `find ... -mtime +${RETENTION_DAYS}` plus an explicit delete of the `RETENTION_DAYS`-ago dated file (`RETENTION_DAYS=7`, hard-coded here, not env-configurable).

## S3 Upload

`scripts/s3_upload.py` (311 lines) is the shared, backend-agnostic boto3 client used by both backup scripts. It works with any S3-compatible endpoint — AWS S3, Yandex Object Storage (default `https://storage.yandexcloud.net`, region `ru-central1`), or MinIO — reading credentials from `/opt/notes/.env`.

Subcommands (dispatched in `__main__`):

- **`<file> [prefix]`** — `upload_to_s3()`: standard `upload_file` with `StorageClass=STANDARD`. Key = `prefix + filename`. Used by ServerPeer.
- **`--stdin <s3_key>`** — `upload_stream_to_s3()`: streams `sys.stdin.buffer` via `upload_fileobj` (automatic multipart for non-seekable streams). Used by the CouchDB per-DB streaming path so no local file is needed.
- **`--delete <s3_key>`** — `delete_object()`: removes a single object; used to clean up a partial object left by a failed stream.
- **`--cleanup <prefix> [--days N]`** — `run_cleanup()` → `cleanup_old_objects()`: paginates `list_objects_v2`, deletes objects whose `LastModified` is older than `now - N days`, batched in groups of 1000 via `delete_objects`. Default `N=7`.
- **`--test`** — `test_s3_connection()`: `head_bucket` reachability check.

Credentials: `S3_ACCESS_KEY_ID`, `S3_SECRET_ACCESS_KEY`, `S3_BUCKET_NAME`, optional `S3_ENDPOINT_URL`, `S3_REGION`. Configured during setup — see [[setup#S3 Backup Configuration]].

## Retention Policy

CouchDB retention is **count-based**, enforced S3-side via `s3_upload.py --prune-sets`: it keeps the `BACKUP_KEEP_SETS` (default 2) most-recent dated set-folders and deletes older ones. This replaced age-based `--cleanup`, which let two overlapping sets coexist and overflow a size-capped bucket. ServerPeer retention is local-file `find -mtime`.

**Backend-aware S3 prefixes** (fallback chains):
- CouchDB: `COUCHDB_S3_BACKUP_PREFIX` → `S3_BACKUP_PREFIX` → `couchdb-backups/`
- ServerPeer: `SERVERPEER_S3_BACKUP_PREFIX` → `S3_BACKUP_PREFIX` → `serverpeer-backups/`

Separate prefixes keep dual-mode backups isolated in the same bucket.

**CouchDB cleanup safety**: the S3 prune runs **only when the current backup set is complete** (`FAILED_DBS == 0`). On an incomplete set the prune is skipped, so older good backups are never deleted while the new set is missing a database. For buckets too small to hold two full sets, `BACKUP_PRUNE_BEFORE=true` prunes old sets *before* upload (keeping the current set + `BACKUP_KEEP_SETS-1` historical) to free room — at the cost of briefly leaving no previous set. See [[troubleshooting#Database bloat / huge document count]] and the capacity caveat there.

**Local cleanup**: none — CouchDB backups stream straight to S3 (`curl | gzip | upload`), writing no local archive, so there is nothing to prune on disk. ServerPeer (legacy) still prunes its own dated `tar.gz` files.

## Systemd Timers

Backups run on a schedule. The repo ships static unit templates `systemd/couchdb-backup.service` and `systemd/couchdb-backup.timer`; `setup.sh` installs backend-aware timers dynamically and also installs a standalone cleanup timer. The runner captures script stdout into `/opt/notes/logs/backup.log`.

`systemd/couchdb-backup.service` is a `Type=oneshot` unit (`After=docker.service`, `User=root`, `WorkingDirectory=/opt/notes`) that runs `couchdb-backup.sh`, appending both stdout and stderr to `/opt/notes/logs/backup.log`. `systemd/couchdb-backup.timer` fires `OnCalendar=*-*-* 03:00:00` with `Persistent=true` (catches up missed runs).

Backend-aware scheduling installed by `setup.sh` (see [[setup#Backup Scheduling]]):
- CouchDB only → couchdb-backup timer at 03:00.
- ServerPeer only → serverpeer-backup timer.
- Both → CouchDB at 03:00, ServerPeer at 03:05.

Recent fixes:
- **Duplicate-timer race**: an earlier bug installed duplicate systemd timers that could run backups concurrently; this was fixed to avoid overlapping runs.
- **Standalone cleanup timer**: `setup.sh` now installs `notes-cleanup.service`/`.timer` (daily 03:30, after the backup), or a `30 3 * * *` cron line, to run `cleanup-system.sh` as an OS-level disk safety net even if a backup run dies early. Previously `cleanup-system.sh` ran only inline at the tail of `couchdb-backup.sh`.
- **De-duplicated logs**: `log()` and inline command logging now write file-only, because the systemd `StandardOutput=append` / cron `>>` runner already re-captures stdout into the same log; the S3 cleanup/delete `if` checks the Python exit code directly rather than `tee`.

## Resource Limits

The CouchDB backup is deliberately low-impact so it can run on a production server without degrading sync. It runs the upload stage under `nice` and `ionice`, gzips at a moderate level, and paces itself between databases.

Tunables defined at the top of `couchdb-backup.sh`:
- `NICE_LEVEL=19` (lowest CPU priority) and `IONICE_CLASS=3` (idle I/O) wrap the `python3 s3_upload.py --stdin` upload stage.
- `COMPRESSION_LEVEL=6` — gzip level for each DB stream (balance of CPU vs. size).
- `BACKUP_BATCH_SIZE=10` — DBs between container-health re-checks; a `sleep 0.5` precedes each DB.
- `CPU_LIMIT=0.5`, `MEMORY_LIMIT=512m`, `UPLOAD_BANDWIDTH=1MB` — declared limits for the backup process.
- Timeouts scale with DB size: `BASE_TIMEOUT=60`, `TIMEOUT_PER_MB=2`, `MAX_TIMEOUT=7200`.

Because data streams straight to S3, the script no longer hard-aborts on low local disk — it only warns. This matches the limited-disk constraint of the production host (verified: a 16GB DB streamed with disk steady at ~15GB free).

## System Cleanup

`scripts/cleanup-system.sh` is an OS-level disk reclaimer that runs **independently of the backup**, so a disk-full condition can never deadlock cleanup. It is scheduled separately by its own timer (see [[backup-system#Systemd Timers]]) rather than running inline at the tail of the backup.

`scripts/cleanup-system.sh` (68 lines, `set -uo pipefail`) sources `/opt/notes/.env` and logs file-only to `${NOTES_LOG_DIR:-/opt/notes/logs}/backup.log` (the systemd/cron runner already captures stdout, so it does not tee). It records free disk before and after via `df -k /`. Steps:

- **systemd journal** — `journalctl --vacuum-size=${CLEANUP_JOURNAL_MAX_SIZE:-200M}` caps journal size.
- **apt cache** — `apt-get clean` (warn-only on failure).
- **system logs** — `truncate -s 0` on `/var/log/btmp`, `/var/log/wtmp`, `/var/log/fail2ban.log` (clears records, not data).
- **project nginx logs** — truncates `*.log` under `${NOTES_LOG_DIR}/nginx`, which are volume-mounted and monitored by fail2ban (see [[firewall-security#fail2ban Integration]]).

**Why decoupled:** `couchdb-backup.sh` aborts early when the disk is critically full, which previously left no path to reclaim space — an ENOSPC condition could cascade into CouchDB returning HTTP 500 (see [[couchdb-backend#Container Definition]]). Running cleanup on its own `notes-cleanup.timer` (daily 03:30, after the backup) guarantees the disk safety net fires even if a backup run dies early. Run manually with `sudo bash /opt/notes/scripts/cleanup-system.sh`.
