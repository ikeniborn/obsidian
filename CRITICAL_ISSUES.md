# CRITICAL: Жесткая привязка к "familybudget"

## Проблема

Система обнаружения сетей и nginx **жестко привязана** к конкретным названиям "familybudget":
- `familybudget_familybudget` - имя сети
- `familybudget-couchdb-notes` - имя контейнера CouchDB
- `familybudget-nginx` - ожидаемое имя nginx контейнера

**Это делает систему НЕ универсальной**, а специфичной только для интеграции с Family Budget.

## Требование

Система должна:
1. **Автоматически обнаруживать ЛЮБЫЕ существующие Docker сети**
2. **Автоматически обнаруживать ЛЮБЫЕ существующие nginx контейнеры**
3. **Предлагать пользователю** переиспользовать найденные ресурсы
4. **НЕ зависеть** от конкретных названий проектов

## Найденные проблемы

### 1. scripts/network-manager.sh:38-49

**Текущий код:**
```bash
detect_network_mode() {
    info "Detecting network mode..."

    if docker network inspect familybudget_familybudget &> /dev/null; then
        success "Detected mode: SHARED (familybudget_familybudget network exists)"
        echo "shared"
        return 0
    else
        success "Detected mode: ISOLATED (familybudget_familybudget network not found)"
        echo "isolated"
        return 0
    fi
}
```

**Проблема:** Проверяет ТОЛЬКО одну конкретную сеть.

**Правильно:**
```bash
detect_network_mode() {
    info "Detecting available Docker networks..."

    # Получить список всех пользовательских сетей (кроме bridge/host/none)
    local networks=$(docker network ls --format '{{.Name}}' | grep -v '^bridge$\|^host$\|^none$' || true)

    if [ -z "$networks" ]; then
        info "No existing custom networks found"
        echo "isolated"
        return 0
    fi

    # Есть существующие сети - предложить shared mode
    info "Found existing networks, suggesting shared mode"
    echo "shared"
    return 0
}
```

### 2. scripts/nginx-setup.sh:80

**Текущий код:**
```bash
if [ "$nginx_mode" = "docker" ]; then
    export COUCHDB_UPSTREAM="familybudget-couchdb-notes"
else
    export COUCHDB_UPSTREAM="127.0.0.1"
fi
```

**Проблема:** Жестко задано имя контейнера CouchDB.

**Правильно:**
```bash
if [ "$nginx_mode" = "docker" ]; then
    # Имя контейнера должно браться из .env или генерироваться
    export COUCHDB_UPSTREAM="${COUCHDB_CONTAINER_NAME:-couchdb-notes}"
else
    export COUCHDB_UPSTREAM="127.0.0.1"
fi
```

### 3. scripts/nginx-setup.sh:189

**Текущий код:**
```bash
if validate_network_connectivity "${network_name}" "notes-nginx" "familybudget-couchdb-notes"; then
```

**Проблема:** Жестко задано имя CouchDB контейнера.

**Правильно:**
```bash
if validate_network_connectivity "${network_name}" "notes-nginx" "${COUCHDB_CONTAINER_NAME:-couchdb-notes}"; then
```

### 4. docker-compose.notes.yml:6

**Текущий код:**
```yaml
container_name: familybudget-couchdb-notes
```

**Проблема:** Жестко задано имя с префиксом "familybudget".

**Правильно:**
```yaml
container_name: ${COUCHDB_CONTAINER_NAME:-couchdb-notes}
```

### 5. docker-compose.notes.yml:56

**Текущий код:**
```yaml
name: ${NETWORK_NAME:-familybudget_familybudget}
```

**Проблема:** Default значение жестко привязано к "familybudget".

**Правильно:**
```yaml
name: ${NETWORK_NAME}  # Без default - должно быть установлено явно
```

Или если нужен fallback:
```yaml
name: ${NETWORK_NAME:-obsidian_network}
```

### 6. deploy.sh:281

**Текущий код:**
```bash
local network_name="${NETWORK_NAME:-familybudget_familybudget}"
```

**Проблема:** Default к "familybudget".

**Правильно:**
```bash
local network_name="${NETWORK_NAME}"
if [ -z "$network_name" ]; then
    error "NETWORK_NAME not set in .env"
    return 1
fi
```

### 7. deploy.sh:292, 299, 315

**Текущий код:**
```bash
if ! docker ps --format '{{.Names}}' | grep -q "^familybudget-couchdb-notes$"; then
if ! docker network inspect "${network_name}" --format '{{range .Containers}}{{.Name}} {{end}}' | grep -q "familybudget-couchdb-notes"; then
if validate_network_connectivity "${network_name}" "notes-nginx" "familybudget-couchdb-notes"; then
```

**Проблема:** Жестко заданные имена контейнеров.

**Правильно:**
```bash
local couchdb_container="${COUCHDB_CONTAINER_NAME:-couchdb-notes}"

if ! docker ps --format '{{.Names}}' | grep -q "^${couchdb_container}$"; then
if ! docker network inspect "${network_name}" --format '{{range .Containers}}{{.Name}} {{end}}' | grep -q "${couchdb_container}"; then
if validate_network_connectivity "${network_name}" "notes-nginx" "${couchdb_container}"; then
```

## Документация

Документация также содержит упоминания "familybudget" как примера, но это менее критично.

### README.md:20-23
```
Docker Network: familybudget_familybudget
├── familybudget-nginx (Family Budget)
├── familybudget-couchdb-notes (CouchDB)
```

**Правильно:** Использовать generic примеры или переменные.

### CLAUDE.md:22-25
Аналогичная проблема в примерах архитектуры.

## Предлагаемое решение

### Фаза 6: Generic Network & Container Detection

**Цель:** Сделать систему полностью универсальной, независимой от конкретных названий.

**Изменения:**

1. **setup.sh** - спрашивать имена контейнеров:
   ```bash
   # Если есть существующие сети - предложить выбор
   # Если есть существующие nginx - предложить выбор
   # Спросить имя для CouchDB контейнера
   ```

2. **.env переменные:**
   ```bash
   COUCHDB_CONTAINER_NAME=couchdb-notes  # configurable
   NGINX_CONTAINER_NAME=notes-nginx      # configurable
   NETWORK_NAME=obsidian_network         # user choice
   ```

3. **network-manager.sh:**
   - `detect_mode` → `list_networks` с выбором
   - `suggest_network` - предложить существующую или создать новую

4. **nginx-setup.sh:**
   - Обнаруживать ЛЮБОЙ nginx контейнер (не только familybudget)
   - Предлагать выбор из найденных

5. **deploy.sh:**
   - Использовать переменные вместо hardcoded имен
   - Валидация обязательных переменных

6. **docker-compose.notes.yml:**
   - Все имена через переменные
   - Убрать fallback к "familybudget"

## Приоритет

**CRITICAL** - блокирует использование в других проектах.

## Следующие шаги

1. Создать Phase 6 plan
2. Исправить все hardcoded имена
3. Обновить документацию
4. Добавить интерактивный выбор сетей/контейнеров
5. Тестирование на чистой системе (без Family Budget)
