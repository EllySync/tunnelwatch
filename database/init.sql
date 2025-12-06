-- ===========================================
-- TunnelWatch Norway - Database Schema
-- ===========================================
-- Run order: 01-init.sql (this file)

-- -------------------------------------------
-- Table: tunnels
-- -------------------------------------------
-- Stores tunnel metadata from Vegvesen API
CREATE TABLE IF NOT EXISTS tunnels (
    id VARCHAR(50) PRIMARY KEY,
    name VARCHAR(200) NOT NULL,
    vegvesen_id VARCHAR(100) UNIQUE NOT NULL,
    latitude NUMERIC(10, 7) NOT NULL,
    longitude NUMERIC(10, 7) NOT NULL,
    length INTEGER,
    road_category VARCHAR(10),
    road_number VARCHAR(10),
    region VARCHAR(50),
    active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_tunnels_vegvesen_id ON tunnels(vegvesen_id);
CREATE INDEX idx_tunnels_active ON tunnels(active);

-- -------------------------------------------
-- Table: status_updates
-- -------------------------------------------
-- Stores historical status changes
CREATE TABLE IF NOT EXISTS status_updates (
    id SERIAL PRIMARY KEY,
    tunnel_id VARCHAR(50) REFERENCES tunnels(id) ON DELETE CASCADE,
    status VARCHAR(50) NOT NULL,
    status_heavy_vehicle VARCHAR(50),
    message_no TEXT,
    message_en TEXT,
    severity VARCHAR(20),
    traffic_messages JSONB DEFAULT '[]',
    expected_change TIMESTAMP WITH TIME ZONE,
    expected_status VARCHAR(50),
    raw_data JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_status_tunnel_id ON status_updates(tunnel_id);
CREATE INDEX idx_status_created_at ON status_updates(created_at DESC);
CREATE INDEX idx_status_tunnel_created ON status_updates(tunnel_id, created_at DESC);

-- -------------------------------------------
-- Table: subscriptions
-- -------------------------------------------
-- Stores Signal notification subscriptions
CREATE TABLE IF NOT EXISTS subscriptions (
    id SERIAL PRIMARY KEY,
    phone_number VARCHAR(20) NOT NULL,
    tunnel_id VARCHAR(50) REFERENCES tunnels(id) ON DELETE CASCADE,
    language VARCHAR(5) DEFAULT 'no',
    active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(phone_number, tunnel_id)
);

CREATE INDEX idx_subscriptions_phone ON subscriptions(phone_number);
CREATE INDEX idx_subscriptions_tunnel ON subscriptions(tunnel_id);
CREATE INDEX idx_subscriptions_active ON subscriptions(active);

-- -------------------------------------------
-- Triggers: Auto-update updated_at
-- -------------------------------------------
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_tunnels_updated_at 
    BEFORE UPDATE ON tunnels
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_subscriptions_updated_at 
    BEFORE UPDATE ON subscriptions
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- -------------------------------------------
-- View: tunnel_current_status
-- -------------------------------------------
-- Easy access to current status of all tunnels
CREATE OR REPLACE VIEW tunnel_current_status AS
SELECT DISTINCT ON (t.id)
    t.id,
    t.name,
    t.vegvesen_id,
    t.latitude,
    t.longitude,
    t.length,
    t.road_category,
    t.road_number,
    t.region,
    t.active,
    COALESCE(su.status, 'unknown') as status,
    su.status_heavy_vehicle,
    su.message_no,
    su.message_en,
    su.severity,
    su.traffic_messages,
    su.expected_change,
    su.expected_status,
    su.created_at as status_updated_at
FROM tunnels t
LEFT JOIN status_updates su ON t.id = su.tunnel_id
WHERE t.active = true
ORDER BY t.id, su.created_at DESC NULLS LAST;

-- -------------------------------------------
-- View: subscription_details
-- -------------------------------------------
-- Subscriptions with tunnel info
CREATE OR REPLACE VIEW subscription_details AS
SELECT 
    s.id,
    s.phone_number,
    s.language,
    s.active,
    t.id as tunnel_id,
    t.name as tunnel_name
FROM subscriptions s
JOIN tunnels t ON s.tunnel_id = t.id
WHERE s.active = true AND t.active = true;
