-- Migration: Create vehicle_trips table
-- This table stores trip records for each driving session

-- Create table for vehicle trips
CREATE TABLE IF NOT EXISTS public.vehicle_trips (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,

    -- Link to vehicle
    vehicle_id TEXT NOT NULL REFERENCES public.vehicles(id) ON DELETE CASCADE,

    -- Session tracking (same session_id as face_detections)
    session_id UUID NOT NULL,

    -- Link to identified driver (NULL if unidentified)
    driver_profile_id UUID REFERENCES public.driver_profiles(id) ON DELETE SET NULL,

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

    -- Speed samples for average calculation
    speed_sample_count INTEGER DEFAULT 0,
    speed_sample_sum INTEGER DEFAULT 0
);

-- Create indexes for faster queries
CREATE INDEX IF NOT EXISTS idx_vehicle_trips_vehicle_id ON public.vehicle_trips(vehicle_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_trips_session_id ON public.vehicle_trips(session_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_trips_started_at ON public.vehicle_trips(started_at DESC);
CREATE INDEX IF NOT EXISTS idx_vehicle_trips_driver_profile ON public.vehicle_trips(driver_profile_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_trips_status ON public.vehicle_trips(status);

-- Enable RLS
ALTER TABLE public.vehicle_trips ENABLE ROW LEVEL SECURITY;

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

-- Enable realtime for vehicle_trips table (for iOS app subscriptions)
ALTER PUBLICATION supabase_realtime ADD TABLE public.vehicle_trips;
