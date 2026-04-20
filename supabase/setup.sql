-- Supabase Setup for Face Detection System
-- Run this in the Supabase SQL Editor

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================
-- STORAGE BUCKETS
-- ============================================

-- Create storage bucket for face snapshots
INSERT INTO storage.buckets (id, name, public)
VALUES ('face-snapshots', 'face-snapshots', false)
ON CONFLICT (id) DO NOTHING;

-- Create storage bucket for user profile pictures
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'user-avatars',
    'user-avatars',
    true, -- Public bucket so avatars can be displayed without signed URLs
    5242880, -- 5MB limit
    ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/heic']
)
ON CONFLICT (id) DO UPDATE SET
    public = EXCLUDED.public,
    file_size_limit = EXCLUDED.file_size_limit,
    allowed_mime_types = EXCLUDED.allowed_mime_types;

-- Create storage bucket for live video frames
INSERT INTO storage.buckets (id, name, public, file_size_limit)
VALUES (
    'live-frames',
    'live-frames',
    true,  -- Public bucket (read access via public URL)
    1048576  -- 1MB limit per file (enough for compressed JPEG frames)
)
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
    owner_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,

    -- Feature toggles (controllable from iOS app)
    enable_yolo BOOLEAN NOT NULL DEFAULT TRUE,
    enable_stream BOOLEAN NOT NULL DEFAULT TRUE,
    enable_shazam BOOLEAN NOT NULL DEFAULT TRUE,
    enable_microphone BOOLEAN NOT NULL DEFAULT TRUE,
    enable_camera BOOLEAN NOT NULL DEFAULT TRUE,
    enable_dashcam BOOLEAN NOT NULL DEFAULT FALSE
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

    -- GPS fix quality
    satellites INTEGER DEFAULT 0,

    -- Status flags
    is_speeding BOOLEAN DEFAULT FALSE,
    is_moving BOOLEAN DEFAULT FALSE,

    -- Driver status (from face detection)
    driver_status TEXT DEFAULT 'unknown', -- 'alert', 'drowsy', 'impaired', 'distracted_phone', 'distracted_drinking', 'unknown'
    intoxication_score INTEGER DEFAULT 0,

    -- Distraction detection
    is_phone_detected BOOLEAN DEFAULT FALSE,
    is_drinking_detected BOOLEAN DEFAULT FALSE,

    -- Remote buzzer control (controlled from iOS app)
    buzzer_active BOOLEAN DEFAULT FALSE,
    buzzer_type TEXT DEFAULT 'alert', -- 'alert', 'emergency', 'warning'
    buzzer_updated_at TIMESTAMPTZ,

    -- Current music info (from Shazam)
    current_song_title TEXT,
    current_song_artist TEXT,
    current_song_detected_at TIMESTAMPTZ,

    -- Gyroscope / accelerometer (from main.py on every realtime tick)
    acc_mag REAL,
    gyro_mag REAL,
    gyrox REAL,
    gyroy REAL,
    gyroz REAL,

    -- Crash detection (set immediately on impact, cleared on session reset)
    crash_detected BOOLEAN DEFAULT FALSE,
    crash_severity TEXT,
    crash_peak_g REAL
);

-- Create indexes for vehicle tables
CREATE INDEX IF NOT EXISTS idx_vehicle_access_user_id ON public.vehicle_access(user_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_access_vehicle_id ON public.vehicle_access(vehicle_id);
CREATE INDEX IF NOT EXISTS idx_vehicles_invite_code ON public.vehicles(invite_code);

-- ============================================
-- FACE DETECTIONS TABLE
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

    -- Distraction detection
    is_phone_detected BOOLEAN DEFAULT FALSE,
    is_drinking_detected BOOLEAN DEFAULT FALSE,
    is_distracted_gaze BOOLEAN DEFAULT FALSE,

    -- Gyroscope / accelerometer
    acc_mag REAL DEFAULT NULL,
    acc_delta REAL DEFAULT NULL,
    gyro_mag REAL DEFAULT NULL,
    gyrox REAL DEFAULT NULL,
    gyroy REAL DEFAULT NULL,
    gyroz REAL DEFAULT NULL,

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

-- Create indexes for faster queries
CREATE INDEX IF NOT EXISTS idx_face_detections_created_at ON public.face_detections(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_face_detections_session_id ON public.face_detections(session_id);
CREATE INDEX IF NOT EXISTS idx_face_detections_intoxication ON public.face_detections(intoxication_score) WHERE intoxication_score >= 2;
CREATE INDEX IF NOT EXISTS idx_face_detections_vehicle_id ON public.face_detections(vehicle_id);

-- ============================================
-- USER PROFILES TABLE
-- ============================================

-- User profiles: stores user preferences and profile data
CREATE TABLE IF NOT EXISTS public.user_profiles (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    user_id UUID NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,

    -- Profile info
    display_name TEXT,
    avatar_path TEXT, -- Path in user-avatars storage bucket

    -- Notification preferences (stored as JSONB for flexibility)
    notification_preferences JSONB DEFAULT '{
        "collision": true,
        "driver_drowsiness": true,
        "speed_limit": true
    }'::jsonb NOT NULL,

    -- Push notification token (for future use)
    push_token TEXT,

    -- Whether notifications are enabled at all
    notifications_enabled BOOLEAN DEFAULT false
);

CREATE INDEX IF NOT EXISTS idx_user_profiles_user_id ON public.user_profiles(user_id);

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to auto-update updated_at on user_profiles
DROP TRIGGER IF EXISTS update_user_profiles_updated_at ON public.user_profiles;
CREATE TRIGGER update_user_profiles_updated_at
    BEFORE UPDATE ON public.user_profiles
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_at_column();

-- ============================================
-- VEHICLE TRIPS TABLE
-- ============================================

-- Stores trip records for each driving session
CREATE TABLE IF NOT EXISTS public.vehicle_trips (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,

    -- Link to vehicle
    vehicle_id TEXT NOT NULL REFERENCES public.vehicles(id) ON DELETE CASCADE,

    -- Session tracking (same session_id as face_detections)
    session_id UUID NOT NULL,

    -- Trip timing
    started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ended_at TIMESTAMPTZ,

    -- Trip status (ok, warning, danger) - computed from max_intoxication_score
    status TEXT DEFAULT 'ok' CHECK (status IN ('ok', 'warning', 'danger')),

    -- Trip statistics
    max_speed_mph INTEGER DEFAULT 0,
    avg_speed_mph REAL DEFAULT 0,
    max_intoxication_score INTEGER DEFAULT 0,

    -- Event counts
    speeding_event_count INTEGER DEFAULT 0,
    drowsy_event_count INTEGER DEFAULT 0,
    excessive_blinking_event_count INTEGER DEFAULT 0,
    unstable_eyes_event_count INTEGER DEFAULT 0,
    face_detection_count INTEGER DEFAULT 0,

    -- Distraction event counts
    phone_distraction_event_count INTEGER DEFAULT 0,
    drinking_event_count INTEGER DEFAULT 0,
    distracted_gaze_event_count INTEGER DEFAULT 0,

    -- Speed samples for average calculation
    speed_sample_count INTEGER DEFAULT 0,
    speed_sample_sum INTEGER DEFAULT 0,

    -- GPS route waypoints (JSONB array of {lat, lng, spd, ts})
    route_waypoints JSONB DEFAULT '[]'::jsonb,

    -- Crash detection
    crash_detected BOOLEAN DEFAULT FALSE,
    crash_severity TEXT DEFAULT NULL
);

CREATE INDEX IF NOT EXISTS idx_vehicle_trips_vehicle_id ON public.vehicle_trips(vehicle_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_trips_session_id ON public.vehicle_trips(session_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_trips_started_at ON public.vehicle_trips(started_at DESC);
CREATE INDEX IF NOT EXISTS idx_vehicle_trips_status ON public.vehicle_trips(status);

-- ============================================
-- MUSIC DETECTIONS TABLE
-- ============================================

CREATE TABLE IF NOT EXISTS public.music_detections (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vehicle_id TEXT NOT NULL REFERENCES public.vehicles(id) ON DELETE CASCADE,
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

CREATE INDEX IF NOT EXISTS idx_music_detections_vehicle_id ON public.music_detections(vehicle_id);
CREATE INDEX IF NOT EXISTS idx_music_detections_session_id ON public.music_detections(session_id);
CREATE INDEX IF NOT EXISTS idx_music_detections_detected_at ON public.music_detections(detected_at DESC);
CREATE INDEX IF NOT EXISTS idx_music_detections_vehicle_detected ON public.music_detections(vehicle_id, detected_at DESC);

COMMENT ON TABLE public.music_detections IS 'Stores music detected by Shazam in vehicles during trips';
COMMENT ON COLUMN public.music_detections.session_id IS 'Links to vehicle_trips.session_id for trip association';

-- ============================================
-- ROW LEVEL SECURITY POLICIES
-- ============================================

-- Enable RLS on all tables
ALTER TABLE public.vehicles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vehicle_access ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vehicle_realtime ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.face_detections ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vehicle_trips ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.music_detections ENABLE ROW LEVEL SECURITY;

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

-- NOTE: DO NOT add policies that query vehicles table from vehicle_access or vice versa,
-- as this creates infinite recursion (vehicles policy queries vehicle_access,
-- and if vehicle_access policy queries vehicles, it loops forever).
-- The get_vehicle_access_users() function uses SECURITY DEFINER to bypass RLS.

-- ============================================
-- VEHICLE REALTIME TABLE POLICIES
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

-- Authenticated users can UPDATE buzzer control for vehicles they have access to
CREATE POLICY "vehicle_realtime_update_buzzer_with_access" ON public.vehicle_realtime
    FOR UPDATE TO authenticated
    USING (
        vehicle_id IN (
            SELECT vehicle_id FROM public.vehicle_access
            WHERE user_id = auth.uid()
        )
    )
    WITH CHECK (
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
-- USER PROFILES TABLE POLICIES
-- ============================================

-- Users can read their own profile
CREATE POLICY "user_profiles_select_own" ON public.user_profiles
    FOR SELECT TO authenticated
    USING (user_id = auth.uid());

-- Users can insert their own profile
CREATE POLICY "user_profiles_insert_own" ON public.user_profiles
    FOR INSERT TO authenticated
    WITH CHECK (user_id = auth.uid());

-- Users can update their own profile
CREATE POLICY "user_profiles_update_own" ON public.user_profiles
    FOR UPDATE TO authenticated
    USING (user_id = auth.uid())
    WITH CHECK (user_id = auth.uid());

-- Users can delete their own profile
CREATE POLICY "user_profiles_delete_own" ON public.user_profiles
    FOR DELETE TO authenticated
    USING (user_id = auth.uid());

-- Service role can do everything (for admin purposes)
CREATE POLICY "user_profiles_service_role_all" ON public.user_profiles
    FOR ALL TO service_role
    USING (true) WITH CHECK (true);

-- Allow reading profiles of users who share vehicle access
CREATE POLICY "user_profiles_select_vehicle_shared" ON public.user_profiles
    FOR SELECT TO authenticated
    USING (
        user_id IN (
            SELECT va.user_id FROM public.vehicle_access va
            WHERE va.vehicle_id IN (
                SELECT va2.vehicle_id FROM public.vehicle_access va2
                WHERE va2.user_id = auth.uid()
            )
        )
        OR
        user_id IN (
            SELECT v.owner_id FROM public.vehicles v
            WHERE v.id IN (
                SELECT va.vehicle_id FROM public.vehicle_access va
                WHERE va.user_id = auth.uid()
            )
        )
    );

-- ============================================
-- VEHICLE TRIPS TABLE POLICIES
-- ============================================

-- Service role can do everything (for main.py to insert/update via service key)
CREATE POLICY "vehicle_trips_service_role_all" ON public.vehicle_trips
    FOR ALL TO service_role
    USING (true) WITH CHECK (true);

-- Authenticated users can read trips for vehicles they have access to
CREATE POLICY "vehicle_trips_select_with_access" ON public.vehicle_trips
    FOR SELECT TO authenticated
    USING (
        vehicle_id IN (
            SELECT vehicle_id FROM public.vehicle_access
            WHERE user_id = auth.uid()
        )
    );

-- ============================================
-- MUSIC DETECTIONS TABLE POLICIES
-- ============================================

-- Users can view music detections from vehicles they have access to
CREATE POLICY "Users can view music from their vehicles"
ON public.music_detections
FOR SELECT
USING (
    vehicle_id IN (
        SELECT vehicle_id
        FROM public.vehicle_access
        WHERE user_id = auth.uid()
    )
);

-- Service role can insert music detections
CREATE POLICY "Service role can insert music detections"
ON public.music_detections
FOR INSERT
WITH CHECK (true);

-- Service role can update music detections
CREATE POLICY "Service role can update music detections"
ON public.music_detections
FOR UPDATE
USING (true);

-- ============================================
-- STORAGE POLICIES
-- ============================================

-- --- face-snapshots ---

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

-- --- user-avatars ---

-- Users can upload to their own folder (path starts with their user_id)
CREATE POLICY "user_avatars_insert_own" ON storage.objects
    FOR INSERT TO authenticated
    WITH CHECK (
        bucket_id = 'user-avatars'
        AND name LIKE (auth.uid()::text || '/%')
    );

-- Users can update files in their own folder
CREATE POLICY "user_avatars_update_own" ON storage.objects
    FOR UPDATE TO authenticated
    USING (
        bucket_id = 'user-avatars'
        AND name LIKE (auth.uid()::text || '/%')
    )
    WITH CHECK (
        bucket_id = 'user-avatars'
        AND name LIKE (auth.uid()::text || '/%')
    );

-- Users can delete files in their own folder
CREATE POLICY "user_avatars_delete_own" ON storage.objects
    FOR DELETE TO authenticated
    USING (
        bucket_id = 'user-avatars'
        AND name LIKE (auth.uid()::text || '/%')
    );

-- Anyone can read avatars (public bucket)
CREATE POLICY "user_avatars_select_public" ON storage.objects
    FOR SELECT TO public
    USING (bucket_id = 'user-avatars');

-- Also allow anon role to read (for unauthenticated access to public bucket)
CREATE POLICY "user_avatars_select_anon" ON storage.objects
    FOR SELECT TO anon
    USING (bucket_id = 'user-avatars');

-- --- live-frames ---

-- Service role (backend) can do everything
CREATE POLICY "live_frames_service_role_all"
ON storage.objects
FOR ALL
TO service_role
USING (bucket_id = 'live-frames')
WITH CHECK (bucket_id = 'live-frames');

-- Authenticated users can download frames from vehicles they have access to
-- Uses SECURITY DEFINER function to avoid RLS recursion issues
CREATE POLICY "live_frames_select_with_vehicle_access"
ON storage.objects
FOR SELECT
TO authenticated
USING (
    bucket_id = 'live-frames'
    AND public.user_has_vehicle_access((storage.foldername(name))[1])
);

-- ============================================
-- ENABLE REALTIME
-- ============================================

-- Enable realtime for vehicle_realtime table (for iOS app subscriptions)
ALTER PUBLICATION supabase_realtime ADD TABLE public.vehicle_realtime;

-- Enable realtime for vehicle_trips table (for iOS app subscriptions)
ALTER PUBLICATION supabase_realtime ADD TABLE public.vehicle_trips;

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

GRANT EXECUTE ON FUNCTION public.join_vehicle_by_invite_code(TEXT) TO authenticated;

-- Helper function to check if user has access to a vehicle
-- Uses SECURITY DEFINER to bypass RLS when checking storage access
CREATE OR REPLACE FUNCTION public.user_has_vehicle_access(p_vehicle_id TEXT)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM public.vehicle_access
        WHERE user_id = auth.uid() AND vehicle_id = p_vehicle_id
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

GRANT EXECUTE ON FUNCTION public.user_has_vehicle_access(TEXT) TO authenticated;

-- ============================================
-- VEHICLE ACCESS MANAGEMENT FUNCTIONS
-- ============================================

-- Returns all users who have access to a vehicle, including the owner
DROP FUNCTION IF EXISTS public.get_vehicle_access_users(TEXT);

CREATE FUNCTION public.get_vehicle_access_users(p_vehicle_id TEXT)
RETURNS TABLE (
    access_id UUID,
    user_id UUID,
    display_name TEXT,
    email TEXT,
    avatar_path TEXT,
    access_level TEXT,
    is_owner BOOLEAN
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, auth
AS $$
    SELECT
        va.id AS access_id,
        va.user_id,
        up.display_name,
        au.email,
        up.avatar_path,
        va.access_level,
        (v.owner_id = va.user_id) AS is_owner
    FROM public.vehicle_access va
    JOIN auth.users au ON au.id = va.user_id
    LEFT JOIN public.user_profiles up ON up.user_id = va.user_id
    JOIN public.vehicles v ON v.id = va.vehicle_id
    WHERE va.vehicle_id = p_vehicle_id
    AND EXISTS (
        SELECT 1 FROM public.vehicle_access check_access
        WHERE check_access.vehicle_id = p_vehicle_id
        AND check_access.user_id = auth.uid()
    )
    ORDER BY (v.owner_id = va.user_id) DESC, up.display_name ASC NULLS LAST, au.email ASC;
$$;

GRANT EXECUTE ON FUNCTION public.get_vehicle_access_users(TEXT) TO authenticated;

-- Allows vehicle owner to remove other users' access
CREATE OR REPLACE FUNCTION public.remove_vehicle_access(p_vehicle_id TEXT, p_user_id TEXT)
RETURNS JSONB AS $$
DECLARE
    v_owner_id UUID;
    v_target_user_id UUID;
BEGIN
    -- Parse the target user ID
    v_target_user_id := p_user_id::UUID;

    -- Get the vehicle owner
    SELECT owner_id INTO v_owner_id
    FROM public.vehicles
    WHERE id = p_vehicle_id;

    -- Check if the calling user is the owner
    IF v_owner_id IS NULL OR v_owner_id != auth.uid() THEN
        RAISE EXCEPTION 'Access denied: Only the vehicle owner can remove other users'' access';
    END IF;

    -- Prevent owner from removing themselves
    IF v_target_user_id = auth.uid() THEN
        RAISE EXCEPTION 'Cannot remove owner: Use leave_vehicle to transfer ownership first';
    END IF;

    -- Delete the access record
    DELETE FROM public.vehicle_access
    WHERE vehicle_id = p_vehicle_id
    AND user_id = v_target_user_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'User does not have access to this vehicle');
    END IF;

    RETURN jsonb_build_object('success', true);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.remove_vehicle_access(TEXT, TEXT) TO authenticated;

-- ============================================
-- USER PROFILE FUNCTIONS
-- ============================================

-- Function to get or create a user profile
CREATE OR REPLACE FUNCTION public.get_or_create_user_profile()
RETURNS public.user_profiles AS $$
DECLARE
    v_profile public.user_profiles;
BEGIN
    -- Try to get existing profile
    SELECT * INTO v_profile
    FROM public.user_profiles
    WHERE user_id = auth.uid();

    -- If not found, create one
    IF v_profile IS NULL THEN
        INSERT INTO public.user_profiles (user_id)
        VALUES (auth.uid())
        RETURNING * INTO v_profile;
    END IF;

    RETURN v_profile;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.get_or_create_user_profile() TO authenticated;

-- Function to update user profile with optional fields
CREATE OR REPLACE FUNCTION public.update_user_profile(
    p_display_name TEXT DEFAULT NULL,
    p_avatar_path TEXT DEFAULT NULL,
    p_notification_preferences JSONB DEFAULT NULL,
    p_notifications_enabled BOOLEAN DEFAULT NULL,
    p_push_token TEXT DEFAULT NULL
)
RETURNS public.user_profiles AS $$
DECLARE
    v_profile public.user_profiles;
BEGIN
    -- Ensure profile exists
    PERFORM public.get_or_create_user_profile();

    -- Update only provided fields
    UPDATE public.user_profiles
    SET
        display_name = COALESCE(p_display_name, display_name),
        avatar_path = COALESCE(p_avatar_path, avatar_path),
        notification_preferences = COALESCE(p_notification_preferences, notification_preferences),
        notifications_enabled = COALESCE(p_notifications_enabled, notifications_enabled),
        push_token = COALESCE(p_push_token, push_token)
    WHERE user_id = auth.uid()
    RETURNING * INTO v_profile;

    RETURN v_profile;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.update_user_profile(TEXT, TEXT, JSONB, BOOLEAN, TEXT) TO authenticated;

-- ============================================
-- REMOTE BUZZER CONTROL FUNCTIONS
-- ============================================

-- Function to activate buzzer remotely
CREATE OR REPLACE FUNCTION public.activate_vehicle_buzzer(
    p_vehicle_id TEXT,
    p_buzzer_type TEXT DEFAULT 'alert'
)
RETURNS JSONB AS $$
DECLARE
    v_has_access BOOLEAN;
BEGIN
    -- Check if user has access to this vehicle
    SELECT EXISTS (
        SELECT 1 FROM public.vehicle_access
        WHERE user_id = auth.uid() AND vehicle_id = p_vehicle_id
    ) INTO v_has_access;

    IF NOT v_has_access THEN
        RETURN jsonb_build_object('success', false, 'error', 'Access denied');
    END IF;

    -- Activate buzzer
    UPDATE public.vehicle_realtime
    SET
        buzzer_active = TRUE,
        buzzer_type = p_buzzer_type,
        buzzer_updated_at = NOW()
    WHERE vehicle_id = p_vehicle_id;

    RETURN jsonb_build_object(
        'success', true,
        'vehicle_id', p_vehicle_id,
        'buzzer_type', p_buzzer_type
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to deactivate buzzer remotely
CREATE OR REPLACE FUNCTION public.deactivate_vehicle_buzzer(p_vehicle_id TEXT)
RETURNS JSONB AS $$
DECLARE
    v_has_access BOOLEAN;
BEGIN
    -- Check if user has access to this vehicle
    SELECT EXISTS (
        SELECT 1 FROM public.vehicle_access
        WHERE user_id = auth.uid() AND vehicle_id = p_vehicle_id
    ) INTO v_has_access;

    IF NOT v_has_access THEN
        RETURN jsonb_build_object('success', false, 'error', 'Access denied');
    END IF;

    -- Deactivate buzzer
    UPDATE public.vehicle_realtime
    SET
        buzzer_active = FALSE,
        buzzer_updated_at = NOW()
    WHERE vehicle_id = p_vehicle_id;

    RETURN jsonb_build_object(
        'success', true,
        'vehicle_id', p_vehicle_id
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.activate_vehicle_buzzer(TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.deactivate_vehicle_buzzer(TEXT) TO authenticated;
