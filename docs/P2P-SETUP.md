# Настройка P2P синхронизации в Obsidian

## Архитектура

```
┌─────────────────────────────────────────────────────────┐
│  Nostr Relay (WebSocket сервер для сигнализации)        │
│  wss://sync.ikeniborn.ru/serverpeer                     │
└──────────────┬──────────────────────────────────────────┘
               │
       ┌───────┴────────┐
       │                │
   ServerPeer      Ваши устройства
 (всегда онлайн)   (Laptop, Phone, Tablet)
```

**Как это работает:**
- **Nostr Relay** - WebSocket сервер, через который устройства находят друг друга
- **ServerPeer** - "всегда онлайн" peer на сервере, работает как буфер для изменений
- **Ваши устройства** - подключаются к relay и синхронизируются между собой + через ServerPeer

**Преимущества:**
- Синхронизация работает даже если устройства не онлайн одновременно
- ServerPeer хранит изменения и передает их когда устройство подключится
- Прямой P2P между устройствами когда они онлайн вместе

---

## Параметры подключения

Используйте эти параметры на **ВСЕХ** устройствах с этим vault:

```
Relay Servers:    wss://sync.ikeniborn.ru/serverpeer
Room ID:          f6-9f-93-de-3a-5d
Passphrase:       f64a50c669934a2f60a6f188aaa29506
Device Name:      [уникальное для каждого устройства]
```

**⚠️ ВАЖНО:**
- Relay, Room ID и Passphrase должны быть **ОДИНАКОВЫМИ** на всех устройствах
- Device Name должен быть **УНИКАЛЬНЫМ** для каждого устройства
- Relay URL указывайте **ТОЧНО** как показано (без лишних символов)

---

## Пошаговая настройка в Obsidian

### Шаг 1: Установите плагин Self-hosted LiveSync

1. Откройте Obsidian
2. Settings → Community Plugins
3. Найдите и установите **Self-hosted LiveSync**
4. Включите плагин

### Шаг 2: Настройте P2P Sync

1. Settings → Self-hosted LiveSync → **Sync Settings** → **Peer-to-Peer Sync**

2. Включите опции:
   ```
   ✓ Enable P2P Sync
   ✓ Enable Auto Connect
   ✓ Enable Auto Broadcast
   ```

3. Заполните параметры:
   ```
   Relay Servers:    wss://sync.ikeniborn.ru/serverpeer
   Room ID:          f6-9f-93-de-3a-5d
   Passphrase:       f64a50c669934a2f60a6f188aaa29506
   This device name: Laptop-Work
                     (или Phone, Tablet-Home, Desktop и т.д.)
   ```

4. Сохраните настройки

### Шаг 3: Проверьте подключение

**В правом нижнем углу Obsidian** должен появиться индикатор P2P подключения.

**В списке peers** вы должны увидеть:
- ServerPeer (всегда онлайн буфер)
- Другие ваши устройства (если они онлайн)

---

## Настройка на втором/третьем устройстве

Повторите те же шаги на каждом устройстве:

1. Установите Self-hosted LiveSync
2. Используйте **ТЕ ЖЕ** параметры:
   - Relay: `wss://sync.ikeniborn.ru/serverpeer`
   - Room ID: `f6-9f-93-de-3a-5d`
   - Passphrase: `f64a50c669934a2f60a6f188aaa29506`
3. Измените только **Device Name** (уникальное имя)

**Пример:**
- Первое устройство: `Laptop-Work`
- Второе устройство: `Phone-Personal`
- Третье устройство: `Tablet-Home`

---

## Проверка работы

### На сервере

```bash
# Проверить ServerPeer
ssh ikenibornsync "docker logs notes-serverpeer --tail 20"
```

**Ожидаемый результат:**
```
peerId: 7gwbhQHhhfq5bTHrViP5 Sending Advertisement to All
peerId: 7gwbhQHhhfq5bTHrViP5 Received advertisement from XYZ123
```

### В Obsidian

**Settings → Self-hosted LiveSync → Sync Settings → Peer-to-Peer Sync**

Вы должны видеть список подключенных peers:
- Минимум 2 peer'а: ServerPeer + ваше устройство
- При добавлении второго устройства - 3 peer'а

---

## Настройка второго vault (опционально)

Если у вас несколько независимых vaults, для каждого нужны **РАЗНЫЕ** Room ID и Passphrase.

**Генерация параметров для нового vault:**

```bash
# На локальной машине
echo "Room ID: $(openssl rand -hex 3 | sed 's/\(  ..\)/\1-/g' | sed 's/-$//')"
echo "Passphrase: $(openssl rand -hex 16)"
```

Relay остается тот же: `wss://sync.ikeniborn.ru/serverpeer`

**Важно:** Одинаковый Relay может обслуживать множество vaults - они изолированы через Room ID.

---

## Troubleshooting

### Устройства не видят друг друга

**Проверьте:**
1. Room ID идентичен на всех устройствах
2. Passphrase идентичен на всех устройствах
3. Relay URL правильный: `wss://sync.ikeniborn.ru/serverpeer`
4. Плагин включен и P2P Sync активирован

**Проверка на сервере:**
```bash
# Проверить Nostr Relay
ssh ikenibornsync "docker logs notes-nostr-relay --tail 50"

# Должны видеть подключения от устройств
```

### Медленная синхронизация

**Нормально:** Первая синхронизация большого vault может занять время.

**Если всегда медленно:**
- Проверьте интернет-соединение
- Проверьте что ServerPeer работает: `docker ps | grep serverpeer`

### Ошибки в логах ServerPeer

```bash
# Просмотр последних 50 строк логов
ssh ikenibornsync "docker logs notes-serverpeer --tail 50"

# Перезапуск ServerPeer
ssh ikenibornsync "docker restart notes-serverpeer"
```

---

## Безопасность

**Room ID и Passphrase - это секретные данные:**
- ✅ Храните их в password manager
- ✅ Не передавайте третьим лицам
- ✅ Используйте разные для разных vaults
- ❌ Не публикуйте в интернете

**Шифрование:**
- Passphrase используется для end-to-end шифрования данных
- Даже если кто-то узнает Room ID, без Passphrase не расшифрует данные

---

**Последнее обновление:** 2025-12-29
**Версия документа:** 1.0
