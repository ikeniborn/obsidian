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

## Проблемы с деплоем

### Ошибка: cp cannot stat nginx config file
**Симптомы:** `deploy.sh` выдает ошибку:
```
cp: cannot stat '[2025-11-19 11:59:47] INFO: Generated nginx config: /home/user/obsidian/notes.conf...
```

**Причина:** Stdout contamination в функции `generate_nginx_config()` - лог-сообщение попадает в command substitution вместе с путем к файлу.

**Решение:**
- Проблема исправлена в версии 2.1.0+
- Обновите репозиторий: `git pull origin master`
- Или примените патч вручную: добавьте `>&2` после вызова `info()` в `scripts/nginx-setup.sh:91`

---

### Ошибка: Port 80 already in use (certbot)
**Симптомы:** `ssl-setup.sh` выдает ошибку:
```
Could not bind TCP port 80 because it is already in use by another process
```

**Причина:** Certbot в режиме `--standalone` пытается запустить HTTP-сервер на порту 80, но порт занят nginx или другим процессом.

**Диагностика:**
```bash
# Проверить что занимает порт 80
sudo netstat -tulpn | grep ':80 '
# или
sudo lsof -i :80
```

**Решение:**
- **Автоматическое (версия 2.1.0+):** Скрипт автоматически останавливает nginx на время получения сертификата
- **Вручную:**
  ```bash
  # Остановить nginx
  docker stop <nginx-container>
  # или
  sudo systemctl stop nginx

  # Запустить ssl-setup
  bash scripts/ssl-setup.sh

  # Запустить nginx обратно
  docker start <nginx-container>
  # или
  sudo systemctl start nginx
  ```

---

### Ошибка: NETWORK_NAME variable is not set
**Симптомы:** `deploy.sh` выдает ошибку:
```
WARN[0000] The "NETWORK_NAME" variable is not set. Defaulting to a blank string.
failed to create network : invalid name: name is empty
```

**Причина:** Файл `/opt/notes/.env` не существует или не содержит требуемую переменную `NETWORK_NAME`.

**Решение:**
```bash
# 1. Проверить существование .env
ls -la /opt/notes/.env

# 2. Если файла нет - запустить setup
bash setup.sh

# 3. Если файл есть - проверить переменные
cat /opt/notes/.env | grep NETWORK_NAME

# 4. Если NETWORK_NAME пустая - запустить setup повторно
bash setup.sh
```

**Precondition:** `setup.sh` ДОЛЖЕН быть выполнен ПЕРЕД `deploy.sh`

---

### Ошибка: UFW is not active
**Симптомы:** `deploy.sh` выдает предупреждение:
```
[ERROR] UFW is not active. Please run install.sh first
```

**Причина:** Firewall UFW не активирован (либо `install.sh` не был запущен, либо UFW был отключен вручную).

**Решение:**
```bash
# ВНИМАНИЕ: Убедитесь что порт SSH (22) открыт ПЕРЕД активацией UFW!

# 1. Проверить UFW status
sudo ufw status

# 2. Разрешить SSH (КРИТИЧНО!)
sudo ufw allow 22/tcp

# 3. Разрешить HTTPS
sudo ufw allow 443/tcp

# 4. Активировать UFW
sudo ufw enable

# 5. Проверить правила
sudo ufw status numbered
```

**Precondition:** `install.sh` ДОЛЖЕН быть выполнен ПЕРЕД `deploy.sh`

---

### Pre-deployment Checklist
Перед запуском `deploy.sh` убедитесь что:

- ✅ `install.sh` выполнен успешно
- ✅ UFW активирован: `sudo ufw status` → `Status: active`
- ✅ Порты открыты: `sudo ufw status | grep -E '22|443'`
- ✅ `setup.sh` выполнен успешно
- ✅ `/opt/notes/.env` существует: `ls -la /opt/notes/.env`
- ✅ Критичные переменные заполнены:
  ```bash
  source /opt/notes/.env
  echo "NETWORK_NAME=$NETWORK_NAME"
  echo "NOTES_DOMAIN=$NOTES_DOMAIN"
  echo "COUCHDB_PASSWORD=$COUCHDB_PASSWORD"
  ```
- ✅ DNS указывает на сервер: `nslookup notes.example.com`

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
docker logs familybudget-notes-couchdb

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
