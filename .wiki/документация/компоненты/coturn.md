---
wiki_sources:
  - "[[scripts/coturn-setup.sh]]"
  - "[[CLAUDE.md]]"
wiki_updated: 2026-05-20
wiki_status: stub
wiki_outgoing_links:
  - "[[serverpeer]]"
  - "[[ufw-setup]]"
wiki_external_links: []
tags: [infrastructure, p2p, networking]
aliases: ["coturn", "TURN сервер", "STUN сервер", "WebRTC relay"]
---

# coturn

TURN/STUN-сервер, обеспечивающий WebRTC P2P-соединения между клиентами Obsidian и ServerPeer при наличии NAT/firewall. Используется только при выборе ServerPeer-бэкенда.

## Основные характеристики

| Параметр | Значение |
|----------|----------|
| Пакет | `coturn` (apt) |
| Управление | systemd (`coturn.service`) |
| Конфигурация | `/etc/turnserver.conf` |
| Порт signaling | 3478 (UDP/TCP) |
| Relay-порты | 49152–65535 (UDP, динамически) |
| Логи | `/var/log/turnserver.log` |

## Настройка

Конфигурация полностью автоматическая:
1. `setup.sh` — генерирует TURN-учётные данные и открывает порты в UFW
2. `deploy.sh` — вызывает `coturn-setup.sh` при выборе ServerPeer

Переменные в `/opt/notes/.env`:
```bash
TURN_USERNAME=obsidian
TURN_PASSWORD=<random-32-char-hex>
TURN_REALM=turn.example.com
COTURN_LISTENING_PORT=3478
COTURN_EXTERNAL_IP=<server-public-ip>
```

## Команды

```bash
sudo systemctl status coturn
sudo systemctl restart coturn
sudo journalctl -u coturn -f
sudo tail -f /var/log/turnserver.log
# Тест TURN (с клиентской машины)
turnutils_uclient -v -u obsidian -w <TURN_PASSWORD> <SERVER_IP>
```

## Связанные концепции

- [[serverpeer]] — использует coturn для WebRTC NAT traversal
- [[ufw-setup]] — открывает необходимые порты TURN
