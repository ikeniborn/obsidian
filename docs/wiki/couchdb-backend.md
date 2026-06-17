# CouchDB Backend

CouchDB is the default, production sync backend — a client-server document store (CouchDB 3.3) accessed over HTTP. It runs as a single Docker container bound to localhost, tuned for Obsidian sync via `local.ini`, and watched by a health-monitoring script. It is one of the project's [[architecture#Dual Sync Backends]].

## Container Definition

`docker-compose.notes.yml` defines a single service `couchdb` (container `${COUCHDB_CONTAINER_NAME:-notes-couchdb}`) on image `couchdb:3.3`. The CouchDB port is published to `127.0.0.1` only; all external access goes through the nginx reverse proxy. The Docker network is resolved dynamically from `.env`.

Key settings:
- **Image / restart**: `couchdb:3.3`, `restart: unless-stopped`, `stop_grace_period: 30s`, `stop_signal: SIGTERM`.
- **Env**: `env_file: /opt/notes/.env`; `COUCHDB_USER` (default `admin`) and `COUCHDB_PASSWORD` passed through.
- **Volumes**: `${NOTES_DATA_DIR:-/opt/notes/data}:/opt/couchdb/data` and `./local.ini:/opt/couchdb/etc/local.ini`.
- **Port**: `127.0.0.1:${COUCHDB_PORT:-5984}:5984` — localhost-only bind.
- **Network**: `notes-network`, with `external: ${NETWORK_EXTERNAL:-false}` and `name: ${NETWORK_NAME}` — switched between shared/isolated/custom via `NETWORK_MODE` in `.env` ([[architecture#Configuration & Secrets]]).
- **Healthcheck**: `curl -f -u $COUCHDB_USER:$COUCHDB_PASSWORD http://localhost:5984/_up` every 30s (timeout 10s, 3 retries, 30s start period).
- **Resources**: limits `cpus: 0.5` / `memory: 512M`; reservations `cpus: 0.1` / `memory: 128M`. The limit was raised from a 384M "optimization" back to 512M after 384M caused a `beam.smp` OOM-kill crash loop (HTTP 502) under heavy sync load on the 891MB-RAM host; a host swap file is also required as a cushion. See [[troubleshooting#HTTP 502 — CouchDB OOM crash loop]].

The proxy in front of this container is documented in [[nginx-proxy#CouchDB Template]]. Backups of these databases are covered in [[backup-system#CouchDB Backup]].

## CouchDB Configuration

`local.ini` (mounted read into the container) configures single-node mode, authentication, CORS for the Obsidian app, and large-document support. It is the single source of CouchDB tuning, optimized 2026-01-11.

Core settings:
- `[couchdb] single_node=true`, `max_document_size = 50000000` (50MB, for attachments).
- `[chttpd] require_valid_user = true` and `[chttpd_auth] require_valid_user = true` — authentication mandatory; `authentication_redirect = /_utils/session.html`.
- `[httpd]` advertises Basic auth realm `couchdb` and `enable_cors = true`.
- `[cors]` restricts `origins` to `app://obsidian.md, capacitor://localhost, http://localhost`, with `credentials = true`, explicit `headers`/`methods`, and `max_age = 3600`.

These map to the Obsidian LiveSync client expectations and to the credentials in `/opt/notes/.env` ([[architecture#Configuration & Secrets]]).

## Performance Optimization

`local.ini` carries layered performance tuning: automatic compaction via the 3.x smoosh daemon, faster bulk writes, request-size protection, and query/connection tuning. These exceed CouchDB defaults and are tuned for sync workloads on a constrained host.

- **Automatic compaction (smoosh, CouchDB 3.x)**: `[smoosh]` runs `ratio_dbs,slack_dbs` (and view equivalents). `[smoosh.ratio_dbs]` triggers when file/active ratio > `1.25` (~20% fragmentation); `[smoosh.slack_dbs]` triggers when wasted space > `209715200` (200MB); both with `wait = 30`. (Note: the 2.x `[compaction_daemon]`/`[compactions]` syntax is ignored in 3.x.)
- **Write optimization**: `delayed_commits = true` (batched writes, 3-5x faster bulk) and `file_compression = snappy`.
- **Request protection**: `max_http_request_size = 1073741824` (1GB) and `max_connections = 200`. Raised from 100MB because LiveSync initial-sync/rebuild `_bulk_docs` batches exceed 100MB and CouchDB rejected them with 413 — it must match the nginx `client_max_body_size`, or the 413 just moves from nginx to CouchDB. Run it lower only after reducing the LiveSync client batch size. See [[troubleshooting#HTTP 413 — Request Entity Too Large]].
- **Query / connection tuning**: `max_dbs_open = 1000`, `attachment_compression_level = 6`, `[query_server_config] os_process_timeout = 10000` (10s) and `os_process_soft_limit = 50`.
- **HTTP / logging**: `compression = true` (gzip responses), `[log] level = warning` (reduced noise, `writer = stderr`), `[stats] interval = 10`.

## Health Monitoring

`scripts/monitor-couchdb.sh` (189 lines) is a daily health check (suggested cron `0 6 * * *`). It verifies CouchDB availability, reports per-database fragmentation, checks disk space, inspects the compaction daemon and active tasks, and logs container resource usage — appending everything to `/opt/notes/logs/health.log`.

Checks performed (`set -euo pipefail`, colored `info`/`warning`/`error` output, all `tee`'d to the log):
- **Availability**: authenticated `GET /_up` using `COUCHDB_PASSWORD` and `COUCHDB_PORT` parsed from `.env`; exits if down.
- **Per-DB fragmentation**: for each non-system DB, computes `(file - active) / file * 100` from `sizes`. Thresholds — **>30%** = HIGH (suggests manual `POST /<db>/_compact`), **>20%** = moderate (auto-compaction should trigger soon), else healthy. Also reports file size (MB) and `doc_count`.
- **Disk space**: `df` on `/opt/notes/data` — error >90%, warning >80%.
- **Compaction daemon**: queries `/_node/_local/_config/compaction_daemon` and warns if not configured.
- **Active compactions**: scans `/_active_tasks` for `database_compaction` and names the DB in progress.
- **Container resources**: `docker stats --no-stream` (CPU%, MemUsage) for `${COUCHDB_CONTAINER_NAME:-notes-couchdb}`; warns if the container is not running.

The fragmentation thresholds align with the smoosh ratio trigger described in [[couchdb-backend#Performance Optimization]].
