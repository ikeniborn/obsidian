# Architecture

## Overview

Obsidian Sync Server is a production-ready, self-hosted sync server for Obsidian notes. It supports two sync backends, flexible Docker networking, an nginx reverse proxy with SSL/TLS, UFW firewall, and automated S3 backups.

Clients run the Obsidian **Self-hosted LiveSync** plugin and connect over HTTPS to a single domain (`NOTES_DOMAIN`). All external traffic terminates at nginx, which reverse-proxies to the selected backend; backend ports never bind to a public interface. The repository orchestrates everything through three scripts (`install.sh`, `setup.sh`, `deploy.sh`) plus helper scripts under `scripts/`. Configuration and secrets live in `/opt/notes/.env`.

Key infrastructure pieces:
- **CouchDB** — document database backend (`couchdb:3.3`).
- **livesync-serverpeer + Nostr relay** — P2P/WebRTC backend (legacy, see below).
- **nginx** — reverse proxy and SSL termination (existing or self-deployed).
- **certbot** — Let's Encrypt certificate acquisition and renewal.
- **UFW** — host firewall; **fail2ban** — dynamic IP banning.

A YAML knowledge graph at `docs/architecture/index.yml` documents components, scripts, workflows, and patterns in depth.

## Dual Sync Backends

The server supports two interchangeable sync backends selected during `setup.sh` (CouchDB only / ServerPeer only / Both). See [[setup#Backend Selection]]. **In practice production runs CouchDB; the ServerPeer/P2P backend is LEGACY and frozen.**

**CouchDB (default, client-server)**
- Protocol: HTTP REST API; storage: document-oriented database (CouchDB 3.3).
- Container `notes-couchdb`, port `5984` bound to `127.0.0.1` only (`docker-compose.notes.yml`).
- Config in `local.ini` (single-node, 50MB max document, CORS for Obsidian, auth required).
- Backup: database dumps → tar.gz → S3 via `scripts/couchdb-backup.sh`.
- Details: [[couchdb-backend#Container Definition]], [[backup-system#CouchDB Backup]].

**livesync-serverpeer (P2P, LEGACY/FROZEN)**
- Protocol: WebSocket (WSS) relay + WebRTC peer-to-peer; storage: filesystem vault.
- Containers `notes-serverpeer` (port `3000`, localhost) and `notes-nostr-relay` (port `7000`, localhost) for signaling. Defined in `docker-compose.serverpeer.yml` and `docker-compose.nostr-relay.yml`.
- Deno-based image built from `serverpeer/Dockerfile`; supports multi-vault setups with isolated Room IDs.
- Requires a TURN/STUN server (coturn) for NAT traversal — see [[turn-stun-p2p#TURN/STUN Purpose]].
- Backup via `scripts/serverpeer-backup.sh` (old local-tar.gz design, not migrated to streaming).
- Status and caveats: [[serverpeer-backend#Legacy Status]].

Both backends share the same nginx proxy, UFW firewall, SSL/TLS, and S3 backup tooling (`scripts/s3_upload.py`).

## Network Architecture

All containers attach to a single logical `notes-network` whose behavior is driven by `.env` variables, giving three modes: **shared**, **isolated**, and **custom**. Mode is chosen interactively during setup. See [[networking#Network Modes]].

The compose files declare:
```yaml
networks:
  notes-network:
    external: ${NETWORK_EXTERNAL:-false}
    name: ${NETWORK_NAME}
```

- **Shared** — reuse an existing Docker network (`NETWORK_EXTERNAL=true`) to integrate with other services; nginx may be an existing container.
- **Isolated** — standalone deployment on an auto-created `obsidian_network` with an auto-selected free subnet (172.24–31.0.0/16); nginx is the project's own `notes-nginx` container.
- **Custom** — explicit `NETWORK_NAME`.

Design rules: backend ports bind to `127.0.0.1` only, all HTTPS traffic flows through the nginx reverse proxy, and the deployment directory is always `/opt/notes`. Nginx detection/integration is handled by `scripts/nginx-setup.sh` — see [[nginx-proxy#Nginx Detection]].

## Deployment Flow

Production deployment is a fixed three-step sequence run from the repository root. Each step writes state that the next consumes, with `/opt/notes/.env` as the shared contract.

1. **`sudo ./install.sh`** — installs Docker/Docker Compose, UFW, Python 3 + `boto3`; creates `/opt/notes`; installs coturn when the ServerPeer backend is selected. See [[installation#Dependency Installation]].
2. **`sudo ./setup.sh`** — interactive configuration. Prompts for backend, `NOTES_DOMAIN`, `CERTBOT_EMAIL`, optional Docker proxy and S3 credentials; generates the CouchDB password; writes `/opt/notes/.env`; sets up cron/systemd backup timers. See [[setup#Environment Generation]] and [[setup#Backend Selection]].
3. **`./deploy.sh`** — orchestrates the full deploy: `nginx-setup.sh` → `ssl-setup.sh` → applies nginx config with SSL → deploys the selected backend → validates and prints a summary. See [[deployment#Deployment Orchestration]].

During deploy, certbot obtains certificates ([[ssl-tls#Certificate Acquisition]]), UFW is configured to allow SSH (22) and HTTPS (443) while keeping port 80 closed except during renewal ([[firewall-security#UFW Configuration]]). DNS must point at the server before `deploy.sh`. Validation tests live in [[testing#Test Suite]] (`scripts/run-all-tests.sh`).

## Directory Layout

The repository root holds the orchestration scripts and compose files; reusable logic lives under `scripts/`, nginx templates under `templates/`, and architecture docs under `docs/`.

```
obsidian/
├── docker-compose.notes.yml        # CouchDB service
├── docker-compose.serverpeer.yml   # ServerPeer service (legacy)
├── docker-compose.nostr-relay.yml  # Nostr relay (P2P signaling)
├── local.ini                       # CouchDB server config
├── install.sh                      # Dependency installation (sudo)
├── setup.sh                        # Interactive configuration → .env
├── deploy.sh                       # Production deployment orchestrator
├── .env.example                    # Variable template
├── serverpeer/Dockerfile           # ServerPeer (Deno) build
├── templates/*.conf.template       # nginx config templates
├── systemd/                        # backup timer/service units
├── nostr-relay/                    # Nostr relay config (config.toml)
├── scripts/
│   ├── couchdb-backup.sh           # CouchDB backup
│   ├── serverpeer-backup.sh        # ServerPeer backup (legacy)
│   ├── nginx-setup.sh              # nginx detection/integration
│   ├── ssl-setup.sh                # Let's Encrypt SSL
│   ├── ufw-setup.sh                # firewall (incl. TURN ports)
│   ├── coturn-setup.sh             # TURN/STUN setup
│   ├── fail2ban-setup.sh           # dynamic IP banning
│   ├── monitor-couchdb.sh          # CouchDB health monitoring
│   ├── s3_upload.py                # S3 upload (backend-agnostic)
│   └── run-all-tests.sh            # test suite orchestrator
└── docs/
    ├── architecture/index.yml      # YAML knowledge graph (entry point)
    └── wiki/                       # this iwiki knowledge base
```

The runtime deployment directory `/opt/notes` (data, backups, logs, `.env`) is created by `install.sh` and is separate from the repository.

## Configuration & Secrets

All runtime configuration and secrets live in a single file, `/opt/notes/.env`, generated by `setup.sh` and `chmod 600`. It is never committed; `.env.example` documents the variables. The compose files load it via `env_file: /opt/notes/.env`.

Core variables:
- `COUCHDB_USER` / `COUCHDB_PASSWORD` — admin credentials; the password is auto-generated with `openssl rand -hex 32` (256-bit).
- `NOTES_DOMAIN`, `CERTBOT_EMAIL` — domain and Let's Encrypt contact.
- `NETWORK_MODE`, `NETWORK_NAME`, `NETWORK_SUBNET`, `NETWORK_EXTERNAL` — networking (see [[networking#Network Modes]]).
- `COUCHDB_CONTAINER_NAME`, `COUCHDB_PORT`, `NOTES_DATA_DIR`, `NOTES_BACKUP_DIR` — CouchDB runtime.
- S3 credentials and backup prefixes (optional) — consumed by `scripts/s3_upload.py`.

Backend-specific variables are only written when the relevant backend is selected. ServerPeer adds `SERVERPEER_*` (room ID, passphrase, relays, vault dir) and TURN credentials (`TURN_USERNAME`, `TURN_PASSWORD`, `SERVERPEER_TURN_SERVERS`) — see [[turn-stun-p2p#TURN/STUN Purpose]]. CouchDB server tuning lives separately in `local.ini` (compaction, write optimization, request limits).
