# Obsidian Self-hosted LiveSync - P2P Configuration Guide

## Правильная конфигурация для sync.ikeniborn.ru

### 1. Базовые настройки плагина

**General Settings → Remote Configuration:**
```
URI: https://sync.ikeniborn.ru/couchdb
Database: work  (или family, в зависимости от хранилища)
Username: admin
Password: [из /opt/notes/.env → COUCHDB_PASSWORD]
```

### 2. P2P Settings (обязательно для ServerPeer)

**Sync Settings → P2P Mode:**

Enable P2P: ✅ (включить)
App ID: `self-hosted-livesync` (по умолчанию)
Passphrase: (установить пароль для шифрования)

**Nostr Relay (signaling server):**
```
wss://sync.ikeniborn.ru/serverpeer
```

**ВАЖНО:** Используйте `wss://` (WebSocket Secure), НЕ `ws://`

### 3. ICE Servers (TURN/STUN) - КРИТИЧНО для работы через NAT

**Вариант A: Через настройки плагина (Settings → P2P → Advanced)**

Enable ICE: ✅

ICE Servers (JSON format):
```json
[
  {
    "urls": "stun:stun.l.google.com:19302"
  },
  {
    "urls": "turn:91.210.106.79:3478",
    "username": "obsidian",
    "credential": "6ef3e7b6dd6dd9975207e32160dfa8d3"
  }
]
```

**Вариант B: Через DevTools Console (Ctrl+Shift+I)**

```javascript
// Enable ICE
app.plugins.plugins['obsidian-livesync'].settings.P2P_UseICE = true;

// Configure ICE servers
app.plugins.plugins['obsidian-livesync'].settings.P2P_ICEServers = [
  { urls: "stun:stun.l.google.com:19302" },
  {
    urls: "turn:91.210.106.79:3478",
    username: "obsidian",
    credential: "6ef3e7b6dd6dd9975207e32160dfa8d3"
  }
];

// Save settings
await app.plugins.plugins['obsidian-livesync'].saveSettings();

console.log("ICE configuration saved!");
```

### 4. Проверка конфигурации

**Откройте DevTools Console (Ctrl+Shift+I) и выполните:**

```javascript
// Check P2P settings
const settings = app.plugins.plugins['obsidian-livesync'].settings;
console.log("P2P Enabled:", settings.P2P_Enabled);
console.log("Nostr Relay:", settings.P2P_relays);
console.log("ICE Enabled:", settings.P2P_UseICE);
console.log("ICE Servers:", settings.P2P_ICEServers);
```

**Ожидаемый вывод:**
```
P2P Enabled: true
Nostr Relay: wss://sync.ikeniborn.ru/serverpeer
ICE Enabled: true
ICE Servers: [
  { urls: "stun:stun.l.google.com:19302" },
  { urls: "turn:91.210.106.79:3478", username: "obsidian", credential: "..." }
]
```

### 5. Тестирование P2P соединения

**В Settings → P2P → Debug:**

1. Нажмите "Test Connection" или "Connect"
2. Проверьте логи в DevTools Console
3. Должны увидеть:
   ```
   [P2P] Connected to relay wss://sync.ikeniborn.ru/serverpeer
   [P2P] Advertisement sent
   [P2P] Peer discovered: z1azviaWYYZLit47QJHJ (Work ServerPeer)
   [P2P] ICE candidate gathered
   [P2P] Connection established
   ```

### 6. Troubleshooting

#### "Could not fetch configuration from remote"
**Причина:** Неправильный URL или учетные данные

**Решение:**
- Проверьте URL: `https://sync.ikeniborn.ru/couchdb` (НЕ `/obsidian`)
- Проверьте пароль в `/opt/notes/.env`
- Проверьте что база данных создана

#### "Relay connection failed"
**Причина:** Неправильный WebSocket URL

**Решение:**
- Используйте `wss://sync.ikeniborn.ru/serverpeer` (НЕ `ws://`)
- Проверьте что nginx проксирует /serverpeer

#### "P2P connection timeout"
**Причина:** ICE серверы не настроены или TURN порты закрыты

**Решение:**
- Проверьте ICE servers конфигурацию (см. Вариант A/B выше)
- Проверьте UFW на сервере:
  ```bash
  sudo ufw status | grep -E "3478|49152"
  ```
  Должны быть открыты:
  - 3478/udp (TURN/STUN)
  - 3478/tcp (TURN/STUN)
  - 49152:65535/udp (TURN relay)

#### "Advertisement sent but no peer response"
**Причина:** ServerPeer не запущен или использует другой room ID

**Решение:**
- Проверьте что ServerPeer запущен:
  ```bash
  docker ps | grep serverpeer
  docker logs notes-serverpeer-work --tail 20
  ```
- Убедитесь что `App ID` и `Passphrase` совпадают с ServerPeer

### 7. Полная конфигурация (пример)

```json
{
  "couchDB_URI": "https://sync.ikeniborn.ru/couchdb",
  "couchDB_DBNAME": "work",
  "couchDB_USER": "admin",
  "couchDB_PASSWORD": "[your-password]",

  "P2P_Enabled": true,
  "P2P_relays": "wss://sync.ikeniborn.ru/serverpeer",
  "P2P_AppID": "self-hosted-livesync",
  "P2P_passphrase": "[your-passphrase]",

  "P2P_UseICE": true,
  "P2P_ICEServers": [
    {
      "urls": "stun:stun.l.google.com:19302"
    },
    {
      "urls": "turn:91.210.106.79:3478",
      "username": "obsidian",
      "credential": "6ef3e7b6dd6dd9975207e32160dfa8d3"
    }
  ]
}
```

## Архитектура P2P синхронизации

```
Obsidian Client (78.107.114.37)
    ↓ (HTTPS)
    ↓ CouchDB: /couchdb → notes-couchdb:5984
    ↓ WebSocket: /serverpeer → notes-nostr-relay:7000
Nginx Reverse Proxy (sync.ikeniborn.ru)
    ↓ (WebSocket Signaling)
Nostr Relay (notes-nostr-relay:7000)
    ↓ (Advertisement exchange)
ServerPeer (notes-serverpeer-work / notes-serverpeer-family)
    ↓ (P2P WebRTC with NAT traversal)
    ↓ STUN: stun.l.google.com:19302 (external IP discovery)
    ↓ TURN: 91.210.106.79:3478 (relay fallback)
Coturn TURN Server
```

## Server Status

**Проверка статуса сервисов:**
```bash
# Docker containers
docker ps | grep -E "couchdb|nginx|nostr|serverpeer"

# Coturn TURN server
sudo systemctl status coturn

# UFW firewall
sudo ufw status | grep -E "443|3478|49152"

# Nostr Relay logs
docker logs notes-nostr-relay --tail 30

# ServerPeer logs
docker logs notes-serverpeer-work --tail 30
```

**Ожидаемые порты:**
- 443/tcp (HTTPS) - nginx reverse proxy
- 3478/udp, 3478/tcp - TURN/STUN signaling
- 49152-65535/udp - TURN relay ports
- 5984/tcp (localhost only) - CouchDB
- 7000/tcp (Docker network only) - Nostr Relay

## Changelog

- 2025-12-30: Initial P2P configuration guide
- Server: sync.ikeniborn.ru (91.210.106.79)
- TURN username: obsidian
- TURN password: 6ef3e7b6dd6dd9975207e32160dfa8d3
