#!/bin/bash
# ===========================================
# TunnelWatch Norway - Find Tunnel ID
# ===========================================

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
echo "Search Vegvesen API for Tunnel"
echo "==================================="
echo ""
echo "Searching for: $TUNNEL_NAME"
echo ""

# Search the API and filter results
curl -s "https://fjelloverganger-backend.atlas.vegvesen.no/v1/tunneler" \
    -H "Accept: application/json" \
    | python3 -c "
import json
import sys

name_filter = '$TUNNEL_NAME'.lower()
data = json.load(sys.stdin)

found = []
for feature in data.get('features', []):
    props = feature.get('properties', {})
    navn = props.get('navn', '')
    if name_filter in navn.lower():
        found.append({
            'id': props.get('id'),
            'navn': navn,
            'lengde': props.get('lengde'),
            'veg': f\"{props.get('vegkategori', '')}{props.get('vegnummer', '')}\",
            'status': props.get('status'),
        })

if found:
    print('Found tunnels:')
    print('-' * 60)
    for t in found:
        print(f\"ID: {t['id']}\")
        print(f\"Name: {t['navn']}\")
        print(f\"Road: {t['veg']}\")
        print(f\"Length: {t['lengde']}m\")
        print(f\"Status: {t['status']}\")
        print('-' * 60)
else:
    print(f'No tunnels found matching: {name_filter}')
"

echo ""
echo "Use the 'ID' value as vegvesen_id in the database"
echo ""
