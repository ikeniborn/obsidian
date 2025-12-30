# Настройка P2P синхронизации для нескольких Vaults

## Архитектура

```
┌────────────────────────────────────────────────────────────┐
│         Nostr Relay (ОДИН сервер для всех vaults)          │
│         wss://sync.ikeniborn.ru/serverpeer                 │
│                                                            │
│  Маршрутизация по Room ID:                                │
│  • Room f6-9f-93-de-3a-5d → Work vault                    │
│  • Room bf-f2-a2          → Personal vault                │
└──────────┬─────────────────────────┬───────────────────────┘
           │                         │
    Work vault                  Personal vault
           │                         │
    ┌──────▼────────┐         ┌──────▼────────┐
    │ ServerPeer    │         │ P2P direct    │
    │ (always-on)   │         │ (между        │
    │               │         │  устройствами)│
    ├───────────────┤         ├───────────────┤
    │ Laptop        │         │ Phone         │
    │ Desktop       │         │ Tablet        │
    │ iPad          │         │ Home-PC       │
    └───────────────┘         └───────────────┘
```

## Принцип работы

**Один Nostr Relay** обслуживает оба vault:
- ✅ Relay маршрутизирует сообщения по **Room ID**
- ✅ Устройства из разных Room ID **не видят** друг друга
- ✅ Дополнительная защита через **Passphrase** (шифрование)

**Work vault** (с ServerPeer):
- ServerPeer = "всегда онлайн" peer, буфер изменений
- Полезен, когда не все устройства онлайн одновременно

**Personal vault** (без ServerPeer):
- Прямая P2P синхронизация между устройствами
- Работает отлично, если 2+ устройства часто онлайн одновременно

---

## Параметры подключения

### Vault 1: Work

**Для всех устройств с Work vault:**

```
Settings → Self-hosted LiveSync → Sync Settings → Peer-to-Peer Sync

✓ Enable P2P Sync
  Relay Servers:    wss://sync.ikeniborn.ru/serverpeer
  Room ID:          f6-9f-93-de-3a-5d
  Passphrase:       f64a50c669934a2f60a6f188aaa29506
  This device name: Work-Laptop (или Work-Desktop, Work-iPad и т.д.)

✓ Enable Auto Connect
✓ Enable Auto Broadcast
```

**Особенность:** В этой комнате работает ServerPeer - всегда доступный peer.

---

### Vault 2: Personal

**Для всех устройств с Personal vault:**

```
Settings → Self-hosted LiveSync → Sync Settings → Peer-to-Peer Sync

✓ Enable P2P Sync
  Relay Servers:    wss://sync.ikeniborn.ru/serverpeer
  Room ID:          bf-f2-a2
  Passphrase:       03737cfab0429ecdd9b2a61c2b3c0032
  This device name: Personal-Phone (или Personal-Tablet, Personal-PC и т.д.)

✓ Enable Auto Connect
✓ Enable Auto Broadcast
```

**Особенность:** Нет ServerPeer - устройства синхронизируются напрямую между собой.

---

## Пошаговая настройка в Obsidian

### Настройка первого устройства (например, Work-Laptop)

1. Откройте vault **Work** в Obsidian
2. Settings → Community Plugins → Self-hosted LiveSync
3. Перейдите в **Sync Settings** → **Peer-to-Peer Sync**
4. Включите **Enable P2P Sync**
5. Заполните параметры:
   - **Relay Servers**: `wss://sync.ikeniborn.ru/serverpeer`
   - **Room ID**: `f6-9f-93-de-3a-5d`
   - **Passphrase**: `f64a50c669934a2f60a6f188aaa29506`
   - **This device name**: `Work-Laptop`
6. Включите:
   - ✓ **Enable Auto Connect**
   - ✓ **Enable Auto Broadcast**
7. Сохраните настройки

**Проверка:** В правом нижнем углу Obsidian должен появиться индикатор P2P подключения.

### Настройка второго устройства (например, Personal-Phone)

1. Откройте vault **Personal** в Obsidian
2. Settings → Community Plugins → Self-hosted LiveSync
3. Перейдите в **Sync Settings** → **Peer-to-Peer Sync**
4. Включите **Enable P2P Sync**
5. Заполните параметры:
   - **Relay Servers**: `wss://sync.ikeniborn.ru/serverpeer`
   - **Room ID**: `bf-f2-a2` ← **ДРУГОЙ Room ID!**
   - **Passphrase**: `03737cfab0429ecdd9b2a61c2b3c0032` ← **ДРУГОЙ Passphrase!**
   - **This device name**: `Personal-Phone`
6. Включите:
   - ✓ **Enable Auto Connect**
   - ✓ **Enable Auto Broadcast**
7. Сохраните настройки

---

## Проверка подключения

### Проверка Work vault (с ServerPeer)

**На сервере:**
```bash
ssh ikenibornsync "docker logs notes-serverpeer --tail 20"
```

**Ожидаемый результат:**
```
peerId: 7gwbhQHhhfq5bTHrViP5 Sending Advertisement to All
peerId: 7gwbhQHhhfq5bTHrViP5 Received advertisement from XYZ123
```

Если видите "Received advertisement from" - ваше устройство успешно подключилось!

### Проверка Personal vault (без ServerPeer)

**На сервере:**
```bash
ssh ikenibornsync "docker logs notes-nostr-relay --tail 30"
```

**Ожидаемый результат:**
```
[INFO] new client connection (cid: abc123, ip: "78.107.114.37")
[INFO] origin: "app://obsidian.md", user-agent: "...obsidian..."
```

Вы должны видеть подключения от ваших устройств с Personal vault.

### В Obsidian

**Work vault (с ServerPeer):**
- Должны видеть минимум 2 peer'а: ServerPeer + ваше устройство
- При добавлении второго устройства - 3 peer'а

**Personal vault (без ServerPeer):**
- При включении на одном устройстве - 1 peer
- При включении на втором устройстве - оба видят друг друга (2 peer'а)

---

## Добавление третьего vault

Для каждого нового vault:

1. **Сгенерируйте новые параметры:**
   ```bash
   # На локальной машине
   echo "Room ID: $(openssl rand -hex 3 | sed 's/\(..\)/\1-/g' | sed 's/-$//')"
   echo "Passphrase: $(openssl rand -hex 16)"
   ```

2. **Используйте тот же Relay:**
   ```
   Relay: wss://sync.ikeniborn.ru/serverpeer
   ```

3. **Настройте в Obsidian** с новыми Room ID и Passphrase

---

## Безопасность

**Изоляция на двух уровнях:**

1. **Маршрутизация:** Nostr Relay отправляет сообщения только peer'ам из той же комнаты (Room ID)
2. **Шифрование:** Даже если сообщение попало не туда, без правильного Passphrase его не расшифровать

**Рекомендации:**
- ✅ Используйте уникальный Room ID для каждого vault
- ✅ Используйте уникальный Passphrase для каждого vault
- ✅ Не используйте одинаковые параметры для разных vaults
- ⚠️ Храните Passphrase в безопасном месте (password manager)

---

## Troubleshooting

### Устройства не видят друг друга

**Проверьте:**
1. Room ID идентичен на всех устройствах этого vault
2. Passphrase идентичен на всех устройствах этого vault
3. Relay URL правильный: `wss://sync.ikeniborn.ru/serverpeer`
4. Оба устройства онлайн одновременно

**Логи на сервере:**
```bash
# Проверить Nostr Relay
ssh ikenibornsync "docker logs notes-nostr-relay --tail 50"

# Должны видеть подключения от всех устройств
```

### Неправильные Room ID в логах

Если в логах видите неожиданные Room ID, проверьте настройки в Obsidian - возможно, опечатка.

### Медленная синхронизация

**Для Personal vault (без ServerPeer):**
- Синхронизация происходит только когда оба устройства онлайн
- Если одно устройство оффлайн, изменения накопятся и синхронизируются при следующем подключении

**Решение:** Разверните ServerPeer для этого vault (см. основную документацию).

---

## Ресурсы

- [Obsidian Self-hosted LiveSync](https://github.com/vrtmrz/obsidian-livesync)
- [P2P Sync Documentation](https://fancy-syncing.vrtmrz.net/blog/0034-p2p-sync-en)
- [Nostr Protocol](https://nostr.com/)

---

**Последнее обновление:** 2025-12-29
**Версия документа:** 1.0
