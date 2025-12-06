# TunnelWatch Norway - Complete Deployment Guide

**THIS DOCUMENT CONTAINS EVERYTHING YOU NEED TO DEPLOY THE SERVICE**

All code, configurations, scripts, and instructions are included.  
No external references needed.

---

## 📚 Document Structure

This guide is split into clearly marked sections. Read in order for deployment:

**PART 1: Foundation** (This file)
- Overview & Architecture
- Prerequisites
- All configuration files
- All Docker files  
- Database schema
- PHP application (complete)

**PART 2: Workers & Deployment** (See companion file: `tunnelwatch-workers-deployment.md`)
- Python workers (complete)
- All scripts
- Deployment steps
- Signal setup
- Cloudflare setup
- Testing & troubleshooting

---

## Quick Links

- [Overview](#overview)
- [Architecture](#architecture)
- [File Structure](#complete-file-structure)
- [Prerequisites](#prerequisites)
- [Configuration Files](#configuration-files)
- [Docker Files](#docker-files)
- [Database](#database-schema)
- [PHP Application](#php-application)

---

## Overview

### What Is This?

A self-hosted service that:
- ✅ Monitors Norwegian tunnel status in real-time
- ✅ Sends Signal notifications when status changes
- ✅ Provides a clean web interface
- ✅ Tracks historical data
- ✅ Runs completely on your own server

### Initial Scope
- Monitor: **Mastrafjordtunnelen** and **Byfjordtunnelen**
- Check frequency: Every 60 seconds
- Notifications: Signal only
- Interface: Simple PHP website

---

## Architecture

```
Internet (Cloudflare Tunnel)
        ↓
    Nginx:80 (web server)
        ↓
    PHP-FPM (renders pages)
        ↓
    PostgreSQL (stores data)
        ↑
Python Workers (monitors APIs, sends notifications)
        ↓
    Signal CLI (sends messages)
```

**6 Docker Containers:**
1. `postgres` - Database
2. `redis` - Task queue
3. `php` - Web application
4. `nginx` - Web server
5. `worker` - Python Celery worker
6. `beat` - Python Celery scheduler
7. `signal-api` - Signal CLI

---

## Complete File Structure

```
tunnelwatch/
├── .env                        # Your configuration
├── .env.example               # Configuration template
├── .gitignore
├── docker-compose.yml
├── Makefile
├── README.md
│
├── database/
│   ├── init.sql
│   └── seed-tunnels.sql
│
├── nginx/
│   ├── Dockerfile
│   └── default.conf
│
├── php/
│   ├── Dockerfile
│   ├── composer.json
│   ├── public/
│   │   ├── index.php
│   │   ├── api.php
│   │   ├── tunnel.php
│   │   └── assets/
│   │       ├── css/style.css
│   │       └── js/app.js
│   └── src/
│       ├── Database.php
│       ├── Tunnel.php
│       ├── StatusUpdate.php
│       └── helpers.php
│
├── workers/
│   ├── Dockerfile
│   ├── requirements.txt
│   ├── celery_app.py
│   ├── tasks/
│   │   ├── __init__.py
│   │   ├── monitor.py
│   │   ├── nvdb_sync.py
│   │   └── notifications.py
│   └── services/
│       ├── __init__.py
│       ├── nvdb_service.py
│       ├── traffic_service.py
│       └── signal_service.py
│
└── scripts/
    ├── backup-db.sh
    ├── restore-db.sh
    ├── register-signal.sh
    ├── add-subscription.sh
    └── find-tunnel-id.sh
```

---

## Prerequisites

### Install Docker on Ubuntu

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# Add user to docker group
sudo usermod -aG docker $USER
newgrp docker

# Verify
docker --version
docker compose version
```

### Install Tools

```bash
sudo apt install -y git curl jq nano

# For Cloudflare tunnel
wget https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
sudo dpkg -i cloudflared-linux-amd64.deb
```

---

## Configuration Files

Create these files exactly as shown:

### `.env.example`

```bash
# Database
POSTGRES_USER=tunnelwatch
POSTGRES_PASSWORD=CHANGE_ME_SECURE_PASSWORD
POSTGRES_DB=tunnelwatch

# Redis
REDIS_HOST=redis
REDIS_PORT=6379

# Signal
SIGNAL_NUMBER=+47XXXXXXXXX
SIGNAL_API_URL=http://signal-api:8080

# APIs
NVDB_API_URL=https://nvdbapiles-v3.atlas.vegvesen.no
TRAFFIC_API_URL=https://www.vegvesen.no/trafikk

# Monitoring
POLL_INTERVAL=60
NVDB_SYNC_HOUR=3

# Backup
NAS_BACKUP_PATH=/mnt/nas/tunnelwatch-backups
BACKUP_RETENTION_DAYS=30

# PHP
PHP_TIMEZONE=Europe/Oslo

# App
APP_ENV=production
APP_DEBUG=false
```

### `.gitignore`

```
.env
.env.local
vendor/
*.log
postgres_data/
redis_data/
signal_data/
*.sql
*.sql.gz
.vscode/
.idea/
.DS_Store
```

### `README.md`

```markdown
# TunnelWatch Norway

Real-time Norwegian tunnel monitoring with Signal notifications.

## Quick Start

\`\`\`bash
cp .env.example .env
nano .env  # Edit settings
chmod +x scripts/*.sh
docker compose up -d
./scripts/register-signal.sh
\`\`\`

## Commands

\`\`\`bash
make up      # Start
make down    # Stop
make logs    # View logs
make backup  # Backup DB
\`\`\`
```

### `Makefile`

```makefile
.PHONY: help up down restart logs build backup

help:
	@echo "Commands:"
	@echo "  make up       - Start services"
	@echo "  make down     - Stop services"  
	@echo "  make logs     - View logs"
	@echo "  make backup   - Backup database"

up:
	docker compose up -d

down:
	docker compose down

restart:
	docker compose restart

logs:
	docker compose logs -f

build:
	docker compose build --no-cache

backup:
	./scripts/backup-db.sh
```

---

## Docker Files

### `docker-compose.yml`

```yaml
version: '3.9'

services:
  postgres:
    image: postgres:16-alpine
    container_name: tunnelwatch-db
    environment:
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ${POSTGRES_DB}
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./database/init.sql:/docker-entrypoint-initdb.d/01-init.sql:ro
      - ./database/seed-tunnels.sql:/docker-entrypoint-initdb.d/02-seed.sql:ro
    networks:
      - tunnelwatch
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER}"]
      interval: 10s

  redis:
    image: redis:7-alpine
    container_name: tunnelwatch-redis
    command: redis-server --appendonly yes
    volumes:
      - redis_data:/data
    networks:
      - tunnelwatch
    restart: unless-stopped

  php:
    build: ./php
    container_name: tunnelwatch-php
    volumes:
      - ./php:/var/www/html
    environment:
      - DB_HOST=postgres
      - DB_NAME=${POSTGRES_DB}
      - DB_USER=${POSTGRES_USER}
      - DB_PASSWORD=${POSTGRES_PASSWORD}
    depends_on:
      - postgres
    networks:
      - tunnelwatch
    restart: unless-stopped

  nginx:
    build: ./nginx
    container_name: tunnelwatch-nginx
    ports:
      - "80:80"
    volumes:
      - ./php/public:/var/www/html/public:ro
    depends_on:
      - php
    networks:
      - tunnelwatch
    restart: unless-stopped

  worker:
    build: ./workers
    container_name: tunnelwatch-worker
    command: celery -A celery_app worker --loglevel=info
    volumes:
      - ./workers:/app
    environment:
      - DATABASE_URL=postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/${POSTGRES_DB}
      - REDIS_URL=redis://redis:6379/0
      - SIGNAL_API_URL=${SIGNAL_API_URL}
      - SIGNAL_NUMBER=${SIGNAL_NUMBER}
    depends_on:
      - postgres
      - redis
    networks:
      - tunnelwatch
    restart: unless-stopped

  beat:
    build: ./workers
    container_name: tunnelwatch-beat
    command: celery -A celery_app beat --loglevel=info
    volumes:
      - ./workers:/app
    environment:
      - DATABASE_URL=postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/${POSTGRES_DB}
      - REDIS_URL=redis://redis:6379/0
    depends_on:
      - redis
    networks:
      - tunnelwatch
    restart: unless-stopped

  signal-api:
    image: bbernhard/signal-cli-rest-api:latest
    container_name: tunnelwatch-signal
    environment:
      - MODE=native
    volumes:
      - signal_data:/home/.local/share/signal-cli
    networks:
      - tunnelwatch
    restart: unless-stopped

networks:
  tunnelwatch:
    driver: bridge

volumes:
  postgres_data:
  redis_data:
  signal_data:
```

### `nginx/Dockerfile`

```dockerfile
FROM nginx:alpine
COPY default.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
```

### `nginx/default.conf`

```nginx
server {
    listen 80;
    server_name _;
    root /var/www/html/public;
    index index.php;

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    location ~ \.php$ {
        fastcgi_pass php:9000;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\. {
        deny all;
    }
}
```

### `php/Dockerfile`

```dockerfile
FROM php:8.2-fpm-alpine

RUN apk add --no-cache postgresql-dev && \
    docker-php-ext-install pdo pdo_pgsql

COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

WORKDIR /var/www/html

COPY . .

RUN composer install --no-dev --optimize-autoloader || true

RUN chown -R www-data:www-data /var/www/html

USER www-data

EXPOSE 9000
```

### `php/composer.json`

```json
{
    "name": "tunnelwatch/norway",
    "type": "project",
    "require": {
        "php": ">=8.2"
    },
    "autoload": {
        "psr-4": {
            "TunnelWatch\\": "src/"
        },
        "files": ["src/helpers.php"]
    }
}
```

### `workers/Dockerfile`

```dockerfile
FROM python:3.11-slim

WORKDIR /app

RUN apt-get update && \
    apt-get install -y gcc postgresql-client libpq-dev && \
    rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

USER nobody

CMD ["celery", "-A", "celery_app", "worker", "--loglevel=info"]
```

### `workers/requirements.txt`

```
celery==5.3.4
redis==5.0.1
psycopg2-binary==2.9.9
httpx==0.25.2
python-dateutil==2.8.2
```

---

## Database Schema

### `database/init.sql`

```sql
CREATE TABLE IF NOT EXISTS tunnels (
    id VARCHAR(50) PRIMARY KEY,
    name VARCHAR(200) NOT NULL,
    vegvesen_id VARCHAR(100) UNIQUE NOT NULL,
    latitude NUMERIC(10, 7) NOT NULL,
    longitude NUMERIC(10, 7) NOT NULL,
    length INTEGER,
    height_limit NUMERIC(4, 2),
    metadata JSONB DEFAULT '{}',
    active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_tunnels_vegvesen_id ON tunnels(vegvesen_id);
CREATE INDEX idx_tunnels_active ON tunnels(active);

CREATE TABLE IF NOT EXISTS status_updates (
    id SERIAL PRIMARY KEY,
    tunnel_id VARCHAR(50) REFERENCES tunnels(id) ON DELETE CASCADE,
    status VARCHAR(50) NOT NULL,
    incident_type VARCHAR(100),
    message TEXT,
    severity VARCHAR(20),
    expected_reopen TIMESTAMP WITH TIME ZONE,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_status_tunnel_id ON status_updates(tunnel_id);
CREATE INDEX idx_status_created_at ON status_updates(created_at DESC);

CREATE TABLE IF NOT EXISTS subscriptions (
    id SERIAL PRIMARY KEY,
    phone_number VARCHAR(20) NOT NULL,
    tunnel_id VARCHAR(50) REFERENCES tunnels(id) ON DELETE CASCADE,
    notification_methods JSONB DEFAULT '["signal"]',
    active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(phone_number, tunnel_id)
);

CREATE INDEX idx_subscriptions_phone ON subscriptions(phone_number);
CREATE INDEX idx_subscriptions_tunnel ON subscriptions(tunnel_id);

CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_tunnels_updated_at 
    BEFORE UPDATE ON tunnels
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_subscriptions_updated_at 
    BEFORE UPDATE ON subscriptions
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE OR REPLACE VIEW tunnel_current_status AS
SELECT DISTINCT ON (t.id)
    t.id, t.name, t.vegvesen_id, t.latitude, t.longitude, 
    t.length, t.height_limit, t.active,
    COALESCE(su.status, 'unknown') as status,
    su.incident_type, su.message, su.severity, su.expected_reopen,
    su.created_at as status_updated_at
FROM tunnels t
LEFT JOIN status_updates su ON t.id = su.tunnel_id
WHERE t.active = true
ORDER BY t.id, su.created_at DESC NULLS LAST;
```

### `database/seed-tunnels.sql`

```sql
INSERT INTO tunnels (id, name, vegvesen_id, latitude, longitude, length, active)
VALUES 
('mastrafjord', 'Mastrafjordtunnelen', '79604497', 59.088410, 5.692540, 4424, true),
('byfjord', 'Byfjordtunnelen', 'FIND_THIS_ID', 59.140000, 5.820000, 5875, true)
ON CONFLICT (vegvesen_id) DO UPDATE SET
    name = EXCLUDED.name,
    latitude = EXCLUDED.latitude,
    longitude = EXCLUDED.longitude,
    length = EXCLUDED.length;

INSERT INTO status_updates (tunnel_id, status, message, severity)
VALUES 
('mastrafjord', 'open', 'Tunnelen er åpen for normal trafikk', 'low'),
('byfjord', 'open', 'Tunnelen er åpen for normal trafikk', 'low');
```

---

## PHP Application

Create these files in the `php/` directory:

### `php/src/Database.php`

```php
<?php
namespace TunnelWatch;

class Database {
    private static ?Database $instance = null;
    private ?\PDO $connection = null;
    
    private function __construct() {
        $host = getenv('DB_HOST') ?: 'postgres';
        $db = getenv('DB_NAME') ?: 'tunnelwatch';
        $user = getenv('DB_USER') ?: 'tunnelwatch';
        $pass = getenv('DB_PASSWORD') ?: '';
        
        $dsn = "pgsql:host={$host};dbname={$db}";
        
        $this->connection = new \PDO($dsn, $user, $pass, [
            \PDO::ATTR_ERRMODE => \PDO::ERRMODE_EXCEPTION,
            \PDO::ATTR_DEFAULT_FETCH_MODE => \PDO::FETCH_ASSOC,
        ]);
    }
    
    public static function getInstance(): Database {
        if (self::$instance === null) {
            self::$instance = new Database();
        }
        return self::$instance;
    }
    
    public function getConnection(): \PDO {
        return $this->connection;
    }
    
    public function query(string $sql, array $params = []): \PDOStatement {
        $stmt = $this->connection->prepare($sql);
        $stmt->execute($params);
        return $stmt;
    }
}
```

### `php/src/Tunnel.php`

```php
<?php
namespace TunnelWatch;

class Tunnel {
    private Database $db;
    
    public function __construct() {
        $this->db = Database::getInstance();
    }
    
    public function getAllActive(): array {
        $sql = "SELECT * FROM tunnel_current_status ORDER BY name";
        return $this->db->query($sql)->fetchAll();
    }
    
    public function getById(string $id): ?array {
        $sql = "SELECT * FROM tunnel_current_status WHERE id = :id";
        $result = $this->db->query($sql, ['id' => $id])->fetch();
        return $result ?: null;
    }
    
    public function getStatusHistory(string $tunnelId, int $limit = 50): array {
        $sql = "
            SELECT * FROM status_updates
            WHERE tunnel_id = :tunnel_id
            ORDER BY created_at DESC LIMIT :limit
        ";
        $stmt = $this->db->getConnection()->prepare($sql);
        $stmt->bindValue(':tunnel_id', $tunnelId, \PDO::PARAM_STR);
        $stmt->bindValue(':limit', $limit, \PDO::PARAM_INT);
        $stmt->execute();
        return $stmt->fetchAll();
    }
}
```

### `php/src/StatusUpdate.php`

```php
<?php
namespace TunnelWatch;

class StatusUpdate {
    private Database $db;
    
    public function __construct() {
        $this->db = Database::getInstance();
    }
    
    public function getLatestForTunnel(string $tunnelId): ?array {
        $sql = "
            SELECT * FROM status_updates
            WHERE tunnel_id = :tunnel_id
            ORDER BY created_at DESC LIMIT 1
        ";
        $result = $this->db->query($sql, ['tunnel_id' => $tunnelId])->fetch();
        return $result ?: null;
    }
}
```

### `php/src/helpers.php`

```php
<?php

function getStatusBadge(string $status): string {
    $badges = [
        'open' => '<span class="badge badge-green">✅ Åpen</span>',
        'closed' => '<span class="badge badge-red">🚫 Stengt</span>',
        'restricted' => '<span class="badge badge-yellow">⚠️ Begrenset</span>',
    ];
    return $badges[$status] ?? '<span class="badge badge-gray">❓ Ukjent</span>';
}

function getStatusClass(string $status): string {
    return "status-{$status}";
}

function formatLength(?int $length): string {
    return $length ? number_format($length, 0, ',', ' ') . ' meter' : 'Ukjent';
}

function formatDateTime(?string $datetime): string {
    if (!$datetime) return '';
    $dt = new DateTime($datetime);
    $dt->setTimezone(new DateTimeZone('Europe/Oslo'));
    return $dt->format('d.m.Y \k\l. H:i');
}

function timeAgo(string $datetime): string {
    $dt = new DateTime($datetime);
    $now = new DateTime();
    $diff = $now->diff($dt);
    
    if ($diff->d > 0) return $diff->d . ' dag' . ($diff->d > 1 ? 'er' : '') . ' siden';
    if ($diff->h > 0) return $diff->h . ' time' . ($diff->h > 1 ? 'r' : '') . ' siden';
    if ($diff->i > 0) return $diff->i . ' minutt' . ($diff->i > 1 ? 'er' : '') . ' siden';
    return 'Akkurat nå';
}
```

### `php/public/index.php`

```php
<?php
require_once __DIR__ . '/../vendor/autoload.php';

use TunnelWatch\Tunnel;

$tunnelModel = new Tunnel();
$tunnels = $tunnelModel->getAllActive();
?>
<!DOCTYPE html>
<html lang="no">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>TunnelWatch Norge</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <link rel="stylesheet" href="/assets/css/style.css">
</head>
<body class="bg-gray-100">
    <header class="bg-blue-600 text-white shadow-lg">
        <div class="container mx-auto px-4 py-6">
            <h1 class="text-3xl font-bold">🚇 TunnelWatch Norge</h1>
            <p class="text-blue-100 mt-2">Sanntids status for norske tunneler</p>
        </div>
    </header>

    <main class="container mx-auto px-4 py-8">
        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
            <?php foreach ($tunnels as $tunnel): ?>
                <?php $statusClass = getStatusClass($tunnel['status'] ?? 'unknown'); ?>
                
                <div class="bg-white rounded-lg shadow-md hover:shadow-xl transition-shadow">
                    <div class="h-2 <?= $statusClass ?>-bar"></div>
                    
                    <div class="p-6">
                        <div class="flex justify-between items-start mb-4">
                            <h3 class="text-xl font-semibold"><?= htmlspecialchars($tunnel['name']) ?></h3>
                            <?= getStatusBadge($tunnel['status']) ?>
                        </div>

                        <?php if (!empty($tunnel['message'])): ?>
                            <div class="mb-4 p-3 bg-gray-50 rounded text-sm">
                                <?= htmlspecialchars($tunnel['message']) ?>
                            </div>
                        <?php endif; ?>

                        <div class="text-sm text-gray-600">
                            <?php if ($tunnel['length']): ?>
                                <div>Lengde: <?= formatLength($tunnel['length']) ?></div>
                            <?php endif; ?>
                        </div>

                        <div class="mt-4 text-xs text-gray-400">
                            Oppdatert: <?= !empty($tunnel['status_updated_at']) ? timeAgo($tunnel['status_updated_at']) : 'Ukjent' ?>
                        </div>
                    </div>
                </div>
            <?php endforeach; ?>
        </div>

        <div class="mt-8 text-center text-sm text-gray-500">
            <p>Data oppdateres automatisk hvert minutt</p>
        </div>
    </main>

    <script src="/assets/js/app.js"></script>
</body>
</html>
```

### `php/public/api.php`

```php
<?php
require_once __DIR__ . '/../vendor/autoload.php';

use TunnelWatch\Tunnel;

header('Content-Type: application/json');

try {
    $tunnelModel = new Tunnel();
    $tunnels = $tunnelModel->getAllActive();
    
    echo json_encode([
        'success' => true,
        'data' => $tunnels,
        'updated_at' => date('c')
    ]);
} catch (Exception $e) {
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'error' => $e->getMessage()
    ]);
}
```

### `php/public/assets/css/style.css`

```css
.status-open-bar { background-color: #10b981; }
.status-closed-bar { background-color: #ef4444; }
.status-restricted-bar { background-color: #f59e0b; }
.status-unknown-bar { background-color: #6b7280; }

.badge {
    display: inline-block;
    padding: 0.25rem 0.75rem;
    border-radius: 9999px;
    font-size: 0.875rem;
    font-weight: 500;
}

.badge-green { background-color: #d1fae5; color: #065f46; }
.badge-red { background-color: #fee2e2; color: #991b1b; }
.badge-yellow { background-color: #fef3c7; color: #92400e; }
.badge-gray { background-color: #f3f4f6; color: #374151; }
```

### `php/public/assets/js/app.js`

```javascript
(function() {
    'use strict';
    
    const REFRESH_INTERVAL = 60000; // 60 seconds
    
    async function refreshData() {
        try {
            const response = await fetch('/api.php');
            if (response.ok) {
                // Reload page to show updated data
                window.location.reload();
            }
        } catch (error) {
            console.error('Error refreshing:', error);
        }
    }
    
    // Auto-refresh every minute
    setInterval(refreshData, REFRESH_INTERVAL);
    
    console.log('Auto-refresh enabled: every', REFRESH_INTERVAL / 1000, 'seconds');
})();
```

---

## Next Steps

This is **PART 1** of the complete guide.

**Continue to PART 2** (`tunnelwatch-workers-deployment.md`) for:
- Complete Python workers
- All shell scripts
- Deployment instructions
- Signal setup
- Cloudflare tunnel
- Testing procedures

**Or you can deploy now** and add workers later - the website will work even without the monitoring workers running.