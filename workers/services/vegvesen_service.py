"""
TunnelWatch Norway - Vegvesen API Service

Fetches real-time tunnel status from the open Vegvesen API.
API: https://fjelloverganger-backend.atlas.vegvesen.no/v1/tunneler
"""

import httpx
import os
from typing import List, Dict, Optional
from datetime import datetime


class VegvesenService:
    """Service for fetching tunnel data from Vegvesen API"""
    
    API_URL = os.getenv(
        'VEGVESEN_API_URL',
        'https://fjelloverganger-backend.atlas.vegvesen.no/v1/tunneler'
    )
    
    # Status mapping: API -> Internal
    STATUS_MAP = {
        'Apen': 'open',
        'Stengt': 'closed',
        'Kolonnekjoring': 'restricted',
    }
    
    async def get_all_tunnels(self) -> List[Dict]:
        """
        Fetch all tunnel data from Vegvesen API
        Returns parsed list of tunnel status objects
        """
        async with httpx.AsyncClient() as client:
            try:
                response = await client.get(
                    self.API_URL,
                    headers={
                        'Accept': 'application/json',
                        'User-Agent': 'TunnelWatch-Norway/1.0'
                    },
                    timeout=30.0
                )
                
                if response.status_code == 200:
                    data = response.json()
                    features = data.get('features', [])
                    return [self._parse_feature(f) for f in features]
                else:
                    print(f"Vegvesen API returned {response.status_code}")
                    return []
                    
            except httpx.TimeoutException:
                print("Vegvesen API request timed out")
                return []
            except Exception as e:
                print(f"Error fetching from Vegvesen API: {e}")
                return []
    
    async def get_tunnel_by_id(self, vegvesen_id: str) -> Optional[Dict]:
        """Get a specific tunnel by its Vegvesen ID"""
        tunnels = await self.get_all_tunnels()
        
        for tunnel in tunnels:
            if tunnel['vegvesen_id'] == vegvesen_id:
                return tunnel
        
        return None
    
    def _parse_feature(self, feature: Dict) -> Dict:
        """Parse GeoJSON feature into our internal format"""
        props = feature.get('properties', {})
        
        # Map status
        api_status = props.get('status', 'unknown')
        internal_status = self.STATUS_MAP.get(api_status, 'unknown')
        
        api_status_heavy = props.get('statusTungbil', 'unknown')
        internal_status_heavy = self.STATUS_MAP.get(api_status_heavy, 'unknown')
        
        # Get center coordinates
        center = props.get('senter', {})
        coords = center.get('coordinates', [0, 0])
        longitude = coords[0] if len(coords) > 0 else 0
        latitude = coords[1] if len(coords) > 1 else 0
        
        # Handle future status
        expected_change = None
        expected_status = None
        fremtidig = props.get('fremtidigStatus')
        if fremtidig:
            expected_status = self.STATUS_MAP.get(fremtidig.get('status'), fremtidig.get('status'))
            start_tid = fremtidig.get('startTid')
            if start_tid:
                try:
                    expected_change = datetime.fromisoformat(start_tid.replace('Z', '+00:00'))
                except:
                    pass
        
        # Generate messages
        message_no = self._generate_message_no(props, internal_status, fremtidig)
        message_en = self._generate_message_en(props, internal_status, fremtidig)
        
        # Determine severity
        severity = self._determine_severity(internal_status, props)
        
        return {
            'vegvesen_id': str(props.get('id', feature.get('id', ''))),
            'name': props.get('navn', 'Unknown'),
            'status': internal_status,
            'status_heavy_vehicle': internal_status_heavy,
            'message_no': message_no,
            'message_en': message_en,
            'severity': severity,
            'latitude': latitude,
            'longitude': longitude,
            'length': props.get('lengde'),
            'road_category': props.get('vegkategori'),
            'road_number': props.get('vegnummer'),
            'region': props.get('regioner', [None])[0] if props.get('regioner') else None,
            'traffic_messages': props.get('trafikkmeldinger', []),
            'expected_change': expected_change.isoformat() if expected_change else None,
            'expected_status': expected_status,
            'raw_data': props,
        }
    
    def _generate_message_no(self, props: Dict, status: str, fremtidig: Optional[Dict]) -> str:
        """Generate Norwegian status message"""
        trafikk = props.get('trafikkmeldinger', [])
        
        if status == 'closed':
            return 'Tunnelen er stengt'
        
        if status == 'restricted':
            return 'Kolonnekjøring i tunnelen'
        
        if trafikk:
            return f'Tunnelen er åpen, men har {len(trafikk)} trafikkmelding(er)'
        
        if fremtidig:
            start_tid = fremtidig.get('startTid')
            if start_tid:
                try:
                    dt = datetime.fromisoformat(start_tid.replace('Z', '+00:00'))
                    tid_str = dt.strftime('%d.%m kl. %H:%M')
                    fremtidig_status = fremtidig.get('status', 'Stengt')
                    return f'Tunnelen er åpen. {fremtidig_status} fra {tid_str}'
                except:
                    pass
        
        return 'Tunnelen er åpen for normal trafikk'
    
    def _generate_message_en(self, props: Dict, status: str, fremtidig: Optional[Dict]) -> str:
        """Generate English status message"""
        trafikk = props.get('trafikkmeldinger', [])
        
        if status == 'closed':
            return 'Tunnel is closed'
        
        if status == 'restricted':
            return 'Convoy driving in tunnel'
        
        if trafikk:
            return f'Tunnel is open, but has {len(trafikk)} traffic message(s)'
        
        if fremtidig:
            start_tid = fremtidig.get('startTid')
            if start_tid:
                try:
                    dt = datetime.fromisoformat(start_tid.replace('Z', '+00:00'))
                    tid_str = dt.strftime('%d.%m at %H:%M')
                    fremtidig_status = self.STATUS_MAP.get(fremtidig.get('status'), fremtidig.get('status'))
                    return f'Tunnel is open. {fremtidig_status.capitalize()} from {tid_str}'
                except:
                    pass
        
        return 'Tunnel is open for normal traffic'
    
    def _determine_severity(self, status: str, props: Dict) -> str:
        """Determine severity level based on status"""
        if status == 'closed':
            return 'high'
        if status == 'restricted':
            return 'medium'
        
        # Check for traffic messages
        if props.get('trafikkmeldinger'):
            return 'low'
        
        return 'low'
