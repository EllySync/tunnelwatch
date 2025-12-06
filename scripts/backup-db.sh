#!/bin/bash
# ===========================================
# TunnelWatch Norway - Database Backup
# ===========================================

set -e

# Configuration
BACKUP_DIR="${NAS_BACKUP_PATH:-./backups}"
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="tunnelwatch_backup_${TIMESTAMP}.sql.gz"

echo "==================================="
echo "TunnelWatch Database Backup"
echo "==================================="
echo ""
echo "Backup directory: ${BACKUP_DIR}"
echo "Retention: ${RETENTION_DAYS} days"
echo ""

# Create backup directory if it doesn't exist
mkdir -p "${BACKUP_DIR}"

# Check if PostgreSQL container is running
if ! docker compose ps postgres | grep -q "Up"; then
    echo "✗ PostgreSQL container is not running!"
    exit 1
fi

echo "Starting backup..."

# Perform backup
docker compose exec -T postgres pg_dump \
    -U tunnelwatch \
    -d tunnelwatch \
    --clean \
    --if-exists \
    | gzip > "${BACKUP_DIR}/${BACKUP_FILE}"

# Check if backup was successful
if [ $? -eq 0 ] && [ -f "${BACKUP_DIR}/${BACKUP_FILE}" ]; then
    BACKUP_SIZE=$(du -h "${BACKUP_DIR}/${BACKUP_FILE}" | cut -f1)
    echo ""
    echo "✓ Backup successful!"
    echo "  File: ${BACKUP_FILE}"
    echo "  Size: ${BACKUP_SIZE}"
    echo ""
    
    # Delete old backups
    echo "Cleaning up old backups (older than ${RETENTION_DAYS} days)..."
    DELETED=$(find "${BACKUP_DIR}" -name "tunnelwatch_backup_*.sql.gz" -mtime +${RETENTION_DAYS} -delete -print 2>/dev/null | wc -l)
    echo "  Deleted: ${DELETED} old backup(s)"
    
    # Count remaining backups
    BACKUP_COUNT=$(find "${BACKUP_DIR}" -name "tunnelwatch_backup_*.sql.gz" 2>/dev/null | wc -l)
    echo "  Total backups: ${BACKUP_COUNT}"
    echo ""
    echo "✓ Backup complete!"
    
    exit 0
else
    echo ""
    echo "✗ Backup failed!"
    exit 1
fi
