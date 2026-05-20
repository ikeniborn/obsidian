---
wiki_sources:
  - "[[scripts/nginx-setup.sh]]"
  - "[[CLAUDE.md]]"
wiki_updated: 2026-05-20
wiki_status: stub
wiki_outgoing_links:
  - "[[nginx]]"
  - "[[deploy]]"
  - "[[сетевые-режимы]]"
wiki_external_links: []
tags: [scripting, infrastructure, nginx]
aliases: ["nginx-setup.sh", "настройка nginx"]
---

# nginx-setup.sh

Скрипт обнаружения и интеграции Nginx. Определяет существующий экземпляр Nginx или разворачивает собственный контейнер `notes-nginx`. Вызывается из `deploy.sh`.

## Основные характеристики

Алгоритм обнаружения (в порядке приоритета):
1. Проверяет `docker ps` на наличие контейнера с именем `nginx`
2. Проверяет `systemctl is-active nginx`
3. Проверяет `pgrep nginx`
4. Если не найден → разворачивает собственный `notes-nginx`

## Функции

- `detect_existing_nginx()` — возвращает тип: docker/systemd/standalone/none
- `get_nginx_config_dir()` — определяет директорию конфигурации Nginx по типу
- Генерирует конфиг из шаблона (`templates/*.conf.template`)
- Перезагружает Nginx после применения конфигурации

## Связанные концепции

- [[nginx]] — компонент, настраиваемый этим скриптом
- [[deploy]] — вызывает nginx-setup в первую очередь
- [[сетевые-режимы]] — влияет на настройку upstream
