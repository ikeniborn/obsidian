# Nginx Reverse Proxy

The Obsidian Sync Server fronts every backend with an nginx reverse proxy that terminates TLS and routes traffic over HTTP/1.1 with WebSocket support. `scripts/nginx-setup.sh` either integrates with an existing nginx (docker/systemd/standalone) or deploys its own `notes-nginx` container, generating config from backend-aware templates in `templates/`.

## Nginx Detection

Leads with auto-detection: `detect_existing_nginx()` probes for a running nginx in three forms, returning the first match (`docker` → `systemd` → `standalone`) or `none`. The result drives `main()` to integrate with the existing server or deploy `notes-nginx`. See [[deployment#Deployment Orchestration]].

`detect_existing_nginx()` (`scripts/nginx-setup.sh:19`) checks, in order:

1. **docker** — `docker ps` lists a container whose name matches `nginx`.
2. **systemd** — `systemctl is-active nginx` succeeds.
3. **standalone** — `pgrep nginx` finds a running process.
4. **none** — nothing found.

`main()` dispatches on the result:
- `docker`/`systemd`/`standalone` → `integrate_with_existing_nginx "<type>"`.
- `none` → `deploy_own_nginx`.

For an existing Docker nginx, `get_nginx_config_dir()` inspects container mounts for `/etc/nginx/conf.d` (then `/etc/nginx`). If no mount exists, `integrate_with_existing_nginx()` falls back to `docker cp`, copying the config straight into the container at `/etc/nginx/conf.d/notes.conf`. `prompt_nginx_selection()` / `detect_nginx_containers()` support interactive selection of a specific container and config directory, honoring `NGINX_CONFIG_DIR` from `/opt/notes/.env` when set.

## Config Generation

Leads with template selection: `generate_nginx_config()` reads `SYNC_BACKEND` from `/opt/notes/.env` and renders one of three templates via `envsubst`, choosing container-name vs `127.0.0.1` upstreams based on whether nginx runs in Docker. After copying the config it runs `nginx -t` and reloads. SSL is obtained separately via [[ssl-tls#Certificate Acquisition]].

`generate_nginx_config()` (`scripts/nginx-setup.sh:85`) maps backend to template:

| `SYNC_BACKEND` | Template | Output |
| --- | --- | --- |
| `both` | `templates/unified.conf.template` | `unified.conf` |
| `serverpeer` | `templates/serverpeer.conf.template` | `serverpeer.conf` |
| `couchdb` (default) | `templates/couchdb.conf.template` | `couchdb.conf` |

**Upstream resolution** — when `nginx_mode = docker`, upstreams are container names (`COUCHDB_CONTAINER_NAME` default `notes-couchdb`, `NOSTR_RELAY_UPSTREAM` default `notes-nostr-relay`, `SERVERPEER_CONTAINER_NAME` default `notes-serverpeer`); otherwise `127.0.0.1`. Location paths default to `/` (single backend) or `/couchdb` and `/serverpeer` (unified). Only the named variables are substituted by `envsubst` so literal nginx `$variables` survive.

**Apply + reload** — `integrate_with_existing_nginx()` writes the rendered file to `<config_dir>/notes.conf` (or `docker cp` into the container), then validates and reloads:
- docker: `docker exec <container> nginx -t` then `nginx -s reload` (waits up to 30s for a restarting container to stabilize).
- systemd/standalone: `sudo nginx -t` then `sudo systemctl reload nginx`; systemd installs a `sites-enabled/notes.conf` symlink when `sites-available` exists.

**Own nginx** — `deploy_own_nginx()` renders `templates/docker-compose.nginx.template` to `/opt/notes/docker-compose.nginx.yml`, pre-pulls `nginx:alpine` (respecting the Docker daemon proxy), writes the initial config to `/opt/notes/nginx/notes.conf`, brings the container up, and validates network connectivity to the backend(s). The compose template mounts `notes.conf` read-only, `/etc/letsencrypt:ro`, and `/opt/notes/logs/nginx` (required for fail2ban — see [[firewall-security#UFW Configuration]]), attaching to the external `${NETWORK_NAME}` per [[architecture#Network Architecture]].

## CouchDB Template

Leads with the design stance: `templates/couchdb.conf.template` is an HTTP reverse proxy that intentionally **exceeds** the official CouchDB nginx recommendation — adding `keepalive 32`, WebSocket upgrade, HTTP/1.1, `client_max_body_size 1024M`, and forwarding headers. Do NOT blindly apply the official CouchDB docs. Backend config: [[couchdb-backend#CouchDB Configuration]].

Key elements of `templates/couchdb.conf.template`:

- **Upstream** — `upstream couchdb_backend { server ${COUCHDB_UPSTREAM}:5984 max_fails=0; keepalive 32; }`. The `keepalive 32` connection pool cuts latency by reusing connections.
- **HTTP→HTTPS** — port 80 server returns `301` to `https://$host$request_uri`.
- **TLS** — `listen 443 ssl; http2 on;`, `ssl_protocols TLSv1.2 TLSv1.3`, `ssl_ciphers HIGH:!aNULL:!MD5`, HSTS `max-age=31536000`. Certs at `/etc/letsencrypt/live/${NOTES_DOMAIN}/`.
- **Location `${COUCHDB_LOCATION}`** — strips the prefix (`rewrite ^${COUCHDB_LOCATION}(.*)$ /$1 break;`), then `proxy_pass http://couchdb_backend`.
- **WebSocket** — a `map $http_upgrade $connection_upgrade` block plus `proxy_http_version 1.1` and `Upgrade`/`Connection` headers. This is **critical** for the CouchDB `_changes` feed real-time sync; the official CouchDB config lacks it and breaks live sync.
- **Headers** — `Host`, `X-Real-IP`, `X-Forwarded-For`, `X-Forwarded-Proto`; `proxy_buffering off`; `proxy_redirect off`.
- **`client_max_body_size 1024M`** — raised from 50M: LiveSync sends large `_bulk_docs` batches during initial sync/rebuild that exceed 50M, producing nginx `413` (the official config omits the directive entirely). CouchDB itself allows up to `chttpd/max_http_request_size` (~4G); the per-document cap is `max_document_size` (50M). See [[troubleshooting#HTTP 413 — Request Entity Too Large]].

## ServerPeer Template

Leads with purpose: `templates/serverpeer.conf.template` is a pure WebSocket (WSS) proxy to the livesync-serverpeer backend on port 3000, with 7-day idle timeouts for long-lived connections. It is selected when `SYNC_BACKEND=serverpeer`. ServerPeer is legacy/frozen — production runs CouchDB. See [[serverpeer-backend#Container Build]].

Elements of `templates/serverpeer.conf.template`:

- **Upstream** — `upstream serverpeer_backend { server ${SERVERPEER_UPSTREAM}:3000 max_fails=0; keepalive 32; }`.
- **HTTP→HTTPS redirect** and the same TLS/HSTS block as the CouchDB template (`TLSv1.2`/`1.3`, `HIGH:!aNULL:!MD5`).
- **Location `${SERVERPEER_LOCATION}`** — strips the prefix, `proxy_pass http://serverpeer_backend`.
- **WebSocket upgrade** — `proxy_http_version 1.1`, `Upgrade $http_upgrade`, `Connection "upgrade"` (hardcoded, since every request is a WebSocket).
- **7-day timeouts** — `proxy_connect_timeout`, `proxy_send_timeout`, `proxy_read_timeout` all set to `7d` so persistent sync sockets are not dropped.
- **Headers** — `Host`, `X-Real-IP`, `X-Forwarded-For`, `X-Forwarded-Proto`; `proxy_buffering off`.

## Unified Template

Leads with the dual-backend layout: `templates/unified.conf.template` serves CouchDB and the Nostr relay simultaneously on separate location blocks (`${COUCHDB_LOCATION}` and `${SERVERPEER_LOCATION}`), selected when `SYNC_BACKEND=both`. The relay endpoint carries WebRTC signaling for P2P — see [[turn-stun-p2p#Nostr Relay Signaling]].

Elements of `templates/unified.conf.template`:

- **Two upstreams** — `couchdb_backend` on `${COUCHDB_UPSTREAM}:5984` and `nostr_relay_backend` on `${NOSTR_RELAY_UPSTREAM}:7000`, both `keepalive 32`.
- **Single TLS server** on port 443 (`http2 on`, TLSv1.2/1.3, HSTS) sharing the `${NOTES_DOMAIN}` certificate.
- **`location ${COUCHDB_LOCATION}`** (default `/couchdb`) — CouchDB HTTP proxy with the `map`-driven `$connection_upgrade`, forwarding headers, and `client_max_body_size 1024M`.
- **`location ${SERVERPEER_LOCATION}`** (default `/serverpeer`) — proxies to the **Nostr relay** (not ServerPeer directly), used as the WebSocket signaling channel for P2P WebRTC, with 7-day timeouts.
- **`location = /`** — returns a `200` plain-text info page listing the available backends and their paths.

**Warning:** Across all three templates, the project deliberately diverges from the official CouchDB nginx recommendation. The official config lacks WebSocket support (breaking real-time `_changes` sync), omits `client_max_body_size` (413 errors on large files), and uses a `proxy_pass $uri` rewrite that produces broken URLs. Do not replace these templates with the upstream example.
