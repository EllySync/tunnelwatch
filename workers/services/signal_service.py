"""
TunnelWatch Norway - Signal Notification Service

Sends notifications via Signal CLI REST API.
"""

import httpx
import os
from typing import List, Optional
from datetime import datetime


class SignalService:
    """Service for sending Signal notifications"""
    
    def __init__(self):
        self.api_url = os.getenv('SIGNAL_API_URL', 'http://signal-api:8080')
        self.sender_number = os.getenv('SIGNAL_NUMBER')
    
    async def send_message(self, recipients: List[str], message: str) -> bool:
        """
        Send a Signal message to one or more recipients
        
        Args:
            recipients: List of phone numbers (with country code)
            message: Message text to send
            
        Returns:
            True if message sent successfully
        """
        if not self.sender_number:
            print("Error: SIGNAL_NUMBER not configured")
            return False
        
        if not recipients:
            print("Error: No recipients specified")
            return False
        
        async with httpx.AsyncClient() as client:
            try:
                response = await client.post(
                    f"{self.api_url}/v2/send",
                    json={
                        "message": message,
                        "number": self.sender_number,
                        "recipients": recipients,
                    },
                    timeout=30.0
                )
                
                if response.status_code in [200, 201]:
                    return True
                else:
                    print(f"Signal API error: {response.status_code} - {response.text}")
                    return False
                    
            except httpx.TimeoutException:
                print("Signal API request timed out")
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
        language: str = 'no',
        expected_change: Optional[str] = None
    ) -> bool:
        """
        Send a formatted tunnel status alert
        
        Args:
            recipients: List of phone numbers
            tunnel_name: Name of the tunnel
            status: Current status (open, closed, restricted)
            message: Status message
            language: 'no' or 'en'
            expected_change: Optional datetime string for expected reopening
        """
        formatted_message = self._format_alert(
            tunnel_name=tunnel_name,
            status=status,
            message=message,
            language=language,
            expected_change=expected_change
        )
        
        return await self.send_message(recipients, formatted_message)
    
    def _format_alert(
        self,
        tunnel_name: str,
        status: str,
        message: str,
        language: str,
        expected_change: Optional[str] = None
    ) -> str:
        """Format the alert message"""
        
        # Status emoji
        emoji_map = {
            'open': '✅',
            'closed': '🚫',
            'restricted': '⚠️',
        }
        emoji = emoji_map.get(status, '📍')
        
        # Status text
        if language == 'en':
            status_text = status.upper()
        else:
            status_map = {
                'open': 'ÅPEN',
                'closed': 'STENGT',
                'restricted': 'BEGRENSET',
            }
            status_text = status_map.get(status, status.upper())
        
        # Build message
        lines = [
            f"{emoji} *{tunnel_name}*",
            "",
            f"Status: {status_text}",
        ]
        
        if message:
            info_label = "Info" if language == 'en' else "Info"
            lines.append(f"{info_label}: {message}")
        
        # Expected change
        if expected_change:
            try:
                dt = datetime.fromisoformat(expected_change)
                if language == 'en':
                    time_str = dt.strftime('%d.%m at %H:%M')
                    lines.append(f"\n⏰ Expected change: {time_str}")
                else:
                    time_str = dt.strftime('%d.%m kl. %H:%M')
                    lines.append(f"\n⏰ Forventet endring: {time_str}")
            except:
                pass
        
        # Footer
        now = datetime.now().strftime('%H:%M')
        lines.append(f"\n_TunnelWatch - {now}_")
        
        return "\n".join(lines)
