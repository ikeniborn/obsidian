# Backup Rotation Design

**Date:** 2026-05-20  
**Status:** Approved

## Problem

S3 backups accumulate indefinitely — no rotation. Local backups already have 7-day retention via `find -mtime +7 -delete`. S3 cleanup was explicitly deferred in `couchdb-backup.sh:478` with a note to use lifecycle policies.

Additionally, ServerPeer backup (`scripts/serverpeer-backup.sh`) runs on a schedule but is not needed.

## Scope

1. Add S3 rotation to `scripts/s3_upload.py` (CouchDB backups only)
2. Remove `scripts/serverpeer-backup.sh` and disable its systemd timer on server

Out of scope: serverpeer backup is removed entirely, not migrated.

## Design

### S3 Rotation — `scripts/s3_upload.py`

Add function:

```python
def cleanup_old_objects(s3_client, bucket, prefix, days):
    """Delete S3 objects under prefix older than days."""
```

Logic:
- Call `list_objects_v2` with the given prefix
- Filter objects where `LastModified < now - days`
- Delete in batches of up to 1000 via `delete_objects` API
- Log each deleted object and total count

Extend CLI interface:

```
s3_upload.py --cleanup <prefix> [--days N]
```

`--days` defaults to 7 if omitted.

### Integration — `scripts/couchdb-backup.sh`

After successful S3 upload (existing line ~459), add:

```bash
python3 "${S3_UPLOAD_SCRIPT}" --cleanup "${S3_PREFIX}" --days "${RETENTION_DAYS}"
```

`RETENTION_DAYS=7` is already defined in the script — no new variable needed.

Cleanup runs only when `S3_UPLOAD_ENABLED=true` (same guard as upload).

### ServerPeer Backup Removal

**Repository:**
- Delete `scripts/serverpeer-backup.sh`

**Server (`ssh ikenibornsync`):**
- `systemctl stop serverpeer-backup.timer`
- `systemctl disable serverpeer-backup.timer`
- Remove unit files: `serverpeer-backup.timer`, `serverpeer-backup.service`
- Remove any cron entries for `serverpeer-backup.sh`
- `systemctl daemon-reload`

## Retention Policy

| Storage | Retention |
|---------|-----------|
| Local   | 7 days (unchanged) |
| S3      | 7 days (new) |

## Error Handling

- Cleanup failure logs a warning but does not fail the backup run — upload success is more important than cleanup success.
- `list_objects_v2` handles pagination automatically (boto3 paginators or manual `NextContinuationToken`).

## Required S3 Permissions

Existing permissions needed for upload: `s3:PutObject`  
New permissions needed: `s3:ListBucket`, `s3:DeleteObject`
