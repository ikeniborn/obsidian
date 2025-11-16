# Security Documentation

## Firewall Architecture

### UFW Configuration

Obsidian Sync Server использует whitelist подход к firewall:

```bash
# Default policy
ufw default deny incoming
ufw default allow outgoing

# Allowed ports
ufw allow 22/tcp    # SSH
ufw allow 443/tcp   # HTTPS
```

**Принципы:**
- **Deny by default** - все входящие соединения блокируются
- **Whitelist approach** - разрешены только необходимые порты
- **Минимальная поверхность атаки** - только SSH и HTTPS

### Port Management Strategy

| Port | Protocol | Status | Purpose | Доступ |
|------|----------|--------|---------|--------|
| 22   | TCP      | ✅ OPEN | SSH управление | Admin only |
| 80   | TCP      | ❌ CLOSED | HTTP (unused) | Blocked (except certbot) |
| 443  | TCP      | ✅ OPEN | HTTPS | Public |
| 5984 | TCP      | 🔒 LOCALHOST | CouchDB | Via nginx only |

**Port 80 Special Handling:**
- По умолчанию **закрыт** в UFW
- Открывается **временно** только для certbot renewal
- Автоматически закрывается после renewal
- Управляется через UFW hooks

## SSL/TLS Configuration

### Certificate Management

**Let's Encrypt Integration:**
- Автоматическое получение сертификатов через certbot
- DNS-based validation (требует A-record)
- Auto-renewal каждые 60 дней (сертификаты действительны 90 дней)

**Renewal Hooks:**
```bash
# Pre-hook: /etc/letsencrypt/renewal-hooks/pre/ufw-open-80.sh
ufw allow 80/tcp

# Post-hook: /etc/letsencrypt/renewal-hooks/post/ufw-close-80.sh
ufw delete allow 80/tcp
```

### TLS Settings

Nginx конфигурация (`scripts/nginx-setup.sh`):

```nginx
# Modern TLS only
ssl_protocols TLSv1.2 TLSv1.3;

# Strong ciphers
ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256...';
ssl_prefer_server_ciphers off;

# Security headers
add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
add_header X-Frame-Options "SAMEORIGIN" always;
add_header X-Content-Type-Options "nosniff" always;
```

**Security Features:**
- TLSv1.2+ only (отключен TLSv1.0/1.1)
- HSTS с 1 годом (принудительный HTTPS)
- X-Frame-Options против clickjacking
- X-Content-Type-Options против MIME sniffing

## Certbot UFW Hooks Mechanism

### Проблема
Let's Encrypt требует доступ к порту 80 для HTTP-01 challenge, но мы хотим держать порт 80 закрытым для безопасности.

### Решение
Автоматические UFW hooks для временного открытия порта 80.

### Workflow

```
1. Certbot renewal triggered (cron: 0 */12 * * *)
   ↓
2. Pre-hook запускается
   → ufw allow 80/tcp
   ↓
3. Certbot выполняет HTTP-01 challenge
   → Let's Encrypt подключается к порту 80
   ↓
4. Post-hook запускается (независимо от успеха/провала)
   → ufw delete allow 80/tcp
   ↓
5. Port 80 снова закрыт
```

### Установка Hooks

```bash
# scripts/ssl-setup.sh автоматически создает:

# Pre-hook
cat > /etc/letsencrypt/renewal-hooks/pre/ufw-open-80.sh <<'EOF'
#!/bin/bash
ufw allow 80/tcp
EOF
chmod +x /etc/letsencrypt/renewal-hooks/pre/ufw-open-80.sh

# Post-hook
cat > /etc/letsencrypt/renewal-hooks/post/ufw-close-80.sh <<'EOF'
#!/bin/bash
ufw delete allow 80/tcp
EOF
chmod +x /etc/letsencrypt/renewal-hooks/post/ufw-close-80.sh
```

### Тестирование Renewal

```bash
# Dry run (не меняет сертификаты)
certbot renew --dry-run

# Проверка что порт 80 закрыт после теста
sudo ufw status | grep 80
# Не должно показывать ALLOW
```

## Network Isolation

### CouchDB Port Binding

CouchDB bind к `127.0.0.1` **только**:

```yaml
# docker-compose.notes.yml
services:
  couchdb:
    ports:
      - "127.0.0.1:5984:5984"  # Localhost only
```

**Результат:**
- CouchDB **недоступен** извне
- Доступ только через nginx reverse proxy
- Nginx выполняет SSL termination и authentication

### Nginx Reverse Proxy

```nginx
location / {
    proxy_pass http://127.0.0.1:5984;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}
```

**Преимущества:**
- Единая точка входа (HTTPS only)
- Централизованное логирование
- Rate limiting возможен
- SSL offloading

## Security Audit Checklist

### Pre-deployment

- [ ] UFW установлен и активен
- [ ] Только порты 22 и 443 открыты
- [ ] SSH использует key-based authentication (опционально)
- [ ] CouchDB password сгенерирован (32+ символов)
- [ ] `.env` файл имеет права `600` (читается только владельцем)

### Post-deployment

```bash
# 1. UFW status
sudo ufw status verbose
# Ожидаемый результат:
# Status: active
# 22/tcp ALLOW IN
# 443/tcp ALLOW IN

# 2. Port scanning (external)
nmap -p 1-65535 <server-ip>
# Ожидаемый результат:
# 22/tcp   open  ssh
# 443/tcp  open  https

# 3. CouchDB не доступен извне
curl -I http://<server-ip>:5984
# Ожидаемый результат: timeout или connection refused

# 4. CouchDB доступен локально
curl http://localhost:5984/_up
# Ожидаемый результат: {"status":"ok"}

# 5. HTTPS работает
curl -I https://<your-domain>
# Ожидаемый результат: HTTP/2 200

# 6. SSL certificate valid
openssl s_client -connect <your-domain>:443 -servername <your-domain> </dev/null
# Проверить: Verify return code: 0 (ok)

# 7. HSTS header присутствует
curl -I https://<your-domain> | grep -i strict
# Ожидаемый результат: Strict-Transport-Security: max-age=31536000

# 8. Certbot hooks существуют
ls -la /etc/letsencrypt/renewal-hooks/{pre,post}/
# Ожидаемый результат:
# pre/ufw-open-80.sh (executable)
# post/ufw-close-80.sh (executable)
```

### Ongoing Monitoring

```bash
# Еженедельно
- Проверить UFW status
- Проверить SSL expiration (bash scripts/check-ssl-expiration.sh)
- Проверить failed login attempts (grep "Failed password" /var/log/auth.log)

# Ежемесячно
- Обновить систему (apt update && apt upgrade)
- Проверить Docker images на уязвимости
- Review backup logs
```

## Incident Response Plan

### Подозрение на компрометацию

**Шаг 1: Изоляция**
```bash
# Временно заблокировать все входящие соединения
sudo ufw default deny incoming
sudo ufw reload
```

**Шаг 2: Анализ**
```bash
# Проверить активные соединения
netstat -tulnp

# Проверить запущенные процессы
ps aux | grep -v "\[.*\]"

# Проверить логи nginx
docker logs familybudget-nginx | grep -E "POST|DELETE"

# Проверить логи auth
grep -i "failed\|error" /var/log/auth.log | tail -50
```

**Шаг 3: Восстановление**
```bash
# Сменить CouchDB password
cd /opt/notes
vim .env  # Обновить COUCHDB_PASSWORD
docker compose -f docker-compose.notes.yml restart

# Восстановить из backup если необходимо
bash couchdb-backup.sh restore <backup-file>

# Вернуть UFW правила
sudo ufw allow 22/tcp
sudo ufw allow 443/tcp
sudo ufw reload
```

### Утечка credentials

**Если .env файл скомпрометирован:**
1. Немедленно сменить `COUCHDB_PASSWORD`
2. Обновить S3 credentials (если используются)
3. Restart CouchDB container
4. Проверить CouchDB databases на подозрительные изменения
5. Review nginx access logs на подозрительную активность

### DDoS attack

**Митигация на уровне nginx:**
```nginx
# Rate limiting (добавить в nginx config)
limit_req_zone $binary_remote_addr zone=api:10m rate=10r/s;
limit_req zone=api burst=20 nodelay;
```

**Временная блокировка IP:**
```bash
# Заблокировать IP
sudo ufw deny from <attacker-ip>

# Разблокировать позже
sudo ufw delete deny from <attacker-ip>
```

## Best Practices

### Credential Management
- ✅ Используйте `openssl rand -hex 32` для генерации паролей
- ✅ Храните `.env` с правами `600`
- ✅ Никогда не коммитьте `.env` в git
- ✅ Используйте разные пароли для dev/prod

### Backup Security
- ✅ Шифруйте backups перед загрузкой в S3
- ✅ Используйте IAM credentials с минимальными правами (S3 PutObject только)
- ✅ Rotate S3 credentials регулярно
- ✅ Тестируйте restore процедуру

### Update Strategy
- ✅ Тестируйте updates в staging окружении
- ✅ Делайте backup перед major updates
- ✅ Подписаны на security advisories (Docker, CouchDB, Nginx)
- ✅ Auto-updates для критичных security patches

### Access Control
- ✅ SSH key-based authentication (отключить password auth)
- ✅ Разные пользователи для deployment и admin
- ✅ Используйте `sudo` вместо root login
- ✅ Регулярно review SSH authorized_keys
