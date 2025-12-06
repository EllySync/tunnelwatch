-- ===========================================
-- TunnelWatch Norway - Seed Data
-- ===========================================
-- Run order: 02-seed.sql (after init.sql)

-- -------------------------------------------
-- MVP Tunnels: Mastrafjordtunnelen & Byfjordtunnelen
-- -------------------------------------------

-- Mastrafjordtunnelen (E39, Rogaland)
-- Source: https://fjelloverganger-backend.atlas.vegvesen.no/v1/tunneler
INSERT INTO tunnels (id, name, vegvesen_id, latitude, longitude, length, road_category, road_number, region, active)
VALUES (
    'mastrafjord',
    'Mastrafjordtunnelen',
    '79604497',
    59.08554359,
    5.6983788,
    4400,
    'E',
    '39',
    'Vest',
    true
)
ON CONFLICT (vegvesen_id) DO UPDATE SET
    name = EXCLUDED.name,
    latitude = EXCLUDED.latitude,
    longitude = EXCLUDED.longitude,
    length = EXCLUDED.length,
    road_category = EXCLUDED.road_category,
    road_number = EXCLUDED.road_number,
    region = EXCLUDED.region;

-- Byfjordtunnelen (E39, Rogaland)
-- Confirmed from Vegvesen API
INSERT INTO tunnels (id, name, vegvesen_id, latitude, longitude, length, road_category, road_number, region, active)
VALUES (
    'byfjord',
    'Byfjordtunnelen',
    '79606017',
    59.0567,
    5.7234,
    5800,
    'E',
    '39',
    'Vest',
    true
)
ON CONFLICT (vegvesen_id) DO UPDATE SET
    name = EXCLUDED.name,
    latitude = EXCLUDED.latitude,
    longitude = EXCLUDED.longitude,
    length = EXCLUDED.length,
    road_category = EXCLUDED.road_category,
    road_number = EXCLUDED.road_number,
    region = EXCLUDED.region;

-- -------------------------------------------
-- Initial Status (Open)
-- -------------------------------------------
INSERT INTO status_updates (tunnel_id, status, status_heavy_vehicle, message_no, message_en, severity)
VALUES 
    ('mastrafjord', 'open', 'open', 'Tunnelen er åpen for normal trafikk', 'Tunnel is open for normal traffic', 'low'),
    ('byfjord', 'open', 'open', 'Tunnelen er åpen for normal trafikk', 'Tunnel is open for normal traffic', 'low');
