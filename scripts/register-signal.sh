#!/bin/bash
# ===========================================
# TunnelWatch Norway - Signal Registration
# ===========================================

set -e

# Get Signal number from environment or prompt
SIGNAL_NUMBER="${SIGNAL_NUMBER:-}"

if [ -z "$SIGNAL_NUMBER" ]; then
    read -p "Enter your Signal phone number (e.g., +4712345678): " SIGNAL_NUMBER
fi

echo "==================================="
echo "Signal CLI Registration"
echo "==================================="
echo ""
echo "Phone number: ${SIGNAL_NUMBER}"
echo ""

# Check if Signal API container is running
if ! docker compose ps signal-api | grep -q "Up"; then
    echo "Starting Signal API container..."
    docker compose up -d signal-api
    echo "Waiting for container to be ready..."
    sleep 10
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

if echo "$RESPONSE" | grep -qi "error"; then
    echo ""
    echo "✗ Verification failed!"
    echo "Response: $RESPONSE"
    exit 1
fi

echo ""
echo "✓ Signal CLI registered successfully!"
echo ""
echo "Step 3: Sending test message"
echo "----------------------------"

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
echo "1. Add subscription: ./scripts/add-subscription.sh +47XXXXXXXX mastrafjord"
echo "2. Test notification: docker compose exec worker celery -A celery_app call tasks.notifications.send_test_notification --args='[\"mastrafjord\"]'"
echo ""
