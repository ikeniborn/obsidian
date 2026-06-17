# Testing

The project ships a set of bash validation scripts under `scripts/` covering security, SSL, nginx, CouchDB, backups and networking. `run-all-tests.sh` is the umbrella runner; focused scripts test SSL renewal, network modes, fail2ban filters, and the legacy ServerPeer backend.

## Test Suite

`scripts/run-all-tests.sh` (163 lines) is the comprehensive validator. It defines `pass`/`fail`/`info` helpers and a `run_test` wrapper that increments counters, then runs grouped checks and prints a Total/Passed/Failed summary, exiting non-zero if any test fails. Results are logged to `/tmp/obsidian-sync-test-results.txt`.

Test groups and representative checks:
- **Security**: UFW active; SSH port 22 ALLOW; HTTPS 443 ALLOW; HTTP 80 closed (see [[firewall-security#Filter Testing]]).
- **SSL/TLS**: `fullchain.pem` exists for `$NOTES_DOMAIN`; cert valid for 24h (`openssl x509 -checkend 86400`); certbot pre/post UFW hooks exist and are executable (see [[ssl-tls#Renewal Testing]]).
- **Nginx**: nginx running (docker or systemd); `nginx -t` config valid; HTTP→HTTPS redirect; `https://$NOTES_DOMAIN/_up` returns `ok`.
- **CouchDB**: container (`COUCHDB_CONTAINER_NAME`, default `notes-couchdb`) running; `localhost:5984/_up` healthy; port 5984 bound to `127.0.0.1` only.
- **Backup**: `couchdb-backup.sh` executable; backup cron job present; `s3_upload.py` executable; `boto3` importable.
- **Network**: delegates to `test-network-modes.sh` (see [[testing#Network Mode Tests]]).

It sources `/opt/notes/.env` for `NOTES_DOMAIN` and container names. Intended to run on a deployed server.

## SSL Tests

`scripts/test-ssl-renewal.sh` validates Let's Encrypt auto-renewal together with the UFW port-80 hooks. It performs a `certbot renew --dry-run` and asserts that port 80 is closed before, opened during, and closed again after renewal — proving the pre/post hooks fire correctly.

Flow (`test_ssl_renewal`):
1. Requires `certbot` installed (errors otherwise).
2. Asserts port 80 is **not** ALLOW in `ufw status` before the test.
3. Runs `sudo certbot renew --dry-run`, teeing output to `/tmp/certbot-renewal-test.log`.
4. After a 2s pause, re-checks `ufw status` and fails if port 80 is still open — catching a broken UFW post-hook.

The script can be sourced or run directly (guarded by `BASH_SOURCE`/`$0`). It complements the SSL group in [[testing#Test Suite]] and the renewal design in [[ssl-tls#Renewal Testing]].

## Network Mode Tests

`scripts/test-network-modes.sh` exercises both deployment network modes end-to-end by writing a synthetic `/opt/notes/.env`, running `deploy.sh`, and verifying the resulting Docker network/container wiring. It cleans up containers and networks between cases. Invoked by `run-all-tests.sh`.

Cases:
- **Isolated** (`test_isolated_mode`): writes `.env` with `NETWORK_MODE=isolated`, `NETWORK_NAME=obsidian_network`; deploys; asserts `obsidian_network` exists and the CouchDB container is running.
- **Shared** (`test_shared_mode`): pre-creates `familybudget_familybudget` network, writes `.env` with `NETWORK_MODE=shared` pointing at it; deploys; asserts the CouchDB container is attached to that shared network via `docker network inspect`.

`cleanup()` tears down compose stacks (`docker-compose.notes.yml`, `docker-compose.nginx.yml`), removes `obsidian_network`, and deletes `.env`. Background on the modes: [[networking#Network Modes]].

## fail2ban Tests

`scripts/test-fail2ban.sh` is a root-only suite (v1.0.0) verifying fail2ban service health, custom filter syntax/matching, UFW integration and a live ban/unban cycle. It supports `--dry-run` and `--filter <name>` flags and tests the `notes-couchdb` and `notes-serverpeer` filters.

Test functions:
- `test_service_running` — `systemctl is-active fail2ban`.
- `test_filter_syntax` — runs `fail2ban-regex /dev/null <filter>` to confirm the filter parses.
- `test_filter_matching` — feeds sample nginx access-log lines (401/403 auth failures plus benign 200/101 lines) through `fail2ban-regex` and confirms `Total matched > 0`; for `notes-serverpeer` the 101 Switching Protocols line must be ignored.
- `test_ufw_integration` — confirms a jail's `banaction` is `ufw`.
- `test_jail_health` — enumerates active jails from `fail2ban-client status`.
- `test_ban_cycle` (skipped in dry-run) — bans/unbans the RFC 5737 test IP `198.51.100.1`, checking the UFW rule appears then disappears.

See the jail/filter design in [[firewall-security#Filter Testing]].

## ServerPeer Tests

`scripts/test-serverpeer.sh` is a minimal, **legacy** smoke test for the frozen P2P backend (see [[serverpeer-backend#Legacy Status]]). It checks the container is up, probes an HTTP `/health` endpoint, verifies the vault directory, and runs the legacy backup script.

Five sequential checks (each `exit 1` on failure):
1. Container — `docker ps | grep notes-serverpeer`.
2. Health — `docker exec notes-serverpeer curl -sf http://localhost:3000/health`.
3. Vault — `test -d /opt/notes/serverpeer-vault`.
4. Backup — runs `scripts/serverpeer-backup.sh` (legacy local-tar.gz design; see [[backup-system#ServerPeer Backup]]).
5. S3 — if `S3_ACCESS_KEY_ID` is set, runs `s3_upload.py --test`.

Note: this script's `/health` probe predates the Dockerfile's process-based `pgrep` health check, reflecting its legacy status. Because the ServerPeer backend is frozen and production runs CouchDB, this test is not part of the routine validation flow.
