# Installation

System bootstrap performed by `install.sh`. It validates Docker prerequisites, installs Python/boto3, rsync, and coturn, ensures a swap cushion on low-RAM hosts, optionally configures UFW, and creates the `/opt/notes` directory tree. Must run as root. Followed by [[setup#Environment Generation]].

## Dependency Installation

`install.sh` is the first script in the deployment chain. It runs with `set -e`/`set -u`, requires root (`check_root` aborts if `$EUID != 0`), and logs every step to `/var/log/notes_install.log`. Its job is to make a fresh host ready for `setup.sh` and `deploy.sh`.

The `main()` flow executes in order: root check, Docker validation, Docker Compose validation, then non-fatal environment checks (UFW, nginx detection, port availability), directory creation, Python dependency install, coturn install, `ensure_swap`, and an optional UFW prompt. Validation failures (Docker missing/stopped, Compose missing) call `error()` which prints guidance and exits 1; environment checks only emit `warning()`.

Python dependencies are installed by `install_python_deps()` (lines 245-269): it ensures `python3` is present, installs `python3-boto3` via apt **only if** `python3 -c "import boto3"` fails, and installs `rsync`. boto3 comes from the system package (not pip) to comply with PEP 668 externally-managed environments. boto3 backs the S3 backup uploads, and rsync is used for deployment synchronization.

After installation completes, the script prints next steps pointing to `./setup.sh` then `./deploy.sh`. See [[setup#Environment Generation]] for the configuration stage and [[architecture#Deployment Flow]] for the full chain.

## Docker Setup

`install.sh` validates an existing Docker installation rather than installing Docker itself. `check_docker()` (lines 88-109) requires the `docker` binary on PATH and that `docker ps` succeeds (daemon running); if either fails it errors out with copy-paste install/start instructions (`curl -fsSL https://get.docker.com | sh`, `systemctl start docker`).

`check_docker_compose()` (lines 111-129) verifies Docker Compose v2 via `docker compose version` and reports the detected version with `docker compose version --short`. The error message notes Compose v2 ships bundled with modern Docker and points to `docker-compose-plugin` for manual install.

Two further non-fatal checks run after the core validations: `detect_nginx()` (lines 150-183) probes for nginx running in Docker, via systemd, or as a bare process, writing results to `/tmp/nginx_detected` and `/tmp/nginx_type`; `check_ports()` (lines 185-216) warns if ports 80 or 443 are already in use (using `netstat` or `ss`). Neither aborts installation. Docker network selection itself happens later in [[setup#Environment Generation]].

## Coturn Installation

`install_coturn()` (lines 271-288) installs the coturn TURN/STUN server used for ServerPeer P2P WebRTC NAT traversal. If `turnserver` is already on PATH it reports the existing version and returns early; otherwise it runs `apt-get install -y coturn`.

After install it enables the service in `/etc/default/coturn` by uncommenting `TURNSERVER_ENABLED=1` via `sed`. coturn is left unconfigured at this stage — `install.sh` only installs and enables the package; credential generation, `/etc/turnserver.conf`, and the firewall ports are handled later by `setup.sh` (TURN credentials) and `deploy.sh`/`coturn-setup.sh`. See [[turn-stun-p2p#Credential Generation]].

Note: coturn is installed unconditionally for every host, even though it is only relevant when the ServerPeer backend is selected during [[setup#Backend Selection]].

## Swap Cushion

`ensure_swap()` creates a swap file on low-RAM hosts so CouchDB's Erlang VM does not get hard OOM-killed under heavy sync load (the cause of the HTTP 502 crash loop — see [[troubleshooting#HTTP 502 — CouchDB OOM crash loop]]). It is idempotent and conservative: it returns early if swap is already active or if total RAM ≥ 1536MB, and skips (with a warning) if free disk is insufficient. Otherwise it creates a 2GB `/swapfile` (`fallocate`, falling back to `dd`), `chmod 600`, `mkswap`, `swapon`, and persists it in `/etc/fstab`. Pairs with the 512M CouchDB memory limit in [[couchdb-backend#Container Definition]].

## UFW Bootstrap

`install.sh` performs a UFW status check and an optional interactive UFW setup. `check_ufw()` (lines 132-148) warns (non-fatally) if `ufw` is not installed or installed-but-inactive, recommending `scripts/ufw-setup.sh`.

Near the end of `main()` (lines 319-340), if `scripts/ufw-setup.sh` exists the script prints what UFW configuration will do (allow SSH/22, allow HTTPS/443, block other incoming traffic) and prompts `Configure UFW now? (y/N)`. On `y` it runs `bash scripts/ufw-setup.sh`; otherwise it warns the user to configure the firewall manually later. The detailed firewall rules and the TURN port additions live in [[firewall-security#UFW Configuration]].

## Directory Structure

`create_directories()` (lines 222-243) builds the `/opt/notes` deployment tree used by every other script. It runs `mkdir -p /opt/notes/{data,backups,logs/nginx}`, creating the parent plus four subdirectories.

The layout is: `data/` for CouchDB persistent storage, `backups/` for backup archives, `logs/` for application logs, and `logs/nginx/` for nginx access/error logs consumed by fail2ban. Ownership is reassigned recursively to the invoking user via `chown -R "${SUDO_USER:-$USER}"` so the non-root user owns the tree after the sudo run. Permissions are set to `755` on the root and all created subdirectories.

This directory is the consistent deployment root referenced as `NOTES_DIR=/opt/notes` across `install.sh`, `setup.sh`, and `deploy.sh`. `setup.sh` writes its `.env` here (`/opt/notes/.env`); see [[architecture#Configuration & Secrets]].
