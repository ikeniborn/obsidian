# Backup

CouchDB backup streams each database directly to S3 — `curl _all_docs | gzip | s3_upload --stdin` — with NO local temp or archive. `scripts/couchdb-backup.sh` orchestrates it; S3 is mandatory.

Peak local disk during a backup is ~0 regardless of DB size: a 16GB database never touches the disk. This replaced an older "export to temp dir, then tar+gzip" design that needed ~`external`-size temp space and filled the disk (see [[backup#Backup#2026-06-16 ENOSPC Incident]]).

## S3 Layout

Each run writes a dated "set" folder with one object per database plus config:
```
couchdb-backups/couchdb-YYYYMMDD/<db>.json.gz
couchdb-backups/couchdb-YYYYMMDD/_config.json.gz
```
`BACKUP_SET="couchdb-$(date -u +%Y%m%d)"`, `S3_SET_PREFIX="${S3_PREFIX}${BACKUP_SET}/"`. Each `<db>.json.gz` is a gzipped `_all_docs?include_docs=true` response.

## Restore

Per-object, not a single tarball: download `<db>.json.gz` from the set prefix, `gunzip`, then re-insert the documents via `POST /{db}/_bulk_docs` (strip `_rev` or use `new_edits=false`). `_config.json.gz` holds the CouchDB config snapshot.

## Streaming Failure Handling

`stream_db_to_s3()` runs the pipe under `set -o pipefail`; `PIPE_RESULT=(${PIPESTATUS[@]})` pinpoints the failed stage (curl/timeout, gzip, upload).

On any non-zero stage the partial S3 object is deleted (`s3_upload.py --delete`) and the DB is counted in `FAILED_DBS`. `curl -fsS` exits non-zero on HTTP errors so an error body is never silently uploaded.

The run still completes if ≥1 DB uploaded (`UPLOADED_DBS>0`); zero uploads is a hard `error_exit`.

## Retention — only prunes a complete set

S3 prune (`s3_upload.py --cleanup <prefix> --days N`) runs ONLY when `FAILED_DBS==0`. An incomplete set must not trigger pruning — otherwise the previous good backup is deleted while the current set is missing a database, leaving no valid copy.

This exact loss happened on 2026-06-16: `RETENTION_DAYS=1` pruned the Jun-4/Jun-5 backups right after a run where `work` timed out, so no complete `work` backup remained (CouchDB data itself was intact). The `FAILED_DBS==0` guard was added to prevent recurrence. `RETENTION_DAYS` (`BACKUP_RETENTION_DAYS` env, default 7; **1 in production**) deletes objects older than N days by `LastModified`; dated sets age out as whole folders.

## Timeout Calculation

`calculate_timeout()` uses `sizes.active` (not `sizes.file`) — a fragmented 5GB file with 1GB active does not take 5x longer. Formula: `BASE_TIMEOUT(60s) + active_mb * TIMEOUT_PER_MB(2s)`, capped at `MAX_TIMEOUT`.

`MAX_TIMEOUT` was raised 1800→7200s: the streaming upload holds `curl` open for the entire S3 upload, which is bandwidth-bound (~5–6 MB/s observed). A ~9GB `work.json.gz` needs ~30 min just to upload; 1800s killed it mid-upload (the 2026-06-16 re-run failure).

## Disk Space Guard (warn-only)

`check_disk_space()` no longer aborts — per-DB streaming writes nothing but log lines locally, so a full disk must NOT block the backup. It now only warns (`<512MB free` / `>90%` / `>80% used`).

The old hard-abort (`<2GB` / `>90%`) prevented backups exactly when most needed — a full disk could not be backed up to free it.

## System Cleanup

`scripts/cleanup-system.sh` reclaims OS-level disk: `journalctl --vacuum-size=200M`, `apt-get clean`, truncate `/var/log/{btmp,wtmp,fail2ban.log}` and project nginx logs.

Called at the end of `couchdb-backup.sh` AND scheduled standalone via `notes-cleanup.timer` (daily 03:30, after the 03:00 backup). The standalone timer is the safety net — it reclaims space even if a backup run dies early.

## Fragmentation Warning

`calculate_timeout()` also reports fragmentation per DB. Warning threshold >30% (not 20%): smoosh should have compacted at the 20% threshold by backup time, so >30% signals smoosh is not running. Warns to log, never aborts.

## Backup Size vs DB Size

Base64-heavy content (binary files stored as chunks) compresses poorly with gzip — expect `<db>.json.gz` ≈ 80–100% of `sizes.external`. For `work` (16.8GB external as of 2026-06-16, up from 9GB) the gzipped export is ~9GB. `family` ~1.3GB.

## 2026-06-16 ENOSPC Incident

Root cause of the original HTTP 500s: the disk hit 100% full. CouchDB `couch_btree:write_node` failed with `{error,enospc}`, every write returned 500, and Obsidian LiveSync `POST /{db}/_bulk_docs` broke (reads still 200).

The disk filled from accumulated local backups + the old temp-export design staging ~17GB of uncompressed JSON. Fix: per-DB streaming to S3 (zero local footprint) + `cleanup-system.sh` + warn-only disk guard.

## Systemd Timer Deduplication

`setup_systemd_timer_for_backend()` (setup.sh) stops, disables, and removes legacy unit files (`couchdb.*` → `couchdb-backup.*`, `serverpeer.*` → `serverpeer-backup.*`) before enabling the current timer.

Why: older setup.sh versions named units `couchdb.timer`; the rename to `couchdb-backup.timer` left the old timer enabled. Two enabled timers fire the same backup script concurrently — a race producing duplicate archives and overlapping S3 uploads. Cleanup guarantees exactly one timer per backend.
