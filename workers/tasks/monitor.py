"""
TunnelWatch Norway - Tunnel Monitoring Task
"""

from celery import shared_task
import psycopg2
import os
import asyncio
from datetime import datetime
from services.vegvesen_service import VegvesenService
from services.signal_service import SignalService

DATABASE_URL = os.getenv('DATABASE_URL')


def get_db_connection():
    """Get PostgreSQL database connection"""
    return psycopg2.connect(DATABASE_URL)


@shared_task
def check_all_tunnels():
    """
    Main monitoring task - checks all active tunnels
    Runs every 60 seconds via Celery Beat
    """
    print(f"[{datetime.now().isoformat()}] Starting tunnel status check...")
    
    conn = get_db_connection()
    cur = conn.cursor()
    
    try:
        # Get all active tunnels
        cur.execute("""
            SELECT id, name, vegvesen_id
            FROM tunnels
            WHERE active = true
        """)
        tunnels = cur.fetchall()
        
        if not tunnels:
            print("No active tunnels to monitor")
            return
        
        print(f"Checking {len(tunnels)} tunnels...")
        
        # Fetch all tunnel data from Vegvesen API
        vegvesen_service = VegvesenService()
        api_data = asyncio.run(vegvesen_service.get_all_tunnels())
        
        if not api_data:
            print("Warning: Could not fetch data from Vegvesen API")
            return
        
        # Create lookup by vegvesen_id
        api_lookup = {t['vegvesen_id']: t for t in api_data}
        
        # Check each tunnel
        for tunnel_id, name, vegvesen_id in tunnels:
            tunnel_data = api_lookup.get(vegvesen_id)
            
            if tunnel_data:
                asyncio.run(process_tunnel_status(tunnel_id, name, tunnel_data))
            else:
                print(f"Warning: No API data for {name} (vegvesen_id: {vegvesen_id})")
        
        print(f"✓ Checked {len(tunnels)} tunnels")
        
    except Exception as e:
        print(f"Error in check_all_tunnels: {e}")
    finally:
        cur.close()
        conn.close()


async def process_tunnel_status(tunnel_id: str, name: str, api_data: dict):
    """Process status for a single tunnel"""
    conn = get_db_connection()
    cur = conn.cursor()
    
    try:
        # Get last known status
        cur.execute("""
            SELECT status, message_no
            FROM status_updates
            WHERE tunnel_id = %s
            ORDER BY created_at DESC
            LIMIT 1
        """, (tunnel_id,))
        
        last_record = cur.fetchone()
        last_status = last_record[0] if last_record else None
        
        # Get new status from API data
        new_status = api_data['status']
        
        # Check if status changed
        if last_status != new_status:
            print(f"📢 Status change for {name}: {last_status} → {new_status}")
            
            # Insert new status record
            cur.execute("""
                INSERT INTO status_updates 
                (tunnel_id, status, status_heavy_vehicle, message_no, message_en, 
                 severity, traffic_messages, expected_change, expected_status, raw_data)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
            """, (
                tunnel_id,
                api_data['status'],
                api_data.get('status_heavy_vehicle'),
                api_data.get('message_no'),
                api_data.get('message_en'),
                api_data.get('severity'),
                psycopg2.extras.Json(api_data.get('traffic_messages', [])),
                api_data.get('expected_change'),
                api_data.get('expected_status'),
                psycopg2.extras.Json(api_data.get('raw_data', {})),
            ))
            conn.commit()
            
            # Send notifications
            await notify_subscribers(tunnel_id, name, api_data)
        else:
            print(f"No change for {name}: {new_status}")
            
    except Exception as e:
        print(f"Error processing tunnel {tunnel_id}: {e}")
        conn.rollback()
    finally:
        cur.close()
        conn.close()


async def notify_subscribers(tunnel_id: str, tunnel_name: str, status_data: dict):
    """Send Signal notifications to subscribers"""
    conn = get_db_connection()
    cur = conn.cursor()
    
    try:
        # Get active subscribers
        cur.execute("""
            SELECT phone_number, language
            FROM subscriptions
            WHERE tunnel_id = %s AND active = true
        """, (tunnel_id,))
        
        subscribers = cur.fetchall()
        
        if not subscribers:
            print(f"No subscribers for {tunnel_name}")
            return
        
        # Group by language
        no_subscribers = [s[0] for s in subscribers if s[1] == 'no']
        en_subscribers = [s[0] for s in subscribers if s[1] == 'en']
        
        signal_service = SignalService()
        
        # Send Norwegian notifications
        if no_subscribers:
            success = await signal_service.send_tunnel_alert(
                recipients=no_subscribers,
                tunnel_name=tunnel_name,
                status=status_data['status'],
                message=status_data.get('message_no', ''),
                language='no'
            )
            if success:
                print(f"✓ Sent notification to {len(no_subscribers)} NO subscribers")
        
        # Send English notifications
        if en_subscribers:
            success = await signal_service.send_tunnel_alert(
                recipients=en_subscribers,
                tunnel_name=tunnel_name,
                status=status_data['status'],
                message=status_data.get('message_en', ''),
                language='en'
            )
            if success:
                print(f"✓ Sent notification to {len(en_subscribers)} EN subscribers")
                
    except Exception as e:
        print(f"Error notifying subscribers: {e}")
    finally:
        cur.close()
        conn.close()


# Import psycopg2.extras for Json adapter
import psycopg2.extras
