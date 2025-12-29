# P2P Sync - Быстрый старт

## ⚠️ ИСПРАВЬТЕ RELAY URL

**В вашей текущей конфигурации Relay URL обрезан!**

❌ Неправильно: `wss://sync.ikeniborn.ru/serverpe`
✅ Правильно: `wss://sync.ikeniborn.ru/serverpeer`

Откройте Settings → Self-hosted LiveSync → P2P Configuration и исправьте URL.

---

## Соответствие параметров

**Obsidian UI → Серверная конфигурация:**

| Поле в Obsidian | Значение | Откуда берется |
|----------------|----------|----------------|
| **Enabled** | ✓ (включено) | Включите чекбокс |
| **Relay URL** | `wss://sync.ikeniborn.ru/serverpeer` | Постоянный для всех vaults |
| **Group ID** | `f6-9f-93-de-3a-5d` | SERVERPEER_ROOMID из .env |
| **Passphrase** | `f64a50c669934a2f60a6f188aaa29506` | SERVERPEER_PASSPHRASE из .env |
| **Device Peer ID** | `ikeniborn-minipc` | Уникальное имя этого устройства |
| **Auto Start P2P Connection** | ✓ | Включите для автоподключения |
| **Auto Broadcast Changes** | ✓ | Включите для автосинхронизации |

---

## Настройка для разных vaults

### Концепция

**Один Relay → Множество vaults:**
- Relay URL один для всех: `wss://sync.ikeniborn.ru/serverpeer`
- Каждый vault = уникальная "комната" (Group ID + Passphrase)
- Device Peer ID уникален для устройства, НО одинаковый для всех vaults на этом устройстве

### Текущий vault (Work)

**Параметры:**
```
Relay URL:       wss://sync.ikeniborn.ru/serverpeer
Group ID:        f6-9f-93-de-3a-5d
Passphrase:      f64a50c669934a2f60a6f188aaa29506
Device Peer ID:  ikeniborn-minipc
```

### Второй vault (Personal) - новые параметры

**Генерация:**
```bash
# На локальной машине
echo "Group ID: $(openssl rand -hex 3 | sed 's/\(  ..\)/\1-/g' | sed 's/-$//')"
echo "Passphrase: $(openssl rand -hex 16)"
```

**Пример результата:**
```
Group ID:        a7-4f-e2
Passphrase:      8c3b5d91a7e24f6c9e1d8a2b5f7c4e6a
```

**Параметры в Obsidian для Personal vault:**
```
Relay URL:       wss://sync.ikeniborn.ru/serverpeer    (ТОТ ЖЕ!)
Group ID:        a7-4f-e2                              (НОВЫЙ!)
Passphrase:      8c3b5d91a7e24f6c9e1d8a2b5f7c4e6a      (НОВЫЙ!)
Device Peer ID:  ikeniborn-minipc                      (ТОТ ЖЕ!)
```

### Третий vault (Projects) - новые параметры

Снова генерируем:
```bash
echo "Group ID: $(openssl rand -hex 3 | sed 's/\(  ..\)/\1-/g' | sed 's/-$//')"
echo "Passphrase: $(openssl rand -hex 16)"
```

---

## Таблица параметров для множества vaults

| Vault | Relay URL | Group ID | Passphrase | Device Peer ID |
|-------|-----------|----------|------------|----------------|
| **Work** | `wss://sync.ikeniborn.ru/serverpeer` | `f6-9f-93-de-3a-5d` | `f64a50c669934a2f60a6f188aaa29506` | `ikeniborn-minipc` |
| **Personal** | `wss://sync.ikeniborn.ru/serverpeer` | `a7-4f-e2` (пример) | `8c3b5d91a7e24f6c...` (пример) | `ikeniborn-minipc` |
| **Projects** | `wss://sync.ikeniborn.ru/serverpeer` | `3c-8a-f1` (пример) | `4f2e9a1c7b8d5e3a...` (пример) | `ikeniborn-minipc` |

**Правило:**
- ✅ Relay URL - **ОДИНАКОВЫЙ** для всех vaults
- ✅ Device Peer ID - **ОДИНАКОВЫЙ** для всех vaults на этом устройстве
- ❌ Group ID - **УНИКАЛЬНЫЙ** для каждого vault
- ❌ Passphrase - **УНИКАЛЬНЫЙ** для каждого vault

---

## Настройка на разных устройствах

### Устройство 1: Laptop (Work vault)

```
Relay URL:       wss://sync.ikeniborn.ru/serverpeer
Group ID:        f6-9f-93-de-3a-5d
Passphrase:      f64a50c669934a2f60a6f188aaa29506
Device Peer ID:  laptop-work
```

### Устройство 2: Phone (Work vault)

```
Relay URL:       wss://sync.ikeniborn.ru/serverpeer
Group ID:        f6-9f-93-de-3a-5d                      (ТОТ ЖЕ что на Laptop!)
Passphrase:      f64a50c669934a2f60a6f188aaa29506        (ТОТ ЖЕ что на Laptop!)
Device Peer ID:  phone-personal                         (ДРУГОЙ!)
```

### Устройство 2: Phone (Personal vault на том же телефоне)

```
Relay URL:       wss://sync.ikeniborn.ru/serverpeer
Group ID:        a7-4f-e2                               (ДРУГОЙ vault!)
Passphrase:      8c3b5d91a7e24f6c9e1d8a2b5f7c4e6a       (ДРУГОЙ vault!)
Device Peer ID:  phone-personal                         (ТОТ ЖЕ что для Work!)
```

---

## Безопасность параметров

**Храните в password manager:**

```
# Vault: Work
Relay:      wss://sync.ikeniborn.ru/serverpeer
Group ID:   f6-9f-93-de-3a-5d
Passphrase: f64a50c669934a2f60a6f188aaa29506

# Vault: Personal
Relay:      wss://sync.ikeniborn.ru/serverpeer
Group ID:   a7-4f-e2
Passphrase: 8c3b5d91a7e24f6c9e1d8a2b5f7c4e6a
```

**⚠️ Не публикуйте Group ID и Passphrase!**

---

## Проверка работы

**После сохранения настроек:**

1. Нажмите **"Test Settings and Continue"**
2. Ожидаемый результат:
   - ✅ "Your settings seem correct"
   - ⚠️ "but no other peers were found" - нормально если другие устройства еще не подключены

**В списке peers должны появиться:**
- ServerPeer (всегда онлайн буфер) - если развернут для этого vault
- Другие ваши устройства с этим же Group ID

**Если "Connection failed":**
- Проверьте Relay URL - должен быть полный: `wss://sync.ikeniborn.ru/serverpeer`
- Проверьте что Nostr Relay работает: `ssh ikenibornsync "docker ps | grep nostr-relay"`

---

## Команды для проверки на сервере

```bash
# Проверить Nostr Relay (обслуживает все vaults)
ssh ikenibornsync "docker logs notes-nostr-relay --tail 30"

# Проверить ServerPeer (только для Work vault)
ssh ikenibornsync "docker logs notes-serverpeer --tail 20"

# Статус контейнеров
ssh ikenibornsync "docker ps --filter 'name=notes-'"
```

---

**Последнее обновление:** 2025-12-29
**Версия:** 1.1
