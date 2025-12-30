# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Obsidian Sync Server** - production-ready self-hosted sync server for Obsidian notes with dual backend support (CouchDB or livesync-serverpeer) and flexible network architecture.

### Key Characteristics
- **Dual backend support**: Choose between CouchDB (client-server) or livesync-serverpeer (P2P)
- **Flexible networking**: Three modes - shared, isolated, custom
- **Auto-detection**: Automatically determines optimal network mode
- **Nginx integration**: Auto-detects existing nginx or deploys its own
- **Security-first**: UFW firewall, SSL/TLS, password generation
- **Automated backups**: S3-compatible storage with cron/systemd scheduling (backend-independent)

## Architecture

### Architecture Documentation

**Location:** `docs/architecture/`

Comprehensive YAML-based knowledge graph documenting all components, scripts, workflows, and architectural patterns.

**Navigation:**
- **Entry point:** `docs/architecture/index.yml` - root of the knowledge graph
- **Structure:** Hierarchical YAML files with ID-based cross-references
- **Categories:**
  - `components/` - Infrastructure (CouchDB, Nginx, Docker, UFW, Certbot, S3) and Application components
  - `scripts/` - Deployment, helper, and testing scripts with function-level documentation
  - `workflows/` - End-to-end process flows (deployment, network setup, backup, SSL renewal)
  - `patterns/` - Architectural patterns (flexible networking, nginx integration, etc.)
  - `data-flows/` - Data flow diagrams through the system
  - `network-topology/` - Network architecture diagrams (shared/isolated modes)
  - `security/` - Security architecture and threat model
  - `configurations/` - Configuration files documentation
  - `dependencies/` - Dependency graphs

**Query Examples:**
```
Q: "What scripts handle SSL certificate management?"
A: Navigate to patterns → certificate-management → check implementation.scripts
   Result: [script:ssl-setup, script:deploy]

Q: "How does deployment work?"
A: Navigate to workflows → deployment-flow → read phases
   Result: Full deployment process with all scripts and dependencies

Q: "What are the dependencies of deploy.sh?"
A: Navigate to scripts.deployment.deploy → check relationships.calls_scripts
   Result: [script:install, script:setup, script:network-manager, ...]
```

**Usage:** Claude Code can use this knowledge graph for efficient context extraction when working with the codebase. Start at `index.yml` and follow ID references to navigate between related files.

### Network Configuration

**Гибкая сетевая архитектура с двумя режимами:**

1. **Shared Mode** - интеграция с существующими сервисами
   - Network: использует существующую Docker сеть (выбирается интерактивно)
   - Примеры: `my_app_network`, `webproxy_default`, `traefik_public`
   - Nginx: может использовать существующий nginx из той же сети
   - CouchDB: в общей сети с другими сервисами

2. **Isolated Mode** - standalone deployment
   - Network: `obsidian_network` (auto-created)
   - Subnet: автовыбор свободной подсети (172.24-31.0.0/16)
   - Nginx: собственный контейнер notes-nginx
   - CouchDB: изолирован от других Docker сервисов

**Interactive Selection Logic:**
- При запуске setup.sh пользователь выбирает режим интерактивно
- Показываются все доступные Docker сети
- Пользователь может выбрать существующую сеть (shared) или создать новую (isolated)
- Аналогично для nginx - выбор существующего контейнера или создание нового
- Все выборы сохраняются в /opt/notes/.env

**Key Design Decisions:**
1. Backend ports bind to `127.0.0.1` only - no external access
2. All HTTPS traffic goes through nginx reverse proxy
3. Flexible network selection for different deployment scenarios
4. Deployment directory `/opt/notes` - consistent across all modes

### Sync Backend Options

The server supports two sync backends, selected during `setup.sh`:

**1. CouchDB (Default)** - Client-Server Architecture
- **Protocol**: HTTP REST API
- **Storage**: Database (document-oriented, CouchDB 3.3)
- **Backup**: Database dumps → tar.gz → S3 (via `couchdb-backup.sh`)
- **Port**: 5984 (localhost only)
- **Container**: `notes-couchdb` (configurable via COUCHDB_CONTAINER_NAME)
- **Use Case**: Traditional client-server sync, proven stability

**2. livesync-serverpeer** - P2P Architecture
- **Protocol**: WebSocket (WSS) relay + WebRTC P2P
- **Storage**: Headless vault (filesystem-based)
- **Backup**: Vault archive → tar.gz → S3 (via `serverpeer-backup.sh`, **NO CouchDB dependency**)
- **Port**: 3000 (localhost only)
- **Container**: `notes-serverpeer` (configurable via SERVERPEER_CONTAINER_NAME)
- **Technology**: Deno-based (https://github.com/vrtmrz/livesync-serverpeer)
- **Dependencies**: Fully containerized (Deno, Node.js, git) - NO host installation required
- **WebSocket Relay**: Uses local Nostr relay by default (ws://notes-nostr-relay:7000 internal, wss://your-domain/serverpeer/ external)
  - **Recommended**: Local relay (best performance & privacy)
  - **Alternative**: External relay (e.g., wss://exp-relay.vrtmrz.net/) - adds latency
- **P2P WebRTC**: Direct peer-to-peer connections using WebRTC
  - **STUN Server**: Google public STUN (stun:stun.l.google.com:19302) for NAT traversal
  - **TURN Server**: Local coturn server (turn:server-ip:3478) for fallback when direct connection fails
  - **NAT Traversal**: Automatic STUN/TURN selection based on network conditions
- **Use Case**: P2P synchronization with WebSocket relay, file-based storage, offline-capable

**Backend-Independent Features**:
- ✅ S3 backups (shared `s3_upload.py` script)
  - **Single backend**: Uses `S3_BACKUP_PREFIX` (couchdb-backups/ or serverpeer-backups/)
  - **Dual mode**: Uses separate prefixes (`COUCHDB_S3_BACKUP_PREFIX` and `SERVERPEER_S3_BACKUP_PREFIX`)
- ✅ Nginx reverse proxy (backend-aware templates)
- ✅ UFW firewall
- ✅ SSL/TLS (Let's Encrypt)
- ✅ Health checks and monitoring
- ✅ Cron-based backup scheduling

**Backend-Specific Commands**:

*CouchDB:*
```bash
docker logs notes-couchdb
docker compose -f docker-compose.notes.yml restart
bash /opt/notes/scripts/couchdb-backup.sh
```

*ServerPeer:*
```bash
docker logs notes-serverpeer
docker compose -f docker-compose.serverpeer.yml restart
bash /opt/notes/scripts/serverpeer-backup.sh  # NO CouchDB dependency
```

## Deployment Workflow

### Common Commands

**Container management:**
```bash
# View logs (container name from .env: COUCHDB_CONTAINER_NAME)
docker logs notes-couchdb
docker logs -f notes-couchdb  # Follow mode

# Restart CouchDB
docker compose -f docker-compose.notes.yml restart

# Stop
docker compose -f docker-compose.notes.yml down

# Health check
curl http://localhost:5984/_up
```

**Testing:**
```bash
# Run all tests (SSL, backup, deployment validation)
bash scripts/run-all-tests.sh

# Test specific components
bash scripts/test-ssl-renewal.sh
bash scripts/test-backup.sh
```

**Backup:**
```bash
# Manual backup
cd /opt/notes
bash scripts/couchdb-backup.sh

# Check backup logs
tail -f /opt/notes/logs/backup.log
```

**SSL management:**
```bash
# Check SSL expiration
bash scripts/check-ssl-expiration.sh

# Test SSL renewal (dry run)
bash scripts/test-ssl-renewal.sh
```

**TURN/STUN server management (for P2P ServerPeer):**
```bash
# Check coturn status
sudo systemctl status coturn

# View coturn logs
sudo journalctl -u coturn -f
sudo tail -f /var/log/turnserver.log

# Restart coturn
sudo systemctl restart coturn

# Test TURN connectivity (from client machine)
# Use turnutils-uclient tool (install: apt-get install coturn-utils)
turnutils_uclient -v -u obsidian -w <TURN_PASSWORD> <SERVER_IP>
```

## Production Deployment

### Sequential Deployment Flow
```bash
# Step 1: Install dependencies (Docker, UFW, Python)
sudo ./install.sh

# Step 2: Configure environment
sudo ./setup.sh  # Requires sudo for Docker proxy and TURN firewall configuration
# Prompts for:
# - Docker proxy (optional, for restricted networks/blocked Docker Hub)
#   * Supports HTTP, HTTPS, SOCKS5 proxies
#   * Configures NO_PROXY for bypassing specific addresses
# - CERTBOT_EMAIL (for Let's Encrypt)
# - NOTES_DOMAIN (e.g., notes.example.com)
# - Sync backend selection (CouchDB/ServerPeer/Both)
#   * For ServerPeer: automatically configures TURN ports in UFW
# - S3 credentials (optional)
# Generates: /opt/notes/.env

# Step 3: Deploy
./deploy.sh
# Executes:
# 1. nginx-setup.sh (detects/integrates with existing nginx)
# 2. ssl-setup.sh (obtains Let's Encrypt certificates)
# 3. Applies nginx config with SSL
# 4. Deploys selected backend (CouchDB/ServerPeer/Both)
#    - For ServerPeer: configures TURN/STUN server (coturn-setup.sh)
# 5. Validates deployment
```

### Important Deployment Notes
- DNS must point to server before running `deploy.sh`
- UFW must allow ports 22 (SSH) and 443 (HTTPS)
- Port 80 remains closed (opened temporarily only for certbot renewal via UFW hooks)
- Auto-detection of existing nginx (docker/systemd/standalone)
- **For P2P ServerPeer**: TURN ports (3478 UDP/TCP, 49152-65535 UDP) are configured automatically by `setup.sh`

### TURN/STUN Server Configuration (P2P WebRTC)

**Purpose:** Enables WebRTC peer-to-peer connections between Obsidian clients and ServerPeer when direct connection fails due to NAT/firewall.

**Components:**
- **STUN Server**: Google public STUN (stun:stun.l.google.com:19302) - discovers external IP addresses
- **TURN Server**: Local coturn (turn:server-ip:3478) - relays traffic when direct P2P connection impossible
- **Nostr Relay**: Local nostr-rs-relay for WebRTC signaling (not data relay)

**Installation:** Automatic via `install.sh` (installs coturn package)

**Configuration:** Fully automatic during setup and deployment
1. `setup.sh` generates TURN credentials and configures firewall:
   - Detects server external IP via `curl -s ifconfig.me`
   - Generates random TURN credentials (username: `obsidian`, password: 32-char hex)
   - **Automatically opens TURN ports in UFW** (3478/udp, 3478/tcp, 49152-65535/udp)
   - Creates `/opt/notes/.env` variables:
     ```bash
     TURN_USERNAME=obsidian
     TURN_PASSWORD=<random-32-char-hex>
     TURN_REALM=turn.example.com
     COTURN_LISTENING_PORT=3478
     COTURN_EXTERNAL_IP=<server-public-ip>
     SERVERPEER_STUN_SERVERS=stun:stun.l.google.com:19302
     SERVERPEER_TURN_SERVERS=turn:obsidian:<password>@<server-ip>:3478
     ```

2. `deploy.sh` automatically configures coturn (calls `scripts/coturn-setup.sh` when ServerPeer backend is selected)

**Manual Configuration (if needed):**
```bash
# 1. Run coturn setup script manually (only if deploy.sh failed)
sudo bash scripts/coturn-setup.sh

# 2. Verify coturn is running
sudo systemctl status coturn

# 3. Check UFW allows TURN ports
sudo ufw status | grep -E "3478|49152"

# 4. Test TURN server (from client machine)
turnutils_uclient -v -u obsidian -w <TURN_PASSWORD> <SERVER_IP>
```

**Firewall Rules (UFW):**
Automatically configured by `setup.sh` when ServerPeer backend is selected:
```bash
# TURN/STUN signaling
ufw allow 3478/udp comment 'TURN/STUN'
ufw allow 3478/tcp comment 'TURN/STUN'

# TURN relay ports (dynamic allocation)
ufw allow 49152:65535/udp comment 'TURN relay'
```

**Note:** If UFW is not installed, `setup.sh` will display a warning with manual commands.

**Obsidian Client Configuration:**
1. Open Obsidian Self-hosted LiveSync settings
2. Navigate to "P2P Settings" or enable via DevTools Console:
   ```javascript
   app.plugins.plugins['obsidian-livesync'].settings.P2P_Enabled = true;
   app.plugins.plugins['obsidian-livesync'].settings.P2P_AutoStart = true;
   app.plugins.plugins['obsidian-livesync'].settings.P2P_AutoBroadcast = true;
   await app.plugins.plugins['obsidian-livesync'].saveSettings();
   ```
3. TURN credentials auto-configured from server settings (shared via CouchDB or manual entry)

**Troubleshooting:**
- **TURN not accessible**: Check UFW rules, verify external IP detection
- **WebRTC connection fails**: Test TURN with `turnutils_uclient`, check coturn logs
- **High latency**: Direct P2P failed, traffic relaying through TURN (expected for strict NAT)
- **Authentication errors**: Verify TURN credentials match in ServerPeer and Obsidian client

**Architecture Diagram:**
```
Obsidian Client (behind NAT)
    ↓ (1) STUN query → discovers external IP
    ↓ (2) WebRTC offer → via Nostr Relay signaling
    ↓ (3) Direct P2P attempt → FAILS (NAT/firewall)
    ↓ (4) TURN fallback → coturn relays traffic
    ↓
ServerPeer (VPS, public IP)
```

**Why TURN is needed:**
- Obsidian clients typically behind home/corporate NAT
- ServerPeer on VPS with public IP
- Symmetric NAT prevents direct P2P connection
- TURN server relays traffic as last resort (adds latency but ensures connectivity)

### Docker Proxy Configuration

**NEW:** setup.sh now supports configuring Docker daemon to use HTTP/HTTPS/SOCKS5 proxy for image pulls. This is essential in restricted networks or when Docker Hub is blocked.

**When to use:**
- Docker Hub is blocked or throttled in your region
- Corporate/network firewall restricts Docker image pulls
- Need to route Docker traffic through authenticated proxy
- Want to bypass regional restrictions

**Configuration (setup.sh:100-212):**
```bash
sudo ./setup.sh
# When prompted:
Configure Docker proxy? (y/N): y
Proxy URL: https://user:pass@proxy.example.com:8080
NO_PROXY addresses [default]: localhost,127.0.0.1,::1
```

**Supported proxy protocols:**
- HTTP: `http://proxy:3128`
- HTTPS: `https://user:pass@proxy:8080`
- SOCKS5: `socks5://proxy:1080`

**What it does:**
1. Creates `/etc/systemd/system/docker.service.d/http-proxy.conf`
2. Sets `HTTP_PROXY`, `HTTPS_PROXY`, `NO_PROXY` environment variables
3. Reloads systemd and restarts Docker daemon
4. Verifies configuration with test pull

**NO_PROXY configuration:**
Comma-separated list of addresses that bypass proxy:
- `localhost,127.0.0.1,::1` - localhost addresses
- `docker-registry.local` - private registries
- `192.168.0.0/16` - internal networks

**Manual configuration:**
If setup.sh didn't configure proxy or you need to change it:
```bash
# Create/edit proxy config
sudo mkdir -p /etc/systemd/system/docker.service.d
sudo nano /etc/systemd/system/docker.service.d/http-proxy.conf

# Add:
[Service]
Environment="HTTP_PROXY=https://proxy:8080"
Environment="HTTPS_PROXY=https://proxy:8080"
Environment="NO_PROXY=localhost,127.0.0.1"

# Apply changes
sudo systemctl daemon-reload
sudo systemctl restart docker

# Verify
systemctl show --property=Environment docker
docker pull hello-world
```

**Remove proxy configuration:**
```bash
sudo rm /etc/systemd/system/docker.service.d/http-proxy.conf
sudo systemctl daemon-reload
sudo systemctl restart docker
```

**Troubleshooting:**
- Test with: `docker pull hello-world`
- Check logs: `journalctl -u docker.service`
- Verify config: `systemctl show --property=Environment docker | grep -i proxy`
- Common issue: Proxy authentication failed → check credentials in URL
- Common issue: SOCKS5 not working → some Docker versions have limited SOCKS5 support

**Common Issue: DNS Hijacking (504 Gateway Time-out)**

Even with proxy configured, Docker pull may fail with:
```
unexpected status from HEAD request to https://dockerhub.hostkey.ru/v2/.../manifests/...:
504 Gateway Time-out
```

**Root cause - ISP DNS hijacking:**
- ISP intercepts DNS queries for docker.io
- Redirects to blocked/unstable mirrors (dockerhub.hostkey.ru in Russia)
- Docker resolves DNS BEFORE applying proxy
- Proxy can't fix already-hijacked domain resolution

**Solution - Docker Hub DNS Fix (setup.sh:100-195):**

Automatically offered if proxy test fails:
```bash
sudo ./setup.sh
# Configure proxy? y
# ...
# [WARNING] Docker pull test failed
# [WARNING] This may be caused by DNS hijacking
# Try fixing Docker Hub DNS now? (Y/n): y
```

**Robust DNS Resolution with Multiple Fallbacks:**

The fix uses a multi-method DNS resolution approach (setup.sh:100-130):

1. **Primary methods** - Tries in order:
   - `dig +short @8.8.8.8` (most reliable)
   - `nslookup <domain> 8.8.8.8`
   - `host -t A <domain> 8.8.8.8`
   - `getent hosts <domain>` (system resolver)

2. **Fallback IPs** - If all DNS methods fail (network blocks 8.8.8.8 queries):
   - Uses verified fallback IPs (updated 2025-01-29)
   - `registry-1.docker.io: 3.226.190.193`
   - `auth.docker.io: 18.205.34.3`
   - `production.cloudflare.docker.com: 104.16.100.215`
   - Asks for user confirmation before applying fallbacks

3. **What it does:**
   - Adds correct IPs to /etc/hosts
   - /etc/hosts has priority over DNS, bypassing hijacking
   - Tests with `docker pull hello-world`

**Why multiple methods needed:**
- Some networks block all DNS queries to external servers (8.8.8.8)
- Different systems may have different DNS tools installed
- Fallback IPs ensure deployment works even in fully restricted networks

**Manual DNS fix:**
```bash
# Try resolving with different tools
dig +short @8.8.8.8 A registry-1.docker.io
nslookup registry-1.docker.io 8.8.8.8
host -t A registry-1.docker.io 8.8.8.8

# If all fail, use fallback IPs in /etc/hosts
sudo nano /etc/hosts
# Add lines:
# 3.226.190.193 registry-1.docker.io
# 18.205.34.3 auth.docker.io
# 104.16.100.215 production.cloudflare.docker.com
```

**Verification:**
```bash
# Check /etc/hosts
grep "Docker Hub" /etc/hosts

# Test
docker pull hello-world
```

**Important: BuildKit vs Docker Daemon Proxy**

Docker daemon proxy (`/etc/systemd/system/docker.service.d/http-proxy.conf`) affects:
- ✅ `docker pull` - downloads images through proxy
- ✅ `docker run` - container runtime
- ❌ `docker build` - BuildKit uses separate daemon (does NOT inherit proxy)

**Why `docker build` fails with proxy:**
- Docker Buildx uses `buildkitd` daemon (separate from Docker daemon)
- BuildKit requires separate proxy configuration via config.toml
- Or use pre-pull workaround (implemented in deploy.sh)

**Solution implemented (deploy.sh:262-283, 334-348):**
```bash
# deploy.sh pre-pulls base images using docker pull (respects proxy)
prepull_serverpeer_images() {
    docker pull denoland/deno:bin-latest  # Uses proxy ✅
    docker pull node:22.14-bookworm-slim  # Uses proxy ✅
}

prepull_couchdb_images() {
    docker pull couchdb:3.3  # Uses proxy ✅
}

# Then docker build uses cached images (no network needed)
docker compose build  # Uses local cache ✅
```

**Benefits:**
- Images pulled through proxy (Docker daemon)
- Build uses cached images (no network/proxy needed)
- Works around BuildKit proxy limitation
- No complex BuildKit configuration required

**Alternative (manual BuildKit proxy config):**
If you prefer to configure BuildKit proxy directly:
```bash
# Create buildkit config
mkdir -p ~/.docker
cat > ~/.docker/buildkitd.toml << EOF
[worker.oci]
  [worker.oci.http]
    [worker.oci.http.proxies]
      [worker.oci.http.proxies.default]
        http = "https://proxy:8080"
        https = "https://proxy:8080"
        no_proxy = "localhost,127.0.0.1"
EOF

# Restart buildkit
docker buildx stop
docker buildx rm default
docker buildx create --use --config ~/.docker/buildkitd.toml
```

### Image Update Detection

**Implementation:** scripts/deploy-helpers.sh:120-199

The prepull mechanism uses **Image ID comparison** (not manifest digest) to detect if an image needs updating. This matches Docker's native behavior:

**How it works:**
1. `get_local_image_id()` - extracts Image ID from local image via `docker inspect --format='{{.Id}}'`
2. `get_remote_image_id()` - extracts Image ID from registry manifest config via `docker manifest inspect`
3. `check_image_needs_update()` - compares local and remote Image IDs

**Why Image ID and not manifest digest:**
- Image ID = Config.Digest (content hash of image configuration)
- Manifest digest = metadata hash (differs for multi-arch images)
- Docker uses Image ID to determine if pull is needed
- Comparing Image IDs ensures consistency with Docker behavior

**Result:** No unnecessary pulls for up-to-date images, even for multi-arch images like `denoland/deno:bin`.

## Configuration Files

### /opt/notes/.env
Generated by `setup.sh`:
- `COUCHDB_PASSWORD` - auto-generated (openssl rand -hex 32)
- `NOTES_DOMAIN` - user-provided domain
- `CERTBOT_EMAIL` - Let's Encrypt notifications
- **Network configuration:**
  - `NETWORK_MODE` - shared/isolated/custom
  - `NETWORK_NAME` - Docker network name
  - `NETWORK_SUBNET` - Subnet для isolated mode
  - `NETWORK_EXTERNAL` - true для shared mode
- S3 credentials (optional)

### local.ini
CouchDB configuration:
- `single_node=true` - single-node mode
- `max_document_size = 50000000` - 50MB for attachments
- `require_valid_user = true` - authentication required
- CORS enabled for Obsidian app

### docker-compose.notes.yml
- Container name: configurable via `COUCHDB_CONTAINER_NAME` (default: `notes-couchdb`)
- Image: `couchdb:3.3`
- Network: Динамическая (из .env переменных)
  - `${NETWORK_NAME}` - имя сети
  - `${NETWORK_EXTERNAL}` - external или internal
  - `${NETWORK_SUBNET}` - подсеть (опционально)
- Volumes: `/opt/notes/data`, `./local.ini`
- Port: `127.0.0.1:5984:5984` (localhost only)
- Resources: CPU 0.1-0.5, Memory 128MB-512MB

### Nginx Configuration Templates

**Location:** `templates/*.conf.template`

The project uses optimized nginx configurations that **EXCEED** official CouchDB recommendations:

#### templates/couchdb.conf.template
**Key optimizations (applied 2025-12-30):**
- ✅ **keepalive 32** - Connection pooling (~5% latency reduction)
- ✅ **WebSocket support** - CRITICAL for CouchDB _changes feed real-time sync
- ✅ **HTTP/1.1** - Required for keep-alive and WebSocket
- ✅ **client_max_body_size 50M** - Matches CouchDB max_document_size
- ✅ **Enhanced headers** - X-Real-IP, X-Forwarded-Proto for security/logging
- ❌ **Removed Accept-Encoding ""** - Enables nginx↔CouchDB compression (+2-3% performance)

**Critical differences from official CouchDB docs:**
- Official recommendation **LACKS WebSocket support** → breaks real-time sync
- Official uses `proxy_pass $uri` with rewrite → creates broken URLs
- Official has no large attachment support → 413 errors for files >1MB

**Comparison analysis:** See `docs/nginx-configuration-analysis.md`

#### templates/unified.conf.template
Unified config for dual-backend (CouchDB + ServerPeer):
- Separate location blocks: `${COUCHDB_LOCATION}` and `${SERVERPEER_LOCATION}`
- Both backends have keepalive 32
- CouchDB: HTTP proxy with WebSocket upgrade
- ServerPeer: WebSocket proxy with 7-day timeouts

#### templates/serverpeer.conf.template
ServerPeer-only WebSocket proxy:
- WebSocket upgrade headers (Upgrade, Connection)
- 7-day timeouts for long-lived connections
- keepalive 32 for connection pooling

**IMPORTANT:** Do NOT blindly apply official CouchDB nginx recommendations - they are outdated and will break:
1. Real-time synchronization (no WebSocket)
2. Large file uploads (no client_max_body_size)
3. URL routing (incorrect proxy_pass with rewrite)

## Script Architecture

### Core Deployment Scripts

**install.sh**
- Validates Docker/Docker Compose
- Creates `/opt/notes` directory structure
- Installs Python dependencies (python3-boto3 from system packages, PEP 668 compliant)
- Installs coturn TURN/STUN server for P2P WebRTC (when ServerPeer backend selected)
- Optionally runs UFW setup
- Must run with sudo

**setup.sh**
- Creates `/opt/notes/.env`
- Prompts for sync backend selection (CouchDB/ServerPeer/Both)
- Prompts for domain and email
- Generates secure CouchDB password (when CouchDB backend selected)
- Configures backend-specific settings (container names, ports, locations)
- Configures TURN/STUN server for P2P WebRTC (when ServerPeer backend selected):
  - Detects server external IP
  - Generates random TURN credentials
  - Configures STUN server (Google public)
  - Configures TURN server (local coturn)
  - **Automatically opens TURN ports in UFW firewall** (3478/udp, 3478/tcp, 49152-65535/udp)
- Optionally configures S3 backup with backend-aware prefix defaults
- Sets up cron/systemd for automatic backups (backend-aware):
  - Dynamically creates systemd unit files matching selected backend
  - CouchDB only: couchdb-backup.timer/service
  - ServerPeer only: serverpeer-backup.timer/service
  - Both: creates both timers (CouchDB at 3:00 AM, ServerPeer at 3:05 AM)
- Requires sudo for: TURN firewall configuration, systemd timer creation
- **Important:** Backend-specific variables (COUCHDB_CONTAINER_NAME, SERVERPEER_CONTAINER_NAME, TURN credentials) are only added to .env when their respective backend is selected

**deploy.sh**
- Orchestrates full deployment
- Calls nginx-setup.sh → ssl-setup.sh → applies config
- Deploys selected backend (CouchDB/ServerPeer/Both)
- Configures TURN server (when ServerPeer backend selected)
- Validates deployment
- Displays summary

### Helper Scripts (scripts/)

**nginx-setup.sh**
- Detects existing nginx (docker/systemd/standalone)
- Integrates with existing or deploys own
- Generates nginx config from template
- Reloads nginx after config changes

**ssl-setup.sh**
- Obtains Let's Encrypt certificates via certbot
- Integrates with UFW (opens port 80 temporarily)
- Supports staging mode for testing
- Installs certbot renewal hooks

**ufw-setup.sh**
- Configures firewall
- Allows: SSH (22), HTTPS (443)
- Allows: TURN/STUN ports (3478 UDP/TCP, 49152-65535 UDP) when ServerPeer backend selected
- Blocks: HTTP (80) - except during certbot renewal
- Creates certbot pre/post hooks for port 80 management

**coturn-setup.sh**
- Configures coturn TURN/STUN server for P2P WebRTC
- Generates `/etc/turnserver.conf` with security settings
- Loads configuration from `/opt/notes/.env`
- Enables and restarts coturn service
- Displays comprehensive summary with credentials
- **Only relevant for ServerPeer backend**

**couchdb-backup.sh**
- Backs up all CouchDB databases
- Compresses with gzip
- Uploads to S3 (if configured)
- Local retention: 7 days
- Resource-aware (CPU limits, nice, ionice)
- Progress tracking and health checks

**s3_upload.py**
- Python script using boto3
- Uploads backups to S3-compatible storage
- Supports: AWS S3, Yandex Object Storage, MinIO
- Called by couchdb-backup.sh

## Testing

### Test Scripts
- `run-all-tests.sh` - runs all validation tests
- `test-ssl-renewal.sh` - dry run of certbot renewal
- `test-backup.sh` - validates backup process
- `check-ssl-expiration.sh` - checks certificate expiration

### Manual Testing
```bash
# Test CouchDB health
curl http://localhost:5984/_up

# Test nginx proxy (requires /etc/hosts entry)
curl http://notes.localhost/_up

# Test HTTPS (production)
curl https://notes.example.com/_up

# Verify authentication
curl -u admin:password http://localhost:5984/_all_dbs
```

## Obsidian Integration

### Plugin: Self-hosted LiveSync
1. Install from Community Plugins
2. URI: `http://notes.localhost` (dev) or `https://notes.example.com` (prod)
3. Username: `admin`
4. Password: from `/opt/notes/.env` → `COUCHDB_PASSWORD`
5. Database: `obsidian` (or custom)

## Security Considerations

### Firewall (UFW)
- Port 22: SSH (always open)
- Port 443: HTTPS (always open)
- Port 80: HTTP (closed, opened only during certbot renewal via hooks)
- Port 5984: CouchDB (bind to 127.0.0.1, not exposed)
- Port 3000: ServerPeer (bind to 127.0.0.1, not exposed)
- **Port 3478** (UDP/TCP): TURN/STUN signaling (P2P WebRTC) - **open when ServerPeer backend selected**
- **Ports 49152-65535** (UDP): TURN relay ports (dynamic allocation) - **open when ServerPeer backend selected**

### fail2ban Integration

**NEW (v5.2.0):** Dynamic intrusion prevention via fail2ban

**Purpose:** Automatically ban IP addresses showing malicious activity (brute-force, scanning, API abuse)

**Architecture:**
```
UFW (Static Rules) ←─── fail2ban (Dynamic IP Bans)
         ↓                        ↑
   Nginx Proxy                    │
         ↓                         │
   Backend APIs ──────(logs)──────┘
```

**Protected Services:**
- SSH (port 22): 5 failures in 10 min → 1 hour ban
- HTTP (nginx): 10 suspicious requests in 10 min → 1 hour ban
- CouchDB API: 3 auth failures in 5 min → 2 hour ban
- ServerPeer WebSocket (WSS): 3 auth failures in 5 min → 2 hour ban

**Integration Point:** `deploy.sh` → after `check_ufw_configured()`, before `deploy_couchdb()`

**Configuration Files:**
- `/etc/fail2ban/jail.local` - Main jail configuration
- `/etc/fail2ban/filter.d/notes-couchdb.conf` - CouchDB API filter (custom)
- `/etc/fail2ban/filter.d/notes-serverpeer.conf` - ServerPeer WSS filter (custom)

**UFW Integration:**
- fail2ban uses `banaction = ufw`
- Bans insert rules: `ufw insert 1 deny from <IP> to any`
- Compatible with SSL renewal UFW hooks (different rule types)

**Common Commands:**
```bash
# View status
sudo fail2ban-client status

# Check specific jail
sudo fail2ban-client status notes-couchdb

# View banned IPs
sudo fail2ban-client get notes-couchdb banip

# Manual unban
sudo fail2ban-client set notes-couchdb unbanip 192.168.1.100

# View logs
tail -f /var/log/fail2ban/fail2ban.log

# Test filters
sudo fail2ban-regex /var/log/nginx/access.log /etc/fail2ban/filter.d/notes-couchdb.conf
```

**Docker Nginx Requirement:**
If using Docker nginx, logs MUST be volume-mounted:
```yaml
volumes:
  - /opt/notes/logs/nginx:/var/log/nginx  # Required for fail2ban
```

**Backend-Aware Jails:**
- CouchDB only: `notes-couchdb` jail enabled
- ServerPeer only: `notes-serverpeer` jail enabled
- Both: Both jails enabled

**WebSocket Secure (WSS) Support:**
- ServerPeer filter monitors WSS connections over HTTPS (port 443)
- Ignores HTTP 101 Switching Protocols (successful WebSocket upgrades)
- Only bans failed authentication attempts (HTTP 401/403)

**Troubleshooting:**
- "Jail not found" → check backend in `/opt/notes/.env`
- "No log file" → verify nginx logging enabled in templates
- "Docker logs not accessible" → add volume mount to docker-compose
- False positives → adjust maxretry or add to ignoreip whitelist

**Rollback:**
```bash
sudo systemctl stop fail2ban
sudo systemctl disable fail2ban
sudo rm -f /etc/fail2ban/jail.local
sudo apt-get purge -y fail2ban  # Optional
```

### Password Security
- Production: 64-char hex (256-bit) via `openssl rand -hex 32`
- Development: Fixed insecure password (dev_password_insecure)
- `/opt/notes/.env` has chmod 600

### SSL/TLS
- Let's Encrypt certificates
- TLSv1.2+ only
- HSTS enabled
- Auto-renewal every 60 days

### CouchDB
- Authentication required (`require_valid_user = true`)
- No external access (port binds to localhost)
- CORS restricted to Obsidian app origins

## Troubleshooting

### Common Issues

**"Docker network not found"**
- Check available networks: `docker network ls`
- For shared mode: ensure the network specified in .env exists
- For isolated mode: network created automatically during deploy

**"env_file: /opt/notes/.env: no such file"**
- Run setup: `bash setup.sh`

**CouchDB health check timeout**
- Check logs: `docker logs notes-couchdb` (or your configured COUCHDB_CONTAINER_NAME)
- Verify port: `netstat -tuln | grep 5984`
- Restart: `docker compose -f docker-compose.notes.yml restart`

**SSL certificate issues**
- Verify DNS: `host notes.example.com`
- Check UFW: `sudo ufw status | grep 443`
- Test renewal: `bash scripts/test-ssl-renewal.sh`

**Backup failures**
- Check permissions: `ls -la /opt/notes/backups/`
- Check S3 credentials in `/opt/notes/.env`
- View logs: `tail -f /opt/notes/logs/backup.log`

## Code Style & Conventions

### Shell Scripts
- Use `set -e` (exit on error) and `set -u` (exit on undefined variable)
- Color-coded output functions: `info()`, `success()`, `warning()`, `error()`
- Comprehensive validation before execution
- Resource limits for backup operations (CPU, memory, I/O)

### Docker
- Container naming: Configurable via .env (COUCHDB_CONTAINER_NAME, NGINX_CONTAINER_NAME)
- External networks for service communication
- Health checks for reliability
- Resource constraints (CPU/memory limits)

### Configuration
- All secrets in `/opt/notes/.env` (never committed)
- `.env.example` for documentation
- chmod 600 for sensitive files

## Project Structure

```
obsidian/
├── docker-compose.notes.yml    # CouchDB service definition
├── docker-compose.serverpeer.yml # ServerPeer service definition
├── local.ini                   # CouchDB configuration
├── install.sh                  # Dependencies installation (sudo)
├── setup.sh                    # Production configuration
├── deploy.sh                   # Production deployment
├── scripts/
│   ├── couchdb-backup.sh       # CouchDB backup script
│   ├── serverpeer-backup.sh    # ServerPeer backup script
│   ├── nginx-setup.sh          # Nginx detection & integration
│   ├── ssl-setup.sh            # Let's Encrypt SSL
│   ├── ufw-setup.sh            # Firewall configuration (includes TURN ports)
│   ├── coturn-setup.sh         # TURN/STUN server configuration (P2P WebRTC)
│   ├── generate-serverpeer-compose.sh # Generate multi-vault ServerPeer compose
│   ├── check-ssl-expiration.sh # SSL monitoring
│   ├── test-ssl-renewal.sh     # SSL renewal testing
│   ├── test-backup.sh          # Backup validation
│   ├── run-all-tests.sh        # Test suite
│   └── s3_upload.py            # S3 upload utility
├── serverpeer/
│   ├── Dockerfile              # ServerPeer container build
│   └── fix-p2p-enabled.patch   # P2P bug fixes
├── docs/
│   ├── prd/                    # Product requirements
│   ├── architecture/           # YAML knowledge graph
│   ├── security.md             # Security documentation
│   └── troubleshooting.md      # Troubleshooting guide
└── requests/                   # Task templates & planning
```

## Dependencies

### External Services
- **Family Budget nginx** (optional but recommended)
  - Provides reverse proxy
  - Handles SSL termination
  - Must be running on same Docker network

### Docker Images
- `couchdb:3.3` - official CouchDB image (for CouchDB backend)
- `denoland/deno:bin-latest` - Deno runtime (for ServerPeer backend)
- `node:22.14-bookworm-slim` - Node.js runtime (for ServerPeer backend)
- `scsibug/nostr-rs-relay:latest` - Nostr relay (for ServerPeer P2P signaling)

### System Requirements
- Docker 20.10+
- Docker Compose v2+
- Python 3 + python3-boto3 package (for S3 backups)
- openssl (for password generation)
- UFW (firewall)
- **coturn** (for ServerPeer P2P WebRTC) - installed automatically via `install.sh`

### Optional
- nginx (if not using existing nginx)
- certbot (for SSL certificates)
- S3-compatible storage (for cloud backups)

## Monitoring & Maintenance

### Regular Checks
```bash
# CouchDB status (use your configured COUCHDB_CONTAINER_NAME)
docker ps | grep notes-couchdb

# ServerPeer status (use your configured SERVERPEER_CONTAINER_NAME)
docker ps | grep notes-serverpeer

# Resource usage
docker stats notes-couchdb
docker stats notes-serverpeer

# Disk usage
du -sh /opt/notes/data
du -sh /opt/notes/backups

# SSL expiration
bash scripts/check-ssl-expiration.sh

# Backup status
tail -20 /opt/notes/logs/backup.log

# TURN server status (for P2P ServerPeer)
sudo systemctl status coturn
sudo journalctl -u coturn --since "1 hour ago"
```

### Logs
- CouchDB: `docker logs notes-couchdb` (or your COUCHDB_CONTAINER_NAME)
- ServerPeer: `docker logs notes-serverpeer` (or your SERVERPEER_CONTAINER_NAME)
- Nostr Relay: `docker logs notes-nostr-relay`
- Backup: `/opt/notes/logs/backup.log`
- Installation: `/var/log/notes_install.log`
- TURN Server: `/var/log/turnserver.log`, `sudo journalctl -u coturn`

### Cron Jobs
```bash
# View backup schedule
crontab -l | grep couchdb-backup

# Default: daily at 3:00 AM
0 3 * * * /bin/bash /opt/notes/scripts/couchdb-backup.sh >> /opt/notes/logs/backup.log 2>&1
```

## Version Information

- **Version:** 5.3.0
- **Last Updated:** 2025-12-30
- **CouchDB Version:** 3.3
- **Docker Compose Version:** v2+
- **Coturn Version:** 4.6+ (installed via apt)
- **ServerPeer:** Deno-based (denoland/deno:bin-latest)
- **Nostr Relay:** nostr-rs-relay (scsibug/nostr-rs-relay:latest)
