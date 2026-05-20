---
wiki_sources:
  - "[[templates/couchdb.conf.template]]"
  - "[[templates/serverpeer.conf.template]]"
  - "[[templates/unified.conf.template]]"
  - "[[scripts/nginx-setup.sh]]"
  - "[[CLAUDE.md]]"
wiki_updated: 2026-05-20
wiki_status: developing
wiki_outgoing_links:
  - "[[couchdb]]"
  - "[[ssl-certbot]]"
  - "[[сетевые-режимы]]"
wiki_external_links:
  - "https://nginx.org/en/docs/"
tags: [infrastructure, docker, nginx]
aliases: ["Nginx", "notes-nginx", "reverse proxy", "обратный прокси"]
---

# Nginx

Reverse proxy (обратный прокси), используемый в Obsidian Sync Server для терминации SSL/TLS и проксирования запросов к бэкендам (CouchDB, ServerPeer). Поддерживает автоматическое обнаружение существующего экземпляра Nginx или развёртывание собственного контейнера.

## Основные характеристики

| Параметр | Значение |
|----------|----------|
| Имя контейнера | `notes-nginx` (конфигурируется через `NGINX_CONTAINER_NAME`) |
| Порты | 80 (HTTP → HTTPS редирект), 443 (HTTPS) |
| SSL | Let's Encrypt через certbot |
| Протоколы | TLSv1.2, TLSv1.3 |
| HSTS | `max-age=31536000` |

## Режимы обнаружения

`nginx-setup.sh` автоматически определяет тип существующего Nginx:

1. **docker** — запущен как Docker-контейнер
2. **systemd** — управляется через systemd
3. **standalone** — запущен отдельно (pgrep nginx)
4. **none** — не обнаружен → развёртывается собственный `notes-nginx`

## Шаблоны конфигурации

| Шаблон | Назначение |
|--------|-----------|
| `couchdb.conf.template` | Только CouchDB-бэкенд |
| `serverpeer.conf.template` | Только ServerPeer-бэкенд |
| `unified.conf.template` | Оба бэкенда одновременно |
| `docker-compose.nginx.template` | Docker Compose для собственного Nginx |

### Ключевые оптимизации в шаблонах

- **keepalive 32** — connection pooling (~5% снижение задержки)
- **WebSocket support** — критично для CouchDB `_changes` feed (real-time sync)
- **HTTP/1.1** — необходим для keep-alive и WebSocket
- **client_max_body_size 50M** — соответствует `max_document_size` CouchDB

## Применение в проекте

```nginx
# Пример: проксирование к CouchDB с WebSocket
upstream couchdb_backend {
    server ${COUCHDB_UPSTREAM}:5984 max_fails=0;
    keepalive 32;
}

location ${COUCHDB_LOCATION} {
    proxy_pass http://couchdb_backend;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    client_max_body_size 50M;
}
```

## Связанные концепции

- [[couchdb]] — основной проксируемый бэкенд
- [[ssl-certbot]] — SSL-сертификаты для HTTPS
- [[сетевые-режимы]] — как Nginx интегрируется в Docker-сеть
