---
wiki_sources:
  - "[[CLAUDE.md]]"
wiki_updated: 2026-05-20
wiki_status: stub
wiki_outgoing_links:
  - "[[serverpeer]]"
wiki_external_links:
  - "https://github.com/scsibug/nostr-rs-relay"
tags: [infrastructure, docker, p2p, networking]
aliases: ["Nostr Relay", "nostr-rs-relay", "notes-nostr-relay", "WebSocket relay"]
---

# Nostr Relay

WebSocket-ретранслятор, используемый ServerPeer для P2P-сигнализации WebRTC. Не является ретранслятором данных — только передаёт сигналы установления WebRTC-соединений.

## Основные характеристики

| Параметр | Значение |
|----------|----------|
| Образ | `scsibug/nostr-rs-relay:latest` |
| Имя контейнера | `notes-nostr-relay` |
| Внутренний порт | 7000 (только внутри Docker-сети) |
| Внешний URL | `wss://your-domain/serverpeer/` |
| Протокол | WebSocket (Nostr protocol) |

## Применение в проекте

Relay предоставляет механизм для обмена WebRTC offer/answer между клиентами Obsidian и ServerPeer. После установления P2P-соединения через WebRTC сигнализацию, данные могут передаваться напрямую (без relay).

Рекомендуется использовать локальный relay (лучшая производительность и приватность). Альтернатива — внешние relay, например `wss://exp-relay.vrtmrz.net/`, но с дополнительной задержкой.

## Связанные концепции

- [[serverpeer]] — использует relay для P2P-сигнализации
