# Networking

## Network Modes

The server supports three Docker network modes recorded in `/opt/notes/.env` as `NETWORK_MODE`: **shared** (join an existing network for integration with other services), **isolated** (create a dedicated `obsidian_network` with an auto-picked subnet), and **custom**. `network-manager.sh` manages all three.

The `.env` variables that drive networking:

- `NETWORK_MODE` — `shared` / `isolated` / `custom`.
- `NETWORK_NAME` — the Docker network name (e.g. an existing network in shared mode, `obsidian_network` in isolated).
- `NETWORK_SUBNET` — subnet for isolated mode (see [[networking#Subnet Selection]]).
- `NETWORK_EXTERNAL` — `true` in shared mode (network is pre-existing/external), interpolated into compose files as `networks.*.external`.

`network-manager.sh` exposes commands via its `main()` dispatcher (network-manager.sh:225): `detect_mode`, `list_networks`, `prompt_network_selection`, `find_free_subnet`, `validate_subnet`, `create_network`, and `validate_connectivity`. `validate_network_connectivity` (network-manager.sh:195) checks both containers are attached to the network and runs an in-container `ping`; it is consumed by [[deployment#Deployment Validation]]. In `prepare_network` (deploy.sh:192) the deploy flow reuses these to confirm the mode and fail early if a configured shared network is missing. See [[architecture#Network Architecture]].

## Network Auto-Detection

When no network mode is preset, the tooling defaults to **isolated**. `detect_network_mode` (network-manager.sh:40) lists custom Docker networks (excluding `bridge`/`host`/`none`) and always returns `isolated`, advising the user to run `setup.sh` to opt into shared mode with an existing network.

`prepare_network` in `deploy.sh` (deploy.sh:207) performs the runtime auto-detection: if `NETWORK_MODE` is empty in `.env`, it checks whether `NETWORK_NAME` already exists via `docker network ls`. If it exists, mode becomes `shared`; otherwise `isolated`. The decision is appended back to `/opt/notes/.env`. In shared mode it errors out if the named network does not exist.

Interactive selection is handled by `prompt_network_selection` (network-manager.sh:85), which lists existing networks (with subnet and driver, via `list_available_networks` at network-manager.sh:59) and lets the user pick an existing network (→ `shared|<name>`) or create a new one (→ `isolated|obsidian_network`). This output feeds [[setup#Environment Generation]].

## Subnet Selection

For isolated mode the subnet is auto-selected from the range **172.24.0.0/16 through 172.31.0.0/16**. `find_free_subnet` (network-manager.sh:144) iterates `172.{24..31}.0.0/16` and returns the first one not already used by any Docker network.

`validate_subnet` (network-manager.sh:128) inspects all existing networks' `IPAM.Config` subnets and fails if the candidate is already in use. `create_network` (network-manager.sh:160) auto-detects a free subnet when none is passed, derives the gateway by replacing `0/16` with `1` (e.g. `172.25.0.0/16` → gateway `172.25.0.1`), and runs `docker network create --driver bridge --subnet ... --gateway ... <name>`. The resulting subnet is stored as `NETWORK_SUBNET` and interpolated into `docker-compose.notes.yml`.

## Docker Proxy

`configure-docker-proxy.sh` configures the Docker daemon to pull images through an HTTP/HTTPS/SOCKS5 proxy by writing `/etc/systemd/system/docker.service.d/http-proxy.conf`, then reloading systemd and restarting Docker. Essential when Docker Hub is blocked or throttled. See [[setup#Docker Proxy Setup]].

`configure_docker_daemon_proxy` (configure-docker-proxy.sh:35) writes a `[Service]` block setting `HTTP_PROXY`, `HTTPS_PROXY`, and `NO_PROXY` (default `localhost,127.0.0.1,...`), then runs `systemctl daemon-reload` and `systemctl restart docker`. `verify_docker_proxy` (configure-docker-proxy.sh:63) prints `systemctl show --property=Environment docker | grep -i proxy` and test-pulls `hello-world:latest`. `remove_docker_proxy` (configure-docker-proxy.sh:79) deletes the override and restarts Docker. `main()` (configure-docker-proxy.sh:116) requires root, validates the URL matches `^(https?|socks5)://`, and supports `--remove` / `--verify` / `--help`.

**Daemon proxy vs BuildKit:** the daemon proxy applies to `docker pull` and `docker run` but NOT to `docker build` (BuildKit's `buildkitd` runs as a separate daemon and needs its own config). The deploy flow sidesteps this by pre-pulling base images through the daemon proxy before building — see [[deployment#Image Prepull]].

## DNS Hijacking Fix

Even with a proxy configured, `docker pull` can fail with a `504 Gateway Time-out` when an ISP hijacks DNS for `docker.io` and redirects to a blocked mirror — because Docker resolves DNS before applying the proxy. The fix pins correct registry IPs in `/etc/hosts`, which takes priority over DNS and bypasses the hijack.

As documented in the project (offered automatically by `setup.sh` when the proxy pull test fails), DNS resolution is attempted with multiple methods in order — `dig +short @8.8.8.8`, `nslookup ... 8.8.8.8`, `host -t A ... 8.8.8.8`, then `getent hosts` (system resolver). If all external queries are blocked, verified fallback IPs are used (with user confirmation):

- `registry-1.docker.io` → `3.226.190.193`
- `auth.docker.io` → `18.205.34.3`
- `production.cloudflare.docker.com` → `104.16.100.215`

The resolved IPs are appended to `/etc/hosts` and verified with `docker pull hello-world`. This is the runtime counterpart to the daemon-vs-BuildKit distinction above: it fixes resolution for the daemon's pulls, while [[deployment#Image Prepull]] ensures builds reuse the already-pulled images. See [[setup#Docker Proxy Setup]].
