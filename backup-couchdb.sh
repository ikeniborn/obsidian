#!/bin/bash

set -e

BACKUP_DIR="/opt/couchdb/backup"
COUCHDB_CONTAINER="couchdb"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="couchdb_backup_$DATE.tar.gz"
DEFAULT_SCHEDULE="0 3 * * *"

# Функция для создания бэкапа
create_backup() {
    echo "Starting CouchDB backup at $(date)"
    
    # Создаем директорию для бэкапов если её нет
    mkdir -p $BACKUP_DIR
    
    # Проверяем, что контейнер запущен
    if ! docker ps | grep -q $COUCHDB_CONTAINER; then
        echo "Error: CouchDB container is not running"
        exit 1
    fi
    
    # Создаем бэкап данных
    cd /opt/couchdb
    tar -czf "$BACKUP_DIR/$BACKUP_FILE" data/ config/
    
    echo "Backup created: $BACKUP_DIR/$BACKUP_FILE"
    
    # Загружаем в S3 если настроен mc
    if command -v mc &> /dev/null; then
        if mc ls yc-s3 &> /dev/null; then
            echo "Uploading backup to S3..."
            mc cp "$BACKUP_DIR/$BACKUP_FILE" "yc-s3/${S3_BUCKET}/couchdb/"
            echo "Backup uploaded successfully"
        else
            echo "Warning: mc client not configured for yc-s3 alias"
        fi
    else
        echo "Warning: mc client not installed"
    fi
    
    # Удаляем старые локальные бэкапы (старше 7 дней)
    find $BACKUP_DIR -name "couchdb_backup_*.tar.gz" -mtime +7 -delete
    
    echo "Backup completed at $(date)"
}

# Функция для настройки mc client
setup_mc_client() {
    echo "=== MinIO Client (mc) Setup for Yandex Cloud S3 ==="
    
    read -p "Enter S3 endpoint [https://storage.yandexcloud.net]: " S3_ENDPOINT
    S3_ENDPOINT=${S3_ENDPOINT:-https://storage.yandexcloud.net}
    
    read -p "Enter Access Key ID: " ACCESS_KEY
    read -s -p "Enter Secret Access Key: " SECRET_KEY
    echo
    read -p "Enter S3 bucket name: " S3_BUCKET
    
    # Устанавливаем mc если не установлен
    if ! command -v mc &> /dev/null; then
        echo "Installing MinIO client..."
        wget https://dl.min.io/client/mc/release/linux-amd64/mc -O /usr/local/bin/mc
        chmod +x /usr/local/bin/mc
    fi
    
    # Настраиваем alias для Yandex Cloud
    mc alias set yc-s3 $S3_ENDPOINT $ACCESS_KEY $SECRET_KEY
    
    # Проверяем подключение
    if mc ls yc-s3; then
        echo "Successfully connected to S3"
    else
        echo "Failed to connect to S3"
        exit 1
    fi
    
    # Сохраняем конфигурацию
    cat > /opt/couchdb/.s3-config << EOF
S3_ENDPOINT=$S3_ENDPOINT
S3_BUCKET=$S3_BUCKET
ACCESS_KEY=$ACCESS_KEY
SECRET_KEY=$SECRET_KEY
EOF
    
    echo "S3 configuration saved"
}

# Функция для настройки cron
setup_cron() {
    read -p "Enter backup schedule in cron format [$DEFAULT_SCHEDULE]: " SCHEDULE
    SCHEDULE=${SCHEDULE:-$DEFAULT_SCHEDULE}
    
    # Создаем cron job
    CRON_JOB="$SCHEDULE /opt/couchdb/backup/backup-couchdb.sh backup >> /var/log/couchdb-backup.log 2>&1"
    
    # Добавляем в crontab если не существует
    if ! crontab -l 2>/dev/null | grep -q "backup-couchdb.sh"; then
        (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
        echo "Cron job added: $SCHEDULE"
        echo "Logs will be written to /var/log/couchdb-backup.log"
    else
        echo "Cron job already exists"
    fi
}

# Основная логика
case "${1:-}" in
    "backup")
        # Загружаем конфигурацию S3 если существует
        if [ -f /opt/couchdb/.s3-config ]; then
            source /opt/couchdb/.s3-config
        fi
        create_backup
        ;;
    "setup-s3")
        setup_mc_client
        ;;
    "setup-cron")
        setup_cron
        ;;
    "install")
        echo "=== CouchDB Backup Setup ==="
        
        # Копируем скрипт в нужное место
        mkdir -p /opt/couchdb/backup
        cp "$0" /opt/couchdb/backup/backup-couchdb.sh
        chmod +x /opt/couchdb/backup/backup-couchdb.sh
        
        echo "1. Setting up MinIO client for S3..."
        setup_mc_client
        
        echo "2. Setting up cron schedule..."
        setup_cron
        
        echo ""
        echo "=== Backup Setup Completed ==="
        echo "Manual backup: /opt/couchdb/backup/backup-couchdb.sh backup"
        echo "Logs: /var/log/couchdb-backup.log"
        ;;
    *)
        echo "Usage: $0 {backup|setup-s3|setup-cron|install}"
        echo ""
        echo "Commands:"
        echo "  backup     - Create backup now"
        echo "  setup-s3   - Setup S3 configuration"
        echo "  setup-cron - Setup cron schedule"
        echo "  install    - Full setup (S3 + cron)"
        exit 1
        ;;
esac