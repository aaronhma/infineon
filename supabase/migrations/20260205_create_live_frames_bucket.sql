-- Migration: Create live-frames storage bucket for video streaming
-- Created: 2026-02-05
-- Description: Stores real-time camera frames uploaded by vehicles for remote viewing via iOS app

-- Create storage bucket for live video frames
INSERT INTO storage.buckets (id, name, public, file_size_limit)
VALUES (
    'live-frames',
    'live-frames',
    true,  -- Public bucket (read access via public URL)
    1048576  -- 1MB limit per file (enough for compressed JPEG frames)
)
ON CONFLICT (id) DO NOTHING;

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

-- STORAGE POLICIES

-- 1. Service role (backend) can do everything
CREATE POLICY "live_frames_service_role_all"
ON storage.objects
FOR ALL
TO service_role
USING (bucket_id = 'live-frames')
WITH CHECK (bucket_id = 'live-frames');

-- 2. Vehicles (service role context) can upload/update/delete their own frames
--    This is enforced by the Python backend which uses service_role credentials
--    and constructs paths as {vehicle_id}/latest.jpg

-- 3. Authenticated users can download frames from vehicles they have access to
--    Uses SECURITY DEFINER function to avoid RLS recursion issues
CREATE POLICY "live_frames_select_with_vehicle_access"
ON storage.objects
FOR SELECT
TO authenticated
USING (
    bucket_id = 'live-frames'
    AND public.user_has_vehicle_access((storage.foldername(name))[1])
);

-- 4. Public read access (optional - enable if you want unauthenticated viewing)
-- CREATE POLICY "live_frames_public_read"
-- ON storage.objects
-- FOR SELECT
-- TO public
-- USING (bucket_id = 'live-frames');
