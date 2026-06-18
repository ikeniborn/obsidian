# Firewall & Security

Network-layer defense for the Obsidian Sync Server: a static UFW ruleset (minimal attack surface) combined with fail2ban (v5.2.0) for dynamic IP banning. UFW provides the static allowlist; fail2ban inserts deny rules through UFW in response to malicious log patterns. Related: [[turn-stun-p2p#TURN/STUN Purpose]], [[ssl-tls#Renewal Hooks]].

## UFW Configuration

`scripts/ufw-setup.sh` builds a deny-by-default firewall: it allows SSH and HTTPS (443), opens TURN/STUN ports when ServerPeer is used, and leaves port 80 closed. Port 80 is only opened transiently during certbot renewal — see [[ssl-tls#UFW Port 80 Handling]].

Defaults set by `configure_ufw_defaults()` (ufw-setup.sh:131): `ufw default deny incoming` and `ufw default allow outgoing`.

Allowed inbound rules:
- **SSH** — `add_ssh_rule()` (line 146). Port auto-detected from `/etc/ssh/sshd_config` via `detect_ssh_port()` (line 106), defaulting to 22. Comment: `SSH access`.
- **HTTPS** — `add_https_rule()` (line 167) opens `443/tcp`, comment `HTTPS for Obsidian Sync`.
- **TURN/STUN** — `add_turn_rules()` (line 186) opens `3478/udp`, `3478/tcp`, and `49152:65535/udp` (relay). Always added by this script regardless of backend; the CLAUDE.md note that these are conditional on ServerPeer reflects the orchestration in `setup.sh`/`deploy.sh`. See [[turn-stun-p2p#NAT Traversal Flow]].

Port 80 (HTTP) is deliberately never added (line 384): `Port 80 (HTTP) will remain BLOCKED`. All other inbound traffic is dropped by the default-deny policy.

Safety mechanisms:
- `check_rule_exists()` (line 234) makes rule additions idempotent — existing rules are skipped, avoiding duplicate entries.
- `verify_ssh_rule_exists()` (line 214) aborts before `ufw enable` if no SSH rule is present, preventing lockout.
- If UFW is already active with both SSH and HTTPS present, no reset is done (only missing rules are added). Otherwise the user is prompted via `confirm_reset()`.
- `--dry-run` flag previews all actions without applying them. Must run as root.

## Certbot Hooks

UFW keeps port 80 closed permanently and relies on certbot pre/post renewal hooks to open it only for the duration of an ACME HTTP-01 challenge, then close it again. This logic lives with the SSL tooling, not `ufw-setup.sh`.

`scripts/ufw-setup.sh` itself never opens port 80. The temporary-open behavior is implemented as certbot renewal hooks installed by the SSL setup. For the hook mechanics (pre-hook opens 80, post-hook closes it) see [[ssl-tls#Renewal Hooks]] and [[ssl-tls#UFW Port 80 Handling]].

This separation keeps the steady-state firewall HTTPS-only: an attacker scanning port 80 finds it closed except during the brief renewal window (every ~60 days).

## fail2ban Integration

`scripts/fail2ban-setup.sh` (v5.2.0) installs fail2ban with `banaction = ufw`, so bans are enforced by inserting UFW deny rules rather than iptables directly. It requires UFW to already be active and `/opt/notes/.env` to exist; it is wired into deployment after the UFW check — see [[deployment#Backend Deployment]].

Prerequisites enforced at start (`main()`, line 671):
- `check_ufw_active()` (line 95) — errors out if UFW is not installed or not active.
- `check_env_file()` (line 109) — requires `/opt/notes/.env`.

The global `[DEFAULT]` block in `/etc/fail2ban/jail.local` (`create_jail_local()`, line 275) sets:
- `banaction = ufw` — bans run as `ufw insert 1 deny from <IP>`, coexisting with the static UFW allowlist and the SSL renewal hooks (different rule types).
- `bantime = 3600`, `findtime = 600`, `maxretry = 5` (defaults).
- `ignoreip = 127.0.0.1/8 ::1` (localhost whitelist).

Service lifecycle: `enable_fail2ban()` (line 526) runs `systemctl enable` + `restart`; `validate_fail2ban()` (line 547) confirms the service is active, counts loaded jails, and verifies `fail2ban-client get sshd banaction` returns `ufw`.

**Docker nginx requirement:** `detect_nginx_logs()` (line 122) inspects a running Docker nginx container's mounts for `/var/log/nginx`. If no host-side volume mount exists, nginx-dependent jails are skipped with a warning to add `/opt/notes/logs/nginx:/var/log/nginx` to the compose file. fail2ban cannot read logs inside an unmounted container. Because this check runs against a *running* container, deploying fail2ban before nginx is up (or before it has produced logs) silently skips the nginx and CouchDB jails — re-run `fail2ban-setup.sh` once nginx logs exist.

**`backend = polling` (mandatory for the file-based jails):** Debian/ALT ship `/etc/fail2ban/jail.d/defaults-debian.conf` with `backend = systemd` in `[DEFAULT]`. With the systemd backend fail2ban reads the journal and **ignores `logpath`**, so a jail pointed at the bind-mounted nginx access log never sees any lines and never bans. The `notes-couchdb`, `notes-serverpeer`, and nginx jails therefore set `backend = polling` explicitly to tail the file. Symptom of the bug: `fail2ban-client status <jail>` shows `Journal matches:` and `Total failed: 0` while the access log clearly contains matching 401s.

## Jail Configuration

Four jail families protect SSH, HTTP, and the backend APIs. SSH and nginx jails use the 1-hour ban tier; the backend API jails (CouchDB / ServerPeer WSS) use a stricter 2-hour tier (3 failures in 5 minutes). Backend jails are enabled based on `SYNC_BACKEND` in `.env` — see [[setup#Backend Selection]].

Created by `create_jails()` (line 511):

- **`[sshd]`** (`create_sshd_jail()`, line 312) — `/etc/fail2ban/jail.d/sshd.local`. Reads `logpath = /var/log/auth.log`, SSH port auto-detected, `maxretry=5`, `findtime=600`, `bantime=3600`.
- **Nginx jails** (`create_nginx_jails()`, line 350) — `/etc/fail2ban/jail.d/nginx.local`. Emits only jails whose filter exists on the host: `nginx-bad-request` and `nginx-botsearch` (both read the access log and ship across versions). fail2ban 1.0+ removed `nginx-noscript`/`nginx-noproxy` and deprecated `nginx-badbots`, so the old four-filter set prevented the service from starting — those are gone. Each `maxretry=5`, `findtime=600`, `bantime=3600`, `port=http,https`, `backend=polling`. Skipped if nginx logs are not accessible.
- **`[notes-couchdb]`** (`create_couchdb_jail()`, line 412) — `/etc/fail2ban/jail.d/notes-couchdb.local`. Uses the custom `notes-couchdb` filter, `maxretry=3` (`API_MAXRETRY`), `findtime=300`, `bantime=7200`, `backend=polling`.
- **`[notes-serverpeer]`** (`create_serverpeer_jail()`, line 447) — `/etc/fail2ban/jail.d/notes-serverpeer.local`. Same 2-hour API tier.

**Backend-aware enabling** — `create_backend_aware_jails()` (line 482) sources `.env`, reads `SYNC_BACKEND` (default `couchdb`):
- `both` → CouchDB + ServerPeer jails
- `serverpeer` → ServerPeer jail only
- `couchdb` (or anything else) → CouchDB jail only

ServerPeer/WSS is a [[serverpeer-backend#Legacy Status]] backend; the corresponding jail is only relevant when it is selected.

## Filter Testing

Two custom filters are written to `/etc/fail2ban/filter.d/` and validated with `fail2ban-regex`. `notes-couchdb.conf` bans HTTP 401 on **any path** (CouchDB is reverse-proxied at the root location `/`, not `/couchdb`); `notes-serverpeer.conf` bans 401/403 on `/serverpeer` while ignoring successful WebSocket upgrades (HTTP 101). Both match nginx access-log lines — see [[nginx-proxy#ServerPeer Template]].

Filters are created unconditionally by `create_custom_filters()` (line 261) — they are harmless when their jail is disabled.

**`notes-couchdb.conf`** (`create_couchdb_filter()`, line 196):
- `failregex` matches `<HOST> ... "(GET|POST|PUT|DELETE|HEAD|OPTIONS|PROPFIND|PATCH|CONNECT) /... HTTP/..." 401` — any method/path, since CouchDB is served at root. Catches both DB brute-force (`PUT /work/... 401`) and scanner probes (`GET /mapi/ 401`).
- `ignoreregex` exempts the public `/_up` health endpoint.
- `datepattern = %%d/%%b/%%Y:%%H:%%M:%%S` — the `%%` is mandatory: fail2ban's configparser treats a lone `%` as interpolation and rejects the filter (`InterpolationSyntaxError`). `%%` unescapes to the real `%d/%b/%Y` pattern.

**`notes-serverpeer.conf`** (`create_serverpeer_filter()`, line 227):
- ServerPeer uses WSS over HTTPS (port 443). `failregex` matches `(GET|POST) /serverpeer... HTTP/..." (401|403)` — failed auth before the WebSocket upgrade.
- `ignoreregex` exempts HTTP 101 (Switching Protocols — a normal WSS handshake) and HTTP 200, so legitimate connections are never banned.

**Validation:**
- `test_fail2ban_filters()` (line 579) runs `fail2ban-regex /dev/null <filter>` after install to confirm each filter parses without error (syntax check only).
- `scripts/test-fail2ban.sh` is the standalone manual test harness for exercising filters against real or sample logs (e.g. `fail2ban-regex /var/log/nginx/access.log /etc/fail2ban/filter.d/notes-couchdb.conf`).
