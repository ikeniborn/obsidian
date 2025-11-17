# Changelog

## [2.0.0] - 2025-11-16

### Added
- **Flexible Network Architecture** - три режима: shared, isolated, custom
- **Auto-detection** - автоопределение сетевого режима при deployment
- **Network Manager** - `scripts/network-manager.sh` для централизованного управления сетями
- **Deployment Validation** - комплексная проверка сетевой связности
- **Auto Subnet Selection** - автовыбор свободной подсети для isolated mode (172.24-31.0.0/16)
- **Network Testing Suite** - `scripts/test-network-modes.sh` для автоматизированного тестирования
- **Migration Guide** - `docs/migration-guide.md` для обновления с предыдущих версий
- **PRD Documentation** - Полная техническая документация (docs/prd/)
- **UFW Firewall Setup** - Автоматическая настройка (только SSH:22, HTTPS:443)
- **Smart Nginx Integration** - Детекция существующего или запуск своего
- **SSL Auto-Setup** - Let's Encrypt с UFW-aware renewal hooks
- **S3 Automated Backups** - Ежедневные backups (3:00 AM) в S3
- **Comprehensive Testing** - Полный набор тестов (security, SSL, nginx, CouchDB, backups)

### Changed
- **docker-compose.notes.yml** - поддержка динамических сетей через переменные
- **scripts/nginx-setup.sh** - полная переработка с интеграцией network manager
- **deploy.sh** - добавлены network preparation и validation
- **setup.sh** - интерактивная настройка сетевого режима
- **.env.example** - новые переменные для сетевой конфигурации
- **install.sh** - Добавлена проверка UFW, nginx detection, port check
- **couchdb-backup.sh** - Использует /opt/notes/.env вместо /opt/budget/.env

### Fixed
- **CRITICAL:** Исправлена некорректная сеть `notes-network` в nginx-setup.sh
- **CRITICAL:** Nginx и CouchDB теперь всегда в одной сети
- Валидация сетевой связности предотвращает silent failures

### Removed
- **BREAKING:** `dev-setup.sh` - только production deployment
- **BREAKING:** Development mode - все deployment теперь production-ready
- `creds.json` - credentials переведены в .env

### Security
- Улучшена изоляция сети - каждый deployment в своей подсети (isolated mode)
- Credentials централизованы в .env (chmod 600)
- Port 80 закрыт по умолчанию (открывается только для certbot renewal)
- UFW firewall configured (whitelist approach)
- SSL/TLS с современными настройками (TLSv1.2+, HSTS)
- CouchDB порт 5984 bind только к localhost

### Migration
See `docs/migration-guide.md` for detailed upgrade instructions.

---

## [1.0.0] - 2025-11-15

### Added
- Базовая установка CouchDB
- Интеграция с Family Budget nginx
- Ручная настройка SSL
