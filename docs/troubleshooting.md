# Troubleshooting Guide

## Проблемы с установкой

### UFW блокирует SSH доступ
**Симптомы:** После `install.sh` потерян SSH доступ

**Решение:**
1. Доступ через консоль (VPS provider console)
2. Проверить UFW: `sudo ufw status`
3. Разрешить SSH: `sudo ufw allow 22/tcp`
4. Перезапустить UFW: `sudo ufw reload`

### Nginx порт 443 занят
**Симптомы:** `deploy.sh` выдает ошибку "port 443 already in use"

**Решение:**
1. Проверить что занимает порт: `sudo netstat -tuln | grep 443`
2. Если другой nginx - будет использован автоматически
3. Если другое приложение - остановить или использовать другой порт

## Проблемы с SSL

### Certbot не может получить сертификат
**Симптомы:** `ssl-setup.sh` выдает ошибку

**Возможные причины:**
1. DNS не указывает на сервер
   - Проверка: `nslookup notes.example.com`
   - Решение: Настроить A-record в DNS
2. Порт 80 заблокирован firewall
   - Проверка: `sudo ufw status | grep 80`
   - Решение: Временно разрешить порт 80
3. Let's Encrypt rate limit
   - Решение: Подождать или использовать --staging

### SSL renewal не работает
**Симптомы:** Сертификат истек, renewal не происходит

**Диагностика:**
```bash
# Тест renewal
certbot renew --dry-run

# Проверка hooks
ls -la /etc/letsencrypt/renewal-hooks/{pre,post}/

# Логи certbot
cat /var/log/letsencrypt/letsencrypt.log
```

**Решение:**
- Проверить что UFW hooks существуют и исполняемы
- Запустить `bash scripts/ssl-setup.sh` повторно

## Проблемы с CouchDB

### CouchDB не отвечает
**Симптомы:** `curl http://localhost:5984/_up` выдает ошибку

**Диагностика:**
```bash
# Проверка контейнера
docker ps | grep couchdb

# Логи
docker logs familybudget-couchdb-notes

# Проверка портов
netstat -tuln | grep 5984
```

**Решение:**
```bash
# Перезапуск
cd /opt/notes
docker compose -f docker-compose.notes.yml restart

# Полный restart
docker compose -f docker-compose.notes.yml down
docker compose -f docker-compose.notes.yml up -d
```

## Проблемы с Backups

### S3 upload не работает
**Симптомы:** Backup создается локально, но не загружается в S3

**Диагностика:**
```bash
# Проверка credentials
cat /opt/notes/.env | grep S3_

# Тест upload
python3 /opt/notes/scripts/s3_upload.py /tmp/test.txt couchdb-backups/
```

**Решение:**
- Проверить S3 credentials в .env
- Проверить S3_ENDPOINT_URL
- Убедиться что boto3 установлен: `pip3 list | grep boto3`

### Cron job не запускается
**Симптомы:** Backups не создаются автоматически

**Диагностика:**
```bash
# Проверка cron job
crontab -l | grep couchdb-backup

# Логи cron
grep CRON /var/log/syslog | grep couchdb

# Права на скрипт
ls -la /opt/notes/couchdb-backup.sh
```

**Решение:**
```bash
# Пересоздать cron job
crontab -e
# Добавить:
# 0 3 * * * cd /opt/notes && bash couchdb-backup.sh >> /opt/notes/logs/backup.log 2>&1
```

## Проверка здоровья системы

### Комплексный health check
```bash
# Запустить все тесты
bash /opt/notes/scripts/run-all-tests.sh

# UFW status
sudo ufw status verbose

# SSL expiration
bash /opt/notes/scripts/check-ssl-expiration.sh

# CouchDB health
curl -s http://localhost:5984/_up

# Nginx config
docker exec <nginx-container> nginx -t

# Последний backup
ls -lh /opt/notes/backups/ | tail -1
```
