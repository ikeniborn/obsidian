---
wiki_sources:
  - "[[scripts/couchdb-backup.sh]]"
  - "[[scripts/s3_upload.py]]"
  - "[[CLAUDE.md]]"
wiki_updated: 2026-05-20
wiki_status: developing
wiki_outgoing_links:
  - "[[couchdb]]"
  - "[[env-конфигурация]]"
wiki_external_links: []
tags: [scripting, infrastructure, backup]
aliases: ["couchdb-backup.sh", "backup CouchDB", "резервное копирование"]
---

# couchdb-backup

Скрипт резервного копирования всех баз данных CouchDB с выгрузкой в S3-совместимое хранилище. Использует ресурсоограниченное выполнение (CPU, nice, ionice).

## Основные характеристики

| Параметр | Значение |
|----------|----------|
| Формат архива | `couchdb-YYYYMMDD.tar.gz` |
| Хранилище | `/opt/notes/backups/` (локально) + S3 (опционально) |
| Лог | `/opt/notes/logs/backup.log` |
| Retention | 7 дней (локально) |
| Расписание | ежедневно в 3:00 AM (через systemd timer или cron) |

## Алгоритм

1. Загружает конфигурацию из `/opt/notes/.env`
2. Валидирует наличие CouchDB-контейнера
3. Создаёт дамп всех БД через CouchDB REST API
4. Сжимает в tar.gz
5. Загружает в S3 через `s3_upload.py` (boto3)
6. Удаляет локальные архивы старше 7 дней

## S3-конфигурация

```bash
S3_ACCESS_KEY_ID=...
S3_SECRET_ACCESS_KEY=...
S3_BUCKET_NAME=...
S3_ENDPOINT_URL=https://storage.yandexcloud.net  # или AWS/MinIO
S3_REGION=ru-central1
# Приоритет префикса: COUCHDB_S3_BACKUP_PREFIX > S3_BACKUP_PREFIX > "couchdb-backups/"
COUCHDB_S3_BACKUP_PREFIX=couchdb-backups/
```

## Команды

```bash
# Ручной запуск
cd /opt/notes && bash scripts/couchdb-backup.sh

# Просмотр лога
tail -f /opt/notes/logs/backup.log

# Проверка расписания
systemctl list-timers couchdb-backup.timer
```

## Связанные концепции

- [[couchdb]] — источник данных для резервного копирования
- [[env-конфигурация]] — S3-учётные данные и параметры
