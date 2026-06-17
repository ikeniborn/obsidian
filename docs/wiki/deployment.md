# Deployment

## Deployment Orchestration

`deploy.sh` orchestrates the full deployment: validate `.env` and UFW, prepare the network, rsync files to `/opt/notes`, set up fail2ban, deploy the selected backend, then configure nginx, SSL, apply config, and validate. Backends deploy before nginx so DNS resolution works.

The entry point `main()` (deploy.sh:741) runs this sequence:

1. `check_env_file` (deploy.sh:88) — sources `/opt/notes/.env`, requires `NOTES_DOMAIN`, `COUCHDB_PORT`, `COUCHDB_USER`, `COUCHDB_PASSWORD`, `CERTBOT_EMAIL`, `NETWORK_NAME`, `NETWORK_MODE`. See [[setup#Environment Generation]].
2. `check_ufw_configured` (deploy.sh:123) — verifies UFW is active and warns if port 443 is closed. See [[firewall-security#fail2ban Integration]].
3. `prepare_network` (deploy.sh:192) — confirms `NETWORK_NAME`/`NETWORK_MODE`; auto-detects shared vs isolated when `NETWORK_MODE` is empty. See [[networking#Network Modes]].
4. `sync_deployment_files` (deploy.sh:288) — previews and applies an rsync sync (`rsync_deployment_files` in deploy-helpers.sh) from the repo to `/opt/notes`, excluding `.env`, `data/`, `backups/`, SSL dirs, etc.
5. `setup_fail2ban` (deploy.sh:141) — runs `/opt/notes/scripts/fail2ban-setup.sh` non-blocking. See [[firewall-security#fail2ban Integration]].
6. Backend deploy (see [[deployment#Backend Deployment]]).
7. `setup_nginx` (deploy.sh:234) → `setup_ssl` (deploy.sh:246) → `verify_ssl` (deploy.sh:258) → `apply_nginx_config` (deploy.sh:276). See [[nginx-proxy#Nginx Detection]] and [[ssl-tls#Certificate Acquisition]].
8. `validate_deployment` (deploy.sh:590), then `save_deployment_lockfile` and `display_summary`.

A `deployment.lock` JSON file (`save_deployment_lockfile`, deploy-helpers.sh:205) records git commit, image digests, and config checksums; `show_deployment_diff` (deploy-helpers.sh:256) prints what changed since the previous deployment. The `--force-pull` flag (deploy.sh:707) forces image pulls.

This flow aligns with [[architecture#Deployment Flow]].

## Image Prepull

Base images are pulled via `docker pull` before `docker compose build`, so they go through the Docker daemon's proxy. This works around BuildKit's proxy limitation: `docker build` uses a separate `buildkitd` daemon that does NOT inherit the daemon proxy. See [[networking#Docker Proxy]].

Three prepull functions select images per backend:

- `prepull_couchdb_images` (deploy.sh:492) — `couchdb:3.3`.
- `prepull_serverpeer_images` (deploy.sh:320) — `denoland/deno:bin` and `node:22.14-bookworm-slim`.
- `prepull_nostr_relay_images` (deploy.sh:426) — `scsibug/nostr-rs-relay:latest`.

Each calls `smart_docker_pull` (deploy-helpers.sh:181) passing `FORCE_PULL`. Because images are already local after prepull, `deploy_couchdb` skips `docker compose pull` and `deploy_serverpeer` builds from the cached base images. On pull failure the functions only warn and suggest checking the daemon proxy (`sudo systemctl show --property=Environment docker | grep -i proxy`), letting deployment proceed with cached images.

## Image Update Detection

`smart_docker_pull` avoids unnecessary pulls by comparing the local and remote **Image ID** (Config.Digest) — the same value `docker pull` itself checks. If they match, the pull is skipped; this matches Docker's native behavior even for multi-arch images.

The comparison chain lives in deploy-helpers.sh:

- `get_local_image_id` (deploy-helpers.sh:120) — `docker inspect --format='{{.Id}}'`.
- `get_remote_image_id` (deploy-helpers.sh:127) — runs `docker manifest inspect` and extracts `config.digest` from the manifest.
- `check_image_needs_update` (deploy-helpers.sh:143) — returns "needs pull" (0) when the image is absent locally, when the local ID cannot be determined, or when local and remote IDs differ; returns "skip" (1) when up-to-date OR when the remote ID cannot be resolved (falls back to the cached local image).

`smart_docker_pull` (deploy-helpers.sh:181) short-circuits to `docker pull` when `force_pull == true`; otherwise it defers to `check_image_needs_update`. Manifest digest is deliberately NOT used because it differs across multi-arch images, whereas the config-based Image ID is stable.

## Backend Deployment

After file sync and fail2ban, `main()` (deploy.sh:769) branches on `SYNC_BACKEND` (default `couchdb`): `both` deploys CouchDB + coturn + Nostr relay + ServerPeer; `serverpeer` deploys coturn + Nostr relay + ServerPeer; otherwise CouchDB only. Each backend waits for container health before continuing.

Per-backend deploy functions:

- `deploy_couchdb` (deploy.sh:508) — prepulls `couchdb:3.3`, exports `NETWORK_*` and `COUCHDB_*` vars, runs `docker compose -f docker-compose.notes.yml up -d`. Health via `wait_for_couchdb_healthy` (deploy.sh:538). See [[couchdb-backend#Container Definition]].
- `deploy_serverpeer` (deploy.sh:344) — first runs `generate-serverpeer-compose.sh` to produce `docker-compose.serverpeers.yml`, creates each vault dir, prepulls images, then `docker compose ... build` and `up -d`. See [[deployment#Image Prepull]] and [[serverpeer-backend#Multi-Vault Support]].
- `deploy_nostr_relay` (deploy.sh:442) — copies `nostr-relay/config.toml` to `/opt/notes`, prepulls the relay image, runs `docker-compose.nostr-relay.yml` (WebSocket signaling for P2P).
- `setup_coturn` (deploy.sh:161) — runs `coturn-setup.sh` non-blocking for TURN/STUN.

`generate-serverpeer-compose.sh` reads `VAULT_COUNT` from `/opt/notes/.env` and emits one `serverpeer-<name>` service per vault, each built from `./serverpeer/Dockerfile`, bound to `127.0.0.1:${VAULT_i_PORT}:3000`, mounting `${VAULT_i_VAULT_DIR}:/app/vault`, attached to the `notes-network` external network, with a `pgrep -f 'deno.*main.ts'` healthcheck and 0.5 CPU / 512M limits. Backends deploy before nginx so nginx can resolve their container names. See [[architecture#Deployment Flow]].

## Deployment Validation

`validate_deployment` (deploy.sh:590) confirms the deployment is healthy: required `.env` vars are present, the Docker network exists, the CouchDB container is running and attached to the network, nginx (if a Docker container) is on the same network and can reach CouchDB, and the CouchDB `/_up` endpoint responds.

Steps in order:

1. `validate_env_variables` (deploy.sh:563) — requires `NETWORK_NAME`, `NETWORK_MODE`, `COUCHDB_CONTAINER_NAME`, `NOTES_DOMAIN`, `COUCHDB_PASSWORD`.
2. Network existence check via `docker network ls`.
3. CouchDB container running (`docker ps`) and connected via `docker network inspect`.
4. If a Docker nginx container is present, verifies it is on the network and runs `validate_network_connectivity` (an in-container `ping` from nginx to CouchDB; see [[networking#Network Modes]]). A systemd/standalone nginx is accepted without this check.
5. CouchDB health: up to 10 attempts of `curl -sf -u $COUCHDB_USER:$COUCHDB_PASSWORD http://0.0.0.0:5984/_up`.

On failure `main()` aborts before saving the lockfile. `display_summary` (deploy.sh:669) then prints the domain, CouchDB status, detected nginx type (`nginx-setup.sh --detect-only`), cert path, and useful commands.
