---
wiki_sources:
  - "[[scripts/ufw-setup.sh]]"
  - "[[CLAUDE.md]]"
wiki_updated: 2026-05-20
wiki_status: stub
wiki_outgoing_links:
  - "[[ssl-certbot]]"
  - "[[coturn]]"
  - "[[deploy]]"
wiki_external_links: []
tags: [scripting, infrastructure, security, networking]
aliases: ["ufw-setup.sh", "UFW", "firewall", "брандмауэр"]
---

# ufw-setup

Скрипт настройки UFW (Uncomplicated Firewall). Конфигурирует минимальную поверхность атаки: только SSH и HTTPS постоянно открыты, порт 80 закрыт (открывается только через certbot hooks).

## Правила UFW

| Порт | Протокол | Состояние | Назначение |
|------|----------|-----------|-----------|
| 22 | TCP | Всегда открыт | SSH (автоопределение порта из sshd_config) |
| 443 | TCP | Всегда открыт | HTTPS |
| 80 | TCP | Закрыт | Временно открывается при обновлении SSL |
| 5984 | TCP | Закрыт | CouchDB bind к 127.0.0.1, не экспонирован |
| 3000 | TCP | Закрыт | ServerPeer bind к 127.0.0.1, не экспонирован |
| 3478 | UDP/TCP | Открыт при ServerPeer | TURN/STUN signaling |
| 49152–65535 | UDP | Открыт при ServerPeer | TURN relay порты |

## Связанные концепции

- [[ssl-certbot]] — создаёт UFW hooks для управления портом 80
- [[coturn]] — требует открытых TURN-портов
- [[deploy]] — интегрирует ufw-setup в процесс развёртывания
