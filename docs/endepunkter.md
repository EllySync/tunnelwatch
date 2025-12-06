# Fjelloverganger API - Tunneler Endepunkt

**Komplett dokumentasjon for Vegvesen sitt åpne API for tunnelstatus**

---

## 📋 Oversikt

**Endepunkt:** `https://fjelloverganger-backend.atlas.vegvesen.no/v1/tunneler`

**Formål:** Hente sanntidsstatus for alle tunneler i Norge

**Autentisering:** ✅ **INGEN PÅKREVD** - Helt åpent API!

**Format:** GeoJSON

**Oppdateringsfrekvens:** Sanntid

**Vedlikeholdt av:** Statens vegvesen

### 🎉 Hvorfor Dette Er Perfekt

- ✅ **Ingen registrering** - Start å bruke med en gang
- ✅ **Ingen API-nøkler** - Ingen hemmeligheter å håndtere
- ✅ **Ingen rate limits** (så vidt vi vet) - Polle så ofte du trenger
- ✅ **Produksjonsklart** - Offisielt API fra Vegvesen
- ✅ **Sanntidsdata** - Oppdatert kontinuerlig

---

## 🔗 API Detaljer

### HTTP Request

```http
GET https://fjelloverganger-backend.atlas.vegvesen.no/v1/tunneler
```

### Headers

```http
Accept: application/json
User-Agent: TunnelWatch-Norway/1.0  (valgfritt, men anbefalt)
```

### Response Format

GeoJSON FeatureCollection

```json
{
  "type": "FeatureCollection",
  "features": [...]
}
```

---

## 📊 Data Struktur

### Feature Object

Hver tunnel i listen er et GeoJSON Feature:

```json
{
  "id": "79604497",
  "type": "Feature",
  "geometry": {
    "type": "LineString",
    "coordinates": [
      [5.67685812, 59.07195047],
      [5.68139798, 59.07313968],
      ...
    ]
  },
  "properties": {
    "id": "79604497",
    "navn": "Mastrafjordtunnelen",
    "status": "Apen",
    "statusTungbil": "Apen",
    "trafikkmeldinger": ["NPRA_HBT_05-12-2025.199568"],
    "lokasjoner": [],
    "vegkategori": "E",
    "vegnummer": "39",
    "regioner": ["Vest"],
    "fylker": [11],
    "lengde": 4400,
    "senter": {
      "type": "Point",
      "coordinates": [5.6983788, 59.08554359]
    },
    "strekningstype": "Tunnel",
    "vurdering": "IkkeRelevant",
    "fremtidigStatus": null
  }
}
```

---

## 📖 Felt Beskrivelse

### Basis Informasjon

| Felt | Type | Beskrivelse | Eksempel |
|------|------|-------------|----------|
| `id` | string | NVDB tunnel ID (vegvesen_id) | `"79604497"` |
| `navn` | string | Offisielt navn på tunnelen | `"Mastrafjordtunnelen"` |
| `lengde` | integer | Lengde i meter | `4400` |
| `vegkategori` | string | Vegkategori (E, Rv, Fv) | `"E"` |
| `vegnummer` | string | Vegnummer | `"39"` |

### Status Felter

| Felt | Type | Mulige Verdier | Beskrivelse |
|------|------|----------------|-------------|
| `status` | string | `"Apen"`, `"Stengt"`, `"Kolonnekjoring"` | **Viktigste felt!** Nåværende status |
| `statusTungbil` | string | `"Apen"`, `"Stengt"`, `"Kolonnekjoring"` | Status for tungbil/vogntog |
| `fremtidigStatus` | object/null | Se nedenfor | Planlagt fremtidig statusendring |

### Fremtidig Status Object

Hvis tunnelen har planlagt stenging/endring:

```json
{
  "status": "Stengt",
  "startTid": "2025-12-08T20:00:00Z"
}
```

| Felt | Type | Beskrivelse |
|------|------|-------------|
| `status` | string | Planlagt status |
| `startTid` | string (ISO 8601) | Tidspunkt for endring (UTC) |

### Trafikkmeldinger

| Felt | Type | Beskrivelse |
|------|------|-------------|
| `trafikkmeldinger` | array[string] | Liste med trafikkmeldings-IDer | 
| `lokasjoner` | array[string] | Tilknyttede lokasjons-IDer |

**Eksempel:**
```json
"trafikkmeldinger": ["NPRA_HBT_05-12-2025.199568"]
```

### Geografisk Informasjon

| Felt | Type | Beskrivelse |
|------|------|-------------|
| `regioner` | array[string] | Hvilke region(er) | `["Vest"]` |
| `fylker` | array[integer] | Fylkesnummer(e) | `[11]` |
| `senter` | GeoJSON Point | Tunnelens senterpunkt (lon, lat) | Se under |

**Senter koordinater:**
```json
"senter": {
  "type": "Point",
  "coordinates": [5.6983788, 59.08554359]  // [longitude, latitude]
}
```

### Geometri

Full geometri for tunnelen (veglenke):

```json
"geometry": {
  "type": "LineString",
  "coordinates": [
    [5.67685812, 59.07195047],  // [longitude, latitude]
    [5.68139798, 59.07313968],
    ...
  ]
}
```

---

## 💡 Eksempler På Bruk

### 1. Grunnleggende Forespørsel

```bash
curl https://fjelloverganger-backend.atlas.vegvesen.no/v1/tunneler
```

### 2. Med Python (httpx)

```python
import httpx
import json

async def get_tunnels():
    async with httpx.AsyncClient() as client:
        response = await client.get(
            "https://fjelloverganger-backend.atlas.vegvesen.no/v1/tunneler",
            headers={"Accept": "application/json"}
        )
        
        if response.status_code == 200:
            data = response.json()
            return data['features']
        return []

# Bruk
tunnels = await get_tunnels()
print(f"Fant {len(tunnels)} tunneler")
```

### 3. Finne Spesifikk Tunnel

```python
async def get_tunnel_by_id(tunnel_id: str):
    """Finn tunnel basert på NVDB ID"""
    tunnels = await get_tunnels()
    
    for feature in tunnels:
        if feature['id'] == tunnel_id:
            return feature['properties']
    
    return None

# Eksempel
mastrafjord = await get_tunnel_by_id("79604497")
print(f"Status: {mastrafjord['status']}")
```

### 4. Filtrere Stengte Tunneler

```python
async def get_closed_tunnels():
    """Finn alle stengte tunneler"""
    tunnels = await get_tunnels()
    
    closed = [
        feature['properties'] 
        for feature in tunnels 
        if feature['properties']['status'] == 'Stengt'
    ]
    
    return closed

# Bruk
stengte = await get_closed_tunnels()
for tunnel in stengte:
    print(f"{tunnel['navn']} er stengt")
```

### 5. Sjekk Fremtidige Stenginger

```python
from datetime import datetime

async def get_upcoming_closures():
    """Finn tunneler med planlagte stenginger"""
    tunnels = await get_tunnels()
    
    upcoming = []
    for feature in tunnels:
        props = feature['properties']
        fremtidig = props.get('fremtidigStatus')
        
        if fremtidig and fremtidig.get('startTid'):
            upcoming.append({
                'navn': props['navn'],
                'status': fremtidig['status'],
                'tid': fremtidig['startTid']
            })
    
    return upcoming

# Bruk
fremtidige = await get_upcoming_closures()
for item in fremtidige:
    print(f"{item['navn']} - {item['status']} fra {item['tid']}")
```

---

## 🎯 TunnelWatch Bruk

### Status Mapping

Konverter API status til vårt interne format:

```python
def map_status(api_status: str) -> str:
    """Konverter API status til TunnelWatch format"""
    mapping = {
        'Apen': 'open',
        'Stengt': 'closed',
        'Kolonnekjoring': 'restricted'
    }
    return mapping.get(api_status, 'unknown')
```

### Generer Brukermelding

```python
def generate_message(props: dict) -> str:
    """Generer lesbar melding basert på tunnelstatus"""
    status = props.get('status')
    trafikk = props.get('trafikkmeldinger', [])
    fremtidig = props.get('fremtidigStatus')
    
    # Stengt
    if status == 'Stengt':
        return 'Tunnelen er stengt'
    
    # Kolonnekjøring
    if status == 'Kolonnekjoring':
        return 'Kolonnekjøring i tunnelen'
    
    # Åpen med trafikkmeldinger
    if len(trafikk) > 0:
        return f'Tunnelen er åpen, men har {len(trafikk)} trafikkmelding(er)'
    
    # Planlagt stenging
    if fremtidig:
        from datetime import datetime
        start_tid = fremtidig.get('startTid')
        if start_tid:
            dt = datetime.fromisoformat(start_tid.replace('Z', '+00:00'))
            tid_str = dt.strftime('%d.%m kl. %H:%M')
            return f'Tunnelen er åpen. {fremtidig["status"]} fra {tid_str}'
    
    # Standard
    return 'Tunnelen er åpen for normal trafikk'
```

### Bestem Alvorlighetsgrad

```python
def determine_severity(props: dict) -> str:
    """Bestem alvorlighetsgrad for notification"""
    status = props.get('status')
    trafikk = props.get('trafikkmeldinger', [])
    
    if status == 'Stengt':
        return 'high'
    if status == 'Kolonnekjoring':
        return 'medium'
    if len(trafikk) > 0:
        return 'low'
    
    return 'low'
```

---

## 🔄 Oppdateringsfrekvens

- **Sanntid:** API-et oppdateres kontinuerlig
- **Anbefalt polling:** Hvert 30-60 sekund
- **Ikke bruk høyere frekvens** enn nødvendig for å unngå unødig belastning

---

## 📊 Eksempel Response

### Mastrafjordtunnelen (Åpen med trafikkmelding)

```json
{
  "id": "79604497",
  "type": "Feature",
  "geometry": {
    "type": "LineString",
    "coordinates": [[5.67685812, 59.07195047], ...]
  },
  "properties": {
    "id": "79604497",
    "navn": "Mastrafjordtunnelen",
    "status": "Apen",
    "statusTungbil": "Apen",
    "trafikkmeldinger": ["NPRA_HBT_05-12-2025.199568"],
    "lokasjoner": [],
    "vegkategori": "E",
    "vegnummer": "39",
    "regioner": ["Vest"],
    "fylker": [11],
    "lengde": 4400,
    "senter": {
      "type": "Point",
      "coordinates": [5.6983788, 59.08554359]
    },
    "strekningstype": "Tunnel",
    "vurdering": "IkkeRelevant",
    "fremtidigStatus": null
  }
}
```

### Fløyfjelltunnelen (Planlagt Stenging)

```json
{
  "id": "82299001",
  "properties": {
    "navn": "Fløyfjelltunnelen",
    "status": "Apen",
    "statusTungbil": "Apen",
    "fremtidigStatus": {
      "status": "Stengt",
      "startTid": "2025-12-08T20:00:00Z"
    },
    "trafikkmeldinger": ["NPRA_HBT_05-12-2025.199342"]
  }
}
```

---

## ⚠️ Viktige Notater

### Status Verdier

- **`"Apen"`** - Normal trafikk (norsk stavemåte med én P)
- **`"Stengt"`** - Tunnelen er helt stengt
- **`"Kolonnekjoring"`** - Begrenset trafikk med kolonnekjøring

### Koordinater Format

- **GeoJSON standard:** `[longitude, latitude]`
- **MERK:** Dette er **MOTSATT** av normal `[lat, lon]` rekkefølge!
- Eksempel: `[5.6983788, 59.08554359]` = Lon: 5.698, Lat: 59.085

### Tidssoner

- **`startTid`** er alltid i **UTC** (suffix `Z`)
- Konverter til norsk tid: UTC + 1 (vintertid) eller UTC + 2 (sommertid)
- Bruk `datetime.fromisoformat()` i Python for korrekt håndtering

### Trafikkmeldinger

- ID-ene refererer til interne trafikkmeldings-systemer
- For detaljert info må du bruke andre API-er (DATEX II)
- For TunnelWatch: Antall meldinger indikerer aktivitet

---

## 🚀 Fordeler Med Dette API-et

✅ **Ingen autentisering** - Helt åpent API  
✅ **Sanntidsdata** - Oppdatert kontinuerlig  
✅ **Komplett data** - Alle tunneler i Norge  
✅ **GeoJSON format** - Standardisert og lett å bruke  
✅ **Fremtidige stenginger** - Planlagte hendelser inkludert  
✅ **Både bil og tungbil** - Separate statuser  

---

## 🔗 Relaterte Endepunkter

Fjelloverganger API har sannsynligvis også:

- `/v1/fjelloverganger` - Fjelloverganger status
- `/v1/broer` - Broer (kanskje?)
- `/v1/ferger` - Ferjer (kanskje?)

*(Ikke bekreftet - test selv hvis interessert)*

---

## 📝 Lisens

Data fra Statens vegvesen er tilgjengelig under:

**Norsk lisens for offentlige data (NLOD)**

- Fri bruk til alle formål
- Må referere til Statens vegvesen som kilde
- Anbefalt referanse: *"Inneholder data under norsk lisens for offentlige data (NLOD) tilgjengeliggjort av Statens vegvesen."*

---

## 🎓 Oppsummering For TunnelWatch

**For å sjekke Mastrafjordtunnelen:**

1. Hent alle tunneler fra API-et
2. Finn tunnel med `id == "79604497"`
3. Les `properties.status`
4. Sjekk `properties.trafikkmeldinger` for antall meldinger
5. Sjekk `properties.fremtidigStatus` for planlagte stenginger
6. Oppdater database hvis status har endret seg
7. Send Signal-notifikasjon til abonnenter

**Kode:**

```python
# Se TrafficService.get_tunnel_status_by_id() i traffic_service.py
status = await traffic_service.get_tunnel_status_by_id("79604497")

if status['status'] != last_status:
    # Oppdater database
    # Send notifikasjoner
```

---

**Dokumentert:** 6. desember 2025  
**For:** TunnelWatch Norway MVP  
**Vedlikeholdt av:** Statens vegvesen