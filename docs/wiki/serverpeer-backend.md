# ServerPeer Backend (Legacy)

> **LEGACY / FROZEN.** This entire backend is no longer actively maintained. Production deployments run the CouchDB backend (see [[architecture#Dual Sync Backends]]). ServerPeer is preserved for reference and existing P2P installs only — do not build new deployments on it.

The livesync-serverpeer backend is a Deno-based P2P sync peer that acts as an always-on buffer for Obsidian Self-hosted LiveSync. It uses WebSocket relay (Nostr) signaling plus WebRTC for direct peer connections, storing notes in a filesystem vault rather than a database.

## Container Build

Built from `serverpeer/Dockerfile`: a two-stage image that copies the Deno binary from `denoland/deno:bin` into a `node:22.14-bookworm-slim` base, then clones and patches upstream livesync-serverpeer at build time. Listens on port 3000. **Legacy** — see [[serverpeer-backend#Legacy Status]].

Real build steps (`serverpeer/Dockerfile`):
- Stage 1 `FROM denoland/deno:bin AS deno-bin`; stage 2 `FROM node:22.14-bookworm-slim`, with `COPY --from=deno-bin /deno /usr/local/bin/deno`.
- Installs `git curl procps` via apt, then `git clone https://github.com/vrtmrz/livesync-serverpeer.git --recursive` into `/app/livesync-serverpeer`.
- Applies two P2P fixes (see [[serverpeer-backend#P2P Patch]]): the `fix-p2p-enabled.patch` file, then a `sed` insert adding `P2P_Enabled: "SLS_SERVER_PEER_P2P_ENABLED"` to `envToSetting` in `src/types.ts`.
- Runs `deno task install || deno install --allow-scripts`, creates `/app/vault`, `EXPOSE 3000`.
- `CMD ["deno", "task", "main"]`.

Because ServerPeer is a P2P client rather than an HTTP server, the `HEALTHCHECK` does not probe an endpoint — it runs `pgrep -f "deno.*main.ts"` to confirm the Deno process is alive. The same process-based health check is mirrored in the compose files. Build images with `docker compose -f docker-compose.serverpeer.yml build --no-cache`. Nginx proxies this WebSocket backend (see [[nginx-proxy#ServerPeer Template]]); deployment is orchestrated per [[deployment#Backend Deployment]].

## P2P Patch

Two upstream bugs prevented P2P from auto-enabling. `serverpeer/fix-p2p-enabled.patch` reorders settings so `P2P_Enabled`/`P2P_AutoStart`/`P2P_AutoBroadcast = true` are set on `conf` *before* `globalVariables.set("settings", conf)`. `serverpeer/validate-patch.sh` verifies the patch applies cleanly against current upstream.

Patch details:
- **Bug 1** (`src/ServerPeer.ts`): upstream called `globalVariables.set("settings", conf)` first, so the later `conf.P2P_Enabled = true` assignments never reached the saved settings. The patch moves `globalVariables.set(...)` to *after* the three P2P flag assignments.
- **Bug 2** (`src/types.ts`): the `envToSetting` map lacked a `P2P_Enabled` entry, so the `SLS_SERVER_PEER_P2P_ENABLED` env var was ignored. Fixed via the Dockerfile `sed` insert (not the patch file).

`serverpeer/validate-patch.sh` is a standalone verifier: it shallow-clones upstream into `/tmp/test-serverpeer-validation`, applies `fix-p2p-enabled.patch`, then asserts (1) the explanatory comment is present and (2) the `globalVariables.set` line number is greater than the `conf.P2P_Enabled = true` line number — exiting non-zero if either check fails. Run it after upstream changes before rebuilding.

## Multi-Vault Support

ServerPeer supports multiple independent vaults, each with its own Room ID (Group ID), passphrase, container, port and storage, all sharing one Nostr relay. `scripts/configure-multiple-vaults.sh` interactively provisions N vaults; `docker-compose.serverpeer.yml` and `docker-compose.serverpeer-personal.yml` define single/personal instances.

Compose services:
- `docker-compose.serverpeer.yml` — service `serverpeer`, container `${SERVERPEER_CONTAINER_NAME:-notes-serverpeer}`, port `127.0.0.1:${SERVERPEER_PORT:-3000}:3000`, vault volume `${SERVERPEER_VAULT_DIR:-/opt/notes/serverpeer-vault}:/app/vault`. Resources: 0.1-0.5 CPU, 128M-512M memory. Network from `.env` (`NETWORK_NAME`/`NETWORK_EXTERNAL`, see [[networking#Network Modes]]).
- `docker-compose.serverpeer-personal.yml` — service `serverpeer-personal`, container `${SERVERPEER_PERSONAL_CONTAINER_NAME:-notes-serverpeer-personal}` on port 3001, using `SERVERPEER_PERSONAL_ROOMID`/`_PASSPHRASE`/`_VAULT_NAME`. Shares `SERVERPEER_RELAYS` with the main instance.

Both inject settings via `SLS_SERVER_PEER_*` environment variables (APPID, ROOMID, PASSPHRASE, RELAYS, NAME, AUTOBROADCAST, AUTOSTART, VAULT_NAME).

`scripts/configure-multiple-vaults.sh` (called from `setup.sh`):
- Prompts for vault count; per vault auto-generates a Room ID (`openssl rand -hex 3` formatted `xx-xx-xx`) and a 32-hex passphrase, assigns port `3000 + i`, container `notes-serverpeer-<name>` and dir `/opt/notes/serverpeer-vault-<name>`, exporting `VAULT_<i>_*` variables.
- Sets a shared relay `SERVERPEER_RELAYS=wss://${NOTES_DOMAIN}${SERVERPEER_LOCATION:-/serverpeer}`, `SERVERPEER_APPID=self-hosted-livesync`, autostart/autobroadcast true, and Nostr relay vars (port 7000, container `notes-nostr-relay`).

The compose file for many vaults is produced by `generate-serverpeer-compose.sh`. P2P NAT traversal relies on STUN/TURN — see [[turn-stun-p2p#TURN/STUN Purpose]] and [[turn-stun-p2p#NAT Traversal Flow]]. Vault data is archived by [[backup-system#ServerPeer Backup]].

## Vault Documentation

`scripts/generate-vault-docs.sh` reads `/opt/notes/.env` and emits `docs/VAULT-PARAMETERS.md` — a human-readable sheet of Obsidian connection parameters (Relay URL, Group ID, Passphrase, per-device Peer IDs) for every configured vault, plus security and troubleshooting notes.

Behavior:
- Sources `.env` (errors out if missing), uses `VAULT_COUNT` (default 1) and the `VAULT_<i>_NAME/ROOMID/PASSPHRASE/CONTAINER` variables.
- Writes a shared relay section, then one section per vault containing the Obsidian P2P config block and example Device Peer IDs (`laptop-<name>`, `phone-<name>`, `tablet-<name>`), plus `docker ps`/`docker logs` commands for that vault's container.
- Appends fixed Security Notes (keep Group ID/Passphrase secret; relay URL is shareable) and Troubleshooting sections (connection checks, Nostr relay log inspection).

This output is the operator's reference for onboarding devices to each P2P room.

## Legacy Status

**This backend is frozen.** It is documented for completeness and to support pre-existing installs, but production runs CouchDB and ServerPeer receives no active development. Treat its scripts and the `serverpeer-backup.sh` design as legacy.

Concrete implications:
- Production sync uses the CouchDB backend; ServerPeer is not the recommended path for new deployments (see [[architecture#Dual Sync Backends]]).
- The legacy backup (`scripts/serverpeer-backup.sh`) still uses the old local-tar.gz design and was **not** migrated to the newer direct-streaming approach used by the CouchDB backup — see [[backup-system#ServerPeer Backup]].
- ServerPeer validation is covered by a minimal legacy test, [[testing#ServerPeer Tests]].
- The P2P patch may drift against upstream over time; `validate-patch.sh` ([[serverpeer-backend#P2P Patch]]) is the guard, but upstream is not regularly tracked.

When in doubt, prefer the CouchDB backend and consult [[deployment#Backend Deployment]].
