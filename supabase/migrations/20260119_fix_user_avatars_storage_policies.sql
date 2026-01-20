-- Migration: Fix user-avatars storage bucket RLS policies
-- Created: 2026-01-19
--
-- This fixes the "new row violates row-level security policy" error
-- by using a simpler path-based check

-- ============================================
-- DROP EXISTING POLICIES (if they exist)
-- ============================================

DROP POLICY IF EXISTS "user_avatars_insert_own" ON storage.objects;
DROP POLICY IF EXISTS "user_avatars_update_own" ON storage.objects;
DROP POLICY IF EXISTS "user_avatars_delete_own" ON storage.objects;
DROP POLICY IF EXISTS "user_avatars_select_public" ON storage.objects;

-- ============================================
-- RECREATE STORAGE POLICIES FOR USER AVATARS
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
