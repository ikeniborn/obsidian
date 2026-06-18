# Troubleshooting

Operational playbook for the production CouchDB sync server, distilled from the
2026-06-17 incident. Each section is symptom → root cause → fix. The full
command-level runbook lives in `docs/troubleshooting.md`; backend internals are
in [[couchdb-backend#Container Definition]] and [[nginx-proxy#CouchDB Template]].

## HTTP 500 — disk full / compaction loop

A 100%-full root filesystem stops CouchDB from writing → HTTP 500. It is
amplified by a disk-full **compaction loop**: smoosh writes a temporary
`*.couch.compact.data`, the full disk kills it mid-way, and it retries every
cycle. Fix: delete the orphan `*.compact.*` (when `/_active_tasks` is empty),
temporarily empty `smoosh` `db_channels`/`view_channels`, restore free space,
then re-enable. Never compact manually on a near-full disk. Compaction tuning:
[[couchdb-backend#Performance Optimization]].

**As of 2026-06-18 smoosh is disabled by default** (`local.ini` ships empty
`db_channels`/`view_channels`) to prevent this loop on the constrained host.
Runtime channel edits race with already-queued jobs, so apply the change in
`local.ini` and **restart** the container (boot config has no race), then delete
any orphan `*.compact.*`. Note a restart frees space the running process pinned
via deleted-but-open file handles. Re-enable only after DB bloat is reset and
the disk has >2x the largest db free.

## HTTP 413 — Request Entity Too Large

LiveSync sends large `_bulk_docs` batches (initial sync/rebuild) that exceed the
nginx `client_max_body_size`. The template default was 50M and is now **1024M**;
CouchDB itself allows up to `chttpd/max_http_request_size` (~4G). On a deployed
server, edit `/opt/notes/nginx/notes.conf` and **restart** `notes-nginx` (a
bind-mounted single file edited with `sed -i` changes its inode, so a reload
alone keeps the old content). Template details: [[nginx-proxy#CouchDB Template]].

## HTTP 502 — CouchDB OOM crash loop

Intermittent 502 with nginx `connect() failed (111: Connection refused)` and a
climbing container `RestartCount` means CouchDB's Erlang VM (`beam.smp`) is
being OOM-killed at its cgroup memory limit and restart-looping. The limit was
raised 384M→**512M** and a **host swap file** added as a cushion (`install.sh`
`ensure_swap` does this on low-RAM hosts — see [[installation#Swap Cushion]]).
Container limits: [[couchdb-backend#Container Definition]].

## Database bloat / huge document count

LiveSync stores 1 chunk = 1 CouchDB document; edits orphan old chunks that are
never garbage-collected, so document count and size balloon (≈178K docs / 17G).
`active ≈ file` means compaction reclaims little. Fix is a clean reset: verify
an S3 backup ([[backup-system#CouchDB Backup]]), drop+recreate the DBs, then
`Rebuild everything → Overwrite remote` from the reference client; other devices
`Fetch everything`.

## Reducing document count (prevention)

Enable LiveSync **Eden** ("Incubate Chunks in Document", `useEden`, Power-User
pane) to keep volatile chunks inside the note document instead of spawning a
document each — the strongest lever. Also: larger chunk size, exclude
attachments, and periodic `Perform cleanup`/rebuild. Changing chunk/Eden
settings is a "tweak" requiring a rebuild + `Fetch everything` on other devices.

## Capacity note

The host (`ikenibornsync`) is 891MB RAM / 39G disk — undersized for a ~30G,
~300K-document workload. The fixes above stabilise it; durable remedies are
reducing data (Eden + excluding attachments) or upgrading the VPS. Backups
stream straight to S3 ([[backup-system#Retention Policy]]) with count-based
retention (`BACKUP_KEEP_SETS`); a size-capped bucket must still fit two full
sets transiently, so raise the bucket limit or use `BACKUP_PRUNE_BEFORE=true`.
