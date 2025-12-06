# TunnelWatch Norway - Complete Deployment Guide (PART 2)

**Workers, Scripts, Deployment & Operations**

This is Part 2 of the complete guide. Part 1 contains configuration, Docker, database, and PHP code.

---

## 📚 Contents

- [Python Workers (Complete)](#python-workers)
- [All Scripts](#all-scripts)
- [Deployment Steps](#deployment-steps)
- [Signal Setup](#signal-setup)
- [Cloudflare Tunnel](#cloudflare-tunnel-setup)
- [NAS Backup Setup](#nas-backup-setup)
- [Testing & Verification](#testing--verification)
- [Troubleshooting](#troubleshooting)
- [Operations & Maintenance](#operations--maintenance)

---

## Python Workers

All Python code for background monitoring and notifications.

### `workers/celery_app.py`

```python
from celery import Celery
from celery.schedules import crontab
import os

REDIS_URL = os.getenv('REDIS_URL', 'redis://redis:6379/0')

app = Celery('tunnelwatch', broker=REDIS_URL, backend=REDIS_URL)

app.conf.update(
    task_serializer='json',
    accept_content=['json'],
    result_serializer='json',
    timezone='Europe/Oslo',
    enable_utc=True,
    broker_connection_retry_on_startup=True,
)

# Task schedule
app.conf.beat_schedule = {
    'monitor-tunnels-every-minute': {
        'task': 'tasks.monitor.check_all_tunnels',
        'schedule': 60.0,  # Every 60 seconds
    },
    'sync-tunnels-from-nvdb-daily': {
        'task': 'tasks.nvdb_sync.sync_all_tunnels',
        'schedule': crontab(hour=int(os.getenv('NVDB_SYNC_HOUR', 3)), minute=0),
    },
}

app.autodiscover_tasks(['tasks'])
```

### `workers/tasks/__init__.py`

```python
# Empty file to make tasks a package
```

### `workers/tasks/monitor.py`

```python
from celery import shared_task
import psycopg2
import os
import asyncio
from services.traffic_service import TrafficService
from services.signal_service import SignalService
from datetime import datetime
from typing import List, Dict

DATABASE_URL = os.getenv('DATABASE_URL')

def get_db_connection():
    """Get PostgreSQL database connection"""
    return psycopg2.connect(DATABASE_URL)

@shared_task
def check_all_tunnels():
    """Main monitoring task - checks all active tunnels"""
    conn = get_db_connection()
    cur = conn.cursor()
    
    try:
        # Get all active tunnels
        cur.execute("""
            SELECT id, name, latitude, longitude
            FROM tunnels
            WHERE active = true
        """)
        
        tunnels = cur.fetchall()
        
        print(f"Checking {len(tunnels)} tunnels...")
        
        for tunnel in tunnels:
            tunnel_id, name, lat, lon = tunnel
            asyncio.run(check_tunnel_status(tunnel_id, name, float(lat), float(lon)))
            
        print(f"✓ Checked {len(tunnels)} tunnels")
            
    except Exception as e:
        print(f"Error in check_all_tunnels: {e}")
    finally:
        cur.close()
        conn.close()

async def check_tunnel_status(tunnel_id: str, name: str, lat: float, lon: float):
    """Check status of a single tunnel"""
    conn = get_db_connection()
    cur = conn.cursor()
    
    try:
        # Get incidents near tunnel
        traffic_service = TrafficService()
        incidents = await traffic_service.get_incidents_near_location(lat, lon, radius_km=1.0)
        
        # Determine status based on incidents
        status = determine_status(incidents)
        
        # Get last known status
        cur.execute("""
            SELECT status
            FROM status_updates
            WHERE tunnel_id = %s
            ORDER BY created_at DESC
            LIMIT 1
        """, (tunnel_id,))
        
        last_status = cur.fetchone()
        last_status_value = last_status[0] if last_status else None
        
        # If status changed, update database and notify
        if last_status_value != status['status']:
            print(f"Status change for {name}: {last_status_value} → {status['status']}")
            
            # Save new status
            cur.execute("""
                INSERT INTO status_updates 
                (tunnel_id, status, incident_type, message, severity, expected_reopen)
                VALUES (%s, %s, %s, %s, %s, %s)
            """, (
                tunnel_id,
                status['status'],
                status.get('incident_type'),
                status.get('message'),
                status.get('severity'),
                status.get('expected_reopen')
            ))
            conn.commit()
            
            # Notify subscribers
            await notify_subscribers(tunnel_id, name, status)
        else:
            print(f"No change for {name}: {status['status']}")
            
    except Exception as e:
        print(f"Error checking tunnel {tunnel_id}: {e}")
    finally:
        cur.close()
        conn.close()

def determine_status(incidents: List[Dict]) -> Dict:
    """Determine tunnel status based on incidents"""
    if not incidents:
        return {
            'status': 'open',
            'message': 'Tunnelen er åpen for normal trafikk',
            'severity': 'low'
        }
    
    # Check for closures
    for incident in incidents:
        desc = incident.get('description', '').lower()
        
        # Keywords indicating closure
        closure_keywords = ['stengt', 'closed', 'lukket', 'sperret', 'blokkert']
        if any(word in desc for word in closure_keywords):
            return {
                'status': 'closed',
                'incident_type': incident.get('type', 'closure'),
                'message': incident.get('description', 'Tunnelen er stengt'),
                'severity': 'high',
                'expected_reopen': incident.get('expected_end')
            }
    
    # If not closed, but has incidents, mark as restricted
    return {
        'status': 'restricted',
        'incident_type': incidents[0].get('type', 'incident'),
        'message': incidents[0].get('description', 'Trafikkmelding i området'),
        'severity': 'medium'
    }

async def notify_subscribers(tunnel_id: str, tunnel_name: str, status: Dict):
    """Send Signal notifications to subscribers"""
    conn = get_db_connection()
    cur = conn.cursor()
    
    try:
        # Get active subscribers for this tunnel
        cur.execute("""
            SELECT phone_number
            FROM subscriptions
            WHERE tunnel_id = %s AND active = true
        """, (tunnel_id,))
        
        subscribers = cur.fetchall()
        
        if not subscribers:
            print(f"No subscribers for {tunnel_name}")
            return
        
        phone_numbers = [sub[0] for sub in subscribers]
        
        print(f"Notifying {len(phone_numbers)} subscribers about {tunnel_name}")
        
        # Send notification via Signal
        signal_service = SignalService()
        success = await signal_service.send_tunnel_alert(
            recipients=phone_numbers,
            tunnel_name=tunnel_name,
            status=status['status'],
            message=status.get('message', ''),
            expected_reopen=status.get('expected_reopen')
        )
        
        if success:
            print(f"✓ Notification sent to {len(phone_numbers)} subscribers")
        else:
            print(f"✗ Failed to send notification")
            
    except Exception as e:
        print(f"Error notifying subscribers: {e}")
    finally:
        cur.close()
        conn.close()
```

### `workers/tasks/nvdb_sync.py`

```python
from celery import shared_task
import psycopg2
import psycopg2.extras
import os
import asyncio
from services.nvdb_service import NVDBService

DATABASE_URL = os.getenv('DATABASE_URL')

def get_db_connection():
    return psycopg2.connect(DATABASE_URL)

@shared_task
def sync_all_tunnels():
    """Sync tunnel metadata from NVDB API (runs daily)"""
    conn = get_db_connection()
    cur = conn.cursor()
    
    try:
        # Get all active tunnels
        cur.execute("""
            SELECT id, vegvesen_id, name
            FROM tunnels
            WHERE active = true
        """)
        
        tunnels = cur.fetchall()
        
        print(f"Syncing metadata for {len(tunnels)} tunnels from NVDB...")
        
        for tunnel in tunnels:
            tunnel_id, vegvesen_id, name = tunnel
            asyncio.run(update_tunnel_metadata(tunnel_id, vegvesen_id))
            
        print(f"✓ Synced {len(tunnels)} tunnels")
        
    except Exception as e:
        print(f"Error in sync_all_tunnels: {e}")
    finally:
        cur.close()
        conn.close()

async def update_tunnel_metadata(tunnel_id: str, vegvesen_id: str):
    """Update metadata for a single tunnel from NVDB"""
    nvdb_service = NVDBService()
    tunnel_data = await nvdb_service.get_tunnel_by_vegvesen_id(vegvesen_id)
    
    if not tunnel_data:
        print(f"Could not fetch NVDB data for tunnel {tunnel_id} (vegvesen_id: {vegvesen_id})")
        return
    
    conn = get_db_connection()
    cur = conn.cursor()
    
    try:
        cur.execute("""
            UPDATE tunnels
            SET 
                name = %s,
                latitude = %s,
                longitude = %s,
                length = %s,
                height_limit = %s,
                metadata = %s,
                updated_at = CURRENT_TIMESTAMP
            WHERE id = %s
        """, (
            tunnel_data['name'],
            tunnel_data['latitude'],
            tunnel_data['longitude'],
            tunnel_data['length'],
            tunnel_data['height_limit'],
            psycopg2.extras.Json(tunnel_data.get('metadata', {})),
            tunnel_id
        ))
        
        conn.commit()
        print(f"✓ Updated metadata for: {tunnel_data['name']}")
        
    except Exception as e:
        print(f"Error updating tunnel {tunnel_id}: {e}")
    finally:
        cur.close()
        conn.close()
```

### `workers/tasks/notifications.py`

```python
from celery import shared_task
import psycopg2
import os
import asyncio
from services.signal_service import SignalService

DATABASE_URL = os.getenv('DATABASE_URL')

def get_db_connection():
    return psycopg2.connect(DATABASE_URL)

@shared_task
def send_test_notification(tunnel_id: str):
    """Send a test notification for a tunnel"""
    asyncio.run(send_test_notification_async(tunnel_id))

async def send_test_notification_async(tunnel_id: str):
    """Async version of test notification"""
    conn = get_db_connection()
    cur = conn.cursor()
    
    try:
        # Get tunnel and subscribers
        cur.execute("""
            SELECT t.name, s.phone_number
            FROM tunnels t
            JOIN subscriptions s ON t.id = s.tunnel_id
            WHERE t.id = %s AND s.active = true
        """, (tunnel_id,))
        
        results = cur.fetchall()
        
        if not results:
            print(f"No subscribers for tunnel {tunnel_id}")
            return
        
        tunnel_name = results[0][0]
        phone_numbers = [row[1] for row in results]
        
        print(f"Sending test notification to {len(phone_numbers)} subscribers")
        
        signal_service = SignalService()
        success = await signal_service.send_tunnel_alert(
            recipients=phone_numbers,
            tunnel_name=tunnel_name,
            status='open',
            message='Dette er en test-melding fra TunnelWatch. Tjenesten fungerer! 🚇'
        )
        
        if success:
            print(f"✓ Test notification sent successfully")
        else:
            print(f"✗ Failed to send test notification")
            
    except Exception as e:
        print(f"Error sending test notification: {e}")
    finally:
        cur.close()
        conn.close()
```

### `workers/services/__init__.py`

```python
# Empty file to make services a package
```

### `workers/services/nvdb_service.py`

```python
import httpx
from typing import List, Dict, Optional

class NVDBService:
    """Service for interacting with Vegvesen NVDB API"""
    
    BASE_URL = "https://nvdbapiles-v3.atlas.vegvesen.no"
    TUNNEL_OBJECT_TYPE = 581  # NVDB object type ID for tunnels
    
    async def get_tunnel_by_vegvesen_id(self, vegvesen_id: str) -> Optional[Dict]:
        """Fetch tunnel details from NVDB API by Vegvesen ID"""
        async with httpx.AsyncClient() as client:
            try:
                response = await client.get(
                    f"{self.BASE_URL}/vegobjekter/{self.TUNNEL_OBJECT_TYPE}/{vegvesen_id}",
                    headers={
                        "Accept": "application/json",
                        "X-Client": "TunnelWatch-Norway"
                    },
                    timeout=30.0
                )
                
                if response.status_code == 200:
                    return self._parse_tunnel_data(response.json())
                else:
                    print(f"NVDB API returned {response.status_code} for tunnel {vegvesen_id}")
                    return None
                    
            except Exception as e:
                print(f"Error fetching tunnel from NVDB: {e}")
                return None
    
    async def search_tunnel_by_name(self, name: str) -> Optional[Dict]:
        """Search for a tunnel by name"""
        async with httpx.AsyncClient() as client:
            try:
                # Property 5225 is "Navn" (Name) in NVDB
                response = await client.get(
                    f"{self.BASE_URL}/vegobjekter/{self.TUNNEL_OBJECT_TYPE}",
                    params={
                        "egenskap": f"5225={name}",
                        "inkluder": "egenskaper,geometri"
                    },
                    headers={
                        "Accept": "application/json",
                        "X-Client": "TunnelWatch-Norway"
                    },
                    timeout=30.0
                )
                
                if response.status_code == 200:
                    data = response.json()
                    objekter = data.get('objekter', [])
                    if objekter:
                        return self._parse_tunnel_data(objekter[0])
                        
            except Exception as e:
                print(f"Error searching tunnel: {e}")
        
        return None
    
    def _parse_tunnel_data(self, nvdb_data: Dict) -> Dict:
        """Parse NVDB API response into our format"""
        properties = {}
        
        # Extract properties
        for prop in nvdb_data.get('egenskaper', []):
            prop_id = prop.get('id')
            
            # 5225 = Name
            if prop_id == 5225:
                properties['name'] = prop.get('verdi')
            # 5277 = Length
            elif prop_id == 5277:
                properties['length'] = int(prop.get('verdi', 0))
            # 5333 = Height limit
            elif prop_id == 5333:
                properties['height_limit'] = float(prop.get('verdi', 0))
        
        # Extract geometry (coordinates)
        geometry = nvdb_data.get('geometri', {})
        if geometry and 'wkt' in geometry:
            # Parse WKT to get coordinates
            # Simple parsing for POINT geometry
            wkt = geometry['wkt']
            if 'POINT' in wkt:
                # Extract coordinates from "POINT Z (lon lat elev)"
                coords_str = wkt.replace('POINT Z (', '').replace('POINT (', '').replace(')', '')
                coords = coords_str.split()
                if len(coords) >= 2:
                    properties['longitude'] = float(coords[0])
                    properties['latitude'] = float(coords[1])
        
        return {
            'vegvesen_id': str(nvdb_data.get('id')),
            'name': properties.get('name', 'Unknown'),
            'latitude': properties.get('latitude', 0.0),
            'longitude': properties.get('longitude', 0.0),
            'length': properties.get('length'),
            'height_limit': properties.get('height_limit'),
            'metadata': nvdb_data
        }
```

### `workers/services/traffic_service.py`

```python
import httpx
from typing import List, Dict
from math import radians, cos, sin, asin, sqrt

class TrafficService:
    """Service for fetching traffic incidents from Vegvesen"""
    
    async def get_incidents(self) -> List[Dict]:
        """
        Fetch current traffic incidents
        
        NOTE: This is a placeholder implementation.
        You may need to:
        1. Register for DATEX II API access at vegvesen.no
        2. Replace this URL with the actual endpoint
        3. Add authentication if required
        """
        
        async with httpx.AsyncClient() as client:
            try:
                # PLACEHOLDER - Replace with actual endpoint
                # Possible endpoints to try:
                # - https://www.vegvesen.no/ws/no/vegvesen/trafikk/trafikkmeldinger/json
                # - Check https://www.vegvesen.no/fag/teknologi/apne-data/
                
                response = await client.get(
                    "https://www.vegvesen.no/trafikk/api/incidents",  # Placeholder
                    headers={
                        "Accept": "application/json",
                        "User-Agent": "TunnelWatch-Norway/1.0"
                    },
                    timeout=30.0
                )
                
                if response.status_code == 200:
                    data = response.json()
                    return data.get('incidents', [])
                else:
                    print(f"Traffic API returned {response.status_code}")
                    
            except Exception as e:
                print(f"Error fetching incidents: {e}")
        
        # Return empty list if API fails
        # This means tunnels will show as "open" by default
        return []
    
    async def get_incidents_near_location(
        self,
        latitude: float,
        longitude: float,
        radius_km: float = 1.0
    ) -> List[Dict]:
        """Get incidents near a specific location"""
        all_incidents = await self.get_incidents()
        nearby = []
        
        for incident in all_incidents:
            inc_lat = incident.get('latitude')
            inc_lon = incident.get('longitude')
            
            if inc_lat and inc_lon:
                distance = self.haversine(longitude, latitude, inc_lon, inc_lat)
                if distance <= radius_km:
                    incident['distance_km'] = round(distance, 2)
                    nearby.append(incident)
        
        return sorted(nearby, key=lambda x: x.get('distance_km', 999))
    
    @staticmethod
    def haversine(lon1: float, lat1: float, lon2: float, lat2: float) -> float:
        """
        Calculate the great circle distance between two points 
        on the earth (specified in decimal degrees)
        Returns distance in kilometers
        """
        # Convert decimal degrees to radians
        lon1, lat1, lon2, lat2 = map(radians, [lon1, lat1, lon2, lat2])
        
        # Haversine formula
        dlon = lon2 - lon1
        dlat = lat2 - lat1
        a = sin(dlat/2)**2 + cos(lat1) * cos(lat2) * sin(dlon/2)**2
        c = 2 * asin(sqrt(a))
        
        # Radius of earth in kilometers
        km = 6371 * c
        return km
```

### `workers/services/signal_service.py`

```python
import httpx
import os
from typing import List
from datetime import datetime

class SignalService:
    """Service for sending notifications via Signal"""
    
    def __init__(self):
        self.api_url = os.getenv('SIGNAL_API_URL', 'http://signal-api:8080')
        self.sender_number = os.getenv('SIGNAL_NUMBER')
    
    async def send_message(self, recipients: List[str], message: str) -> bool:
        """Send a Signal message to one or more recipients"""
        async with httpx.AsyncClient() as client:
            try:
                response = await client.post(
                    f"{self.api_url}/v2/send",
                    json={
                        "message": message,
                        "number": self.sender_number,
                        "recipients": recipients
                    },
                    timeout=30.0
                )
                
                if response.status_code == 201:
                    return True
                else:
                    print(f"Signal API returned {response.status_code}: {response.text}")
                    return False
                    
            except Exception as e:
                print(f"Error sending Signal message: {e}")
                return False
    
    async def send_tunnel_alert(
        self,
        recipients: List[str],
        tunnel_name: str,
        status: str,
        message: str,
        expected_reopen: datetime = None
    ) -> bool:
        """Send a formatted tunnel alert notification"""
        formatted_message = self.format_alert(
            tunnel_name, 
            status, 
            message, 
            expected_reopen
        )
        
        return await self.send_message(recipients, formatted_message)
    
    def format_alert(
        self,
        tunnel_name: str,
        status: str,
        message: str,
        expected_reopen: datetime = None
    ) -> str:
        """Format a tunnel status alert message"""
        # Status emoji mapping
        emoji = {
            'open': '✅',
            'closed': '🚫',
            'restricted': '⚠️',
            'unknown': '❓'
        }.get(status.lower(), '📍')
        
        # Build message
        msg = f"{emoji} *{tunnel_name}*\n\n"
        msg += f"Status: {status.upper()}\n"
        msg += f"Info: {message}\n"
        
        # Add expected reopening time if available
        if expected_reopen:
            if isinstance(expected_reopen, str):
                reopen_str = expected_reopen
            else:
                reopen_str = expected_reopen.strftime('%d.%m.%Y kl. %H:%M')
            msg += f"\n⏰ Forventet åpning: {reopen_str}"
        
        # Add timestamp
        now = datetime.now().strftime('%H:%M')
        msg += f"\n\n_TunnelWatch - {now}_"
        
        return msg
```

---

## All Scripts

Create these in the `scripts/` directory and make them executable.

### `scripts/backup-db.sh`

```bash
#!/bin/bash
set -e

# Configuration
BACKUP_DIR="${NAS_BACKUP_PATH:-/mnt/nas/tunnelwatch-backups}"
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
if [ $? -eq 0 ]; then
    BACKUP_SIZE=$(du -h "${BACKUP_DIR}/${BACKUP_FILE}" | cut -f1)
    echo ""
    echo "✓ Backup successful!"
    echo "  File: ${BACKUP_FILE}"
    echo "  Size: ${BACKUP_SIZE}"
    echo ""
    
    # Delete old backups
    echo "Cleaning up old backups (older than ${RETENTION_DAYS} days)..."
    DELETED=$(find "${BACKUP_DIR}" -name "tunnelwatch_backup_*.sql.gz" -mtime +${RETENTION_DAYS} -delete -print | wc -l)
    echo "  Deleted: ${DELETED} old backup(s)"
    
    # Count remaining backups
    BACKUP_COUNT=$(find "${BACKUP_DIR}" -name "tunnelwatch_backup_*.sql.gz" | wc -l)
    echo "  Total backups: ${BACKUP_COUNT}"
    echo ""
    echo "✓ Backup complete!"
    
    exit 0
else
    echo ""
    echo "✗ Backup failed!"
    exit 1
fi
```

### `scripts/restore-db.sh`

```bash
#!/bin/bash
set -e

BACKUP_FILE=$1

if [ -z "$BACKUP_FILE" ]; then
    echo "Usage: ./restore-db.sh <backup_file.sql.gz>"
    echo ""
    echo "Available backups:"
    ls -lh /mnt/nas/tunnelwatch-backups/tunnelwatch_backup_*.sql.gz 2>/dev/null || echo "  No backups found"
    exit 1
fi

if [ ! -f "$BACKUP_FILE" ]; then
    echo "✗ Error: Backup file not found: $BACKUP_FILE"
    exit 1
fi

echo "==================================="
echo "TunnelWatch Database Restore"
echo "==================================="
echo ""
echo "⚠️  WARNING: This will REPLACE the current database!"
echo ""
echo "Backup file: $BACKUP_FILE"
echo ""
read -p "Are you absolutely sure? Type 'yes' to continue: " confirmation

if [ "$confirmation" != "yes" ]; then
    echo "Restore cancelled"
    exit 0
fi

echo ""
echo "Stopping all services except PostgreSQL..."
docker compose stop nginx php worker beat signal-api

echo "Waiting for connections to close..."
sleep 3

echo "Restoring database..."
gunzip < "${BACKUP_FILE}" | docker compose exec -T postgres \
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
```

### `scripts/register-signal.sh`

```bash
#!/bin/bash
set -e

SIGNAL_NUMBER="${SIGNAL_NUMBER:-+47XXXXXXXXX}"

echo "==================================="
echo "Signal CLI Registration"
echo "==================================="
echo ""
echo "This script will register your Signal number with the Signal CLI."
echo ""
echo "Phone number: ${SIGNAL_NUMBER}"
echo ""

# Check if Signal API container is running
if ! docker compose ps signal-api | grep -q "Up"; then
    echo "Starting Signal API container..."
    docker compose up -d signal-api
    echo "Waiting for container to be ready..."
    sleep 5
fi

echo ""
echo "Step 1: Requesting verification code"
echo "--------------------------------------"
echo "You will receive an SMS with a 6-digit code..."
echo ""

# Request verification code
docker compose exec signal-api curl -s -X POST \
  "http://localhost:8080/v1/register/${SIGNAL_NUMBER}"

echo ""
echo ""
read -p "Enter the 6-digit verification code from SMS: " VERIFICATION_CODE

if [ -z "$VERIFICATION_CODE" ]; then
    echo "✗ No code entered. Exiting."
    exit 1
fi

echo ""
echo "Step 2: Verifying code"
echo "----------------------"

# Verify the code
RESPONSE=$(docker compose exec signal-api curl -s -X POST \
  "http://localhost:8080/v1/register/${SIGNAL_NUMBER}/verify/${VERIFICATION_CODE}")

if echo "$RESPONSE" | grep -q "error"; then
    echo ""
    echo "✗ Verification failed!"
    echo "Response: $RESPONSE"
    exit 1
fi

echo ""
echo "✓ Signal CLI registered successfully!"
echo ""
echo "Step 3: Testing"
echo "---------------"
echo "Sending a test message to yourself..."

docker compose exec signal-api curl -s -X POST \
  "http://localhost:8080/v2/send" \
  -H "Content-Type: application/json" \
  -d "{
    \"message\": \"✅ TunnelWatch Signal bot is ready! 🚇\",
    \"number\": \"${SIGNAL_NUMBER}\",
    \"recipients\": [\"${SIGNAL_NUMBER}\"]
  }"

echo ""
echo ""
echo "==================================="
echo "Registration Complete!"
echo "==================================="
echo ""
echo "Check your Signal app - you should have received a test message!"
echo ""
echo "Next steps:"
echo "1. Add test subscription: ./scripts/add-subscription.sh +47YOURNUMBER mastrafjord"
echo "2. Test notification: docker compose exec worker celery -A celery_app call tasks.notifications.send_test_notification --args='[\"mastrafjord\"]'"
echo ""
```

### `scripts/add-subscription.sh`

```bash
#!/bin/bash
set -e

PHONE_NUMBER=$1
TUNNEL_ID=$2

if [ -z "$PHONE_NUMBER" ] || [ -z "$TUNNEL_ID" ]; then
    echo "Usage: ./add-subscription.sh <phone_number> <tunnel_id>"
    echo ""
    echo "Examples:"
    echo "  ./add-subscription.sh +4798765432 mastrafjord"
    echo "  ./add-subscription.sh +4798765432 byfjord"
    echo ""
    echo "Available tunnels:"
    docker compose exec postgres psql -U tunnelwatch -d tunnelwatch -t -c "SELECT id, name FROM tunnels WHERE active = true;"
    exit 1
fi

echo "==================================="
echo "Add Subscription"
echo "==================================="
echo ""
echo "Phone: $PHONE_NUMBER"
echo "Tunnel: $TUNNEL_ID"
echo ""

# Add subscription
docker compose exec postgres psql -U tunnelwatch -d tunnelwatch -c "
  INSERT INTO subscriptions (phone_number, tunnel_id, notification_methods, active)
  VALUES ('${PHONE_NUMBER}', '${TUNNEL_ID}', '[\"signal\"]', true)
  ON CONFLICT (phone_number, tunnel_id) 
  DO UPDATE SET active = true, updated_at = CURRENT_TIMESTAMP;
"

if [ $? -eq 0 ]; then
    echo ""
    echo "✓ Subscription added successfully!"
    echo ""
    echo "Verify with:"
    echo "  docker compose exec postgres psql -U tunnelwatch -d tunnelwatch -c \"SELECT * FROM subscriptions WHERE phone_number = '${PHONE_NUMBER}';\""
    echo ""
    echo "Send test notification:"
    echo "  docker compose exec worker celery -A celery_app call tasks.notifications.send_test_notification --args='[\"${TUNNEL_ID}\"]'"
    echo ""
else
    echo ""
    echo "✗ Failed to add subscription"
    exit 1
fi
```

### `scripts/find-tunnel-id.sh`

```bash
#!/bin/bash

TUNNEL_NAME=$1

if [ -z "$TUNNEL_NAME" ]; then
    echo "Usage: ./find-tunnel-id.sh <tunnel_name>"
    echo ""
    echo "Examples:"
    echo "  ./find-tunnel-id.sh Byfjordtunnelen"
    echo "  ./find-tunnel-id.sh Mastrafjordtunnelen"
    echo "  ./find-tunnel-id.sh Ryfast"
    echo ""
    exit 1
fi

echo "==================================="
echo "Search NVDB for Tunnel"
echo "==================================="
echo ""
echo "Searching for: $TUNNEL_NAME"
echo ""

# Search NVDB API for tunnel
# Object type 581 = Tunnel
# Property 5225 = Name
curl -s "https://nvdbapiles-v3.atlas.vegvesen.no/vegobjekter/581?egenskap=5225=${TUNNEL_NAME}" \
  -H "Accept: application/json" \
  -H "X-Client: TunnelWatch-Norway" \
  | jq '.objekter[] | {
      id: .id,
      navn: (.egenskaper[] | select(.id == 5225) | .verdi),
      lengde: (.egenskaper[] | select(.id == 5277) | .verdi)
    }'

echo ""
echo "Use the 'id' value as VEGVESEN_ID in seed-tunnels.sql"
echo ""
```

### Make Scripts Executable

```bash
chmod +x scripts/*.sh
```

---

## Deployment Steps

Complete step-by-step deployment process.

### 1. Initial Server Setup

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install Docker (if not done)
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER
newgrp docker

# Install tools
sudo apt install -y git curl jq nano htop
```

### 2. Create Project Structure

```bash
# Create project directory
mkdir -p ~/tunnelwatch
cd ~/tunnelwatch

# Create all directories
mkdir -p database nginx/conf.d php/{public/assets/{css,js},src} workers/{tasks,services} scripts
```

### 3. Create All Files

Copy all files from Part 1 and Part 2 into the correct locations.

**Checklist:**
- [ ] `.env` (from `.env.example`, with your passwords)
- [ ] `.gitignore`
- [ ] `docker-compose.yml`
- [ ] `Makefile`
- [ ] `README.md`
- [ ] All `database/*.sql` files
- [ ] All `nginx/*` files
- [ ] All `php/*` files
- [ ] All `workers/*` files
- [ ] All `scripts/*.sh` files (and make executable)

### 4. Find Byfjordtunnelen ID

```bash
# Search for the tunnel
./scripts/find-tunnel-id.sh Byfjordtunnelen

# Update database/seed-tunnels.sql with the correct ID
nano database/seed-tunnels.sql
# Replace 'FIND_THIS_ID' with the actual vegvesen_id
```

### 5. Configure Environment

```bash
# Create .env from template
cp .env.example .env

# Edit configuration
nano .env
```

**Required changes in `.env`:**
```bash
POSTGRES_PASSWORD=your_secure_password_here    # Change this!
SIGNAL_NUMBER=+47XXXXXXXXX                      # Your Signal number
```

### 6. Start Services

```bash
# Build and start all containers
docker compose up -d

# Watch logs
docker compose logs -f

# Check all services are running
docker compose ps
```

Expected output:
```
NAME                    STATUS
tunnelwatch-db          Up (healthy)
tunnelwatch-redis       Up
tunnelwatch-php         Up
tunnelwatch-nginx       Up
tunnelwatch-worker      Up
tunnelwatch-beat        Up
tunnelwatch-signal      Up
```

### 7. Verify Database

```bash
# Check tables were created
docker compose exec postgres psql -U tunnelwatch -d tunnelwatch -c "\dt"

# Check tunnels were inserted
docker compose exec postgres psql -U tunnelwatch -d tunnelwatch -c "SELECT id, name FROM tunnels;"

# Check view works
docker compose exec postgres psql -U tunnelwatch -d tunnelwatch -c "SELECT * FROM tunnel_current_status;"
```

### 8. Test Website

```bash
# Test locally
curl http://localhost

# Should see HTML with TunnelWatch content
```

---

## Signal Setup

Complete Signal registration process.

### Register Signal Number

```bash
# Run registration script
./scripts/register-signal.sh

# Follow prompts:
# 1. Verification code will be sent via SMS
# 2. Enter the code
# 3. Test message will be sent to yourself
```

### Add Test Subscription

```bash
# Add yourself as a subscriber
./scripts/add-subscription.sh +47YOURNUMBER mastrafjord

# Verify subscription
docker compose exec postgres psql -U tunnelwatch -d tunnelwatch -c \
  "SELECT * FROM subscriptions;"
```

### Send Test Notification

```bash
# Send test notification
docker compose exec worker celery -A celery_app call \
  tasks.notifications.send_test_notification --args='["mastrafjord"]'

# Check worker logs
docker compose logs worker

# You should receive a Signal message!
```

---

## Cloudflare Tunnel Setup

Expose your service to the internet securely.

### 1. Install Cloudflared

```bash
wget https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
sudo dpkg -i cloudflared-linux-amd64.deb
```

### 2. Authenticate

```bash
cloudflared tunnel login
```

This opens a browser. Select your Cloudflare domain.

### 3. Create Tunnel

```bash
cloudflared tunnel create tunnelwatch
```

Note the Tunnel ID from output (e.g., `abc123-def456-ghi789`)

### 4. Configure Tunnel

```bash
mkdir -p ~/.cloudflared
nano ~/.cloudflared/config.yml
```

**Config file:**
```yaml
tunnel: YOUR_TUNNEL_ID_HERE
credentials-file: /home/YOUR_USERNAME/.cloudflared/YOUR_TUNNEL_ID.json

ingress:
  - hostname: tunnelwatch.yourdomain.com
    service: http://localhost:80
  - service: http_status:404
```

Replace:
- `YOUR_TUNNEL_ID_HERE` with your tunnel ID
- `YOUR_USERNAME` with your Ubuntu username
- `tunnelwatch.yourdomain.com` with your desired subdomain

### 5. Route DNS

```bash
cloudflared tunnel route dns tunnelwatch tunnelwatch.yourdomain.com
```

### 6. Test Tunnel

```bash
# Test the tunnel
cloudflared tunnel run tunnelwatch

# Visit https://tunnelwatch.yourdomain.com in browser
```

### 7. Install as Service

```bash
# Install as system service
sudo cloudflared service install

# Start and enable
sudo systemctl start cloudflared
sudo systemctl enable cloudflared

# Check status
sudo systemctl status cloudflared
```

---

## NAS Backup Setup

Configure automated backups to NAS.

### Option 1: NFS Mount

```bash
# Install NFS client
sudo apt install -y nfs-common

# Create mount point
sudo mkdir -p /mnt/nas/tunnelwatch-backups

# Test mount
sudo mount NAS_IP:/path/to/share /mnt/nas/tunnelwatch-backups

# If works, add to /etc/fstab for auto-mount
echo "NAS_IP:/path/to/share /mnt/nas/tunnelwatch-backups nfs defaults 0 0" | \
  sudo tee -a /etc/fstab

# Mount all
sudo mount -a
```

### Option 2: SMB/CIFS Mount

```bash
# Install CIFS utils
sudo apt install -y cifs-utils

# Create credentials file
sudo nano /root/.smbcredentials
```

**Credentials file:**
```
username=your_nas_user
password=your_nas_password
```

```bash
# Secure credentials
sudo chmod 600 /root/.smbcredentials

# Add to fstab
echo "//NAS_IP/share /mnt/nas/tunnelwatch-backups cifs credentials=/root/.smbcredentials,uid=1000,gid=1000 0 0" | \
  sudo tee -a /etc/fstab

# Mount
sudo mount -a

# Verify
ls -la /mnt/nas/tunnelwatch-backups
```

### Setup Automated Backups

```bash
# Test backup script
./scripts/backup-db.sh

# Add to crontab for daily backups at 2 AM
crontab -e
```

**Add this line:**
```
0 2 * * * /home/YOUR_USERNAME/tunnelwatch/scripts/backup-db.sh >> /var/log/tunnelwatch-backup.log 2>&1
```

---

## Testing & Verification

### System Health Check

```bash
# Check all containers
docker compose ps

# Check logs
docker compose logs --tail=50

# Check resource usage
docker stats --no-stream
```

### Database Check

```bash
# Connect to database
docker compose exec postgres psql -U tunnelwatch -d tunnelwatch

# Run queries
SELECT COUNT(*) FROM tunnels;
SELECT COUNT(*) FROM status_updates;
SELECT COUNT(*) FROM subscriptions;
SELECT * FROM tunnel_current_status;

# Exit
\q
```

### Worker Check

```bash
# Check worker logs
docker compose logs worker

# Trigger manual check
docker compose exec worker celery -A celery_app call tasks.monitor.check_all_tunnels

# Check beat schedule
docker compose logs beat
```

### Website Check

```bash
# Local check
curl http://localhost

# Check API endpoint
curl http://localhost/api.php | jq .

# External check (after Cloudflare setup)
curl https://tunnelwatch.yourdomain.com
```

### Signal Check

```bash
# Check Signal API status
docker compose exec signal-api curl http://localhost:8080/v1/about

# Send test message
./scripts/add-subscription.sh +47YOURNUMBER mastrafjord
docker compose exec worker celery -A celery_app call \
  tasks.notifications.send_test_notification --args='["mastrafjord"]'
```

---

## Troubleshooting

### Container Won't Start

```bash
# Check logs
docker compose logs CONTAINER_NAME

# Rebuild container
docker compose build --no-cache CONTAINER_NAME
docker compose up -d CONTAINER_NAME

# Check configuration
docker compose config
```

### Database Connection Errors

```bash
# Check PostgreSQL is running
docker compose ps postgres

# Check if ready
docker compose exec postgres pg_isready -U tunnelwatch

# Check environment variables
docker compose exec php printenv | grep DB_

# Try connecting manually
docker compose exec postgres psql -U tunnelwatch -d tunnelwatch
```

### Signal Not Working

```bash
# Check Signal API logs
docker compose logs signal-api

# Check if registered
docker compose exec signal-api signal-cli -u $SIGNAL_NUMBER listAccounts

# Re-register if needed
./scripts/register-signal.sh

# Test sending
docker compose exec signal-api curl -X POST \
  http://localhost:8080/v2/send \
  -H "Content-Type: application/json" \
  -d '{"message": "test", "number": "+47XXXXXXXXX", "recipients": ["+47XXXXXXXXX"]}'
```

### Workers Not Running

```bash
# Check worker logs
docker compose logs worker beat

# Check Redis connection
docker compose exec worker python -c "import redis; r=redis.from_url('redis://redis:6379/0'); print(r.ping())"

# Check database connection
docker compose exec worker python -c "import psycopg2; conn=psycopg2.connect('postgresql://tunnelwatch:PASSWORD@postgres:5432/tunnelwatch'); print('OK')"

# Restart workers
docker compose restart worker beat
```

### Website Not Loading

```bash
# Check nginx logs
docker compose logs nginx

# Check PHP logs
docker compose logs php

# Test PHP-FPM
docker compose exec php php-fpm -t

# Check nginx config
docker compose exec nginx nginx -t

# Restart web stack
docker compose restart nginx php
```

---

## Operations & Maintenance

### Daily Operations

```bash
# View all logs
make logs

# Check status
make status
# or
docker compose ps
docker stats --no-stream

# Restart service
docker compose restart SERVICE_NAME
```

### Weekly Tasks

```bash
# Check disk space
df -h

# Check backup status
ls -lh /mnt/nas/tunnelwatch-backups/

# Review logs for errors
docker compose logs --since 7d | grep -i error
```

### Monthly Tasks

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Pull latest Docker images
docker compose pull

# Clean up old images
docker image prune -a

# Verify backups work
./scripts/restore-db.sh /mnt/nas/tunnelwatch-backups/tunnelwatch_backup_LATEST.sql.gz
```

### Updating Code

```bash
# Pull latest changes
git pull

# Rebuild containers
docker compose up -d --build

# Check everything works
docker compose ps
docker compose logs --tail=50
```

### Adding More Tunnels

```bash
# 1. Find tunnel ID
./scripts/find-tunnel-id.sh "Tunnel Name"

# 2. Add to database
docker compose exec postgres psql -U tunnelwatch -d tunnelwatch

INSERT INTO tunnels (id, name, vegvesen_id, latitude, longitude, length, active)
VALUES ('tunnel-id', 'Tunnel Name', 'VEGVESEN_ID', LAT, LON, LENGTH, true);

INSERT INTO status_updates (tunnel_id, status, message)
VALUES ('tunnel-id', 'open', 'Tunnelen er åpen for normal trafikk');

\q

# 3. Verify
curl http://localhost/api.php | jq '.data'
```

### Monitoring Best Practices

```bash
# Set up log rotation
sudo nano /etc/logrotate.d/tunnelwatch
```

**Log rotation config:**
```
/var/log/tunnelwatch-backup.log {
    weekly
    rotate 4
    compress
    missingok
    notifempty
}
```

### Security Checklist

- [ ] Strong database password in `.env`
- [ ] Firewall configured (UFW or iptables)
- [ ] Only port 80/443 exposed externally
- [ ] Cloudflare proxy enabled
- [ ] Regular backups tested
- [ ] Logs monitored for suspicious activity
- [ ] Docker images regularly updated
- [ ] System packages kept up to date

---

## Production Checklist

Before going live:

- [ ] All environment variables configured
- [ ] Strong passwords set
- [ ] Signal number registered and tested
- [ ] Cloudflare tunnel working
- [ ] NAS backups configured and tested
- [ ] Cron job for backups added
- [ ] All tunnels added to database
- [ ] Website accessible externally
- [ ] Workers running and monitoring
- [ ] Test notifications received
- [ ] Logs being captured
- [ ] Resource usage acceptable
- [ ] Documentation updated

---

## Complete Deployment Success!

If you've followed all steps in Part 1 and Part 2, you now have:

✅ **Fully functional TunnelWatch service**  
✅ **Real-time tunnel monitoring**  
✅ **Signal notifications working**  
✅ **Public website via Cloudflare**  
✅ **Automated backups to NAS**  
✅ **Complete maintenance procedures**  

**Your service is production-ready!**

---

## Getting Help

If you encounter issues:

1. Check the troubleshooting section above
2. Review container logs: `docker compose logs SERVICE_NAME`
3. Verify configuration: `docker compose config`
4. Check this documentation for similar issues

**Happy monitoring! 🚇**