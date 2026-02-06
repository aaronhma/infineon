-- Migration: Add music detection (Shazam) functionality
-- This allows vehicles to detect and log playing music in real-time

-- Create music_detections table
CREATE TABLE IF NOT EXISTS music_detections (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vehicle_id TEXT NOT NULL REFERENCES vehicles(id) ON DELETE CASCADE,
    session_id UUID,

    -- Song metadata
    title TEXT NOT NULL,
    artist TEXT NOT NULL,
    album TEXT,
    release_year TEXT,
    genres TEXT[], -- Array of genre strings
    label TEXT,

    -- External links
    shazam_url TEXT,
    apple_music_url TEXT,
    spotify_url TEXT,

    -- Timestamps
    detected_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Add indexes for fast lookups
CREATE INDEX idx_music_detections_vehicle_id ON music_detections(vehicle_id);
CREATE INDEX idx_music_detections_session_id ON music_detections(session_id);
CREATE INDEX idx_music_detections_detected_at ON music_detections(detected_at DESC);
CREATE INDEX idx_music_detections_vehicle_detected ON music_detections(vehicle_id, detected_at DESC);

-- Note: Duplicate prevention is handled at the application level via rate limiting
-- (ShazamRecognizer has 5s cooldown, MusicRecognizer has configurable interval)

-- Enable RLS
ALTER TABLE music_detections ENABLE ROW LEVEL SECURITY;

-- RLS Policies

-- Users can view music detections from vehicles they have access to
CREATE POLICY "Users can view music from their vehicles"
ON music_detections
FOR SELECT
USING (
    vehicle_id IN (
        SELECT vehicle_id
        FROM vehicle_access
        WHERE user_id = auth.uid()
    )
);

-- Service role can insert music detections
CREATE POLICY "Service role can insert music detections"
ON music_detections
FOR INSERT
WITH CHECK (true);

-- Service role can update music detections
CREATE POLICY "Service role can update music detections"
ON music_detections
FOR UPDATE
USING (true);

-- Add current music info to vehicle_realtime table
ALTER TABLE vehicle_realtime
ADD COLUMN IF NOT EXISTS current_song_title TEXT,
ADD COLUMN IF NOT EXISTS current_song_artist TEXT,
ADD COLUMN IF NOT EXISTS current_song_detected_at TIMESTAMPTZ;

-- Add comment for documentation
COMMENT ON TABLE music_detections IS 'Stores music detected by Shazam in vehicles during trips';
COMMENT ON COLUMN music_detections.session_id IS 'Links to vehicle_trips.session_id for trip association';
COMMENT ON COLUMN vehicle_realtime.current_song_title IS 'Currently playing song title (from Shazam)';
COMMENT ON COLUMN vehicle_realtime.current_song_artist IS 'Currently playing song artist (from Shazam)';
COMMENT ON COLUMN vehicle_realtime.current_song_detected_at IS 'When the current song was detected';
