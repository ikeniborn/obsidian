#!/bin/bash

set -e

echo "=== UFW Firewall Setup for Obsidian Services ==="

if [ "$EUID" -ne 0 ]; then 
  echo "Please run as root"
  exit 1
fi

# Проверяем, установлен ли UFW
if ! command -v ufw &> /dev/null; then
    echo "Installing UFW..."
    apt-get update
    apt-get install -y ufw
fi

# Базовая настройка UFW
echo "Configuring UFW basic rules..."

# Сбрасываем правила к дефолтным
ufw --force reset

# Устанавливаем политики по умолчанию
ufw default deny incoming
ufw default allow outgoing

# Разрешаем SSH (важно сделать это первым!)
read -p "Enter SSH port [22]: " SSH_PORT
SSH_PORT=${SSH_PORT:-22}
ufw allow $SSH_PORT/tcp comment "SSH"

# Разрешаем HTTP и HTTPS для Traefik
ufw allow 80/tcp comment "HTTP (Traefik)"
ufw allow 443/tcp comment "HTTPS (Traefik)"

# Спрашиваем про порты для сервисов
echo ""
echo "Configuring service ports..."

read -p "Configure CouchDB direct access? [y/N]: " SETUP_COUCHDB
if [[ $SETUP_COUCHDB =~ ^[Yy]$ ]]; then
    read -p "Enter CouchDB port [5984]: " COUCHDB_PORT
    COUCHDB_PORT=${COUCHDB_PORT:-5984}
    ufw allow $COUCHDB_PORT/tcp comment "CouchDB"
fi

read -p "Configure Obsidian sync direct access? [y/N]: " SETUP_OBSIDIAN
if [[ $SETUP_OBSIDIAN =~ ^[Yy]$ ]]; then
    read -p "Enter Obsidian sync port [3001]: " OBSIDIAN_PORT
    OBSIDIAN_PORT=${OBSIDIAN_PORT:-3001}
    ufw allow $OBSIDIAN_PORT/tcp comment "Obsidian LiveSync"
fi

# Дополнительные правила для Docker
echo "Configuring Docker-specific rules..."

# Разрешаем Docker bridge network
ufw allow from 172.16.0.0/12 comment "Docker networks"
ufw allow from 192.168.0.0/16 comment "Local networks"

# Включаем UFW
echo "Enabling UFW..."
ufw --force enable

# Показываем текущие правила
echo ""
echo "=== Current UFW Rules ==="
ufw status numbered

echo ""
echo "=== UFW Configuration Completed ==="
echo ""
echo "Important notes:"
echo "1. SSH access is allowed on port $SSH_PORT"
echo "2. HTTP (80) and HTTPS (443) are open for Traefik"
if [[ $SETUP_COUCHDB =~ ^[Yy]$ ]]; then
    echo "3. CouchDB direct access on port $COUCHDB_PORT"
fi
if [[ $SETUP_OBSIDIAN =~ ^[Yy]$ ]]; then
    echo "4. Obsidian sync direct access on port $OBSIDIAN_PORT"
fi
echo ""
echo "To check status: ufw status"
echo "To add rules: ufw allow <port>/tcp"
echo "To remove rules: ufw delete <rule_number>"