# PRD: Obsidian Sync Server

**Версия:** 1.0
**Дата:** 2025-11-16
**Автор:** Development Team
**Статус:** Draft

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Architecture](#architecture)
3. [Security Requirements](#security-requirements)
4. [Functional Requirements](#functional-requirements)
5. [Deployment Process](#deployment-process)
6. [Backup & Recovery](#backup--recovery)
7. [Acceptance Criteria](#acceptance-criteria)
8. [Known Limitations & Future Improvements](#known-limitations--future-improvements)

---

## Executive Summary

Obsidian Sync Server - это production-ready self-hosted решение для синхронизации заметок Obsidian через CouchDB. Проект предоставляет полностью автоматизированную установку и настройку сервера с упором на безопасность, надежность и простоту использования.

**Ключевые возможности:**
- Автоматическая установка всех зависимостей
- Интеграция с существующим Nginx или запуск собственного
- Автоматическое получение SSL сертификатов через Let's Encrypt
- Встроенная firewall защита (UFW)
- Автоматические S3 бэкапы
- Health checks и мониторинг

---

## Architecture

### Общая архитектура

```
┌─────────────────────────────────────────────────────────┐
│                     INTERNET                            │
└────────────────────┬────────────────────────────────────┘
                     │
                     │ HTTPS (443)
                     │
            ┌────────▼─────────┐
            │   UFW FIREWALL   │
            │  (SSH:22, 443)   │
            └────────┬─────────┘
                     │
                     │
            ┌────────▼─────────┐
            │      NGINX       │
            │  (Reverse Proxy) │
            │   SSL Termination│
            └────────┬─────────┘
                     │
                     │ HTTP (127.0.0.1:5984)
                     │
            ┌────────▼─────────┐
            │     CouchDB      │
            │   (Docker)       │
            │  Port: 5984      │
            │  Bind: localhost │
            └──────────────────┘
                     │
                     │ Backup
                     │
            ┌────────▼─────────┐
            │    S3 Bucket     │
            │  (Daily backups) │
            └──────────────────┘
```

### Компоненты системы

#### 1. CouchDB 3.3
- **Роль:** Database для синхронизации заметок
- **Деплой:** Docker container
- **Порт:** 5984 (bind только к 127.0.0.1)
- **Конфигурация:** local.ini (CORS, admin credentials)
- **Данные:** Volume mapping для персистентности

#### 2. Nginx
- **Роль:** Reverse proxy + SSL termination
- **Деплой:**
  - Обнаружение существующего системного Nginx
  - Или запуск собственного в Docker
- **Конфигурация:**
  - Reverse proxy на CouchDB (127.0.0.1:5984)
  - Редирект HTTP (80) → HTTPS (443)
  - SSL сертификаты Let's Encrypt

#### 3. Certbot
- **Роль:** Автоматическое получение и обновление SSL сертификатов
- **Интеграция:**
  - Pre/post hooks для временного открытия порта 80
  - UFW integration
  - Auto-renewal через systemd timer или cron

#### 4. UFW (Uncomplicated Firewall)
- **Роль:** Network security
- **Правила по умолчанию:**
  - SSH: 22 (allow)
  - HTTPS: 443 (allow)
  - HTTP: 80 (deny, временно открывается для certbot)
- **Управление:** Автоматическое через install.sh

#### 5. Docker & Docker Compose

**Network Architecture:**
- **Shared Mode:** использование `familybudget_familybudget` network для интеграции с Family Budget
- **Isolated Mode:** создание `obsidian_network` с автоматическим выбором свободной подсети (172.24-31.0.0/16)
- **Custom Mode:** пользовательская сеть через .env конфигурацию

**Auto-detection:**
- При deployment автоматически определяется наличие Family Budget
- Режим может быть переопределен через NETWORK_MODE в .env

**Isolation:**
- CouchDB изолирован в Docker network
- Port 5984 binds только на 127.0.0.1 (no external access)
- Доступ только через nginx reverse proxy

---

## Security Requirements

### Модель безопасности

#### Network Security (UFW)

**Принцип:** Deny all by default, allow only essential ports

**Firewall Rules:**
```bash
# Открытые порты
ufw allow 22/tcp    # SSH
ufw allow 443/tcp   # HTTPS

# Закрытые порты
ufw deny 80/tcp     # HTTP (по умолчанию)
ufw deny 5984/tcp   # CouchDB (прямой доступ запрещен)

# Default policies
ufw default deny incoming
ufw default allow outgoing
```

**Временное открытие порта 80 для Certbot:**
```bash
# Pre-hook (до certbot renewal)
ufw allow 80/tcp

# Post-hook (после certbot renewal)
ufw deny 80/tcp
```

**Критично:** Порт 5984 (CouchDB) НЕ должен быть доступен извне. Доступ только через nginx reverse proxy.

#### SSL/TLS Requirements

**Сертификаты:**
- Провайдер: Let's Encrypt
- Renewal: Автоматический через certbot
- Validity: 90 дней, renewal за 30 дней до истечения

**Nginx SSL Configuration:**
```nginx
ssl_protocols TLSv1.2 TLSv1.3;
ssl_ciphers HIGH:!aNULL:!MD5;
ssl_prefer_server_ciphers on;
```

**HTTP to HTTPS Redirect:**
```nginx
server {
    listen 80;
    server_name your-domain.com;
    return 301 https://$server_name$request_uri;
}
```

**Certbot Renewal Automation:**
- Systemd timer (preferred) или cron job
- UFW hooks для временного открытия порта 80
- Nginx reload после успешного renewal

#### CouchDB Security

**Admin Credentials:**
- Генерация: Автоматическая в setup.sh
- Формат: Случайные secure пароли (24+ символов)
- Хранение:
  - `.env` файл (chmod 600)
  - `local.ini` (CouchDB config, chmod 600)

**Network Binding:**
```ini
[chttpd]
bind_address = 127.0.0.1
port = 5984
```

**Критично:** CouchDB bind ТОЛЬКО к localhost. Внешний доступ ТОЛЬКО через nginx reverse proxy.

**CORS Configuration:**
```ini
[cors]
origins = https://your-domain.com
credentials = true
methods = GET, PUT, POST, HEAD, DELETE
headers = accept, authorization, content-type, origin, referer
```

**Access Control:**
- Доступ только для авторизованных пользователей
- Admin права изолированы от user прав
- Регулярный аудит access logs

#### S3 Backup Security

**Credentials Management:**
- Хранение: `/opt/notes/.env` (chmod 600)
- Формат:
  ```bash
  S3_ACCESS_KEY=...
  S3_SECRET_KEY=...
  S3_BUCKET_NAME=...
  S3_REGION=...
  ```
- Доступ: Только root или deployment user

**Backup Encryption (опционально):**
```bash
# Server-side encryption (SSE-S3)
aws s3 cp backup.tar.gz s3://bucket/ --sse

# Client-side encryption (GPG)
gpg --encrypt --recipient email@example.com backup.tar.gz
```

**S3 Bucket Policy:**
- Private by default
- Versioning enabled (для recovery)
- Lifecycle policy для retention management

**Security Checklist:**
- [ ] UFW enabled с правильными rules
- [ ] Порт 5984 НЕ доступен извне
- [ ] SSL сертификаты валидны и auto-renew работает
- [ ] CouchDB admin credentials случайные и secure
- [ ] `.env` файлы chmod 600
- [ ] S3 credentials изолированы
- [ ] HTTP → HTTPS redirect работает

---

## Functional Requirements

### FR-001: Автоматическая установка зависимостей

**Описание:** Скрипт `install.sh` автоматически устанавливает все необходимые системные зависимости.

**Зависимости:**
- Docker
- Docker Compose
- UFW (Uncomplicated Firewall)
- Nginx (опционально, если не установлен)
- Certbot
- AWS CLI (для S3 backups)
- git, curl, jq, tar

**Процесс:**
1. Проверка ОС (поддержка Ubuntu/Debian)
2. Обновление package manager (apt update)
3. Установка Docker + Docker Compose
4. Установка и настройка UFW
5. Проверка существующего Nginx
6. Установка Certbot с nginx plugin
7. Установка AWS CLI
8. Проверка успешности установки всех компонентов

**Acceptance Criteria:**
- Все зависимости установлены без ошибок
- Docker и Docker Compose запущены
- UFW активирован с базовыми правилами (SSH:22)
- Certbot готов к использованию

---

### FR-002: Интерактивная настройка конфигурации

**Описание:** Скрипт `setup.sh` проводит пользователя через интерактивную настройку всех параметров.

**Конфигурационные параметры:**
- Домен для Obsidian Sync
- Email для Let's Encrypt
- CouchDB admin credentials (генерация или ввод вручную)
- S3 backup настройки (bucket, region, credentials)
- Backup schedule (по умолчанию: 3:00 AM daily)

**Процесс:**
1. Проверка prerequisite (install.sh выполнен)
2. Интерактивные промпты для каждого параметра
3. Валидация входных данных (email format, domain reachability)
4. Генерация secure credentials (если не указаны)
5. Создание `.env` файла
6. Создание/обновление `local.ini` для CouchDB
7. Установка правильных permissions (chmod 600)
8. Сводка настроек для review

**Acceptance Criteria:**
- `.env` файл создан с корректными параметрами
- `local.ini` настроен для CouchDB
- Credentials случайные и secure (если auto-generated)
- Файлы имеют корректные permissions (600)

---

### FR-003: Умная Nginx интеграция

**Описание:** Система обнаруживает существующий Nginx и интегрируется с ним, либо запускает собственный в Docker. Поддерживает три сетевых режима.

**Scenario 1: Existing nginx (systemd/standalone)**
- Detection: проверка systemd, процессов
- Action: copy config to `/etc/nginx/sites-available/`
- Network: через localhost (127.0.0.1:5984)

**Scenario 2: Existing Family Budget Docker nginx**
- Detection: проверка container `familybudget-nginx`
- Action: copy config to nginx volume
- Network: shared (`familybudget_familybudget`)
- Mode: **shared**

**Scenario 3: No existing nginx (isolated deployment)**
- Action: deploy собственный nginx container
- Network: isolated (`obsidian_network` с автовыбором подсети)
- Mode: **isolated**
- SSL: Let's Encrypt через certbot

**Nginx Configuration Template:**
```nginx
server {
    listen 80;
    server_name ${DOMAIN};
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name ${DOMAIN};

    ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;

    location / {
        proxy_pass http://127.0.0.1:5984;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

**Acceptance Criteria:**
- Nginx обнаруживается корректно (системный vs Docker)
- Конфигурация создается автоматически
- Reverse proxy работает (CouchDB доступен через HTTPS)
- HTTP → HTTPS redirect функционирует

---

### FR-004: Автоматические SSL сертификаты

**Описание:** Автоматическое получение и обновление SSL сертификатов через Let's Encrypt.

**Процесс получения сертификата:**
1. Валидация домена (DNS проверка)
2. Временное открытие порта 80 через UFW
3. Запуск certbot: `certbot certonly --nginx -d ${DOMAIN} --email ${EMAIL}`
4. Закрытие порта 80 через UFW
5. Установка сертификатов в Nginx конфигурацию
6. Nginx reload

**Auto-renewal Setup:**
```bash
# Systemd timer (preferred)
systemctl enable certbot.timer
systemctl start certbot.timer

# Или cron job
0 3 * * * certbot renew --quiet --pre-hook "ufw allow 80/tcp" --post-hook "ufw deny 80/tcp && systemctl reload nginx"
```

**Renewal Hooks:**
- **Pre-hook:** `ufw allow 80/tcp` (открыть порт для ACME challenge)
- **Post-hook:** `ufw deny 80/tcp && systemctl reload nginx` (закрыть порт, reload nginx)

**Acceptance Criteria:**
- SSL сертификат получен успешно
- Nginx использует валидный сертификат
- Auto-renewal настроен и протестирован
- UFW hooks работают корректно
- HTTPS доступ к домену работает

---

### FR-005: Автоматические S3 бэкапы

**Описание:** Ежедневные автоматические бэкапы CouchDB в S3 bucket.

**Backup Process:**
1. Остановка записи в CouchDB (опционально)
2. Создание backup через CouchDB API или file copy
3. Архивирование (tar.gz)
4. Опционально: шифрование (GPG)
5. Загрузка в S3 bucket
6. Проверка успешности загрузки
7. Очистка локальных бэкапов старше N дней

**Backup Script (`couchdb-backup.sh`):**
```bash
#!/bin/bash
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/var/backups/couchdb"
BACKUP_FILE="couchdb_backup_${DATE}.tar.gz"

# Create backup
tar -czf ${BACKUP_DIR}/${BACKUP_FILE} /path/to/couchdb/data

# Upload to S3
aws s3 cp ${BACKUP_DIR}/${BACKUP_FILE} s3://${S3_BUCKET_NAME}/backups/

# Cleanup old local backups (keep 7 days)
find ${BACKUP_DIR} -name "couchdb_backup_*.tar.gz" -mtime +7 -delete
```

**Scheduling (Cron):**
```cron
0 3 * * * /opt/notes/couchdb-backup.sh >> /var/log/couchdb-backup.log 2>&1
```

**S3 Lifecycle Policy:**
- Хранение daily backups: 30 дней
- Transition to Glacier: после 30 дней
- Deletion: после 365 дней (настраивается)

**Acceptance Criteria:**
- Backup script создан и executable
- Cron job настроен (3:00 AM daily)
- S3 credentials работают
- Бэкап успешно загружается в S3
- Локальные старые бэкапы удаляются
- Логирование работает

---

### FR-006: HTTP to HTTPS Redirect

**Описание:** Все HTTP запросы автоматически перенаправляются на HTTPS.

**Nginx Configuration:**
```nginx
server {
    listen 80;
    server_name ${DOMAIN};
    return 301 https://$server_name$request_uri;
}
```

**Security Headers (опционально):**
```nginx
add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
add_header X-Frame-Options "SAMEORIGIN" always;
add_header X-Content-Type-Options "nosniff" always;
```

**Acceptance Criteria:**
- HTTP запросы возвращают 301 redirect
- HTTPS запросы обрабатываются корректно
- HSTS header присутствует (опционально)

---

### FR-007: CouchDB CORS для Obsidian

**Описание:** Настройка CORS для работы Obsidian LiveSync плагина.

**CORS Configuration (`local.ini`):**
```ini
[cors]
origins = https://${DOMAIN}
credentials = true
methods = GET, PUT, POST, HEAD, DELETE
headers = accept, authorization, content-type, origin, referer
```

**Acceptance Criteria:**
- CORS настроен в local.ini
- Obsidian LiveSync плагин может подключиться к серверу
- Нет CORS ошибок в browser console

---

### FR-008: Health Checks

**Описание:** Автоматические проверки здоровья всех компонентов системы.

**Health Check Script (`health-check.sh`):**
```bash
#!/bin/bash

# Check CouchDB
curl -f http://127.0.0.1:5984/_up || echo "CouchDB DOWN"

# Check Nginx
systemctl is-active nginx || echo "Nginx DOWN"

# Check SSL Certificate Validity
openssl x509 -in /etc/letsencrypt/live/${DOMAIN}/fullchain.pem -noout -checkend 604800 || echo "SSL expires in < 7 days"

# Check UFW status
ufw status | grep -q "Status: active" || echo "UFW NOT ACTIVE"

# Check Docker containers
docker ps | grep -q couchdb || echo "CouchDB container DOWN"
```

**Scheduling:**
```cron
*/5 * * * * /opt/notes/health-check.sh >> /var/log/health-check.log 2>&1
```

**Acceptance Criteria:**
- Health check script работает
- Проверяет все критичные компоненты
- Логирует результаты
- Опционально: отправка alerts (email/slack)

---

## Deployment Process

### Процесс установки (Новый сервер)

**Шаг 1: Подготовка сервера**
```bash
# Обновление системы
sudo apt update && sudo apt upgrade -y

# Клонирование репозитория
git clone https://github.com/your-repo/obsidian-sync-server.git
cd obsidian-sync-server
```

**Шаг 2: Установка зависимостей**
```bash
# Запуск install.sh (требует sudo)
sudo ./install.sh
```

**Что делает install.sh:**
- Устанавливает Docker, Docker Compose
- Устанавливает и настраивает UFW
- Устанавливает Nginx (если отсутствует)
- Устанавливает Certbot
- Устанавливает AWS CLI
- Активирует базовые firewall правила (SSH:22, HTTPS:443)

**Шаг 3: Настройка конфигурации**
```bash
# Запуск setup.sh (интерактивный)
./setup.sh
```

**Интерактивные промпты:**
1. Введите домен (например: sync.example.com)
2. Введите email для Let's Encrypt
3. Сгенерировать CouchDB admin пароль? (Y/n)
4. Настроить S3 бэкапы? (Y/n)
   - S3 bucket name
   - S3 region
   - S3 access key
   - S3 secret key
5. Backup schedule (по умолчанию: 3:00 AM)

**Что делает setup.sh:**
- Создает `.env` файл с параметрами
- Генерирует secure credentials (если auto-gen)
- Настраивает `local.ini` для CouchDB
- Устанавливает permissions (chmod 600)
- Выводит summary для review

**Шаг 4: Деплой всех сервисов**
```bash
# Запуск deploy.sh
./deploy.sh
```

**Что делает deploy.sh:**
1. Проверяет prerequisite (install + setup завершены)
2. Обнаруживает существующий Nginx или запускает Docker Nginx
3. Запускает CouchDB через docker-compose
4. Получает SSL сертификат через Certbot (с UFW hooks)
5. Настраивает Nginx reverse proxy
6. Настраивает auto-renewal для SSL
7. Настраивает S3 backup cron job
8. Настраивает health checks
9. Проверяет, что все сервисы работают
10. Выводит финальные инструкции и credentials

**Шаг 5: Валидация**
```bash
# Проверка статуса сервисов
docker ps
systemctl status nginx
ufw status

# Проверка доступности
curl https://your-domain.com/_up

# Проверка SSL
openssl s_client -connect your-domain.com:443 -servername your-domain.com
```

---

### Процесс обновления (Существующий сервер)

**Шаг 1: Backup текущей конфигурации**
```bash
# Создать backup .env и local.ini
cp .env .env.backup
cp local.ini local.ini.backup

# Backup CouchDB data (опционально)
./couchdb-backup.sh
```

**Шаг 2: Получить обновления**
```bash
git pull origin main
```

**Шаг 3: Запустить deploy.sh**
```bash
./deploy.sh
```

**Что делает deploy.sh при обновлении:**
- Обнаруживает существующую конфигурацию (.env)
- Останавливает текущие контейнеры
- Применяет новые изменения (docker-compose pull)
- Перезапускает контейнеры
- Проверяет health checks
- Rollback при ошибках (опционально)

**Шаг 4: Проверка**
```bash
# Проверка логов
docker logs couchdb
tail -f /var/log/nginx/error.log

# Health check
./health-check.sh
```

---

### Rollback Strategy

**Сценарий: Деплой завершился с ошибками**

**Автоматический Rollback (в deploy.sh):**
```bash
if ! ./health-check.sh; then
    echo "Health check FAILED. Rolling back..."
    git checkout HEAD~1
    docker-compose down
    docker-compose up -d
    echo "Rollback completed"
fi
```

**Ручной Rollback:**
```bash
# Откатить git к предыдущему коммиту
git log --oneline  # найти предыдущий commit hash
git checkout <previous-commit-hash>

# Восстановить .env из backup
cp .env.backup .env
cp local.ini.backup local.ini

# Перезапустить сервисы
docker-compose down
docker-compose up -d

# Проверить здоровье
./health-check.sh
```

**Восстановление из S3 Backup:**
```bash
# Скачать последний бэкап
aws s3 cp s3://${S3_BUCKET_NAME}/backups/latest.tar.gz ./

# Остановить CouchDB
docker-compose down

# Восстановить данные
tar -xzf latest.tar.gz -C /path/to/couchdb/data

# Запустить CouchDB
docker-compose up -d
```

---

### Мониторинг и логи

**Логи:**
- **CouchDB:** `docker logs couchdb`
- **Nginx:** `/var/log/nginx/access.log`, `/var/log/nginx/error.log`
- **Certbot:** `/var/log/letsencrypt/letsencrypt.log`
- **Backup:** `/var/log/couchdb-backup.log`
- **Health Check:** `/var/log/health-check.log`

**Мониторинг (базовый):**
```bash
# Проверка всех сервисов
systemctl status nginx
docker ps
ufw status verbose

# Проверка SSL expiration
certbot certificates

# Проверка disk space
df -h

# Проверка последнего бэкапа
ls -lh /var/backups/couchdb/
aws s3 ls s3://${S3_BUCKET_NAME}/backups/
```

**Мониторинг (advanced - опционально):**
- Prometheus + Grafana (metrics)
- ELK Stack (centralized logging)
- Uptimerobot или Pingdom (external monitoring)

---

## Backup & Recovery

### Backup Strategy

**Что бэкапится:**
1. **CouchDB databases** - все данные синхронизации
2. **CouchDB configuration** - `local.ini`
3. **Environment configuration** - `.env`
4. **Nginx configuration** - nginx config files
5. **SSL certificates** - Let's Encrypt certificates (опционально)

**Backup Schedule:**
- **Daily backups:** 3:00 AM (настраивается)
- **Retention policy:**
  - Локально: 7 дней
  - S3 Standard: 30 дней
  - S3 Glacier: 365 дней

**Backup Process:**
```bash
#!/bin/bash
# couchdb-backup.sh

set -e

DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/var/backups/couchdb"
BACKUP_NAME="couchdb_backup_${DATE}"
BACKUP_FILE="${BACKUP_NAME}.tar.gz"

# Create backup directory
mkdir -p ${BACKUP_DIR}

# Backup CouchDB data
docker exec couchdb couchdb-backup -b -H 127.0.0.1 -u admin -p ${COUCHDB_PASSWORD} -d /tmp/backup

# Copy backup from container
docker cp couchdb:/tmp/backup ${BACKUP_DIR}/${BACKUP_NAME}

# Add configuration files
cp .env ${BACKUP_DIR}/${BACKUP_NAME}/
cp local.ini ${BACKUP_DIR}/${BACKUP_NAME}/

# Create archive
tar -czf ${BACKUP_DIR}/${BACKUP_FILE} -C ${BACKUP_DIR} ${BACKUP_NAME}

# Upload to S3
aws s3 cp ${BACKUP_DIR}/${BACKUP_FILE} s3://${S3_BUCKET_NAME}/backups/ \
    --storage-class STANDARD \
    --metadata "backup-date=${DATE},retention=30days"

# Cleanup local backups older than 7 days
find ${BACKUP_DIR} -name "couchdb_backup_*.tar.gz" -mtime +7 -delete

# Cleanup temp backup directory
rm -rf ${BACKUP_DIR}/${BACKUP_NAME}

echo "Backup completed: ${BACKUP_FILE}"
echo "Uploaded to: s3://${S3_BUCKET_NAME}/backups/${BACKUP_FILE}"
```

**Backup Verification:**
```bash
# Проверка, что backup в S3
aws s3 ls s3://${S3_BUCKET_NAME}/backups/ --recursive | tail -n 5

# Проверка размера бэкапа (должен быть > 0)
aws s3 ls s3://${S3_BUCKET_NAME}/backups/latest.tar.gz --human-readable
```

---

### Recovery Process

#### Сценарий 1: Восстановление на том же сервере

**Шаг 1: Остановить сервисы**
```bash
docker-compose down
systemctl stop nginx
```

**Шаг 2: Скачать бэкап из S3**
```bash
# Список доступных бэкапов
aws s3 ls s3://${S3_BUCKET_NAME}/backups/

# Скачать нужный бэкап
aws s3 cp s3://${S3_BUCKET_NAME}/backups/couchdb_backup_20251116_030000.tar.gz ./
```

**Шаг 3: Распаковать бэкап**
```bash
tar -xzf couchdb_backup_20251116_030000.tar.gz
```

**Шаг 4: Восстановить данные**
```bash
# Восстановить CouchDB data
rm -rf /path/to/couchdb/data/*
cp -r couchdb_backup_20251116_030000/couchdb_data/* /path/to/couchdb/data/

# Восстановить конфигурацию
cp couchdb_backup_20251116_030000/.env ./
cp couchdb_backup_20251116_030000/local.ini ./
```

**Шаг 5: Запустить сервисы**
```bash
docker-compose up -d
systemctl start nginx
```

**Шаг 6: Проверка**
```bash
./health-check.sh
curl https://your-domain.com/_up
```

---

#### Сценарий 2: Восстановление на новом сервере (Disaster Recovery)

**Prerequisite:** Новый сервер подготовлен (Ubuntu/Debian)

**Шаг 1: Клонировать репозиторий**
```bash
git clone https://github.com/your-repo/obsidian-sync-server.git
cd obsidian-sync-server
```

**Шаг 2: Установить зависимости**
```bash
sudo ./install.sh
```

**Шаг 3: Скачать бэкап из S3**
```bash
aws s3 cp s3://${S3_BUCKET_NAME}/backups/latest.tar.gz ./
tar -xzf latest.tar.gz
```

**Шаг 4: Восстановить конфигурацию**
```bash
cp latest_backup/.env ./
cp latest_backup/local.ini ./
```

**Шаг 5: Обновить DNS (если новый IP)**
```bash
# Обновить A запись для домена на новый IP сервера
# Подождать propagation (5-60 минут)
```

**Шаг 6: Запустить deploy**
```bash
./deploy.sh
```

**Шаг 7: Восстановить CouchDB данные**
```bash
docker exec -it couchdb bash
# Внутри контейнера восстановить данные из бэкапа
```

**Шаг 8: Получить новый SSL сертификат**
```bash
# deploy.sh должен автоматически получить сертификат
# Если нет, то вручную:
sudo certbot certonly --nginx -d your-domain.com --email your-email@example.com
```

**Шаг 9: Проверка**
```bash
./health-check.sh
curl https://your-domain.com/_up
```

---

### Disaster Recovery Plan

**RTO (Recovery Time Objective):** 2 часа
**RPO (Recovery Point Objective):** 24 часа (daily backups)

**Disaster Scenarios:**

1. **Server Failure:**
   - Восстановление на новом сервере (см. Сценарий 2)
   - Время: ~1-2 часа
   - Потеря данных: до 24 часов (с момента последнего бэкапа)

2. **Data Corruption:**
   - Восстановление из S3 бэкапа (см. Сценарий 1)
   - Время: ~30 минут
   - Потеря данных: до 24 часов

3. **Regional Outage (S3 недоступен):**
   - Использование локальных бэкапов (7 дней retention)
   - Время: ~15 минут
   - Потеря данных: до 7 дней (если S3 недоступен > 7 дней)

4. **Human Error (случайное удаление):**
   - Восстановление конкретной базы из бэкапа
   - Время: ~20 минут
   - Потеря данных: до 24 часов

**Emergency Contacts:**
- DevOps Lead: [contact]
- Cloud Provider Support: [S3 support]
- Domain Registrar: [DNS support]

---

## Acceptance Criteria

### Phase 1: PRD Documentation (Текущая фаза)
- [x] PRD документ создан
- [x] Архитектура описана
- [x] Security Requirements детализированы
- [x] Functional Requirements документированы
- [x] Deployment Process описан
- [x] Backup & Recovery стратегия готова
- [x] Acceptance Criteria и Testing Plan созданы

### Phase 2: Core Scripts Implementation
- [ ] `install.sh` создан и протестирован
- [ ] `setup.sh` создан с интерактивными промптами
- [ ] `deploy.sh` создан с умной Nginx интеграцией
- [ ] `couchdb-backup.sh` создан и протестирован
- [ ] Все скрипты имеют error handling
- [ ] Syntax check passed для всех скриптов

### Phase 3: Docker & Configuration
- [ ] `docker-compose.notes.yml` создан
- [ ] CouchDB конфигурация (`local.ini`) настроена
- [ ] Nginx configuration template создан
- [ ] `.env.example` создан с документацией
- [ ] Все конфигурации валидны

### Phase 4: Security & SSL Implementation
- [ ] UFW rules настроены корректно
- [ ] Certbot integration с UFW hooks работает
- [ ] SSL сертификаты получаются автоматически
- [ ] Auto-renewal настроен и протестирован
- [ ] HTTP → HTTPS redirect работает
- [ ] Порт 5984 недоступен извне

### Phase 5: Testing & Validation
- [ ] Полный integration test пройден
- [ ] Security audit выполнен:
  - [ ] Port scanning (только 22, 443 открыты)
  - [ ] SSL validation (A+ rating на SSL Labs)
  - [ ] Credentials security проверена
- [ ] Backup/Recovery протестирован
- [ ] Health checks работают
- [ ] Documentation review завершен

---

## Known Limitations & Future Improvements

### Текущие ограничения

1. **Single-node CouchDB**
   - Ограничение: Нет built-in high availability
   - Impact: Downtime при обновлениях или сбоях сервера
   - Workaround: Быстрый recovery из S3 backups

2. **Базовый мониторинг**
   - Ограничение: Только health checks, нет metrics
   - Impact: Реактивное, а не проактивное решение проблем
   - Workaround: Регулярные manual checks

3. **S3-only backup destination**
   - Ограничение: Зависимость от AWS S3
   - Impact: Vendor lock-in
   - Workaround: Локальные бэкапы (7 дней)

4. **Manual SSL renewal при firewall issues**
   - Ограничение: UFW hooks могут сломаться
   - Impact: Необходимость manual intervention
   - Workaround: Мониторинг SSL expiration

5. **Ubuntu/Debian only**
   - Ограничение: Не протестировано на других дистрибутивах
   - Impact: Непредсказуемое поведение на RHEL/CentOS
   - Workaround: Использовать только поддерживаемые ОС

---

### Future Improvements

#### High Priority

**1. Multi-node CouchDB Cluster**
- Описание: CouchDB cluster для high availability
- Преимущества:
  - Zero-downtime deployments
  - Automatic failover
  - Horizontal scaling
- Требования:
  - 3+ nodes
  - Load balancer (HAProxy или Nginx upstream)
  - Shared storage или replication

**2. Prometheus + Grafana Monitoring**
- Описание: Полноценный metrics-based мониторинг
- Метрики:
  - CouchDB performance (request rate, latency, errors)
  - System resources (CPU, RAM, disk, network)
  - Nginx metrics (connections, request rate)
  - SSL certificate expiration
  - Backup success/failure
- Alerts:
  - Email/Slack при критичных событиях
  - PagerDuty integration для on-call

**3. Automated Integration Tests**
- Описание: CI/CD pipeline с автоматическими тестами
- Tests:
  - Deployment validation
  - Security scanning (OWASP ZAP)
  - SSL configuration testing
  - Backup/Recovery validation
- Tools: GitHub Actions, GitLab CI, или Jenkins

---

#### Medium Priority

**4. Multi-cloud Backup Support**
- Описание: Поддержка нескольких backup destinations
- Destinations:
  - AWS S3 (текущая)
  - Google Cloud Storage
  - Azure Blob Storage
  - Self-hosted MinIO
- Преимущества: Избежание vendor lock-in

**5. Web UI для управления**
- Описание: Простой web interface для:
  - Просмотр статуса сервисов
  - Управление бэкапами
  - Просмотр логов
  - Управление пользователями CouchDB
- Stack: Node.js + React или Python Flask

**6. Docker Swarm / Kubernetes Support**
- Описание: Orchestration для production deployments
- Преимущества:
  - Service discovery
  - Auto-scaling
  - Self-healing
  - Rolling updates
- Требования: Переписать docker-compose в Swarm/K8s manifests

---

#### Low Priority

**7. Ansible/Terraform Automation**
- Описание: Infrastructure as Code
- Преимущества:
  - Reproducible deployments
  - Version control для infrastructure
  - Multi-environment support (dev, staging, prod)

**8. Custom Domain для Backups**
- Описание: Использование custom S3 endpoint или CDN
- Преимущества: Независимость от AWS URLs

**9. Two-Factor Authentication для CouchDB**
- Описание: 2FA для admin доступа
- Реализация: Proxy с 2FA перед CouchDB

**10. Rate Limiting**
- Описание: Защита от abuse (nginx rate limiting)
- Конфигурация:
  ```nginx
  limit_req_zone $binary_remote_addr zone=couchdb:10m rate=10r/s;
  limit_req zone=couchdb burst=20;
  ```

---

### Roadmap

**Q1 2025:**
- ✅ Phase 1-5: Core implementation (текущий проект)
- [ ] Prometheus + Grafana мониторинг
- [ ] Automated integration tests

**Q2 2025:**
- [ ] Multi-node CouchDB cluster
- [ ] Web UI для управления
- [ ] Multi-cloud backup support

**Q3 2025:**
- [ ] Kubernetes support
- [ ] Ansible/Terraform automation

**Q4 2025:**
- [ ] 2FA для CouchDB
- [ ] Rate limiting
- [ ] Performance optimization

---

## Приложения

### A. Ссылки на связанные документы
- [README.md](../../README.md) - Getting Started
- [Phase Plans](../plans/) - Детальные планы для каждой фазы
- [Scripts Documentation](../scripts/) - Документация для всех скриптов (будет создана)

### B. Глоссарий
- **CouchDB:** Document-oriented NoSQL database
- **CORS:** Cross-Origin Resource Sharing
- **UFW:** Uncomplicated Firewall (frontend для iptables)
- **Let's Encrypt:** Бесплатный CA для SSL сертификатов
- **S3:** Amazon Simple Storage Service
- **RTO:** Recovery Time Objective
- **RPO:** Recovery Point Objective
- **ACME:** Automatic Certificate Management Environment

### C. Версионирование документа
- **v1.0 (2025-11-16):** Initial PRD creation
- Будущие версии будут документировать изменения в requirements

---

**Конец документа**
