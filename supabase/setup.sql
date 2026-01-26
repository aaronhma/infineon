-- Supabase Setup for Face Detection System
-- Run this in the Supabase SQL Editor

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Enable pgvector extension for face embedding storage and similarity search
CREATE EXTENSION IF NOT EXISTS vector;

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

-- ============================================
-- DRIVER PROFILES TABLE
-- ============================================

-- Driver profiles: named faces for identification
CREATE TABLE IF NOT EXISTS public.driver_profiles (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,

    -- Link to vehicle (drivers are per-vehicle)
    vehicle_id TEXT NOT NULL REFERENCES public.vehicles(id) ON DELETE CASCADE,

    -- Driver info
    name TEXT NOT NULL,
    notes TEXT,

    -- Reference face image (path in storage bucket)
    profile_image_path TEXT,

    -- Created by user
    created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_driver_profiles_vehicle_id ON public.driver_profiles(vehicle_id);

-- ============================================
-- FACE DETECTIONS TABLE (with driver profile link)
-- ============================================

-- Create table for face detection events
CREATE TABLE IF NOT EXISTS public.face_detections (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,

    -- Link to vehicle
    vehicle_id TEXT REFERENCES public.vehicles(id) ON DELETE CASCADE,

    -- Link to identified driver (NULL if unidentified)
    driver_profile_id UUID REFERENCES public.driver_profiles(id) ON DELETE SET NULL,

    -- Face detection metadata
    face_bbox JSONB, -- {x_min, y_min, x_max, y_max}

    -- Face embedding for similarity matching (128-dimensional vector)
    face_embedding vector(128),

    -- Cluster ID to group similar unidentified faces
    face_cluster_id UUID,

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
CREATE INDEX IF NOT EXISTS idx_face_detections_driver_profile ON public.face_detections(driver_profile_id);
CREATE INDEX IF NOT EXISTS idx_face_detections_unidentified ON public.face_detections(vehicle_id) WHERE driver_profile_id IS NULL;

-- Create index for efficient similarity search on face embeddings
CREATE INDEX IF NOT EXISTS idx_face_detections_embedding
ON public.face_detections
USING ivfflat (face_embedding vector_cosine_ops)
WITH (lists = 100);

-- Create index for cluster lookups
CREATE INDEX IF NOT EXISTS idx_face_detections_cluster_id
ON public.face_detections(face_cluster_id)
WHERE face_cluster_id IS NOT NULL;

-- ============================================
-- ROW LEVEL SECURITY POLICIES
-- ============================================

-- Enable RLS on all tables
ALTER TABLE public.vehicles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vehicle_access ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vehicle_realtime ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.face_detections ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.driver_profiles ENABLE ROW LEVEL SECURITY;

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

-- Authenticated users can update driver_profile_id for vehicles they have access to
CREATE POLICY "face_detections_update_driver_profile" ON public.face_detections
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
-- DRIVER PROFILES TABLE POLICIES
-- ============================================

-- Service role can do everything
CREATE POLICY "driver_profiles_service_role_all" ON public.driver_profiles
    FOR ALL TO service_role
    USING (true) WITH CHECK (true);

-- Authenticated users can read profiles for vehicles they have access to
CREATE POLICY "driver_profiles_select_with_access" ON public.driver_profiles
    FOR SELECT TO authenticated
    USING (
        vehicle_id IN (
            SELECT vehicle_id FROM public.vehicle_access
            WHERE user_id = auth.uid()
        )
    );

-- Authenticated users can create profiles for vehicles they have access to
CREATE POLICY "driver_profiles_insert_with_access" ON public.driver_profiles
    FOR INSERT TO authenticated
    WITH CHECK (
        vehicle_id IN (
            SELECT vehicle_id FROM public.vehicle_access
            WHERE user_id = auth.uid()
        )
    );

-- Authenticated users can update profiles for vehicles they have access to
CREATE POLICY "driver_profiles_update_with_access" ON public.driver_profiles
    FOR UPDATE TO authenticated
    USING (
        vehicle_id IN (
            SELECT vehicle_id FROM public.vehicle_access
            WHERE user_id = auth.uid()
        )
    );

-- Authenticated users can delete profiles for vehicles they have access to
CREATE POLICY "driver_profiles_delete_with_access" ON public.driver_profiles
    FOR DELETE TO authenticated
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

-- ============================================
-- FACE CLUSTERING FUNCTIONS
-- ============================================

-- Function to find similar faces and return a cluster_id
-- If a similar face exists, returns its cluster_id
-- If no similar face exists, returns a new UUID
CREATE OR REPLACE FUNCTION public.find_or_create_face_cluster(
    p_vehicle_id TEXT,
    p_embedding vector(128),
    p_similarity_threshold FLOAT DEFAULT 0.6
)
RETURNS UUID AS $$
DECLARE
    v_cluster_id UUID;
    v_similar_face RECORD;
BEGIN
    -- Find the most similar unidentified face in the same vehicle
    -- Using cosine similarity (1 - cosine_distance)
    SELECT
        face_cluster_id,
        1 - (face_embedding <=> p_embedding) as similarity
    INTO v_similar_face
    FROM public.face_detections
    WHERE vehicle_id = p_vehicle_id
        AND face_embedding IS NOT NULL
        AND face_cluster_id IS NOT NULL
        -- Only compare with faces from the last 30 days for performance
        AND created_at > NOW() - INTERVAL '30 days'
    ORDER BY face_embedding <=> p_embedding ASC
    LIMIT 1;

    -- If found a similar face above threshold, use its cluster_id
    IF v_similar_face IS NOT NULL AND v_similar_face.similarity >= p_similarity_threshold THEN
        RETURN v_similar_face.face_cluster_id;
    END IF;

    -- No similar face found, generate new cluster_id
    RETURN uuid_generate_v4();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to propagate driver_profile_id to all faces in the same cluster
CREATE OR REPLACE FUNCTION public.propagate_driver_profile_to_cluster()
RETURNS TRIGGER AS $$
BEGIN
    -- Only run when driver_profile_id is being set (not cleared)
    -- and when the face has a cluster_id
    IF NEW.driver_profile_id IS NOT NULL
        AND OLD.driver_profile_id IS NULL
        AND NEW.face_cluster_id IS NOT NULL THEN

        -- Update all faces in the same cluster that don't have a profile yet
        UPDATE public.face_detections
        SET driver_profile_id = NEW.driver_profile_id
        WHERE face_cluster_id = NEW.face_cluster_id
            AND vehicle_id = NEW.vehicle_id
            AND driver_profile_id IS NULL
            AND id != NEW.id;

        RAISE NOTICE 'Propagated driver_profile_id % to cluster %',
            NEW.driver_profile_id, NEW.face_cluster_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create trigger to automatically propagate profile assignments
DROP TRIGGER IF EXISTS trigger_propagate_driver_profile ON public.face_detections;
CREATE TRIGGER trigger_propagate_driver_profile
    AFTER UPDATE OF driver_profile_id ON public.face_detections
    FOR EACH ROW
    EXECUTE FUNCTION public.propagate_driver_profile_to_cluster();

-- Function to get all unidentified face clusters for a vehicle
-- Returns one representative face per cluster for display in the app
CREATE OR REPLACE FUNCTION public.get_unidentified_face_clusters(p_vehicle_id TEXT)
RETURNS TABLE (
    cluster_id UUID,
    face_count BIGINT,
    first_seen TIMESTAMPTZ,
    last_seen TIMESTAMPTZ,
    representative_image_path TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        fd.face_cluster_id as cluster_id,
        COUNT(*) as face_count,
        MIN(fd.created_at) as first_seen,
        MAX(fd.created_at) as last_seen,
        (
            SELECT fd2.image_path
            FROM public.face_detections fd2
            WHERE fd2.face_cluster_id = fd.face_cluster_id
            ORDER BY fd2.created_at DESC
            LIMIT 1
        ) as representative_image_path
    FROM public.face_detections fd
    WHERE fd.vehicle_id = p_vehicle_id
        AND fd.driver_profile_id IS NULL
        AND fd.face_cluster_id IS NOT NULL
    GROUP BY fd.face_cluster_id
    ORDER BY last_seen DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to assign a profile to an entire cluster
CREATE OR REPLACE FUNCTION public.assign_profile_to_cluster(
    p_cluster_id UUID,
    p_profile_id UUID
)
RETURNS JSONB AS $$
DECLARE
    v_updated_count INTEGER;
BEGIN
    -- Update all faces in the cluster
    UPDATE public.face_detections
    SET driver_profile_id = p_profile_id
    WHERE face_cluster_id = p_cluster_id
        AND driver_profile_id IS NULL;

    GET DIAGNOSTICS v_updated_count = ROW_COUNT;

    RETURN jsonb_build_object(
        'success', true,
        'updated_count', v_updated_count,
        'cluster_id', p_cluster_id,
        'profile_id', p_profile_id
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION public.find_or_create_face_cluster(TEXT, vector(128), FLOAT) TO service_role;
GRANT EXECUTE ON FUNCTION public.get_unidentified_face_clusters(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.assign_profile_to_cluster(UUID, UUID) TO authenticated;
