#!/usr/bin/env python3
"""Unit tests for s3_upload.cleanup_old_objects"""
import sys
import os
import unittest
from unittest.mock import MagicMock, patch
from datetime import datetime, timezone, timedelta

sys.path.insert(0, os.path.dirname(__file__))
from s3_upload import cleanup_old_objects


class TestCleanupOldObjects(unittest.TestCase):

    def _make_client(self, objects=None):
        """Return mock S3 client. Pass None to simulate empty prefix (no Contents key)."""
        mock_paginator = MagicMock()
        page = {'Contents': objects} if objects is not None else {}
        mock_paginator.paginate.return_value = [page]
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

    def test_boundary_object_at_exactly_retention_is_kept(self):
        now = datetime.now(timezone.utc)
        cutoff = now - timedelta(days=7)
        client = self._make_client([
            {'Key': 'couchdb-backups/boundary.tar.gz', 'LastModified': cutoff},
        ])

        # Mock datetime.now to return consistent value (avoids timing drift)
        with patch('s3_upload.datetime') as mock_datetime:
            mock_datetime.now.return_value = now
            count = cleanup_old_objects(client, 'my-bucket', 'couchdb-backups/', 7)

        client.delete_objects.assert_not_called()
        self.assertEqual(count, 0)

    def test_empty_prefix_returns_zero(self):
        client = self._make_client(None)

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
        calls = client.delete_objects.call_args_list
        self.assertEqual(len(calls[0].kwargs['Delete']['Objects']), 1000)
        self.assertEqual(len(calls[1].kwargs['Delete']['Objects']), 500)

    def test_partial_delete_errors_not_counted(self):
        now = datetime.now(timezone.utc)
        key_ok = 'couchdb-backups/old-ok.tar.gz'
        key_err = 'couchdb-backups/old-err.tar.gz'
        client = self._make_client([
            {'Key': key_ok, 'LastModified': now - timedelta(days=10)},
            {'Key': key_err, 'LastModified': now - timedelta(days=10)},
        ])
        client.delete_objects.return_value = {
            'Errors': [{'Key': key_err, 'Code': '403', 'Message': 'Forbidden'}]
        }

        count = cleanup_old_objects(client, 'my-bucket', 'couchdb-backups/', 7)

        self.assertEqual(count, 1)


if __name__ == '__main__':
    unittest.main(verbosity=2)
