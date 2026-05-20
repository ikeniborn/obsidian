---
wiki_sources:
  - "[[install.sh]]"
  - "[[CLAUDE.md]]"
wiki_updated: 2026-05-20
wiki_status: stub
wiki_outgoing_links:
  - "[[deploy]]"
  - "[[ufw-setup]]"
wiki_external_links: []
tags: [scripting, infrastructure]
aliases: ["install.sh", "установка зависимостей"]
---

# install.sh

Скрипт установки системных зависимостей для Obsidian Sync Server. Запускается первым в цепочке `install.sh → setup.sh → deploy.sh`. Требует прав sudo.

## Основные характеристики

Устанавливает и валидирует:
- **Docker** 20.10+ и Docker Compose v2+
- **Python 3** + `python3-boto3` (из системных пакетов, PEP 668 совместимо)
- **coturn** — TURN/STUN сервер для P2P WebRTC (при выборе ServerPeer)
- **openssl** — генерация паролей
- Создаёт структуру директорий `/opt/notes/`
- Опционально запускает `ufw-setup.sh`

## Команды

```bash
sudo ./install.sh
```

Лог установки: `/var/log/notes_install.log`

## Связанные концепции

- [[deploy]] — следующий шаг после install
- [[ufw-setup]] — опционально вызывается из install
