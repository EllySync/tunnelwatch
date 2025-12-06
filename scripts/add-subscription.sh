#!/bin/bash
# ===========================================
# TunnelWatch Norway - Add Subscription
# ===========================================

set -e

PHONE_NUMBER=$1
TUNNEL_ID=$2
LANGUAGE=${3:-no}

if [ -z "$PHONE_NUMBER" ] || [ -z "$TUNNEL_ID" ]; then
    echo "Usage: ./add-subscription.sh <phone_number> <tunnel_id> [language]"
    echo ""
    echo "Arguments:"
    echo "  phone_number  Phone number with country code (e.g., +4712345678)"
    echo "  tunnel_id     Tunnel ID to subscribe to"
    echo "  language      Language for notifications: 'no' or 'en' (default: no)"
    echo ""
    echo "Examples:"
    echo "  ./add-subscription.sh +4712345678 mastrafjord"
    echo "  ./add-subscription.sh +4712345678 byfjord en"
    echo ""
    echo "Available tunnels:"
    docker compose exec postgres psql -U tunnelwatch -d tunnelwatch -t -c \
        "SELECT id, name FROM tunnels WHERE active = true;"
    exit 1
fi

echo "==================================="
echo "Add Subscription"
echo "==================================="
echo ""
echo "Phone: $PHONE_NUMBER"
echo "Tunnel: $TUNNEL_ID"
echo "Language: $LANGUAGE"
echo ""

# Add subscription
docker compose exec postgres psql -U tunnelwatch -d tunnelwatch -c "
    INSERT INTO subscriptions (phone_number, tunnel_id, language, active)
    VALUES ('${PHONE_NUMBER}', '${TUNNEL_ID}', '${LANGUAGE}', true)
    ON CONFLICT (phone_number, tunnel_id) 
    DO UPDATE SET 
        language = '${LANGUAGE}',
        active = true, 
        updated_at = CURRENT_TIMESTAMP;
"

if [ $? -eq 0 ]; then
    echo ""
    echo "✓ Subscription added successfully!"
    echo ""
    echo "To verify:"
    echo "  docker compose exec postgres psql -U tunnelwatch -d tunnelwatch -c \"SELECT * FROM subscriptions WHERE phone_number = '${PHONE_NUMBER}';\""
    echo ""
    echo "To send test notification:"
    echo "  docker compose exec worker celery -A celery_app call tasks.notifications.send_test_notification --args='[\"${TUNNEL_ID}\"]'"
    echo ""
else
    echo ""
    echo "✗ Failed to add subscription"
    exit 1
fi
