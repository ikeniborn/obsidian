---
wiki_sources:
  - "[[docker-compose.notes.yml]]"
  - "[[local.ini]]"
  - "[[CLAUDE.md]]"
wiki_updated: 2026-05-20
wiki_status: developing
wiki_outgoing_links:
  - "[[nginx]]"
  - "[[couchdb-backup]]"
  - "[[local-ini-конфигурация]]"
wiki_external_links:
  - "https://docs.couchdb.org/en/stable/"
tags: [infrastructure, docker, couchdb]
aliases: ["CouchDB", "notes-couchdb", "база данных"]
---

# CouchDB

Документно-ориентированная база данных, используемая в качестве основного бэкенда синхронизации Obsidian Sync Server. Реализует клиент-серверную архитектуру для хранения и синхронизации заметок Obsidian через REST API.

## Основные характеристики

| Параметр | Значение |
|----------|----------|
| Образ | `couchdb:3.3` |
| Имя контейнера | `notes-couchdb` (конфигурируется через `COUCHDB_CONTAINER_NAME`) |
| Порт | `127.0.0.1:5984:5984` (только localhost, без внешнего доступа) |
| Хранилище данных | `/opt/notes/data` (volume) |
| Конфигурация | `./local.ini` (volume) |
| CPU | 0.1 (резерв) — 0.5 (лимит) |
| Память | 128MB (резерв) — 384MB (лимит, оптимизировано с 512MB) |

## Конфигурация

Ключевые настройки из `local.ini`:

- **Единственный узел**: `single_node=true`
- **Аутентификация обязательна**: `require_valid_user = true`
- **Макс. размер документа**: 50 МБ (`max_document_size = 50000000`)
- **CORS**: разрешён для `app://obsidian.md`, `capacitor://localhost`, `http://localhost`

### Оптимизации производительности

- **Отложенные коммиты**: `delayed_commits = true` — пакетная запись (окно 1с), ускорение в 3–5 раз
- **Сжатие файлов**: `file_compression = snappy` — быстрое сжатие (20–30% экономии)
- **Автокомпакция**: срабатывает при фрагментации >20%, только для БД >50 МБ
- **Лимит HTTP-запросов**: 100 МБ (`max_http_request_size = 104857600`)
- **Макс. соединений**: 200 (`max_connections = 200`)

## Применение в проекте

CouchDB используется только при выборе бэкенда `CouchDB` или `Both` в `setup.sh`. Порт 5984 привязан к `127.0.0.1` — внешний доступ возможен только через Nginx reverse proxy.

### Health check

```bash
curl http://localhost:5984/_up
curl -u admin:password http://localhost:5984/_all_dbs
```

### Управление контейнером

```bash
docker logs notes-couchdb
docker logs -f notes-couchdb
docker compose -f docker-compose.notes.yml restart
docker compose -f docker-compose.notes.yml down
docker stats notes-couchdb
```

## Связанные концепции

- [[nginx]] — reverse proxy перед CouchDB, обрабатывает HTTPS
- [[couchdb-backup]] — резервное копирование данных CouchDB
- [[local-ini-конфигурация]] — детали конфигурационного файла
