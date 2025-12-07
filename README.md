# TunnelWatch Norway 🚇

Real-time Norwegian tunnel status monitoring with Signal notifications.

## Quick Start

```bash
# 1. Configure environment
cp .env.example .env
# Edit .env with your settings (especially SIGNAL_NUMBER)

# 2. Start services
make up

# 3. Visit the website
open http://localhost
```

## Features

- ✅ Real-time tunnel status from Vegvesen API
- ✅ Signal notifications on status changes
- ✅ Multi-language support (Norwegian/English)
- ✅ Clean, responsive web interface
- ✅ Docker-based deployment

## Architecture

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Nginx     │────▶│   PHP-FPM   │────▶│ PostgreSQL  │
│   :80       │     │             │     │             │
└─────────────┘     └─────────────┘     └─────────────┘
                                               ▲
                    ┌─────────────┐             │
                    │   Celery    │─────────────┘
                    │   Worker    │
                    └─────────────┘
                           │
                    ┌──────▼──────┐     ┌─────────────┐
                    │  Vegvesen   │     │  Signal CLI │
                    │    API      │     │    API      │
                    └─────────────┘     └─────────────┘
```

## Commands

```bash
make up           # Start all services
make down         # Stop all services
make logs         # View logs
make status       # Check service health
make backup       # Backup database
make shell-db     # Open database shell
make check-tunnels # Manually trigger tunnel check
```

## Signal Setup (External Service)

TunnelWatch uses an external Signal service for notifications. This allows multiple apps to share one Signal registration.

### 1. Set up Signal Service (one-time)

```bash
# Clone and start the signal service
cd ~/signal-service
docker compose up -d
./register.sh +47XXXXXXXX
```

See: [signal-service](https://github.com/EllySync/signal-service)

### 2. Configure TunnelWatch

In your `.env`:
```
SIGNAL_NUMBER=+47XXXXXXXX
SIGNAL_API_URL=http://localhost:8080
```

### 3. Add subscription

```bash
./scripts/add-subscription.sh +4712345678 mastrafjord
```

## API Endpoints

| Endpoint | Description |
|----------|-------------|
| `/` | Web interface |
| `/api.php` | JSON API for tunnel status |
| `/health.php` | Health check endpoint |

## Data Source

Tunnel data is fetched from Vegvesen's open API:
- **Endpoint:** `https://fjelloverganger-backend.atlas.vegvesen.no/v1/tunneler`
- **No authentication required**
- **Real-time updates**

## License

Data: Norsk lisens for offentlige data (NLOD) - Statens vegvesen
