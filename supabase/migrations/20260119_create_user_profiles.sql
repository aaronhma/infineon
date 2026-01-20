-- Migration: Create user_profiles table and user-avatars storage bucket
-- Created: 2026-01-19

-- ============================================
-- USER PROFILES TABLE
-- ============================================

-- User profiles: stores user preferences and profile data
-- Links to auth.users via user_id
CREATE TABLE IF NOT EXISTS public.user_profiles (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    user_id UUID NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,

    -- Profile info
    display_name TEXT,
    avatar_path TEXT, -- Path in user-avatars storage bucket

    -- Notification preferences (stored as JSONB for flexibility)
    -- Keys: unidentified_face, collision, driver_drowsiness, speed_limit, drunk_driving, fsd
    notification_preferences JSONB DEFAULT '{
        "unidentified_face": true,
        "collision": true,
        "driver_drowsiness": true,
        "speed_limit": true,
        "drunk_driving": true,
        "fsd": true
    }'::jsonb NOT NULL,

    -- Push notification token (for future use)
    push_token TEXT,

    -- Whether notifications are enabled at all
    notifications_enabled BOOLEAN DEFAULT false
);

-- Create index for faster lookups
CREATE INDEX IF NOT EXISTS idx_user_profiles_user_id ON public.user_profiles(user_id);

-- ============================================
-- AUTO-UPDATE TIMESTAMP TRIGGER
-- ============================================

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
-- STORAGE BUCKET FOR USER AVATARS
-- ============================================

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

-- ============================================
-- ROW LEVEL SECURITY POLICIES
-- ============================================

-- Enable RLS on user_profiles table
ALTER TABLE public.user_profiles ENABLE ROW LEVEL SECURITY;

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

-- ============================================
-- STORAGE POLICIES FOR USER AVATARS
-- ============================================

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

-- ============================================
-- HELPER FUNCTION: GET OR CREATE USER PROFILE
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

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION public.get_or_create_user_profile() TO authenticated;

-- ============================================
-- HELPER FUNCTION: UPDATE USER PROFILE
-- ============================================

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

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION public.update_user_profile(TEXT, TEXT, JSONB, BOOLEAN, TEXT) TO authenticated;
