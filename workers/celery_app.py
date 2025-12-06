"""
TunnelWatch Norway - Celery Application Configuration
"""

from celery import Celery
from celery.schedules import crontab
import os
import sys

# Ensure the app directory is in the path
sys.path.insert(0, '/app')

# Redis URL from environment
REDIS_URL = os.getenv('REDIS_URL', 'redis://redis:6379/0')

# Create Celery app
app = Celery('tunnelwatch', broker=REDIS_URL, backend=REDIS_URL)

# Configuration
app.conf.update(
    task_serializer='json',
    accept_content=['json'],
    result_serializer='json',
    timezone='Europe/Oslo',
    enable_utc=True,
    broker_connection_retry_on_startup=True,
    
    # Task settings
    task_acks_late=True,
    task_reject_on_worker_lost=True,
    
    # Result settings
    result_expires=3600,  # 1 hour
    
    # Import tasks explicitly
    imports=('tasks.monitor', 'tasks.notifications'),
)

# Beat schedule - periodic tasks
app.conf.beat_schedule = {
    'check-tunnel-status-every-minute': {
        'task': 'tasks.monitor.check_all_tunnels',
        'schedule': 60.0,  # Every 60 seconds
    },
}

if __name__ == '__main__':
    app.start()
