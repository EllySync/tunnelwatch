"""
TunnelWatch Norway - Notification Tasks
"""

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
    asyncio.run(_send_test_notification(tunnel_id))


async def _send_test_notification(tunnel_id: str):
    """Async implementation of test notification"""
    conn = get_db_connection()
    cur = conn.cursor()
    
    try:
        # Get tunnel and subscribers
        cur.execute("""
            SELECT t.name, s.phone_number, s.language
            FROM tunnels t
            JOIN subscriptions s ON t.id = s.tunnel_id
            WHERE t.id = %s AND s.active = true
        """, (tunnel_id,))
        
        results = cur.fetchall()
        
        if not results:
            print(f"No subscribers for tunnel {tunnel_id}")
            return
        
        tunnel_name = results[0][0]
        
        # Group by language
        no_subscribers = [r[1] for r in results if r[2] == 'no']
        en_subscribers = [r[1] for r in results if r[2] == 'en']
        
        signal_service = SignalService()
        
        # Send test messages
        if no_subscribers:
            await signal_service.send_tunnel_alert(
                recipients=no_subscribers,
                tunnel_name=tunnel_name,
                status='open',
                message='Dette er en test-melding fra TunnelWatch. Tjenesten fungerer! 🚇',
                language='no'
            )
            print(f"✓ Test sent to {len(no_subscribers)} NO subscribers")
        
        if en_subscribers:
            await signal_service.send_tunnel_alert(
                recipients=en_subscribers,
                tunnel_name=tunnel_name,
                status='open',
                message='This is a test message from TunnelWatch. The service is working! 🚇',
                language='en'
            )
            print(f"✓ Test sent to {len(en_subscribers)} EN subscribers")
            
    except Exception as e:
        print(f"Error sending test notification: {e}")
    finally:
        cur.close()
        conn.close()
