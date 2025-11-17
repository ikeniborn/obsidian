# Notes - CouchDB Obsidian Sync

Изолированное приложение для синхронизации заметок Obsidian через CouchDB.

## 📋 Описание

Notes - это **полностью изолированное** приложение для хранения и синхронизации заметок Obsidian. Использует:
- **CouchDB** - база данных для хранения заметок
- **Nginx** - reverse proxy (из основного приложения Family Budget)
- **Docker Compose** - изолированное развертывание

## 🏗️ Архитектура

### Network Modes

Obsidian Sync Server поддерживает гибкую сетевую конфигурацию:

**Shared Mode (по умолчанию при интеграции с Family Budget):**
```
Docker Network: familybudget_familybudget
├── familybudget-nginx (Family Budget)
├── familybudget-couchdb-notes (CouchDB)
└── [другие Family Budget сервисы]
```

**Isolated Mode (standalone deployment):**
```
Docker Network: obsidian_network (auto-created, 172.24-31.0.0/16)
├── notes-nginx (собственный nginx)
└── familybudget-couchdb-notes (CouchDB)
```

**Custom Mode:**
Настраивается через .env (NETWORK_MODE=custom, NETWORK_NAME, NETWORK_SUBNET)

### Network Selection Logic
1. Автоопределение при deploy:
   - Если существует `familybudget_familybudget` → shared mode
   - Если нет → isolated mode (создает obsidian_network)
2. Переопределение через .env:
   - `NETWORK_MODE=shared|isolated|custom`
3. Валидация сетевой связности после deployment

## 🚀 Быстрый старт

### Production (Рекомендуется)

**Шаг 1: Установка зависимостей и UFW**
```bash
cd ~/obsidian-sync
sudo ./install.sh
```

Установит:
- Docker и Docker Compose (если не установлены)
- UFW firewall (разрешены только SSH:22 и HTTPS:443)
- Python 3 и boto3 (для S3 backups)
- Проверит nginx (детекция существующего)

**Шаг 2: Конфигурация**
```bash
./setup.sh
```

Настроит:
- Генерация безопасного COUCHDB_PASSWORD
- Запрос NOTES_DOMAIN (например: notes.example.com)
- Запрос CERTBOT_EMAIL (для Let's Encrypt уведомлений)
- Запрос S3 credentials (опционально)
- Создание cron job для автоматических backups (3:00 AM)

**Шаг 3: Deployment**
```bash
./deploy.sh
```

Выполнит:
- Nginx setup (детекция/интеграция или запуск своего)
- SSL сертификаты (Let's Encrypt через certbot)
- CouchDB deployment
- Валидация всех компонентов

**Доступ:**
- HTTPS: https://notes.example.com
- HTTP: Автоматический редирект на HTTPS
- Credentials: `admin` / [пароль из /opt/notes/.env]

### Migration from Previous Versions

Для обновления с версии 1.x на 2.0 (с новой сетевой архитектурой), см. детальный [Migration Guide](docs/migration-guide.md).

**Краткая инструкция:**
```bash
# 1. Backup текущей конфигурации
sudo cp /opt/notes/.env /opt/notes/.env.backup

# 2. Pull изменений
git pull origin dev
git checkout feature/network-isolation-refactor

# 3. Обновить .env (добавить сетевые переменные)
cat >> /opt/notes/.env <<EOF
NETWORK_MODE=shared
NETWORK_NAME=familybudget_familybudget
NETWORK_EXTERNAL=true
EOF

# 4. Re-deploy
sudo ./deploy.sh
```


## 📂 Структура файлов

```
notes/
├── docker-compose.notes.yml  # Изолированный docker-compose
├── .env.example              # Template переменных
├── README.md                 # Эта документация
├── install.sh                # Установка зависимостей
├── setup.sh                  # Конфигурация (/opt/notes/.env)
├── deploy.sh                 # Production deployment
├── local.ini                 # CouchDB server config
├── couchdb-backup.sh         # Backup script
└── scripts/                  # Helper scripts
```

## 🔧 Требования

### Обязательные
- Docker 20.10+
- Docker Compose v2+
- Family Budget nginx running (`familybudget-nginx` container)
- Docker network `familybudget_familybudget` exists

### Проверка зависимостей
```bash
# Проверить Family Budget nginx
docker ps | grep familybudget-nginx

# Проверить docker network
docker network ls | grep familybudget_familybudget

# Проверить CouchDB running
docker ps | grep familybudget-couchdb-notes
```

## 🛠️ Управление

### Запуск
```bash
cd notes/
docker compose -f docker-compose.notes.yml up -d
```

### Остановка
```bash
cd notes/
docker compose -f docker-compose.notes.yml down
```

### Логи
```bash
docker logs familybudget-couchdb-notes
docker logs -f familybudget-couchdb-notes  # Follow mode
```

### Health check
```bash
# CouchDB health endpoint
curl http://localhost:5984/_up

# Через nginx (требует настройки NOTES_DOMAIN в /etc/hosts)
curl http://notes.localhost/_up
```

### Backup
```bash
# Manual backup
cd /opt/notes
bash couchdb-backup.sh

# Backups сохраняются в: /opt/notes/backups/
```

## ⚙️ Конфигурация

### CouchDB Settings (`local.ini`)

```ini
[couchdb]
single_node=true                    # Single-node mode
max_document_size = 50000000        # 50MB (для attachments)

[chttpd]
require_valid_user = true           # Authentication required
max_http_request_size = 4294967296  # 4GB

[httpd]
enable_cors = true                  # CORS для Obsidian

[cors]
origins = app://obsidian.md,capacitor://localhost,http://localhost
```

### Environment Variables

Все переменные в `/opt/notes/.env`:

| Переменная | Описание | Пример |
|------------|----------|--------|
| `COUCHDB_USER` | CouchDB admin user | `admin` |
| `COUCHDB_PASSWORD` | CouchDB admin password (auto-generated) | `abc123...` (32 hex) |
| `NOTES_DOMAIN` | Subdomain for nginx | `notes.localhost` |
| `NOTES_DATA_DIR` | Data directory | `/opt/notes/data` |
| `NOTES_BACKUP_DIR` | Backups directory | `/opt/notes/backups` |
| `COUCHDB_PORT` | CouchDB port | `5984` |

## 🔐 Security

### Firewall (UFW)
Настроен автоматически через `install.sh`:
- ✅ SSH (22) - разрешен
- ✅ HTTPS (443) - разрешен
- ❌ HTTP (80) - **закрыт** (открывается только для certbot renewal)
- ❌ Все остальные порты - закрыты

### SSL/TLS
- Автоматическое получение сертификатов через Let's Encrypt
- Auto-renewal с UFW hooks (безопасное управление портом 80)
- Современные TLS настройки (TLSv1.2+, HSTS)
- HTTP → HTTPS редирект

### CouchDB
- Порт 5984 bind только к 127.0.0.1 (не доступен извне)
- Доступ **только** через nginx reverse proxy
- Безопасный пароль (генерируется автоматически)
- Authentication required

### Password Generation
`setup.sh` автоматически генерирует безопасный пароль:
```bash
openssl rand -hex 32  # 64 characters (256 bits)
```

## 💾 Automatic Backups

Настраиваются через `setup.sh` (опционально):
- **Расписание:** Ежедневно в 3:00 AM
- **Локально:** /opt/notes/backups/ (хранится 7 дней)
- **S3:** Загрузка в S3-compatible storage (опционально)
- **Логи:** /opt/notes/logs/backup.log

### Ручной запуск backup
```bash
bash /opt/notes/couchdb-backup.sh
```

### Проверка статуса backups
```bash
# Локальные backups
ls -lh /opt/notes/backups/

# Последний лог
tail -f /opt/notes/logs/backup.log

# Cron job
crontab -l | grep couchdb-backup
```

## 🐛 Troubleshooting

### Ошибка: "Family Budget nginx not running"
```bash
# Запустите основное приложение Family Budget
cd ~/familyBudget
./deploy.sh --profile full
```

### Ошибка: "Docker network familybudget_familybudget not found"
```bash
# Создайте network (делается автоматически при запуске Family Budget)
docker network create familybudget_familybudget
```

### Ошибка: "env_file: /opt/notes/.env: no such file"
```bash
# Запустите setup для создания .env
cd ~/familyBudget/notes
bash setup.sh
```

### CouchDB не отвечает на health check
```bash
# Проверить логи
docker logs familybudget-couchdb-notes

# Проверить порт
netstat -tuln | grep 5984

# Рестарт
docker compose -f docker-compose.notes.yml restart
```

### Backup fails
```bash
# Проверить права доступа
ls -la /opt/notes/backups/

# Создать директорию если не существует
sudo mkdir -p /opt/notes/backups
sudo chown -R $(whoami):$(whoami) /opt/notes
```

## 📚 Интеграция с Obsidian

### Установка плагина
1. Obsidian → Settings → Community Plugins
2. Поиск: "Self-hosted LiveSync"
3. Install & Enable

### Настройка синхронизации
1. Plugin Settings → Setup wizard
2. URI: `http://notes.localhost` (dev) или `https://notes.yourdomain.com` (prod)
3. Username: `admin`
4. Password: из `/opt/notes/.env` (`COUCHDB_PASSWORD`)
5. Database name: `obsidian` (или custom)

### Первая синхронизация
1. Choose "Remote database to Local" или "Local to Remote"
2. Sync → Start
3. Wait for initial sync to complete

## 🔄 Updates

### Обновление Notes
```bash
# Pull latest changes
cd ~/familyBudget
git pull

# Redeploy notes (production)
cd notes/
./deploy.sh

# Redeploy notes (development)
docker compose -f docker-compose.notes.yml pull
docker compose -f docker-compose.notes.yml up -d
```

## 📊 Monitoring

### Resource Usage
```bash
docker stats familybudget-couchdb-notes
```

**Лимиты:**
- CPU: 0.5 cores max, 0.1 cores reserved
- Memory: 512MB max, 128MB reserved

### Disk Usage
```bash
du -sh /opt/notes/data
du -sh /opt/notes/backups
```

## 🔗 Links

- [CouchDB Documentation](https://docs.couchdb.org/)
- [Obsidian Self-hosted LiveSync](https://github.com/vrtmrz/obsidian-livesync)
- [Family Budget Main App](../README.md)

---

**Version:** 5.1.0
**Last Updated:** 2025-11-16
