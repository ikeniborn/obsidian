# Backup

CouchDB backup via `_all_docs?include_docs=true` API — exports current document versions as JSON, compresses to tar.gz, uploads to S3. `scripts/couchdb-backup.sh` orchestrates the full pipeline.

## Disk Space Guard

Backup aborts early if disk is critically full. Thresholds in `check_disk_space()`:
- `< 2GB free` → hard abort
- `> 90% used` → hard abort
- `> 80% used` → warning, continue

Why: CouchDB `external` size for `work` DB is ~9GB. JSON export before gzip can temporarily use equal or more space than the compressed result. Without this guard, a daily backup on a near-full disk causes disk-full failures that corrupt the archive.

## Timeout Calculation

`calculate_timeout()` uses `sizes.active` (not `sizes.file`) to estimate export time. Using `sizes.file` would over-estimate timeout for fragmented databases — a 5GB file with 1GB active data does not take 5x longer to export.

Formula: `timeout = BASE_TIMEOUT(60s) + active_mb * TIMEOUT_PER_MB(2s)`, capped at 1800s.

## Fragmentation Warning

During backup each database is checked for fragmentation. Warning threshold: >30%. Warns to log but does not abort — backup of fragmented data is still valid.

Why 30% not 20%: at backup time smoosh should have already compacted at the 20% threshold. A warning at 30% signals that smoosh is not running correctly.

## Backup Size vs DB Size

Backup (gzip'd JSON) is typically smaller than `sizes.active` for text vaults, but near-equal for base64-heavy content (binary files stored as chunks). Base64 does not compress well with gzip — expect backup ≈ 80-100% of `sizes.external`.

For `work` DB (9GB external): backup ≈ 7-9GB compressed. Plan disk: need `2 * backup_size` free during backup (current + new archive before old is deleted).
