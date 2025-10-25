-- Dynamic Pricing Database Schema

-- Zone window metrics for historical analysis
CREATE TABLE zone_window_metrics (
    zone_id INTEGER NOT NULL,
    window_start TIMESTAMPTZ NOT NULL,
    window_end TIMESTAMPTZ NOT NULL,
    demand INTEGER NOT NULL DEFAULT 0,
    supply INTEGER NOT NULL DEFAULT 0,
    ratio DECIMAL(10,4) NOT NULL DEFAULT 0,
    surge_multiplier DECIMAL(4,2) NOT NULL DEFAULT 1.0,
    ts_compute TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT pk_zone_window_metrics PRIMARY KEY (zone_id, window_start)
);

-- Current price snapshot per zone (latest state)
CREATE TABLE zone_price_snapshot (
    zone_id INTEGER NOT NULL,
    surge_multiplier DECIMAL(4,2) NOT NULL DEFAULT 1.0,
    demand INTEGER NOT NULL DEFAULT 0,
    supply INTEGER NOT NULL DEFAULT 0,
    ratio DECIMAL(10,4) NOT NULL DEFAULT 0,
    window_start TIMESTAMPTZ NOT NULL,
    window_end TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT pk_zone_price_snapshot PRIMARY KEY (zone_id)
);

-- Base fare configuration per zone
CREATE TABLE fare_config (
    zone_id INTEGER NOT NULL,
    base_fare DECIMAL(8,2) NOT NULL,
    distance_rate DECIMAL(6,2) NOT NULL, -- per km
    time_rate DECIMAL(6,2) NOT NULL,     -- per minute
    minimum_fare DECIMAL(8,2) NOT NULL,
    zone_type VARCHAR(20) NOT NULL DEFAULT 'STANDARD',
    active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT pk_fare_config PRIMARY KEY (zone_id)
);

-- Create indexes for performance
CREATE INDEX idx_zone_window_metrics_zone_time ON zone_window_metrics(zone_id, window_start DESC);
CREATE INDEX idx_zone_window_metrics_compute_time ON zone_window_metrics(ts_compute);
CREATE INDEX idx_zone_price_snapshot_updated ON zone_price_snapshot(updated_at);

-- Insert realistic fare configurations based on zone types (16 zones total)
-- Zones 1-4: DOWNTOWN (Premium - Business district, high demand)
INSERT INTO fare_config (zone_id, base_fare, distance_rate, time_rate, minimum_fare, zone_type)
SELECT 
    zone_id,
    8.00 + (RANDOM() * 2.00)::DECIMAL(8,2) as base_fare,      -- R$ 8.00-10.00
    2.80 + (RANDOM() * 0.40)::DECIMAL(6,2) as distance_rate,  -- R$ 2.80-3.20/km  
    0.65 + (RANDOM() * 0.15)::DECIMAL(6,2) as time_rate,      -- R$ 0.65-0.80/min
    9.50 + (RANDOM() * 1.50)::DECIMAL(8,2) as minimum_fare,   -- R$ 9.50-11.00
    'DOWNTOWN'
FROM generate_series(1, 4) as zone_id;

-- Zones 5-8: URBAN (Standard - Residential/Commercial mix)
INSERT INTO fare_config (zone_id, base_fare, distance_rate, time_rate, minimum_fare, zone_type)
SELECT 
    zone_id,
    5.50 + (RANDOM() * 1.50)::DECIMAL(8,2) as base_fare,      -- R$ 5.50-7.00
    2.20 + (RANDOM() * 0.30)::DECIMAL(6,2) as distance_rate,  -- R$ 2.20-2.50/km
    0.45 + (RANDOM() * 0.15)::DECIMAL(6,2) as time_rate,      -- R$ 0.45-0.60/min
    6.00 + (RANDOM() * 1.00)::DECIMAL(8,2) as minimum_fare,   -- R$ 6.00-7.00
    'URBAN'
FROM generate_series(5, 8) as zone_id;

-- Zones 9-12: SUBURBAN (Economy - Residential suburbs)
INSERT INTO fare_config (zone_id, base_fare, distance_rate, time_rate, minimum_fare, zone_type)
SELECT 
    zone_id,
    4.00 + (RANDOM() * 1.00)::DECIMAL(8,2) as base_fare,      -- R$ 4.00-5.00
    1.80 + (RANDOM() * 0.20)::DECIMAL(6,2) as distance_rate,  -- R$ 1.80-2.00/km
    0.30 + (RANDOM() * 0.10)::DECIMAL(6,2) as time_rate,      -- R$ 0.30-0.40/min
    4.50 + (RANDOM() * 0.50)::DECIMAL(8,2) as minimum_fare,   -- R$ 4.50-5.00
    'SUBURBAN'
FROM generate_series(9, 12) as zone_id;

-- Zones 13-16: AIRPORT/SPECIAL (Premium routes - Airport, events, etc.)
INSERT INTO fare_config (zone_id, base_fare, distance_rate, time_rate, minimum_fare, zone_type)
SELECT 
    zone_id,
    12.00 + (RANDOM() * 3.00)::DECIMAL(8,2) as base_fare,     -- R$ 12.00-15.00
    3.50 + (RANDOM() * 0.50)::DECIMAL(6,2) as distance_rate,  -- R$ 3.50-4.00/km
    0.80 + (RANDOM() * 0.20)::DECIMAL(6,2) as time_rate,      -- R$ 0.80-1.00/min
    15.00 + (RANDOM() * 2.00)::DECIMAL(8,2) as minimum_fare,  -- R$ 15.00-17.00
    'AIRPORT'
FROM generate_series(13, 16) as zone_id;

-- Sample price snapshots representing different demand scenarios (16 zones)
INSERT INTO zone_price_snapshot (zone_id, surge_multiplier, demand, supply, ratio, window_start, window_end)
VALUES 
    -- High demand downtown zones (rush hour)
    (1, 2.3, 28, 12, 2.33, NOW() - INTERVAL '1 minute', NOW() - INTERVAL '46 seconds'),
    (3, 1.8, 18, 10, 1.80, NOW() - INTERVAL '1 minute', NOW() - INTERVAL '46 seconds'),
    
    -- Normal urban zones
    (6, 1.0, 8, 15, 0.53, NOW() - INTERVAL '1 minute', NOW() - INTERVAL '46 seconds'),
    (8, 1.1, 12, 11, 1.09, NOW() - INTERVAL '1 minute', NOW() - INTERVAL '46 seconds'),
    
    -- Suburban zones
    (10, 1.0, 5, 12, 0.42, NOW() - INTERVAL '1 minute', NOW() - INTERVAL '46 seconds'),
    (12, 1.2, 8, 9, 0.89, NOW() - INTERVAL '1 minute', NOW() - INTERVAL '46 seconds'),
    
    -- Airport with moderate surge
    (14, 1.5, 15, 10, 1.50, NOW() - INTERVAL '1 minute', NOW() - INTERVAL '46 seconds'),
    (16, 2.0, 22, 11, 2.00, NOW() - INTERVAL '1 minute', NOW() - INTERVAL '46 seconds');

-- Grant permissions
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO pricing;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO pricing;