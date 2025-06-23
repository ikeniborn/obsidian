#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "======================================================"
echo "    Obsidian + CouchDB Services Installation"
echo "======================================================"
echo ""

if [ "$EUID" -ne 0 ]; then 
  echo "Please run as root"
  exit 1
fi

# Проверяем зависимости
echo "Checking dependencies..."

# Docker
if ! command -v docker &> /dev/null; then
    echo "Installing Docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    rm get-docker.sh
    systemctl enable docker
    systemctl start docker
fi

# Docker Compose
if ! command -v docker-compose &> /dev/null; then
    echo "Installing Docker Compose..."
    curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
fi

# Git
if ! command -v git &> /dev/null; then
    echo "Installing Git..."
    apt-get update
    apt-get install -y git
fi

# Проверяем сеть Traefik
if ! docker network ls | grep -q traefik; then
    echo "Creating Traefik network..."
    docker network create traefik
fi

echo ""
echo "Dependencies check completed."
echo ""

# Выбираем что устанавливать
echo "What would you like to install?"
echo "1) CouchDB only"
echo "2) Obsidian LiveSync only"
echo "3) Both services"
echo "4) Firewall setup only"
echo "5) Full installation (all + firewall)"
echo ""
read -p "Enter your choice [1-5]: " INSTALL_CHOICE

case $INSTALL_CHOICE in
    1)
        echo "Installing CouchDB..."
        chmod +x "$SCRIPT_DIR/install-couchdb.sh"
        "$SCRIPT_DIR/install-couchdb.sh"
        
        read -p "Setup CouchDB backup? [y/N]: " SETUP_BACKUP
        if [[ $SETUP_BACKUP =~ ^[Yy]$ ]]; then
            chmod +x "$SCRIPT_DIR/backup-couchdb.sh"
            "$SCRIPT_DIR/backup-couchdb.sh" install
        fi
        ;;
    2)
        echo "Installing Obsidian LiveSync..."
        chmod +x "$SCRIPT_DIR/install-obsidian-sync.sh"
        "$SCRIPT_DIR/install-obsidian-sync.sh"
        ;;
    3)
        echo "Installing both services..."
        
        echo "Step 1: Installing CouchDB..."
        chmod +x "$SCRIPT_DIR/install-couchdb.sh"
        "$SCRIPT_DIR/install-couchdb.sh"
        
        echo ""
        echo "Step 2: Installing Obsidian LiveSync..."
        chmod +x "$SCRIPT_DIR/install-obsidian-sync.sh"
        "$SCRIPT_DIR/install-obsidian-sync.sh"
        
        read -p "Setup CouchDB backup? [y/N]: " SETUP_BACKUP
        if [[ $SETUP_BACKUP =~ ^[Yy]$ ]]; then
            chmod +x "$SCRIPT_DIR/backup-couchdb.sh"
            "$SCRIPT_DIR/backup-couchdb.sh" install
        fi
        ;;
    4)
        echo "Setting up firewall..."
        chmod +x "$SCRIPT_DIR/setup-firewall.sh"
        "$SCRIPT_DIR/setup-firewall.sh"
        ;;
    5)
        echo "Full installation..."
        
        echo "Step 1: Setting up firewall..."
        chmod +x "$SCRIPT_DIR/setup-firewall.sh"
        "$SCRIPT_DIR/setup-firewall.sh"
        
        echo ""
        echo "Step 2: Installing CouchDB..."
        chmod +x "$SCRIPT_DIR/install-couchdb.sh"
        "$SCRIPT_DIR/install-couchdb.sh"
        
        echo ""
        echo "Step 3: Installing Obsidian LiveSync..."
        chmod +x "$SCRIPT_DIR/install-obsidian-sync.sh"
        "$SCRIPT_DIR/install-obsidian-sync.sh"
        
        echo ""
        echo "Step 4: Setting up CouchDB backup..."
        chmod +x "$SCRIPT_DIR/backup-couchdb.sh"
        "$SCRIPT_DIR/backup-couchdb.sh" install
        ;;
    *)
        echo "Invalid choice. Exiting."
        exit 1
        ;;
esac

echo ""
echo "======================================================"
echo "              Installation Completed"
echo "======================================================"
echo ""
echo "Installed services location: /opt/"
echo ""
echo "Service management:"
echo ""
if [ -d "/opt/couchdb" ]; then
    echo "CouchDB:"
    echo "  Start: cd /opt/couchdb && docker-compose up -d"
    echo "  Stop:  cd /opt/couchdb && docker-compose down"
    echo "  Logs:  cd /opt/couchdb && docker-compose logs -f"
    echo ""
fi

if [ -d "/opt/obsidian-sync" ]; then
    echo "Obsidian LiveSync:"
    echo "  Start: cd /opt/obsidian-sync && docker-compose up -d"
    echo "  Stop:  cd /opt/obsidian-sync && docker-compose down"
    echo "  Logs:  cd /opt/obsidian-sync && docker-compose logs -f"
    echo "  Or use management scripts:"
    echo "    /opt/obsidian-sync/start.sh"
    echo "    /opt/obsidian-sync/stop.sh"
    echo "    /opt/obsidian-sync/update.sh"
    echo ""
fi

echo "Important next steps:"
echo "1. Configure your domain DNS to point to this server"
echo "2. Ensure Traefik is running and configured properly"
echo "3. Check that all services are accessible via their domains"
echo "4. Review and customize .env files for security"
echo ""
echo "For troubleshooting, check Docker logs for each service."