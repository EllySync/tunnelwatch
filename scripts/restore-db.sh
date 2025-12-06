#!/bin/bash
# ===========================================
# TunnelWatch Norway - Database Restore
# ===========================================

set -e

BACKUP_FILE=$1
BACKUP_DIR="${NAS_BACKUP_PATH:-./backups}"

if [ -z "$BACKUP_FILE" ]; then
    echo "Usage: ./restore-db.sh <backup_file.sql.gz>"
    echo ""
    echo "Available backups:"
    ls -lh "${BACKUP_DIR}"/tunnelwatch_backup_*.sql.gz 2>/dev/null || echo "  No backups found in ${BACKUP_DIR}"
    exit 1
fi

# Check if file exists (try both as-is and in backup dir)
if [ -f "$BACKUP_FILE" ]; then
    FULL_PATH="$BACKUP_FILE"
elif [ -f "${BACKUP_DIR}/${BACKUP_FILE}" ]; then
    FULL_PATH="${BACKUP_DIR}/${BACKUP_FILE}"
else
    echo "✗ Error: Backup file not found: $BACKUP_FILE"
    exit 1
fi

echo "==================================="
echo "TunnelWatch Database Restore"
echo "==================================="
echo ""
echo "⚠️  WARNING: This will REPLACE the current database!"
echo ""
echo "Backup file: $FULL_PATH"
echo ""
read -p "Are you absolutely sure? Type 'yes' to continue: " confirmation

if [ "$confirmation" != "yes" ]; then
    echo "Restore cancelled"
    exit 0
fi

echo ""
echo "Stopping services that use the database..."
docker compose stop nginx php worker beat

echo "Waiting for connections to close..."
sleep 3

echo "Restoring database..."
gunzip < "${FULL_PATH}" | docker compose exec -T postgres \
    psql -U tunnelwatch -d tunnelwatch

if [ $? -eq 0 ]; then
    echo ""
    echo "✓ Database restored successfully!"
    echo ""
    echo "Restarting all services..."
    docker compose up -d
    
    echo ""
    echo "✓ All services restarted"
    echo ""
    echo "Verify restoration with:"
    echo "  docker compose exec postgres psql -U tunnelwatch -d tunnelwatch -c 'SELECT COUNT(*) FROM tunnels;'"
    
    exit 0
else
    echo ""
    echo "✗ Database restore failed!"
    echo "Restarting services anyway..."
    docker compose up -d
    exit 1
fi
