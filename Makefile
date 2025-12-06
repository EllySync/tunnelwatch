.PHONY: help up down restart logs build backup clean test

# Default target
help:
	@echo "TunnelWatch Norway - Available Commands"
	@echo "========================================"
	@echo ""
	@echo "  make up        Start all services"
	@echo "  make down      Stop all services"
	@echo "  make restart   Restart all services"
	@echo "  make logs      View logs (follow mode)"
	@echo "  make build     Rebuild all containers"
	@echo "  make backup    Backup database"
	@echo "  make clean     Remove volumes and rebuild"
	@echo "  make status    Show container status"
	@echo "  make shell-db  Open PostgreSQL shell"
	@echo "  make shell-php Open PHP container shell"
	@echo ""

# Start services
up:
	docker compose up -d
	@echo ""
	@echo "✓ Services started"
	@echo "  Website: http://localhost"
	@echo "  API: http://localhost/api.php"
	@echo "  Health: http://localhost/health.php"

# Stop services
down:
	docker compose down

# Restart services
restart:
	docker compose restart

# View logs
logs:
	docker compose logs -f

# View specific service logs
logs-worker:
	docker compose logs -f worker beat

logs-web:
	docker compose logs -f nginx php

# Build containers
build:
	docker compose build --no-cache

# Backup database
backup:
	./scripts/backup-db.sh

# Show status
status:
	@docker compose ps
	@echo ""
	@echo "Health check:"
	@curl -s http://localhost/health.php | python3 -m json.tool 2>/dev/null || echo "Service not responding"

# Open database shell
shell-db:
	docker compose exec postgres psql -U tunnelwatch -d tunnelwatch

# Open PHP shell
shell-php:
	docker compose exec php sh

# Open worker shell
shell-worker:
	docker compose exec worker sh

# Clean everything and rebuild
clean:
	docker compose down -v
	docker compose build --no-cache
	docker compose up -d

# Run a manual tunnel check
check-tunnels:
	docker compose exec worker celery -A celery_app call tasks.monitor.check_all_tunnels

# Send test notification
test-notify:
	@read -p "Enter tunnel ID (e.g., mastrafjord): " tid; \
	docker compose exec worker celery -A celery_app call tasks.notifications.send_test_notification --args="[\"$$tid\"]"
