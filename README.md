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

## Signal Setup

```bash
# 1. Register your Signal number
./scripts/register-signal.sh

# 2. Add a subscription
./scripts/add-subscription.sh +4712345678 mastrafjord

# 3. Test notification
make test-notify
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
