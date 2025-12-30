# P2P Sync Troubleshooting Guide

**Дата:** 2025-12-30
**Версия:** 1.0.0

---

## Проблема: Obsidian не может найти peer

### Симптомы

В Obsidian плагине Self-hosted LiveSync:
- Отображается сообщение "cannot find peers"
- P2P Replicator показывает 0 connected peers
- ServerPeer запущен и работает, но не отображается как peer

### Диагностика

**Шаг 1:** Проверьте статус P2P в ServerPeer:

```bash
docker logs notes-serverpeer-work | grep -E "P2P_Enabled|Settings:" -A 15
```

**Если видите `P2P_Enabled: false`** → P2P выключен в headless vault (см. [Решение 1](#решение-1-включить-p2p-в-serverpeer))

**Если видите `P2P_Enabled: true`** → Проблема в настройках (см. [Решение 2](#решение-2-проверить-настройки-obsidian))

---

## Решение 1: Включить P2P в ServerPeer

### Причина

По умолчанию плагин Self-hosted LiveSync создает headless vault с **P2P выключенным** (`P2P_Enabled: false`).

Это экспериментальная функция и должна быть включена явно через настройку в `.obsidian/plugins/obsidian-livesync/data.json`.

### Автоматическое исправление (для новых деплоев)

Начиная с коммита bb8c9a0, P2P включается **на уровне Docker образа** через патч ServerPeer.ts.

Для применения исправления:

```bash
cd ~/obsidian
git pull origin dev
./deploy.sh
```

При деплое:
1. Docker собирает образ ServerPeer
2. Применяется патч `serverpeer/fix-p2p-enabled.patch` к ServerPeer.ts
3. Патч исправляет порядок инициализации: `P2P_Enabled` устанавливается **ДО** сохранения в globalVariables
4. Контейнер запускается с P2P включенным с самого начала

После деплоя логи покажут:
```
Settings: { P2P_Enabled: true, ... }
```

### Ручное исправление (для существующих деплоев)

Если ServerPeer уже запущен с P2P выключенным, нужно **пересобрать Docker образ**:

```bash
cd ~/obsidian
git pull origin dev

# Пересобрать образ ServerPeer с патчем
docker compose -f docker-compose.serverpeers.yml build --no-cache

# Перезапустить контейнеры
docker compose -f docker-compose.serverpeers.yml up -d

# Проверить логи
docker logs notes-serverpeer-work --tail 30 | grep -E "P2P_Enabled|Settings:" -A 15
```

Должно показать:
```
Settings: {
  P2P_Enabled: true,
  ...
}
```

---

## Решение 2: Проверить настройки Obsidian

Если ServerPeer показывает `P2P_Enabled: true`, но peers не найдены, проверьте настройки в Obsidian.

### Шаг 1: Проверить Room ID (Group ID)

В Obsidian:
1. Откройте Settings → Self-hosted LiveSync → Peer-to-Peer Replicator
2. **Group ID** должен совпадать с `VAULT_1_ROOMID` из `/opt/notes/.env`

Проверить на сервере:

```bash
cat /opt/notes/.env | grep VAULT_1_ROOMID
# Пример вывода: VAULT_1_ROOMID=cb-70-18
```

**Group ID в Obsidian ДОЛЖЕН быть:** `cb-70-18` (без кавычек)

### Шаг 2: Проверить Passphrase

В Obsidian:
1. Settings → Self-hosted LiveSync → Peer-to-Peer Replicator
2. **Password** должен совпадать с `VAULT_1_PASSPHRASE`

Проверить на сервере:

```bash
cat /opt/notes/.env | grep VAULT_1_PASSPHRASE
# Пример вывода: VAULT_1_PASSPHRASE=033c0a16262ba4742062708dfcf4d050
```

**Password в Obsidian ДОЛЖЕН быть:** `033c0a16262ba4742062708dfcf4d050`

### Шаг 3: Проверить Relay URL

В Obsidian:
1. Settings → Self-hosted LiveSync → Peer-to-Peer Replicator → Advanced
2. **Relay Servers** должен содержать:

```
wss://sync.ikeniborn.ru/serverpeer
```

(или ваш NOTES_DOMAIN из .env)

### Шаг 4: Включить P2P в Obsidian

В Obsidian:
1. Откройте Command Palette (Ctrl+P)
2. Выполните: `"Open P2P Replicator"`
3. Включите toggle: **Enable P2P Replicator**
4. Включите: **Auto Connect**
5. Включите: **Start change-broadcasting on Connect**

---

## Решение 3: Проверить Nostr Relay

Если все настройки правильные, но peers не найдены, проверьте Nostr Relay:

```bash
# Проверить статус Nostr Relay
docker ps --filter "name=nostr-relay"

# Проверить логи на ошибки
docker logs notes-nostr-relay --tail 50 | grep -i "error\|blocked"
```

**НЕ должно быть:**
```
blocked: pubkey is not allowed to publish to this relay
```

Если видите эту ошибку → см. [DEPLOYMENT-INSTRUCTIONS.md](DEPLOYMENT-INSTRUCTIONS.md)

---

## Проверка после исправления

После применения любого из решений:

**1. Проверить ServerPeer логи:**

```bash
docker logs notes-serverpeer-work --tail 30
```

Должно показывать:
```
Settings: {
  P2P_Enabled: true,
  P2P_AutoAccepting: 0,
  P2P_AppID: "self-hosted-livesync",
  P2P_roomID: "cb-70-18",
  P2P_passphrase: "********************************",
  P2P_relays: "wss://sync.ikeniborn.ru/serverpeer",
  ...
}
```

**2. Проверить Obsidian P2P Replicator:**

В Obsidian плагине должно отображаться:
- ✅ Connected to relay
- ✅ 1+ peers found (ServerPeer должен появиться как peer)

**3. Проверить синхронизацию:**

1. Создать тестовую заметку в Obsidian
2. Проверить появилась ли в ServerPeer vault:

```bash
ls -la /opt/notes/serverpeer-vault-work/
```

---

## Технические детали

### Почему P2P выключен по умолчанию?

P2P Sync - **экспериментальная функция** плагина Self-hosted LiveSync (с версии 0.24.11).

По умолчанию она выключена в настройках плагина через параметр `P2P_Enabled: false` в `data.json`.

### Почему нет переменной окружения SLS_SERVER_PEER_P2P_ENABLED?

ServerPeer использует переменные окружения для **настройки соединения** (ROOMID, PASSPHRASE, RELAYS), но **не для включения/выключения P2P**.

`P2P_Enabled` - это настройка **плагина Obsidian LiveSync**, а не переменная окружения ServerPeer.

Плагин читает эту настройку из своего конфига `.obsidian/plugins/obsidian-livesync/data.json` внутри vault.

### Как работает исправление через патч?

При сборке Docker образа ServerPeer (`serverpeer/Dockerfile`):

1. Клонируется репозиторий livesync-serverpeer
2. Применяется патч `serverpeer/fix-p2p-enabled.patch` к `src/ServerPeer.ts`
3. Патч исправляет **порядок операций** в функции `startServer()`:

**ДО патча (баг):**
```typescript
globalVariables.set("settings", conf);  // Сохраняет settings
conf.P2P_Enabled = true;                 // Изменяет conf ПОСЛЕ сохранения
// Результат: globalVariables имеет P2P_Enabled: false
```

**ПОСЛЕ патча (исправлено):**
```typescript
conf.P2P_Enabled = true;                 // Устанавливает P2P_Enabled ПЕРЕД
globalVariables.set("settings", conf);  // сохранением в globalVariables
// Результат: globalVariables имеет P2P_Enabled: true
```

4. После применения патча запускается `deno task install`
5. Образ готов с исправленным ServerPeer

---

## Проблема: Docker build fails - "malformed patch at line 14"

### Симптомы

При сборке Docker образа ServerPeer (`docker compose build`):

```
=> ERROR [serverpeer stage-1  8/10] RUN patch -p1 < /tmp/fix-p2p-enabled.patch
------
 > [serverpeer stage-1  8/10] RUN patch -p1 < /tmp/fix-p2p-enabled.patch:
1.013 patching file src/ServerPeer.ts
1.016 patch: **** malformed patch at line 14:
------
```

### Причина

Файл патча `serverpeer/fix-p2p-enabled.patch` **устарел** и больше не соответствует текущей структуре кода upstream репозитория `vrtmrz/livesync-serverpeer`.

**Что произошло:**
- Upstream репозиторий обновил структуру кода (например, commit d983f1e рефакторил imports)
- Патч был создан против старой версии кода
- При сборке Docker образа git clone загружает **новую версию** upstream кода
- Патч не может применитьсяк новому коду (контекст не совпадает)

### Диагностика

**Шаг 1:** Клонировать текущий upstream и проверить патч:

```bash
# Клонировать свежую копию upstream
cd /tmp
git clone https://github.com/vrtmrz/livesync-serverpeer.git test-serverpeer
cd test-serverpeer

# Попробовать применить патч
patch -p1 --dry-run < ~/obsidian/serverpeer/fix-p2p-enabled.patch
```

**Если видите ошибку:**
```
patch: **** malformed patch at line 14:
```
→ Патч устарел и требует регенерации

**Если видите:**
```
patching file src/ServerPeer.ts
```
→ Патч актуален, проблема в другом

### Решение: Регенерировать патч

**Вариант 1: Использовать валидационный скрипт**

В репозитории есть готовый скрипт для тестирования патча:

```bash
cd ~/obsidian
bash serverpeer/validate-patch.sh
```

Скрипт проверит:
- ✅ Патч применяется к текущему upstream
- ✅ Комментарий добавлен
- ✅ globalVariables.set перенесён после P2P settings

**Вариант 2: Ручная регенерация патча**

Если патч устарел:

```bash
# 1. Клонировать свежий upstream
cd /tmp
rm -rf livesync-serverpeer
git clone https://github.com/vrtmrz/livesync-serverpeer.git
cd livesync-serverpeer

# 2. Вручную отредактировать src/ServerPeer.ts
#    Переместить строку:
#      globalVariables.set("settings", conf);
#    С позиции ПЕРЕД conf.P2P_Enabled
#    На позицию ПОСЛЕ conf.P2P_AutoBroadcast
#
#    Добавить комментарий перед conf.P2P_Enabled:
#      // Set P2P_Enabled BEFORE saving to globalVariables (fix for P2P disabled bug)

# 3. Сгенерировать новый патч
git diff src/ServerPeer.ts > /tmp/fix-p2p-enabled-new.patch

# 4. Заменить старый патч
cp /tmp/fix-p2p-enabled-new.patch ~/obsidian/serverpeer/fix-p2p-enabled.patch

# 5. Пересобрать Docker образ
cd ~/obsidian
docker compose -f docker-compose.serverpeer.yml build --no-cache
```

### Проверка после исправления

**1. Патч применяется без ошибок:**

```bash
cd /tmp/livesync-serverpeer
git checkout .  # Сброс изменений
patch -p1 < ~/obsidian/serverpeer/fix-p2p-enabled.patch
# Должно вывести: patching file src/ServerPeer.ts (без ошибок)
```

**2. Docker build завершается успешно:**

```bash
cd ~/obsidian
docker compose -f docker-compose.serverpeer.yml build --no-cache
docker compose -f docker-compose.serverpeer-personal.yml build --no-cache
# Оба build должны завершиться без ошибок
```

**3. Патч применён в образе:**

```bash
# Извлечь ServerPeer.ts из собранного образа
docker run --rm --entrypoint cat notes-serverpeer /app/livesync-serverpeer/src/ServerPeer.ts | head -15

# Должно показать (строки 7-13):
# export async function startServer(conf: ServerP2PSetting) {
#     const { globalVariables } = await Synchromesh();
#     // Set P2P_Enabled BEFORE saving to globalVariables (fix for P2P disabled bug)
#     conf.P2P_Enabled = true;
#     conf.P2P_AutoStart = true;
#     conf.P2P_AutoBroadcast = true;
#     globalVariables.set("settings", conf);  // ← Перенесено ПОСЛЕ P2P settings
```

### Предотвращение в будущем

**Регулярная проверка патча:**

После обновления upstream репозитория всегда тестировать патч:

```bash
# Проверка патча перед деплоем
cd /tmp
rm -rf test-serverpeer
git clone https://github.com/vrtmrz/livesync-serverpeer.git test-serverpeer
cd test-serverpeer
patch -p1 --dry-run < ~/obsidian/serverpeer/fix-p2p-enabled.patch

# Если ошибка → регенерировать патч
# Если OK → можно делать deploy
```

**Автоматизация (TODO):**

Добавить в CI/CD pipeline проверку актуальности патча перед Docker build.

---

## См. также

- [DEPLOYMENT-INSTRUCTIONS.md](DEPLOYMENT-INSTRUCTIONS.md) - Инструкция по деплою Nostr Relay fix
- [docs/architecture/components/infrastructure/serverpeer.yml](architecture/components/infrastructure/serverpeer.yml) - Архитектурная документация ServerPeer
- [P2P Sync Blog (EN)](https://fancy-syncing.vrtmrz.net/blog/0034-p2p-sync-en) - Официальный блог автора плагина

---

**Последнее обновление:** 2025-12-30
**Автор:** Claude Code (analysis) + Development Team
