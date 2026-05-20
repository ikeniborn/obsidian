---
wiki_sources:
  - "[[CLAUDE.md]]"
  - "[[setup.sh]]"
  - "[[docker-compose.notes.yml]]"
wiki_updated: 2026-05-20
wiki_status: developing
wiki_outgoing_links:
  - "[[setup]]"
  - "[[couchdb]]"
  - "[[serverpeer]]"
  - "[[сетевые-режимы]]"
wiki_external_links: []
tags: [infrastructure, configuration]
aliases: [".env", "/opt/notes/.env", "environment variables", "переменные окружения"]
---

# .env конфигурация

Главный файл конфигурации Obsidian Sync Server. Создаётся `setup.sh`, расположен в `/opt/notes/.env`. Chmod 600 (только для root).

## Обязательные переменные

### Общие
```bash
NOTES_DOMAIN=notes.example.com
CERTBOT_EMAIL=admin@example.com
```

### Сеть (Docker)
```bash
NETWORK_MODE=shared|isolated|custom
NETWORK_NAME=<docker_network_name>
NETWORK_EXTERNAL=true|false
NETWORK_SUBNET=172.25.0.0/16   # только isolated
```

## CouchDB-переменные (при выборе CouchDB-бэкенда)

```bash
COUCHDB_USER=admin
COUCHDB_PASSWORD=<64-char-hex>   # openssl rand -hex 32
COUCHDB_CONTAINER_NAME=notes-couchdb
COUCHDB_PORT=5984
COUCHDB_LOCATION=/   # URL-путь для nginx
NOTES_DATA_DIR=/opt/notes/data
NOTES_BACKUP_DIR=/opt/notes/backups
NOTES_LOG_DIR=/opt/notes/logs
```

## ServerPeer-переменные (при выборе ServerPeer-бэкенда)

```bash
SERVERPEER_CONTAINER_NAME=notes-serverpeer
SERVERPEER_PORT=3000
SERVERPEER_LOCATION=/serverpeer/
SERVERPEER_APPID=<app-id>
SERVERPEER_ROOMID=<room-id>
SERVERPEER_PASSPHRASE=<passphrase>
SERVERPEER_RELAYS=ws://notes-nostr-relay:7000
SERVERPEER_NAME=<server-name>
SERVERPEER_AUTOBROADCAST=true
SERVERPEER_AUTOSTART=true
SERVERPEER_VAULT_NAME=<vault-name>
SERVERPEER_VAULT_DIR=/opt/notes/serverpeer-vault
SERVERPEER_STUN_SERVERS=stun:stun.l.google.com:19302
SERVERPEER_TURN_SERVERS=turn:obsidian:<password>@<ip>:3478
```

## TURN-переменные (только ServerPeer)

```bash
TURN_USERNAME=obsidian
TURN_PASSWORD=<random-32-char-hex>
TURN_REALM=turn.example.com
COTURN_LISTENING_PORT=3478
COTURN_EXTERNAL_IP=<server-public-ip>
```

## S3-переменные (опционально)

```bash
S3_ACCESS_KEY_ID=...
S3_SECRET_ACCESS_KEY=...
S3_BUCKET_NAME=...
S3_ENDPOINT_URL=https://storage.yandexcloud.net
S3_REGION=ru-central1
# При использовании только одного бэкенда:
S3_BACKUP_PREFIX=couchdb-backups/
# При использовании Both:
COUCHDB_S3_BACKUP_PREFIX=couchdb-backups/
SERVERPEER_S3_BACKUP_PREFIX=serverpeer-backups/
```

## Безопасность

- Пароли генерируются через `openssl rand -hex 32` (256-bit entropy)
- Файл имеет права `chmod 600` — только root
- Файл никогда не коммитится в git (в `.gitignore`)
- `.env.example` — шаблон без секретов для документации

## Связанные концепции

- [[setup]] — создаёт этот файл
- [[сетевые-режимы]] — NETWORK_* переменные
- [[couchdb]] — использует COUCHDB_* переменные
- [[serverpeer]] — использует SERVERPEER_* переменные
