---
wiki_sources:
  - "[[local.ini]]"
  - "[[CLAUDE.md]]"
wiki_updated: 2026-05-20
wiki_status: developing
wiki_outgoing_links:
  - "[[couchdb]]"
wiki_external_links:
  - "https://docs.couchdb.org/en/stable/config/index.html"
tags: [infrastructure, configuration, couchdb]
aliases: ["local.ini", "CouchDB конфигурация"]
---

# local.ini (CouchDB конфигурация)

Конфигурационный файл CouchDB, монтируемый в контейнер как volume. Оптимизирован для production-использования с Obsidian Self-hosted LiveSync.

## Основные секции

### [couchdb]
```ini
single_node=true                 # одиночный узел
max_document_size = 50000000     # 50 МБ (для вложений)
delayed_commits = true           # пакетная запись (3-5x быстрее)
file_compression = snappy        # быстрое сжатие (20-30% экономии)
max_dbs_open = 1000              # лучшая производительность при многих БД
attachment_compression_level = 6 # сбалансированное сжатие вложений
```

### [chttpd]
```ini
require_valid_user = true        # аутентификация обязательна
max_http_request_size = 104857600  # 100 МБ (защита от DoS)
max_connections = 200            # пул соединений
```

### [cors]
```ini
origins = app://obsidian.md,capacitor://localhost,http://localhost
credentials = true
methods = GET, PUT, POST, HEAD, DELETE
```

### [compaction_daemon] — автоматическая компакция
```ini
check_interval = 300             # проверка каждые 5 минут
min_file_size = 52428800        # компактировать только БД > 50 МБ
strict_window = false            # без ограничений по времени суток
```

### [compactions]
```ini
_default = [{db_fragmentation, "20%"}, {view_fragmentation, "20%"}]
# Компактировать при фрагментации > 20%
```

### [log]
```ini
level = warning    # только предупреждения и выше (меньше шума)
```

## Применение в проекте

Файл монтируется в контейнер через Docker volume:
```yaml
volumes:
  - ./local.ini:/opt/couchdb/etc/local.ini
```

Изменения вступают в силу после перезапуска контейнера CouchDB.

## Мониторинг

```bash
# Проверка фрагментации и состояния компакции
bash /opt/notes/scripts/monitor-couchdb.sh
# Предупреждение при > 20% фрагментации, алерт при > 30%
```

## Связанные концепции

- [[couchdb]] — компонент, использующий эту конфигурацию
