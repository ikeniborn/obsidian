---
wiki_sources:
  - "[[setup.sh]]"
  - "[[CLAUDE.md]]"
wiki_updated: 2026-05-20
wiki_status: developing
wiki_outgoing_links:
  - "[[deploy]]"
  - "[[env-конфигурация]]"
  - "[[ufw-setup]]"
wiki_external_links: []
tags: [scripting, infrastructure]
aliases: ["setup.sh", "конфигурация окружения", "настройка"]
---

# setup.sh

Интерактивный скрипт конфигурации окружения. Создаёт `/opt/notes/.env` с параметрами развёртывания. Второй шаг в цепочке `install.sh → setup.sh → deploy.sh`. Требует прав sudo для настройки firewall и systemd.

## Основные характеристики

Интерактивно запрашивает и сохраняет:
- **Docker proxy** — опционально, для ограниченных сетей/заблокированного Docker Hub
- **CERTBOT_EMAIL** — email для Let's Encrypt
- **NOTES_DOMAIN** — домен (например, `notes.example.com`)
- **Бэкенд** — CouchDB / ServerPeer / Both
- **S3-учётные данные** — опционально для резервного копирования

## Конфигурация по бэкенду

### CouchDB
- Генерирует `COUCHDB_PASSWORD` (64-символьный hex через `openssl rand -hex 32`)
- Задаёт `COUCHDB_CONTAINER_NAME`, `COUCHDB_PORT`, `COUCHDB_LOCATION`

### ServerPeer
- Определяет внешний IP сервера (`curl -s ifconfig.me`)
- Генерирует TURN-учётные данные (`TURN_USERNAME=obsidian`, `TURN_PASSWORD`)
- **Автоматически открывает TURN-порты в UFW**: 3478/udp, 3478/tcp, 49152–65535/udp
- Задаёт `SERVERPEER_STUN_SERVERS`, `SERVERPEER_TURN_SERVERS`

## Планировщики резервного копирования

Создаёт systemd unit-файлы динамически в зависимости от бэкенда:
- CouchDB: `couchdb-backup.timer/service` (3:00 AM)
- ServerPeer: `serverpeer-backup.timer/service` (3:05 AM)
- Both: оба таймера

## Docker Proxy

При ограниченном сетевом доступе настраивает прокси для Docker daemon:
1. Создаёт `/etc/systemd/system/docker.service.d/http-proxy.conf`
2. Устанавливает `HTTP_PROXY`, `HTTPS_PROXY`, `NO_PROXY`
3. Перезапускает Docker
4. При неудаче — предлагает исправить DNS-хайджекинг через `/etc/hosts`

## Команды

```bash
sudo ./setup.sh
```

## Связанные концепции

- [[deploy]] — следующий шаг после setup
- [[env-конфигурация]] — файл, создаваемый setup
- [[ufw-setup]] — вызывается при выборе ServerPeer
