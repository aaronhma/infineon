-- Supabase Setup for Face Detection System
-- Run this in the Supabase SQL Editor

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Create storage bucket for face snapshots
INSERT INTO storage.buckets (id, name, public)
VALUES ('face-snapshots', 'face-snapshots', false)
ON CONFLICT (id) DO NOTHING;

-- ============================================
-- VEHICLE MANAGEMENT TABLES
-- ============================================

-- Vehicles table: stores vehicle information and invite codes
CREATE TABLE IF NOT EXISTS public.vehicles (
    id TEXT PRIMARY KEY, -- Vehicle ID (set in .env)
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,

    -- Vehicle info
    name TEXT,
    description TEXT,

    -- Invite code for sharing access (6-digit alphanumeric)
    invite_code TEXT UNIQUE NOT NULL,

    -- Owner (optional, for future use)
    owner_id UUID REFERENCES auth.users(id) ON DELETE SET NULL
);

-- Generate random 6-character alphanumeric invite code
CREATE OR REPLACE FUNCTION generate_invite_code()
RETURNS TEXT AS $$
DECLARE
    chars TEXT := 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    result TEXT := '';
    i INTEGER;
BEGIN
    FOR i IN 1..6 LOOP
        result := result || substr(chars, floor(random() * length(chars) + 1)::int, 1);
    END LOOP;
    RETURN result;
END;
$$ LANGUAGE plpgsql;

-- Vehicle access table: tracks which users have access to which vehicles
CREATE TABLE IF NOT EXISTS public.vehicle_access (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,

    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    vehicle_id TEXT NOT NULL REFERENCES public.vehicles(id) ON DELETE CASCADE,

    -- Access level (for future use: 'viewer', 'admin', etc.)
    access_level TEXT DEFAULT 'viewer',

    UNIQUE(user_id, vehicle_id)
);

-- Vehicle real-time location table: stores current location/speed (one row per vehicle)
CREATE TABLE IF NOT EXISTS public.vehicle_realtime (
    vehicle_id TEXT PRIMARY KEY REFERENCES public.vehicles(id) ON DELETE CASCADE,
    updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,

    -- Location (for future GPS integration)
    latitude DOUBLE PRECISION,
    longitude DOUBLE PRECISION,

    -- Speed and direction
    speed_mph INTEGER DEFAULT 0,
    speed_limit_mph INTEGER DEFAULT 65,
    heading_degrees INTEGER DEFAULT 0, -- 0-359
    compass_direction TEXT DEFAULT 'N', -- N, NE, E, SE, S, SW, W, NW

    -- Status flags
    is_speeding BOOLEAN DEFAULT FALSE,
    is_moving BOOLEAN DEFAULT FALSE,

    -- Driver status (from face detection)
    driver_status TEXT DEFAULT 'unknown', -- 'alert', 'drowsy', 'impaired', 'unknown'
    intoxication_score INTEGER DEFAULT 0
);

-- Create indexes for vehicle tables
CREATE INDEX IF NOT EXISTS idx_vehicle_access_user_id ON public.vehicle_access(user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_access_vehicle_id ON public.vehicle_access(vehicle_id);
CREATE INDEX IF NOT EXISTS idx_vehicles_invite_code ON public.vehicles(invite_code);

-- ============================================
-- FACE DETECTIONS TABLE (updated with vehicle_id)
-- ============================================

-- Create table for face detection events
CREATE TABLE IF NOT EXISTS public.face_detections (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,

    -- Link to vehicle
    vehicle_id TEXT REFERENCES public.vehicles(id) ON DELETE CASCADE,

    -- Face detection metadata
    face_bbox JSONB, -- {x_min, y_min, x_max, y_max}

    -- Eye state data
    left_eye_state TEXT, -- 'OPEN' or 'CLOSED'
    left_eye_ear REAL, -- Eye Aspect Ratio (0-1)
    right_eye_state TEXT,
    right_eye_ear REAL,
    avg_ear REAL,

    -- Intoxication indicators
    is_drowsy BOOLEAN DEFAULT FALSE,
    is_excessive_blinking BOOLEAN DEFAULT FALSE,
    is_unstable_eyes BOOLEAN DEFAULT FALSE,
    intoxication_score INTEGER DEFAULT 0, -- 0-6 scale

    -- Driving context (if available)
    speed_mph INTEGER,
    heading_degrees INTEGER,
    compass_direction TEXT,
    is_speeding BOOLEAN DEFAULT FALSE,

    -- Image reference
    image_path TEXT, -- Path in storage bucket

    -- Session tracking
    session_id UUID DEFAULT uuid_generate_v4()
);

-- Create index for faster queries
CREATE INDEX IF NOT EXISTS idx_face_detections_created_at ON public.face_detections(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_face_detections_session_id ON public.face_detections(session_id);
CREATE INDEX IF NOT EXISTS idx_face_detections_intoxication ON public.face_detections(intoxication_score) WHERE intoxication_score >= 2;
CREATE INDEX IF NOT EXISTS idx_face_detections_vehicle_id ON public.face_detections(vehicle_id);

-- ============================================
-- ROW LEVEL SECURITY POLICIES
-- ============================================

-- Enable RLS on all tables
ALTER TABLE public.vehicles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vehicle_access ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vehicle_realtime ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.face_detections ENABLE ROW LEVEL SECURITY;

-- ============================================
-- VEHICLES TABLE POLICIES
-- ============================================

-- Service role can do everything (for main.py to register vehicles)
CREATE POLICY "vehicles_service_role_all" ON public.vehicles
    FOR ALL TO service_role
    USING (true) WITH CHECK (true);

-- Authenticated users can read vehicles they have access to
CREATE POLICY "vehicles_select_with_access" ON public.vehicles
    FOR SELECT TO authenticated
    USING (
        id IN (
            SELECT vehicle_id FROM public.vehicle_access
            WHERE user_id = auth.uid()
        )
    );

-- ============================================
-- VEHICLE ACCESS TABLE POLICIES
-- ============================================

-- Service role can do everything
CREATE POLICY "vehicle_access_service_role_all" ON public.vehicle_access
    FOR ALL TO service_role
    USING (true) WITH CHECK (true);

-- Users can see their own access records
CREATE POLICY "vehicle_access_select_own" ON public.vehicle_access
    FOR SELECT TO authenticated
    USING (user_id = auth.uid());

-- Users can delete their own access (leave a vehicle)
CREATE POLICY "vehicle_access_delete_own" ON public.vehicle_access
    FOR DELETE TO authenticated
    USING (user_id = auth.uid());

-- ============================================
-- VEHICLE REALTIME TABLE POLICIES (for iOS app)
-- ============================================

-- Service role can do everything (main.py updates via service key)
CREATE POLICY "vehicle_realtime_service_role_all" ON public.vehicle_realtime
    FOR ALL TO service_role
    USING (true) WITH CHECK (true);

-- Authenticated users can only READ vehicles they have access to
CREATE POLICY "vehicle_realtime_select_with_access" ON public.vehicle_realtime
    FOR SELECT TO authenticated
    USING (
        vehicle_id IN (
            SELECT vehicle_id FROM public.vehicle_access
            WHERE user_id = auth.uid()
        )
    );

-- ============================================
-- FACE DETECTIONS TABLE POLICIES
-- ============================================

-- Service role can do everything (main.py inserts via service key)
CREATE POLICY "face_detections_service_role_all" ON public.face_detections
    FOR ALL TO service_role
    USING (true) WITH CHECK (true);

-- Authenticated users can read detections for vehicles they have access to
CREATE POLICY "face_detections_select_with_access" ON public.face_detections
    FOR SELECT TO authenticated
    USING (
        vehicle_id IN (
            SELECT vehicle_id FROM public.vehicle_access
            WHERE user_id = auth.uid()
        )
    );

-- ============================================
-- STORAGE POLICIES
-- ============================================

-- Service role full access to storage
CREATE POLICY "storage_service_role_all" ON storage.objects
    FOR ALL TO service_role
    USING (bucket_id = 'face-snapshots')
    WITH CHECK (bucket_id = 'face-snapshots');

-- Authenticated users can read images for vehicles they have access to
-- (images are stored as {vehicle_id}/{session_id}/{timestamp}.jpg)
CREATE POLICY "storage_select_with_vehicle_access" ON storage.objects
    FOR SELECT TO authenticated
    USING (
        bucket_id = 'face-snapshots'
        AND (storage.foldername(name))[1] IN (
            SELECT vehicle_id FROM public.vehicle_access
            WHERE user_id = auth.uid()
        )
    );

-- ============================================
-- ENABLE REALTIME
-- ============================================

-- Enable realtime for vehicle_realtime table (for iOS app subscriptions)
ALTER PUBLICATION supabase_realtime ADD TABLE public.vehicle_realtime;

-- ============================================
-- HELPER FUNCTIONS
-- ============================================

-- Function to join a vehicle using invite code
CREATE OR REPLACE FUNCTION public.join_vehicle_by_invite_code(p_invite_code TEXT)
RETURNS JSONB AS $$
DECLARE
    v_vehicle_id TEXT;
    v_vehicle_name TEXT;
BEGIN
    -- Find vehicle by invite code
    SELECT id, name INTO v_vehicle_id, v_vehicle_name
    FROM public.vehicles
    WHERE invite_code = UPPER(p_invite_code);

    IF v_vehicle_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Invalid invite code');
    END IF;

    -- Check if user already has access
    IF EXISTS (
        SELECT 1 FROM public.vehicle_access
        WHERE user_id = auth.uid() AND vehicle_id = v_vehicle_id
    ) THEN
        RETURN jsonb_build_object('success', false, 'error', 'Already have access to this vehicle');
    END IF;

    -- Grant access
    INSERT INTO public.vehicle_access (user_id, vehicle_id, access_level)
    VALUES (auth.uid(), v_vehicle_id, 'viewer');

    RETURN jsonb_build_object(
        'success', true,
        'vehicle_id', v_vehicle_id,
        'vehicle_name', v_vehicle_name
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION public.join_vehicle_by_invite_code(TEXT) TO authenticated;
