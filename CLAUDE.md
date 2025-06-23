# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository contains a collection of bash scripts for automated deployment of CouchDB and Obsidian LiveSync server infrastructure. The system is designed to deploy services to `/opt/` directory with Docker containers managed by Traefik reverse proxy.

## Key Commands

### Main Installation
```bash
# Full interactive installation (must run as root)
sudo ./install.sh

# Individual service installations
sudo ./install-couchdb.sh
sudo ./install-obsidian-sync.sh
sudo ./setup-firewall.sh
```

### Service Management (After Installation)
```bash
# CouchDB
cd /opt/couchdb && docker-compose up -d
cd /opt/couchdb && docker-compose down
cd /opt/couchdb && docker-compose logs -f

# Obsidian LiveSync
/opt/obsidian-sync/start.sh
/opt/obsidian-sync/stop.sh
/opt/obsidian-sync/update.sh

# Backup management
/opt/couchdb/backup/backup-couchdb.sh backup
/opt/couchdb/backup/backup-couchdb.sh setup-s3
```

## Architecture

### Script Architecture
- **`install.sh`**: Master orchestration script that handles dependency installation and service selection
- **`install-couchdb.sh`**: CouchDB deployment with single-node configuration and Traefik integration
- **`install-obsidian-sync.sh`**: Obsidian LiveSync server deployment using vrtmrz/livesync-serverpeer repository
- **`backup-couchdb.sh`**: Multi-mode backup system with S3 integration and cron scheduling
- **`setup-firewall.sh`**: UFW firewall configuration for Docker networks and service ports

### Deployment Architecture
The scripts create this production infrastructure:
```
/opt/
├── couchdb/
│   ├── docker-compose.yml (Traefik labels, single-node config)
│   ├── data/ (persistent storage)
│   ├── config/ (CouchDB configuration)
│   └── backup/ (backup scripts and archives)
└── obsidian-sync/
    ├── docker-compose.yml (Deno-based service with Traefik)
    ├── Dockerfile (production build)
    └── management scripts (start.sh, stop.sh, update.sh)
```

### Service Integration
- All services use external Traefik network for routing
- CouchDB configured for single-node operation with authentication
- Obsidian LiveSync clones and builds from upstream repository
- Backup system integrates with Yandex Cloud S3 via MinIO client
- UFW firewall configured for Docker bridge networks and service ports

## Script Behavior Patterns

### Interactive Configuration
All installation scripts prompt for:
- Domain names for service routing
- Port configurations (with defaults)
- Authentication credentials
- S3 backup settings (optional)

### Error Handling
Scripts use `set -e` for fail-fast behavior and include:
- Root permission validation
- Service availability checks
- Docker network creation
- Dependency installation verification

### File Management
- Configuration files stored as `.env` with service parameters
- Docker Compose files generated with Traefik labels
- Backup scripts support multiple operation modes (backup, setup-s3, setup-cron, install)

## Dependencies and Requirements

- Target OS: Ubuntu/Debian Linux
- Required: Docker, Docker Compose, Git (auto-installed)
- External: Traefik reverse proxy (not included)
- Optional: MinIO client for S3 backups
- Network: External Traefik network must exist or be created