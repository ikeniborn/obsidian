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
- **Container**: `couchdb-notes` (configurable via COUCHDB_CONTAINER_NAME)
- **Use Case**: Traditional client-server sync, proven stability

**2. livesync-serverpeer** - P2P Architecture
- **Protocol**: WebSocket (WSS) relay
- **Storage**: Headless vault (filesystem-based)
- **Backup**: Vault archive → tar.gz → S3 (via `serverpeer-backup.sh`, **NO CouchDB dependency**)
- **Port**: 3000 (localhost only)
- **Container**: `serverpeer-notes` (configurable via SERVERPEER_CONTAINER_NAME)
- **Technology**: Deno-based (https://github.com/vrtmrz/livesync-serverpeer)
- **Dependencies**: Fully containerized (Deno, Node.js, git) - NO host installation required
- **WebSocket Relay**: Uses local server by default (wss://your-domain/serverpeer/)
  - **Recommended**: Local relay (best performance & privacy)
  - **Alternative**: External relay (e.g., wss://exp-relay.vrtmrz.net/) - adds latency
- **Use Case**: P2P synchronization with WebSocket relay, file-based storage

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
docker logs couchdb-notes
docker compose -f docker-compose.notes.yml restart
bash /opt/notes/scripts/couchdb-backup.sh
```

*ServerPeer:*
```bash
docker logs serverpeer-notes
docker compose -f docker-compose.serverpeer.yml restart
bash /opt/notes/scripts/serverpeer-backup.sh  # NO CouchDB dependency
```

## Deployment Workflow

### Common Commands

**Container management:**
```bash
# View logs (container name from .env: COUCHDB_CONTAINER_NAME)
docker logs couchdb-notes
docker logs -f couchdb-notes  # Follow mode

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

## Production Deployment

### Sequential Deployment Flow
```bash
# Step 1: Install dependencies (Docker, UFW, Python)
sudo ./install.sh

# Step 2: Configure environment
./setup.sh
# Prompts for:
# - CERTBOT_EMAIL (for Let's Encrypt)
# - NOTES_DOMAIN (e.g., notes.example.com)
# - S3 credentials (optional)
# Generates: /opt/notes/.env

# Step 3: Deploy
./deploy.sh
# Executes:
# 1. nginx-setup.sh (detects/integrates with existing nginx)
# 2. ssl-setup.sh (obtains Let's Encrypt certificates)
# 3. Applies nginx config with SSL
# 4. Deploys CouchDB via docker compose
# 5. Validates deployment
```

### Important Deployment Notes
- DNS must point to server before running `deploy.sh`
- UFW must allow ports 22 (SSH) and 443 (HTTPS)
- Port 80 remains closed (opened temporarily only for certbot renewal via UFW hooks)
- Auto-detection of existing nginx (docker/systemd/standalone)

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
- Container name: configurable via `COUCHDB_CONTAINER_NAME` (default: `couchdb-notes`)
- Image: `couchdb:3.3`
- Network: Динамическая (из .env переменных)
  - `${NETWORK_NAME}` - имя сети
  - `${NETWORK_EXTERNAL}` - external или internal
  - `${NETWORK_SUBNET}` - подсеть (опционально)
- Volumes: `/opt/notes/data`, `./local.ini`
- Port: `127.0.0.1:5984:5984` (localhost only)
- Resources: CPU 0.1-0.5, Memory 128MB-512MB

## Script Architecture

### Core Deployment Scripts

**install.sh**
- Validates Docker/Docker Compose
- Creates `/opt/notes` directory structure
- Installs Python dependencies (python3-boto3 from system packages, PEP 668 compliant)
- Optionally runs UFW setup
- Must run with sudo

**setup.sh**
- Creates `/opt/notes/.env`
- Prompts for sync backend selection (CouchDB/ServerPeer/Both)
- Prompts for domain and email
- Generates secure CouchDB password (when CouchDB backend selected)
- Configures backend-specific settings (container names, ports, locations)
- Optionally configures S3 backup with backend-aware prefix defaults
- Sets up cron/systemd for automatic backups (backend-aware):
  - Dynamically creates systemd unit files matching selected backend
  - CouchDB only: couchdb-backup.timer/service
  - ServerPeer only: serverpeer-backup.timer/service
  - Both: creates both timers (CouchDB at 3:00 AM, ServerPeer at 3:05 AM)
- No sudo required (except for systemd timer creation)
- **Important:** Backend-specific variables (COUCHDB_CONTAINER_NAME, SERVERPEER_CONTAINER_NAME) are only added to .env when their respective backend is selected

**deploy.sh**
- Orchestrates full deployment
- Calls nginx-setup.sh → ssl-setup.sh → applies config
- Deploys CouchDB container
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
- Blocks: HTTP (80) - except during certbot renewal
- Creates certbot pre/post hooks for port 80 management

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
- Check logs: `docker logs couchdb-notes` (or your configured COUCHDB_CONTAINER_NAME)
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
├── local.ini                   # CouchDB configuration
├── install.sh                  # Dependencies installation (sudo)
├── setup.sh                    # Production configuration
├── deploy.sh                   # Production deployment
├── scripts/
│   ├── couchdb-backup.sh       # Backup script
│   ├── nginx-setup.sh          # Nginx detection & integration
│   ├── ssl-setup.sh            # Let's Encrypt SSL
│   ├── ufw-setup.sh            # Firewall configuration
│   ├── check-ssl-expiration.sh # SSL monitoring
│   ├── test-ssl-renewal.sh     # SSL renewal testing
│   ├── test-backup.sh          # Backup validation
│   ├── run-all-tests.sh        # Test suite
│   └── s3_upload.py            # S3 upload utility
├── docs/
│   ├── prd/                    # Product requirements
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
- `couchdb:3.3` - official CouchDB image

### System Requirements
- Docker 20.10+
- Docker Compose v2+
- Python 3 + python3-boto3 package (for S3 backups)
- openssl (for password generation)
- UFW (firewall)

### Optional
- nginx (if not using Family Budget nginx)
- certbot (for SSL certificates)
- S3-compatible storage (for cloud backups)

## Monitoring & Maintenance

### Regular Checks
```bash
# CouchDB status (use your configured COUCHDB_CONTAINER_NAME)
docker ps | grep couchdb-notes

# Resource usage
docker stats couchdb-notes

# Disk usage
du -sh /opt/notes/data
du -sh /opt/notes/backups

# SSL expiration
bash scripts/check-ssl-expiration.sh

# Backup status
tail -20 /opt/notes/logs/backup.log
```

### Logs
- CouchDB: `docker logs couchdb-notes` (or your COUCHDB_CONTAINER_NAME)
- Backup: `/opt/notes/logs/backup.log`
- Installation: `/var/log/notes_install.log`

### Cron Jobs
```bash
# View backup schedule
crontab -l | grep couchdb-backup

# Default: daily at 3:00 AM
0 3 * * * /bin/bash /opt/notes/scripts/couchdb-backup.sh >> /opt/notes/logs/backup.log 2>&1
```

## Version Information

- **Version:** 5.1.0
- **Last Updated:** 2025-11-16
- **CouchDB Version:** 3.3
- **Docker Compose Version:** v2+
