# Migration Guide: Upgrading to Network Isolation Architecture

## Overview

Версия 2.0 вводит гибкую сетевую архитектуру с поддержкой трех режимов: shared, isolated, custom.

## Changes Summary

**Breaking Changes:**
- `dev-setup.sh` удален - только production deployment
- Docker networks: переход на переменные окружения
- Требуется обновление .env файла

**Backward Compatibility:**
- Автоопределение режима сохраняет совместимость
- Существующие установки продолжат работать в shared mode

## Migration Steps

### For Existing Installations

**Step 1: Backup current configuration**
```bash
sudo cp /opt/notes/.env /opt/notes/.env.backup
```

**Step 2: Pull latest changes**
```bash
git pull origin dev
git checkout feature/network-isolation-refactor
```

**Step 3: Update .env file**
Add network configuration:
```bash
cat >> /opt/notes/.env <<EOF
# Network Configuration
NETWORK_MODE=shared
NETWORK_NAME=familybudget_familybudget
NETWORK_EXTERNAL=true
EOF
```

**Step 4: Re-run deployment**
```bash
sudo ./deploy.sh
```

**Step 5: Validate**
```bash
# Check network
docker network inspect familybudget_familybudget

# Check containers
docker ps | grep familybudget-couchdb-notes

# Test health
curl http://127.0.0.1:5984/_up
```

### For Development Workflow Migration

**Previous (dev-setup.sh):**
```bash
bash dev-setup.sh
docker compose -f docker-compose.notes.yml up -d
```

**New (production only):**
```bash
sudo ./install.sh
./setup.sh  # use real domain and email
sudo ./deploy.sh
```

**Alternative: Local testing**
```bash
# Use test domain and staging SSL
./setup.sh
# domain: notes.test.local
# email: test@example.com

# Add to /etc/hosts
echo "127.0.0.1 notes.test.local" | sudo tee -a /etc/hosts

sudo ./deploy.sh
```

## Troubleshooting

**Issue: "Network familybudget_familybudget not found"**
Solution: Режим автоматически переключится на isolated, будет создана obsidian_network

**Issue: "CouchDB not accessible"**
Solution: Проверьте сетевую связность:
```bash
docker network inspect <network_name>
docker logs familybudget-couchdb-notes
```

**Issue: "Port 5984 already in use"**
Solution: Остановите conflicting service:
```bash
docker ps | grep 5984
docker stop <container_name>
```

## Rollback

If issues occur, rollback to previous version:
```bash
# Stop services
sudo docker compose -f /opt/notes/docker-compose.notes.yml down

# Checkout previous version
git checkout <previous_commit>

# Restore .env
sudo mv /opt/notes/.env.backup /opt/notes/.env

# Re-deploy
sudo ./deploy.sh
```

## Support

For issues, please:
1. Check logs: `docker logs familybudget-couchdb-notes`
2. Run validation: `bash scripts/run-all-tests.sh`
3. Open issue: https://github.com/[your-repo]/issues
