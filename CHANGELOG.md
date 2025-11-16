# Changelog

## [2.0.0] - 2025-11-16

### Added
- **PRD Documentation** - Полная техническая документация (docs/prd/)
- **UFW Firewall Setup** - Автоматическая настройка (только SSH:22, HTTPS:443)
- **Smart Nginx Integration** - Детекция существующего или запуск своего
- **SSL Auto-Setup** - Let's Encrypt с UFW-aware renewal hooks
- **HTTP → HTTPS Redirect** - Автоматический редирект в nginx
- **S3 Automated Backups** - Ежедневные backups (3:00 AM) в S3
- **Python S3 Upload Script** - boto3-based upload для любого S3-compatible storage
- **Comprehensive Testing** - Полный набор тестов (security, SSL, nginx, CouchDB, backups)
- **Troubleshooting Guide** - docs/troubleshooting.md
- **Security Documentation** - docs/security.md

### Changed
- **install.sh** - Добавлена проверка UFW, nginx detection, port check
- **setup.sh** - Запрос CERTBOT_EMAIL, S3 credentials, cron setup
- **deploy.sh** - Интеграция nginx-setup и ssl-setup
- **couchdb-backup.sh** - Использует /opt/notes/.env вместо /opt/budget/.env
- **.env.example** - Добавлены SSL и S3 секции

### Security
- Port 80 закрыт по умолчанию (открывается только для certbot renewal)
- UFW firewall configured (whitelist approach)
- SSL/TLS с современными настройками (TLSv1.2+, HSTS)
- CouchDB порт 5984 bind только к localhost
- Безопасное хранение credentials (/opt/notes/.env chmod 600)

### Breaking Changes
- Требуется пере-запуск setup.sh для существующих установок
- UFW будет автоматически настроен (может заблокировать нестандартные порты)

## [1.0.0] - 2025-11-15

### Added
- Базовая установка CouchDB
- Интеграция с Family Budget nginx
- Ручная настройка SSL
