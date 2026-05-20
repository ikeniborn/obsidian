---
review:
  plan_hash: cb5f5dc809a1f606
  spec_hash: 7eacce8a903f2c7b
  last_run: 2026-05-20
  phases:
    structure:     { status: passed }
    coverage:      { status: passed }
    dependencies:  { status: passed }
    verifiability: { status: passed }
    consistency:   { status: passed }
  section_hashes:
    Task1: a7f500b8385f0c2f
    Task2: 10946fc9dbca93a7
    Task3: b20b166ad0ad5a1f
    Task4: c427bfaed7fd5d0a
    Task5: d0f1524f256a42b5
  findings:
    - id: F-001
      phase: coverage
      severity: INFO
      section: Task5
      section_hash: d0f1524f256a42b5
      text: "Spec §Required S3 Permissions (s3:ListBucket, s3:DeleteObject) not covered by any plan step — no verification that bucket policy allows listing/deletion before running cleanup"
      verdict: fixed
      verdict_at: 2026-05-20
    - id: F-002
      phase: verifiability
      severity: WARNING
      section: Task5
      section_hash: d0f1524f256a42b5
      text: "Task 5 Step 6 runs 'git add -A && git commit' but Task 5 makes no repo changes — commit will fail with 'nothing to commit'"
      verdict: fixed
      verdict_at: 2026-05-20
---

# Backup Rotation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add S3 backup rotation (delete objects older than 7 days) and disable ServerPeer backup schedule on the server.

**Architecture:** Add `cleanup_old_objects()` to `scripts/s3_upload.py`, extend its CLI with `--cleanup <prefix> [--days N]`, call it from `couchdb-backup.sh` after successful upload. Server-side: SSH to disable and remove serverpeer-backup systemd units.

**Tech Stack:** Python 3, boto3, bash, systemd

---

## File Map

| File | Change |
|------|--------|
| `scripts/s3_upload.py` | Add `cleanup_old_objects()`, `run_cleanup()`, extend CLI |
| `scripts/couchdb-backup.sh` | Add cleanup call after upload; remove stale S3 lifecycle comment |
| `scripts/test_s3_cleanup.py` | NEW — unit tests for cleanup function |
| server: systemd units | Disable/remove `serverpeer-backup.timer` + `.service` |

---

### Task 1: Unit tests for cleanup_old_objects

**Files:**
- Create: `scripts/test_s3_cleanup.py`

- [ ] **Step 1: Create test file**

```python
#!/usr/bin/env python3
"""Unit tests for s3_upload.cleanup_old_objects"""
import sys
import os
import unittest
from unittest.mock import MagicMock
from datetime import datetime, timezone, timedelta

sys.path.insert(0, os.path.dirname(__file__))
from s3_upload import cleanup_old_objects


class TestCleanupOldObjects(unittest.TestCase):

    def _make_client(self, objects):
        """Return mock S3 client with given objects list."""
        mock_paginator = MagicMock()
        mock_paginator.paginate.return_value = [{'Contents': objects}]
        client = MagicMock()
        client.get_paginator.return_value = mock_paginator
        return client

    def test_deletes_objects_older_than_days(self):
        now = datetime.now(timezone.utc)
        old_key = 'couchdb-backups/couchdb-20260512.tar.gz'
        new_key = 'couchdb-backups/couchdb-20260517.tar.gz'
        client = self._make_client([
            {'Key': old_key, 'LastModified': now - timedelta(days=8)},
            {'Key': new_key, 'LastModified': now - timedelta(days=3)},
        ])

        count = cleanup_old_objects(client, 'my-bucket', 'couchdb-backups/', 7)

        client.delete_objects.assert_called_once_with(
            Bucket='my-bucket',
            Delete={'Objects': [{'Key': old_key}]}
        )
        self.assertEqual(count, 1)

    def test_keeps_objects_within_retention(self):
        now = datetime.now(timezone.utc)
        client = self._make_client([
            {'Key': 'couchdb-backups/couchdb-20260519.tar.gz',
             'LastModified': now - timedelta(days=1)},
        ])

        count = cleanup_old_objects(client, 'my-bucket', 'couchdb-backups/', 7)

        client.delete_objects.assert_not_called()
        self.assertEqual(count, 0)

    def test_empty_prefix_returns_zero(self):
        mock_paginator = MagicMock()
        mock_paginator.paginate.return_value = [{}]  # no 'Contents' key
        client = MagicMock()
        client.get_paginator.return_value = mock_paginator

        count = cleanup_old_objects(client, 'my-bucket', 'couchdb-backups/', 7)

        client.delete_objects.assert_not_called()
        self.assertEqual(count, 0)

    def test_batches_large_deletions(self):
        now = datetime.now(timezone.utc)
        objects = [
            {'Key': f'prefix/file-{i}.tar.gz', 'LastModified': now - timedelta(days=10)}
            for i in range(1500)
        ]
        client = self._make_client(objects)

        count = cleanup_old_objects(client, 'my-bucket', 'prefix/', 7)

        self.assertEqual(client.delete_objects.call_count, 2)  # 1000 + 500
        self.assertEqual(count, 1500)


if __name__ == '__main__':
    unittest.main(verbosity=2)
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd /home/ikeniborn/Documents/Project/obsidian
python3 scripts/test_s3_cleanup.py -v
```

Expected: `ImportError: cannot import name 'cleanup_old_objects' from 's3_upload'`

---

### Task 2: Implement cleanup_old_objects and run_cleanup in s3_upload.py

**Files:**
- Modify: `scripts/s3_upload.py`

- [ ] **Step 1: Add imports and cleanup_old_objects function**

In `scripts/s3_upload.py`, add after the existing imports (after `from pathlib import Path`):

```python
from datetime import datetime, timezone, timedelta
```

Then add this function before `test_s3_connection()`:

```python
def cleanup_old_objects(s3_client, bucket, prefix, days):
    """Delete S3 objects under prefix older than days. Returns count deleted."""
    cutoff = datetime.now(timezone.utc) - timedelta(days=days)
    to_delete = []

    paginator = s3_client.get_paginator('list_objects_v2')
    for page in paginator.paginate(Bucket=bucket, Prefix=prefix):
        for obj in page.get('Contents', []):
            if obj['LastModified'] < cutoff:
                to_delete.append({'Key': obj['Key']})

    deleted_count = 0
    for i in range(0, len(to_delete), 1000):
        batch = to_delete[i:i + 1000]
        s3_client.delete_objects(Bucket=bucket, Delete={'Objects': batch})
        for obj in batch:
            print(f"Deleted: {obj['Key']}")
        deleted_count += len(batch)

    if deleted_count == 0:
        print(f"No objects older than {days} days in {prefix}")
    else:
        print(f"Cleanup: {deleted_count} objects deleted from {prefix}")

    return deleted_count
```

- [ ] **Step 2: Add run_cleanup function**

Add after `cleanup_old_objects`, before `test_s3_connection()`:

```python
def run_cleanup(prefix, days=7):
    """Load config, create S3 client, run cleanup. Returns True on success."""
    env = load_env_file()

    access_key = env.get('S3_ACCESS_KEY_ID') or os.getenv('S3_ACCESS_KEY_ID')
    secret_key = env.get('S3_SECRET_ACCESS_KEY') or os.getenv('S3_SECRET_ACCESS_KEY')
    bucket_name = env.get('S3_BUCKET_NAME') or os.getenv('S3_BUCKET_NAME')
    endpoint_url = env.get('S3_ENDPOINT_URL') or os.getenv('S3_ENDPOINT_URL')
    region = env.get('S3_REGION', 'ru-central1')

    if not all([access_key, secret_key, bucket_name]):
        print("ERROR: S3 credentials not configured in .env")
        return False

    try:
        s3_client = boto3.client(
            's3',
            aws_access_key_id=access_key,
            aws_secret_access_key=secret_key,
            endpoint_url=endpoint_url,
            region_name=region
        )
    except Exception as e:
        print(f"ERROR: Failed to create S3 client: {e}")
        return False

    try:
        cleanup_old_objects(s3_client, bucket_name, prefix, days)
        return True
    except ClientError as e:
        print(f"ERROR: S3 cleanup failed: {e}")
        return False
```

- [ ] **Step 3: Run tests to verify they pass**

```bash
cd /home/ikeniborn/Documents/Project/obsidian
python3 scripts/test_s3_cleanup.py -v
```

Expected: 4 tests pass, `OK`

- [ ] **Step 4: Commit**

```bash
git add scripts/s3_upload.py scripts/test_s3_cleanup.py
git commit -m "feat(backup): add S3 cleanup function with pagination and batching"
```

---

### Task 3: Extend s3_upload.py CLI with --cleanup

**Files:**
- Modify: `scripts/s3_upload.py` (the `if __name__ == "__main__":` block)

- [ ] **Step 1: Replace the CLI block**

Replace the existing `if __name__ == "__main__":` block (lines 120–134) with:

```python
if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: s3_upload.py <file_path> [s3_prefix]")
        print("       s3_upload.py --test")
        print("       s3_upload.py --cleanup <prefix> [--days N]")
        sys.exit(1)

    if sys.argv[1] == "--test":
        success = test_s3_connection()
        sys.exit(0 if success else 1)

    if sys.argv[1] == "--cleanup":
        if len(sys.argv) < 3:
            print("Usage: s3_upload.py --cleanup <prefix> [--days N]")
            sys.exit(1)
        prefix = sys.argv[2]
        days = 7
        if "--days" in sys.argv:
            idx = sys.argv.index("--days")
            days = int(sys.argv[idx + 1])
        success = run_cleanup(prefix, days)
        sys.exit(0 if success else 1)

    file_path = sys.argv[1]
    s3_prefix = sys.argv[2] if len(sys.argv) > 2 else ""
    success = upload_to_s3(file_path, s3_prefix)
    sys.exit(0 if success else 1)
```

- [ ] **Step 2: Run tests to confirm nothing broke**

```bash
cd /home/ikeniborn/Documents/Project/obsidian
python3 scripts/test_s3_cleanup.py -v
```

Expected: 4 tests pass, `OK`

- [ ] **Step 3: Commit**

```bash
git add scripts/s3_upload.py
git commit -m "feat(backup): extend s3_upload.py CLI with --cleanup <prefix> [--days N]"
```

---

### Task 4: Wire cleanup into couchdb-backup.sh

**Files:**
- Modify: `scripts/couchdb-backup.sh`

- [ ] **Step 1: Add cleanup call after successful upload**

In `scripts/couchdb-backup.sh`, find the block starting at line 454. Replace:

```bash
    if python3 "${S3_UPLOAD_SCRIPT}" "${BACKUP_DIR}/${BACKUP_NAME}" "${S3_PREFIX}" 2>&1 | tee -a "${LOG_FILE}"; then
        upload_end_time=$(date +%s)
        upload_duration=$((upload_end_time - upload_start_time))

        log "✅ Upload completed in ${upload_duration} seconds"
        update_progress "Backup uploaded to S3"
    else
```

With:

```bash
    if python3 "${S3_UPLOAD_SCRIPT}" "${BACKUP_DIR}/${BACKUP_NAME}" "${S3_PREFIX}" 2>&1 | tee -a "${LOG_FILE}"; then
        upload_end_time=$(date +%s)
        upload_duration=$((upload_end_time - upload_start_time))

        log "✅ Upload completed in ${upload_duration} seconds"
        update_progress "Backup uploaded to S3"

        log "Cleaning up S3 objects older than ${RETENTION_DAYS} days..."
        if python3 "${S3_UPLOAD_SCRIPT}" --cleanup "${S3_PREFIX}" --days "${RETENTION_DAYS}" 2>&1 | tee -a "${LOG_FILE}"; then
            log "S3 cleanup completed"
        else
            log "WARNING: S3 cleanup failed (backup upload was successful)"
        fi
    else
```

- [ ] **Step 2: Remove stale S3 lifecycle comment (lines 478–481)**

Find and remove these lines:

```bash
# Note: S3 old backup cleanup should be done via S3 lifecycle policies
# Manual cleanup can be done using AWS CLI or S3 web console
log "ℹ️  S3 backup retention: Configure lifecycle policy in S3 bucket settings"
log "   Recommended: Delete objects older than ${RETENTION_DAYS} days"
```

- [ ] **Step 3: Commit**

```bash
git add scripts/couchdb-backup.sh
git commit -m "feat(backup): call S3 cleanup after successful upload in couchdb-backup.sh"
```

---

### Task 5: Disable ServerPeer backup on server

**No repo file changes. SSH operations only.**

- [ ] **Step 1: Check current state**

```bash
ssh ikenibornsync "systemctl list-timers | grep serverpeer; crontab -l 2>/dev/null | grep serverpeer || echo 'no cron'; systemctl status serverpeer-backup.timer 2>&1 | head -5"
```

- [ ] **Step 2: Verify S3 cleanup permissions**

Required: bucket must allow `s3:ListBucket` and `s3:DeleteObject` for the IAM user in `.env`.

```bash
ssh ikenibornsync "cd /opt/notes && source .env && python3 scripts/s3_upload.py --cleanup ${S3_BACKUP_PREFIX:-couchdb-backups/} --days 9999"
```

Expected: `No objects older than 9999 days in couchdb-backups/`

If you see `Access Denied` — update the bucket IAM policy to add `s3:ListBucket` and `s3:DeleteObject` for the backup user, then rerun.

- [ ] **Step 3: Stop and disable the timer**

```bash
ssh ikenibornsync "sudo systemctl stop serverpeer-backup.timer 2>/dev/null || true; sudo systemctl disable serverpeer-backup.timer 2>/dev/null || true"
```

- [ ] **Step 4: Remove unit files**

```bash
ssh ikenibornsync "sudo rm -f /etc/systemd/system/serverpeer-backup.timer /etc/systemd/system/serverpeer-backup.service; sudo systemctl daemon-reload"
```

- [ ] **Step 5: Remove cron entries if any**

```bash
ssh ikenibornsync "crontab -l 2>/dev/null | grep -v 'serverpeer-backup' | crontab - 2>/dev/null || true"
```

- [ ] **Step 6: Verify timer is gone**

```bash
ssh ikenibornsync "systemctl list-timers | grep serverpeer || echo 'OK: no serverpeer timer found'"
```

Expected: `OK: no serverpeer timer found`

---

## Self-Review Checklist

- [x] `cleanup_old_objects` — covered by Task 1+2
- [x] CLI `--cleanup` — covered by Task 3
- [x] `couchdb-backup.sh` integration — covered by Task 4
- [x] Cleanup only runs when `S3_UPLOAD_ENABLED=true` — guaranteed: cleanup call is inside the `if python3 upload ...; then` success branch
- [x] Cleanup failure doesn't break backup — WARNING log, no `exit 1`
- [x] Stale comment removed — Task 4 Step 2
- [x] ServerPeer disabled on server — Task 5
- [x] No placeholders, no TBDs
- [x] Function name consistent: `cleanup_old_objects` in all tasks
