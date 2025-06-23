#!/bin/bash

set -e

INSTALL_DIR="/opt/couchdb"
DEFAULT_PORT=5984

echo "=== CouchDB Installation Script ==="

if [ "$EUID" -ne 0 ]; then 
  echo "Please run as root"
  exit 1
fi

# Спрашиваем параметры у пользователя
read -p "Enter domain for CouchDB (e.g., example.com): " DOMAIN
read -p "Enter CouchDB admin username [admin]: " COUCHDB_USER
COUCHDB_USER=${COUCHDB_USER:-admin}
read -s -p "Enter CouchDB admin password: " COUCHDB_PASSWORD
echo
read -p "Enter CouchDB port [$DEFAULT_PORT]: " COUCHDB_PORT
COUCHDB_PORT=${COUCHDB_PORT:-$DEFAULT_PORT}

# Создаем структуру директорий
echo "Creating directory structure..."
mkdir -p $INSTALL_DIR/{data,config,backup}
cd $INSTALL_DIR

# Настройка UFW
echo "Configuring UFW firewall..."
ufw allow $COUCHDB_PORT/tcp comment "CouchDB"

# Создаем docker-compose.yml
cat > docker-compose.yml << EOF
version: '3.8'

services:
  couchdb:
    image: couchdb:3.3
    container_name: couchdb
    restart: unless-stopped
    environment:
      - COUCHDB_USER=\${COUCHDB_USER}
      - COUCHDB_PASSWORD=\${COUCHDB_PASSWORD}
    ports:
      - "\${COUCHDB_PORT}:5984"
    volumes:
      - ./data:/opt/couchdb/data
      - ./config:/opt/couchdb/etc/local.d
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.couchdb.rule=Host(\`couchdb.\${DOMAIN}\`)"
      - "traefik.http.routers.couchdb.entrypoints=websecure"
      - "traefik.http.routers.couchdb.tls.certresolver=letsencrypt"
      - "traefik.http.services.couchdb.loadbalancer.server.port=5984"
      - "traefik.http.routers.couchdb-insecure.rule=Host(\`couchdb.\${DOMAIN}\`)"
      - "traefik.http.routers.couchdb-insecure.entrypoints=web"
      - "traefik.http.routers.couchdb-insecure.middlewares=redirect-to-https"
      - "traefik.http.middlewares.redirect-to-https.redirectscheme.scheme=https"
    networks:
      - traefik

networks:
  traefik:
    external: true
EOF

# Создаем .env файл
cat > .env << EOF
DOMAIN=$DOMAIN
COUCHDB_USER=$COUCHDB_USER
COUCHDB_PASSWORD=$COUCHDB_PASSWORD
COUCHDB_PORT=$COUCHDB_PORT
EOF

# Создаем конфигурацию CouchDB
cat > config/10-docker-default.ini << EOF
[couchdb]
single_node=true

[chttpd]
require_valid_user = true
enable_cors = true

[httpd]
enable_cors = true

[cors]
origins = *
credentials = true
methods = GET, PUT, POST, HEAD, DELETE
headers = accept, authorization, content-type, origin, referer, x-csrf-token
EOF

# Устанавливаем права доступа
chown -R 5984:5984 $INSTALL_DIR/data $INSTALL_DIR/config

echo ""
echo "=== CouchDB Installation Completed ==="
echo "Location: $INSTALL_DIR"
echo "Domain: couchdb.$DOMAIN"
echo "Port: $COUCHDB_PORT"
echo "Admin User: $COUCHDB_USER"
echo ""
echo "To start CouchDB:"
echo "cd $INSTALL_DIR && docker-compose up -d"
echo ""
echo "To check status:"
echo "docker-compose ps"
echo ""
echo "Web interface will be available at:"
echo "https://couchdb.$DOMAIN (via Traefik)"
echo "http://localhost:$COUCHDB_PORT (direct access)"