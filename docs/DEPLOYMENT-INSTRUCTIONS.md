# Deployment Instructions - Nostr Relay Configuration Fix

**Дата:** 2025-12-30
**Проблема:** ServerPeer не может публиковать события в Nostr Relay
**Ошибка:** `Trystero: relay failure - blocked: pubkey is not allowed to publish to this relay`
**Статус:** ✅ Исправлено в репозитории, требуется деплой на сервер

---

## Описание проблемы

### Симптомы

При попытке ServerPeer подключиться к Nostr Relay появляется ошибка:

```
Trystero: relay failure from wss://sync.ikeniborn.ru/serverpeer - blocked: pubkey is not allowed to publish to this relay
```

В логах ServerPeer:
```
2025-12-30T06:25:11.519Z        Initializing...
2025-12-30T06:25:11.524Z        peerId: Cuvcij0w6MdWNIBEk4z5 Sending Advertisement to All
Trystero: relay failure from wss://sync.ikeniborn.ru/serverpeer - blocked: pubkey is not allowed to publish to this relay
```

### Причина

В конфигурации Nostr Relay (`nostr-relay/config.toml`) была секция:

```toml
[authorization]
pubkey_whitelist = []
```

**Проблема:** В nostr-rs-relay, когда секция `[authorization]` определена (даже с пустым массивом), relay активирует проверку whitelist. Пустой список означает "блокировать всех", а не "разрешить всем".

**Поведение nostr-rs-relay:**
- ✅ **Секция отсутствует/закомментирована:** Allow all (публичный relay)
- ❌ **`pubkey_whitelist = []`:** Block all (никто не может публиковать)
- ✅ **`pubkey_whitelist = ["pubkey1", "pubkey2"]`:** Allow only listed pubkeys

---

## Решение

### Что было изменено

**Файл:** `nostr-relay/config.toml`

```diff
- [authorization]
- # No pubkey restriction for P2P sync
- pubkey_whitelist = []
+ # Authorization disabled - allow all peers to publish events
+ # NOTE: When pubkey_whitelist is defined (even as empty array []),
+ # nostr-rs-relay blocks ALL publishing. To allow unrestricted publishing,
+ # the [authorization] section must be completely absent or commented out.
+ # [authorization]
+ # pubkey_whitelist = []
```

**Результат:** Теперь Nostr Relay работает в режиме публичного relay (allow all), что необходимо для P2P синхронизации через ServerPeer.

---

## Инструкция по деплою на сервер

### Шаг 1: Обновить код на сервере

На сервере `ikeniborn@ikeniborn`:

```bash
cd ~/obsidian
git pull origin dev
```

### Шаг 2: Проверить изменения

```bash
# Проверить, что config.toml обновился
cat nostr-relay/config.toml | grep -A 5 "Authorization"
```

Должно показать:
```toml
# Authorization disabled - allow all peers to publish events
# NOTE: When pubkey_whitelist is defined (even as empty array []),
# nostr-rs-relay blocks ALL publishing. To allow unrestricted publishing,
# the [authorization] section must be completely absent or commented out.
# [authorization]
# pubkey_whitelist = []
```

### Шаг 3: Применить изменения

#### Вариант A: Пересоздать контейнер (рекомендуется)

```bash
# Остановить и удалить текущий контейнер
docker compose -f docker-compose.nostr-relay.yml down

# Удалить volume с конфигурацией (если был примонтирован)
# ВНИМАНИЕ: Это НЕ удалит данные relay (они в NOSTR_RELAY_DATA_DIR)
docker volume ls | grep nostr

# Создать и запустить новый контейнер с исправленной конфигурацией
docker compose -f docker-compose.nostr-relay.yml up -d
```

#### Вариант B: Перезапустить контейнер (быстрее, но требует замены файла)

```bash
# Копировать обновленный config.toml в контейнер
docker cp nostr-relay/config.toml notes-nostr-relay:/usr/src/app/config.toml

# Перезапустить контейнер
docker restart notes-nostr-relay
```

### Шаг 4: Проверить логи Nostr Relay

```bash
docker logs notes-nostr-relay --tail 30
```

Должно показать:
```
relay listening on: 0.0.0.0:7000
[INFO] new client connection (cid: xxx, ip: '...')
```

**НЕ должно быть:**
```
Event publishing restricted to N pubkey(s)
```

### Шаг 5: Проверить логи ServerPeer

```bash
docker logs notes-serverpeer-work --tail 30
```

Должно показать:
```
2025-12-30T...  peerId: ... Sending Advertisement to All
```

**БЕЗ ошибок:**
```
Trystero: relay failure from wss://sync.ikeniborn.ru/serverpeer - blocked: pubkey is not allowed to publish to this relay
```

### Шаг 6: Проверить соединение от Obsidian

В Obsidian плагине Self-hosted LiveSync:
1. Откройте настройки плагина
2. Перейдите в раздел P2P Sync
3. Проверьте статус подключения к relay
4. Должно показать "Connected" или аналогичное

---

## Валидация успешного деплоя

### Контрольные точки

✅ **1. Nostr Relay запущен и слушает**
```bash
docker ps --filter "name=nostr-relay"
# Должен показать STATUS: Up
```

✅ **2. Конфигурация применена**
```bash
docker exec notes-nostr-relay cat /usr/src/app/config.toml | grep -A 5 "Authorization"
# Должна быть закомментированная секция [authorization]
```

✅ **3. ServerPeer успешно подключается**
```bash
docker logs notes-serverpeer-work --tail 10 | grep -i "blocked"
# НЕ должно быть строк с "blocked: pubkey is not allowed"
```

✅ **4. WebSocket соединение работает**
```bash
# Если установлен wscat:
wscat -c wss://sync.ikeniborn.ru/serverpeer
# Должен успешно подключиться (не ошибка 403/401)
```

---

## Откат (Rollback)

Если после деплоя возникли проблемы:

```bash
# Вернуться к предыдущей версии кода
cd ~/obsidian
git log --oneline -5  # Найти предыдущий commit
git checkout <previous-commit-hash>

# Пересоздать контейнер с старой конфигурацией
docker compose -f docker-compose.nostr-relay.yml down
docker compose -f docker-compose.nostr-relay.yml up -d
```

---

## Дополнительные ресурсы

### Документация nostr-rs-relay

- **GitHub Issue:** [Dynamically update whitelisted users #68](https://github.com/scsibug/nostr-rs-relay/issues/68)
- **Configuration Reference:** [nostr-rs-relay config.toml](https://github.com/scsibug/nostr-rs-relay/blob/master/config.toml)
- **Relay Setup Guide:** [How to Set Up Your Own nostr-rs-relay](https://gist.github.com/leesalminen/801e50a2d6034b05fa39da982c8f0c40)

### Обновленная архитектурная документация

- `docs/architecture/components/infrastructure/nostr-relay.yml` - добавлен раздел troubleshooting → pubkey_blocked_publishing
- `nostr-relay/config.toml` - добавлены комментарии о поведении authorization

---

## Проверка после деплоя

После успешного деплоя рекомендуется:

1. **Мониторинг в течение 24 часов:**
   ```bash
   watch -n 60 'docker logs notes-serverpeer-work --tail 5 | grep -i "relay failure"'
   ```

2. **Проверка синхронизации между устройствами:**
   - Создать тестовую заметку на одном устройстве
   - Проверить появление на другом устройстве через P2P

3. **Логирование для аудита:**
   ```bash
   docker logs notes-nostr-relay > /tmp/nostr-relay-after-fix.log
   docker logs notes-serverpeer-work > /tmp/serverpeer-after-fix.log
   ```

---

## Контакты

При возникновении проблем:
- Проверьте логи контейнеров
- Сверьтесь с секцией Troubleshooting в `docs/architecture/components/infrastructure/nostr-relay.yml`
- Создайте issue в репозитории с полными логами

**Последнее обновление:** 2025-12-30
**Автор исправления:** Claude Code (analysis) + Development Team
