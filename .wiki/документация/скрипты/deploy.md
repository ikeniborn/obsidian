---
wiki_sources:
  - "[[deploy.sh]]"
  - "[[CLAUDE.md]]"
wiki_updated: 2026-05-20
wiki_status: developing
wiki_outgoing_links:
  - "[[nginx-setup]]"
  - "[[ssl-certbot]]"
  - "[[ufw-setup]]"
  - "[[install]]"
  - "[[setup]]"
wiki_external_links: []
tags: [scripting, infrastructure, docker]
aliases: ["deploy.sh", "деплой", "развёртывание"]
---

# deploy.sh

Главный оркестрирующий скрипт развёртывания Obsidian Sync Server. Координирует все этапы деплоя: настройку Nginx, получение SSL-сертификатов, развёртывание выбранного бэкенда и валидацию.

## Основные характеристики

- **Расположение**: `/opt/notes/` (или корень репозитория)
- **Требования**: предварительный запуск `install.sh` и `setup.sh`, наличие `/opt/notes/.env`
- **Версия**: 2.0.0

## Порядок выполнения

```
1. Валидация .env-конфигурации
2. nginx-setup.sh     → обнаружение/интеграция Nginx
3. ssl-setup.sh       → получение Let's Encrypt сертификатов
4. Применение nginx-конфига с SSL
5. Развёртывание бэкенда:
   - CouchDB: docker compose -f docker-compose.notes.yml up -d
   - ServerPeer: prepull образов → docker compose build → up
   - Both: оба бэкенда последовательно
6. coturn-setup.sh    → (только при ServerPeer)
7. fail2ban-setup.sh  → настройка intrusion prevention
8. Валидация развёртывания
9. Итоговый отчёт
```

## Особенности

### Pre-pull механизм для образов
При ограниченном сетевом доступе (proxy/DNS hijacking) `deploy.sh` предварительно скачивает базовые образы через `docker pull` (уважает proxy Docker daemon), а затем `docker build` использует кэш. Это обходит ограничение BuildKit, который не наследует прокси-настройки Docker.

```bash
# Предварительно скачивает:
docker pull denoland/deno:bin-latest
docker pull node:22.14-bookworm-slim
docker pull couchdb:3.3
```

### Определение необходимости обновления образов
Использует сравнение Image ID (не manifest digest) через `scripts/deploy-helpers.sh`. Совпадает с поведением Docker — не выполняет лишних pull для актуальных образов.

## Команды

```bash
# Запуск деплоя
./deploy.sh

# Перезапуск только CouchDB
docker compose -f docker-compose.notes.yml restart

# Остановка
docker compose -f docker-compose.notes.yml down
```

## Связанные концепции

- [[install]] — предшествует deploy (установка зависимостей)
- [[setup]] — предшествует deploy (конфигурация окружения)
- [[nginx-setup]] — вызывается из deploy
- [[ssl-certbot]] — вызывается из deploy
