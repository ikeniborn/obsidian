# SSL/TLS

The Obsidian Sync Server secures all external traffic with Let's Encrypt certificates obtained via certbot. `scripts/ssl-setup.sh` installs certbot, opens UFW port 80 only for the challenge, runs `certbot certonly --standalone`, then closes port 80 and installs renewal hooks. Certificates feed the nginx templates (TLSv1.2+/HSTS) documented in [[nginx-proxy#Config Generation]].

## Certificate Acquisition

Leads with the flow: `obtain_certificate()` sources `/opt/notes/.env` for `CERTBOT_EMAIL` and `NOTES_DOMAIN`, skips renewal if the existing cert is valid >30 days, stops any running nginx to free port 80, and runs `certbot certonly --standalone`. A `CERTBOT_STAGING=true` flag switches to Let's Encrypt's test environment.

`obtain_certificate()` (`scripts/ssl-setup.sh:85`):

1. Validates `CERTBOT_EMAIL` and `NOTES_DOMAIN` from `/opt/notes/.env`.
2. If `/etc/letsencrypt/live/${NOTES_DOMAIN}` exists, checks `openssl x509 ... -checkend 2592000` (30 days); if still valid, returns early.
3. **Staging** — when `CERTBOT_STAGING=true`, adds `--staging` so issuance uses Let's Encrypt's test CA (untrusted certs, no rate limits) for safe dry runs.
4. Opens port 80 (see below), stops nginx (Docker container or systemd service), then runs:
   ```bash
   certbot certonly --standalone --non-interactive --agree-tos \
     --email "${CERTBOT_EMAIL}" --domain "${NOTES_DOMAIN}" ${staging_flag}
   ```
5. Restarts nginx, closes port 80, and errors out on a non-zero certbot exit code.

`main()` runs `install_certbot` → `create_ufw_hooks` → `obtain_certificate` → `verify_certificate` → `setup_auto_renewal`. `verify_certificate()` confirms the cert is valid for at least 24 hours (`-checkend 86400`) and prints the expiry date. `install_certbot()` installs the `certbot` apt package if missing. This script is invoked during full deployment — see [[deployment#Deployment Orchestration]].

## UFW Port 80 Handling

Leads with the security model: port 80 stays closed normally and is opened only for the brief HTTP-01 challenge, then closed again. During initial acquisition `obtain_certificate()` runs `ufw allow 80/tcp` before certbot and `ufw delete allow 80/tcp` after. The same open/close discipline is encoded in the renewal hooks. Firewall policy: [[firewall-security#UFW Configuration]].

The `--standalone` certbot plugin binds its own temporary web server to port 80 to answer the ACME HTTP-01 challenge, so any nginx already holding port 80 must be stopped first. `obtain_certificate()`:

- Opens port 80: `sudo ufw allow 80/tcp comment 'Certbot initial setup'`, then `sleep 2`.
- Detects and stops a running nginx — a Docker container matching `nginx` (`docker stop`) or the systemd `nginx` service (`systemctl stop`).
- After certbot finishes (success or failure), restarts the same nginx and runs `sudo ufw delete allow 80/tcp` to re-close port 80.

This guarantees the firewall returns to its locked-down state even if issuance fails.

## Renewal Hooks

Leads with automation: `create_ufw_hooks()` writes certbot pre/post hooks that automate the port-80 open/close and nginx stop/start cycle for unattended renewals, mirroring the manual acquisition logic. These coexist with fail2ban UFW rules — see [[firewall-security#Certbot Hooks]].

`create_ufw_hooks()` (`scripts/ssl-setup.sh:34`) installs two executable scripts:

- **Pre-hook** `/etc/letsencrypt/renewal-hooks/pre/ufw-open-80.sh`:
  - `ufw allow 80/tcp comment 'Certbot renewal (temporary)'`, `sleep 2`.
  - Sources `/opt/notes/.env`, and if a container named `${NGINX_CONTAINER_NAME:-notes-nginx}` is running, `docker stop`s it and touches `/tmp/certbot-nginx-was-running`.
- **Post-hook** `/etc/letsencrypt/renewal-hooks/post/ufw-close-80.sh`:
  - `ufw delete allow 80/tcp`.
  - If the marker file exists, `docker start`s the nginx container and removes the marker.

Both are `chmod +x`. certbot runs every hook in these directories automatically on each renewal attempt, so port 80 is opened just-in-time and re-closed afterward without manual intervention.

## Expiration Monitoring

Leads with the health check: `scripts/check-ssl-expiration.sh` reports days remaining on the live certificate and signals urgency via exit codes — exit 2 when under 7 days, exit 0 otherwise (with a NOTICE under 30 days). Suitable for cron-based alerting.

`scripts/check-ssl-expiration.sh`:

1. Sources `/opt/notes/.env` and requires `NOTES_DOMAIN`.
2. Reads `openssl x509 -in /etc/letsencrypt/live/${NOTES_DOMAIN}/fullchain.pem -noout -enddate`.
3. Computes `DAYS_LEFT` from the expiry epoch vs now.
4. Prints domain, expiry date, and days left, then:
   - `< 7` days → `WARNING`, **exit 2**.
   - `< 30` days → `NOTICE`, exit 0.
   - otherwise → `OK`, exit 0.

The distinct exit 2 lets monitoring wrappers escalate only the urgent case.

## Renewal Testing

Leads with verification: `scripts/test-ssl-renewal.sh` proves the renewal pipeline (including the UFW hooks) works without issuing a real certificate. It asserts port 80 is closed before, runs `certbot renew --dry-run`, then asserts port 80 is closed again afterward.

`scripts/test-ssl-renewal.sh`:

1. Errors if `certbot` is not installed.
2. Pre-check: `ufw status` must NOT show `80/tcp ... ALLOW` (port 80 closed = correct starting state).
3. Runs `sudo certbot renew --dry-run`, teeing output to `/tmp/certbot-renewal-test.log`.
4. Post-check (`sleep 2`): port 80 must again be closed — if it is still open, the **post-hook failed** and the test errors.

A passing run confirms the pre/post hooks open and re-close port 80 correctly around a renewal. `ssl-setup.sh` also exposes an internal `test_renewal_dry_run()` and `setup_auto_renewal()` that verifies the systemd `certbot.timer` (or a certbot cron job) is active — certbot auto-renews certificates roughly every 60 days. The nginx config that consumes these certs is generated per [[nginx-proxy#Config Generation]].
