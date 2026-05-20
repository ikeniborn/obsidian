---
wiki_sources:
  - "[[docker-compose.serverpeer.yml]]"
  - "[[serverpeer/Dockerfile]]"
  - "[[CLAUDE.md]]"
wiki_updated: 2026-05-20
wiki_status: developing
wiki_outgoing_links:
  - "[[nginx]]"
  - "[[coturn]]"
  - "[[nostr-relay]]"
  - "[[сетевые-режимы]]"
wiki_external_links:
  - "https://github.com/vrtmrz/livesync-serverpeer"
tags: [infrastructure, docker, sync, p2p]
aliases: ["ServerPeer", "livesync-serverpeer", "notes-serverpeer", "P2P бэкенд"]
---

# ServerPeer

P2P-бэкенд для синхронизации Obsidian, альтернативный CouchDB. Реализует WebSocket-ретранслятор и WebRTC P2P соединения. Хранит данные в виде файлового vault (файловая система), а не базы данных.

## Основные характеристики

| Параметр | Значение |
|----------|----------|
| Образ | Собирается из `serverpeer/Dockerfile` |
| Runtime | Deno (denoland/deno:bin-latest) |
| Node.js | node:22.14-bookworm-slim |
| Имя контейнера | `notes-serverpeer` (через `SERVERPEER_CONTAINER_NAME`) |
| Порт | `127.0.0.1:3000:3000` (только localhost) |
| Хранилище | `/opt/notes/serverpeer-vault` (файловый vault) |
| CPU | 0.1 (резерв) — 0.5 (лимит) |
| Память | 128MB (резерв) — 512MB (лимит) |

## Компоненты P2P-стека

### WebSocket-ретранслятор (Nostr Relay)
- **Внутренний URL**: `ws://notes-nostr-relay:7000`
- **Внешний URL**: `wss://your-domain/serverpeer/`
- **Образ**: `scsibug/nostr-rs-relay:latest`
- Рекомендуется локальный relay (производительность и приватность)

### WebRTC (NAT traversal)
- **STUN**: Google Public STUN (`stun:stun.l.google.com:19302`) — определение внешнего IP
- **TURN**: Локальный coturn (`turn:server-ip:3478`) — relay при невозможности прямого P2P

## Зависимости

Полностью контейнеризировано — установка Deno, Node.js, git на хосте **не требуется**.

## Применение в проекте

ServerPeer выбирается при установке бэкенда `ServerPeer` или `Both` в `setup.sh`. При выборе автоматически:
1. Настраиваются TURN-порты в UFW (3478/udp, 3478/tcp, 49152–65535/udp)
2. Генерируются TURN-учётные данные
3. Конфигурируется coturn через `coturn-setup.sh`

### Проверка состояния

```bash
docker logs notes-serverpeer
docker compose -f docker-compose.serverpeer.yml restart
```

### Health check

Проверяет запущен ли процесс `deno run main.ts` (не HTTP endpoint).

## Связанные концепции

- [[coturn]] — TURN/STUN сервер для WebRTC
- [[nostr-relay]] — WebSocket ретранслятор для P2P сигнализации
- [[nginx]] — reverse proxy для WSS-соединений
