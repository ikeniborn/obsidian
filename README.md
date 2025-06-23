# Obsidian + CouchDB Services Installation Scripts

Набор bash-скриптов для развертывания CouchDB и Obsidian LiveSync сервера с использованием Docker и Traefik.

## Структура проекта

```
├── install.sh                 # Главный скрипт установки
├── install-couchdb.sh         # Установка CouchDB
├── install-obsidian-sync.sh   # Установка Obsidian LiveSync сервера
├── backup-couchdb.sh          # Настройка бэкапов CouchDB в S3
├── setup-firewall.sh          # Настройка UFW firewall
└── README.md                  # Этот файл
```

## Быстрый старт

1. **Скачайте все скрипты** в одну директорию
2. **Запустите главный скрипт** от имени root:
   ```bash
   sudo chmod +x install.sh
   sudo ./install.sh
   ```

## Что будет установлено

### После установки в `/opt/` будут созданы:

- **`/opt/couchdb/`** - CouchDB с Traefik интеграцией
- **`/opt/obsidian-sync/`** - Obsidian LiveSync сервер  

### Сервисы будут доступны по адресам:
- **CouchDB**: `https://couchdb.ваш-домен.com`
- **Obsidian**: `https://obsidian.ваш-домен.com`

## Подробное описание скриптов

### 1. `install.sh`
Главный скрипт, который:
- Проверяет и устанавливает зависимости (Docker, Docker Compose, Git)
- Создает сеть Traefik
- Предлагает выбор установки (отдельные сервисы или всё сразу)

### 2. `install-couchdb.sh`
Устанавливает CouchDB:
- Запрашивает домен и учетные данные
- Создает docker-compose.yml с настройками Traefik
- Настраивает UFW правила
- Создает конфигурацию для single-node режима

### 3. `install-obsidian-sync.sh`
Устанавливает Obsidian LiveSync сервер:
- Клонирует репозиторий `vrtmrz/livesync-serverpeer`
- Создает Dockerfile для продакшена
- Настраивает docker-compose.yml с Traefik
- Создает скрипты управления (start.sh, stop.sh, update.sh)

### 4. `backup-couchdb.sh`
Настраивает систему бэкапов:
- Настройка MinIO клиента для Yandex Cloud S3
- Создание cron задачи (по умолчанию в 3:00 UTC)
- Автоматическая очистка старых локальных бэкапов
- Загрузка в S3 облачное хранилище

### 5. `setup-firewall.sh`
Настраивает UFW firewall:
- Базовые правила безопасности
- Открытие портов для SSH, HTTP, HTTPS
- Опционально: прямой доступ к CouchDB и Obsidian
- Правила для Docker сетей

## Управление сервисами

### CouchDB
```bash
# Запуск
cd /opt/couchdb && docker-compose up -d

# Остановка
cd /opt/couchdb && docker-compose down

# Логи
cd /opt/couchdb && docker-compose logs -f
```

### Obsidian LiveSync
```bash
# Использование скриптов
/opt/obsidian-sync/start.sh
/opt/obsidian-sync/stop.sh
/opt/obsidian-sync/update.sh

# Или напрямую через docker-compose
cd /opt/obsidian-sync && docker-compose up -d
```

### Бэкапы CouchDB
```bash
# Ручной запуск бэкапа
/opt/couchdb/backup/backup-couchdb.sh backup

# Настройка S3
/opt/couchdb/backup/backup-couchdb.sh setup-s3

# Настройка расписания
/opt/couchdb/backup/backup-couchdb.sh setup-cron
```

## Требования

- **ОС**: Ubuntu/Debian Linux
- **Права**: root доступ
- **Сеть**: доступ в интернет для скачивания образов
- **Домен**: настроенный домен с DNS записями
- **Traefik**: должен быть запущен отдельно (не входит в эти скрипты)

## Настройка после установки

1. **Настройте DNS записи** для ваших поддоменов:
   - `couchdb.ваш-домен.com` → IP сервера
   - `obsidian.ваш-домен.com` → IP сервера

2. **Проверьте работу Traefik** - он должен быть запущен и настроен

3. **Настройте аутентификацию** в файлах `.env`:
   - `/opt/couchdb/.env` - пароли CouchDB
   - `/opt/obsidian-sync/.env` - токены для Obsidian

4. **Настройте S3 бэкапы** (если используете):
   ```bash
   /opt/couchdb/backup/backup-couchdb.sh setup-s3
   ```

## Безопасность

- Все сервисы работают через Traefik с HTTPS
- UFW firewall настраивается автоматически
- Требуется аутентификация для доступа к CouchDB
- Рекомендуется изменить дефолтные пароли и токены

## Логи и мониторинг

- **CouchDB логи**: `docker-compose logs -f` в `/opt/couchdb/`
- **Obsidian логи**: `docker-compose logs -f` в `/opt/obsidian-sync/`
- **Логи бэкапов**: `/var/log/couchdb-backup.log`
- **UFW статус**: `ufw status`

## Поддержка

Все скрипты содержат детальные сообщения об ошибках и инструкции. При проблемах:

1. Проверьте логи сервисов
2. Убедитесь, что Traefik запущен
3. Проверьте DNS настройки
4. Проверьте статус UFW: `ufw status`

## Версии

- **CouchDB**: 3.3
- **Deno**: 2.2.10 (для Obsidian LiveSync)
- **Docker Compose**: latest
- **MinIO Client**: latest