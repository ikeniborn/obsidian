---
wiki_sources:
  - "[[scripts/ssl-setup.sh]]"
  - "[[CLAUDE.md]]"
wiki_updated: 2026-05-20
wiki_status: stub
wiki_outgoing_links:
  - "[[ufw-setup]]"
  - "[[nginx]]"
  - "[[deploy]]"
wiki_external_links:
  - "https://letsencrypt.org/docs/"
tags: [scripting, infrastructure, ssl]
aliases: ["ssl-setup.sh", "certbot", "Let's Encrypt", "SSL сертификаты"]
---

# ssl-certbot

Скрипт получения и обновления SSL/TLS-сертификатов через Let's Encrypt (certbot). Интегрируется с UFW: временно открывает порт 80 только на время получения/обновления сертификата.

## Основные характеристики

- **Инструмент**: certbot
- **Сертификаты**: Let's Encrypt
- **Хранилище**: `/etc/letsencrypt/live/${NOTES_DOMAIN}/`
- **Авто-обновление**: каждые 60 дней (через хуки certbot)

## Интеграция с UFW

Создаёт certbot renewal hooks:
- **Pre-hook** (`/etc/letsencrypt/renewal-hooks/pre/ufw-open-80.sh`): открывает порт 80, останавливает `notes-nginx`
- **Post-hook** (`/etc/letsencrypt/renewal-hooks/post/ufw-close-80.sh`): закрывает порт 80, запускает `notes-nginx`

Порт 80 остаётся закрытым в UFW в штатном режиме.

## Проверка и тестирование

```bash
# Проверка срока действия сертификата
bash scripts/check-ssl-expiration.sh

# Тест обновления (dry run, без реального запроса)
bash scripts/test-ssl-renewal.sh

# Ручная проверка
openssl s_client -connect notes.example.com:443 -servername notes.example.com
```

## Связанные концепции

- [[ufw-setup]] — управляет портом 80 через хуки
- [[nginx]] — использует сертификаты для HTTPS
- [[deploy]] — вызывает ssl-setup после nginx-setup
