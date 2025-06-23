#!/bin/bash

set -e

INSTALL_DIR="/opt/obsidian-sync"
DEFAULT_PORT=3001
REPO_URL="https://github.com/vrtmrz/livesync-serverpeer.git"

echo "=== Obsidian LiveSync Server Installation Script ==="

if [ "$EUID" -ne 0 ]; then 
  echo "Please run as root"
  exit 1
fi

# Спрашиваем параметры у пользователя
read -p "Enter domain for Obsidian sync (e.g., example.com): " DOMAIN
read -p "Enter port for Obsidian sync [$DEFAULT_PORT]: " OBSIDIAN_PORT
OBSIDIAN_PORT=${OBSIDIAN_PORT:-$DEFAULT_PORT}

# Создаем структуру директорий
echo "Creating directory structure..."
mkdir -p $INSTALL_DIR/{config,data}
cd $INSTALL_DIR

# Настройка UFW
echo "Configuring UFW firewall..."
ufw allow $OBSIDIAN_PORT/tcp comment "Obsidian LiveSync"

# Клонируем репозиторий во временную директорию
echo "Downloading livesync-serverpeer..."
TEMP_DIR=$(mktemp -d)
git clone $REPO_URL $TEMP_DIR
cp $TEMP_DIR/Dockerfile ./
cp $TEMP_DIR/*.ts ./
cp $TEMP_DIR/*.json ./
cp $TEMP_DIR/.env.sample ./
rm -rf $TEMP_DIR

# Создаем Dockerfile для продакшена
cat > Dockerfile << 'EOF'
FROM denoland/deno:2.2.10

WORKDIR /app

# Копируем файлы проекта
COPY *.ts ./
COPY *.json ./

# Кэшируем зависимости
COPY deno.json deno.lock* ./
RUN deno cache --lock=deno.lock mod.ts

# Собираем приложение
RUN deno task build || deno compile --allow-net --allow-read --allow-write --allow-env mod.ts

EXPOSE 3001

CMD ["deno", "task", "start"]
EOF

# Создаем docker-compose.yml
cat > docker-compose.yml << EOF
version: '3.8'

services:
  obsidian-sync:
    build: .
    container_name: obsidian-sync
    restart: unless-stopped
    environment:
      - PORT=3001
    env_file:
      - .env
    ports:
      - "\${OBSIDIAN_PORT}:3001"
    volumes:
      - ./data:/app/data
      - ./config:/app/config
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.obsidian.rule=Host(\`obsidian.\${DOMAIN}\`)"
      - "traefik.http.routers.obsidian.entrypoints=websecure"
      - "traefik.http.routers.obsidian.tls.certresolver=letsencrypt"
      - "traefik.http.services.obsidian.loadbalancer.server.port=3001"
      - "traefik.http.routers.obsidian-insecure.rule=Host(\`obsidian.\${DOMAIN}\`)"
      - "traefik.http.routers.obsidian-insecure.entrypoints=web"
      - "traefik.http.routers.obsidian-insecure.middlewares=redirect-to-https"
      - "traefik.http.middlewares.redirect-to-https.redirectscheme.scheme=https"
    networks:
      - traefik

networks:
  traefik:
    external: true
EOF

# Создаем .env файл на основе примера
if [ -f .env.sample ]; then
    cp .env.sample .env
else
    cat > .env << EOF
# Server configuration
PORT=3001
HOST=0.0.0.0

# Security
ENABLE_AUTH=true
AUTH_TOKEN=change_this_secure_token

# Logging
LOG_LEVEL=info

# Data directory
DATA_DIR=/app/data
EOF
fi

# Добавляем наши параметры в .env
cat >> .env << EOF

# Custom configuration
DOMAIN=$DOMAIN
OBSIDIAN_PORT=$OBSIDIAN_PORT
EOF

# Создаем start script
cat > start.sh << 'EOF'
#!/bin/bash

cd /opt/obsidian-sync

echo "Starting Obsidian LiveSync Server..."
docker-compose up -d

echo "Checking status..."
docker-compose ps

echo ""
echo "Service started successfully!"
echo "Check logs with: docker-compose logs -f"
EOF

# Создаем stop script
cat > stop.sh << 'EOF'
#!/bin/bash

cd /opt/obsidian-sync

echo "Stopping Obsidian LiveSync Server..."
docker-compose down

echo "Service stopped."
EOF

# Создаем update script
cat > update.sh << 'EOF'
#!/bin/bash

cd /opt/obsidian-sync

echo "Updating Obsidian LiveSync Server..."

# Останавливаем сервис
docker-compose down

# Обновляем код
TEMP_DIR=$(mktemp -d)
git clone https://github.com/vrtmrz/livesync-serverpeer.git $TEMP_DIR

# Сохраняем конфигурацию
cp .env .env.backup

# Обновляем файлы
cp $TEMP_DIR/*.ts ./
cp $TEMP_DIR/*.json ./

# Восстанавливаем конфигурацию
mv .env.backup .env

# Пересобираем образ
docker-compose build --no-cache

# Запускаем сервис
docker-compose up -d

rm -rf $TEMP_DIR

echo "Update completed!"
EOF

chmod +x start.sh stop.sh update.sh

# Устанавливаем права доступа
chown -R root:root $INSTALL_DIR

echo ""
echo "=== Obsidian LiveSync Server Installation Completed ==="
echo "Location: $INSTALL_DIR"
echo "Domain: obsidian.$DOMAIN"
echo "Port: $OBSIDIAN_PORT"
echo ""
echo "Important: Edit .env file to configure authentication and other settings"
echo ""
echo "To build and start the service:"
echo "cd $INSTALL_DIR && docker-compose up -d --build"
echo ""
echo "Management scripts:"
echo "$INSTALL_DIR/start.sh   - Start service"
echo "$INSTALL_DIR/stop.sh    - Stop service"
echo "$INSTALL_DIR/update.sh  - Update service"
echo ""
echo "To check status:"
echo "docker-compose ps"
echo ""
echo "Web interface will be available at:"
echo "https://obsidian.$DOMAIN (via Traefik)"
echo "http://localhost:$OBSIDIAN_PORT (direct access)"
echo ""
echo "Don't forget to configure authentication in .env file!"