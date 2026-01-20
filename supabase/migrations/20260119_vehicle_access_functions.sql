-- Migration: Add vehicle access management functions
-- Created: 2026-01-19

-- ============================================
-- FUNCTION: GET VEHICLE ACCESS USERS
-- Returns all users who have access to a vehicle, including the owner
-- ============================================

-- Drop existing function first
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
    -- Check access and return users in one query
    -- The WHERE clause ensures only users with access can call this
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

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION public.get_vehicle_access_users(TEXT) TO authenticated;


-- ============================================
-- FUNCTION: REMOVE VEHICLE ACCESS
-- Allows vehicle owner to remove other users' access
-- ============================================

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

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION public.remove_vehicle_access(TEXT, TEXT) TO authenticated;


-- ============================================
-- NOTE ON RLS POLICIES
-- ============================================

-- We keep only the original "vehicle_access_select_own" policy from setup.sql
-- which checks user_id = auth.uid() with no subqueries.
--
-- DO NOT add policies that query vehicles table from vehicle_access or vice versa,
-- as this creates infinite recursion (vehicles policy queries vehicle_access,
-- and if vehicle_access policy queries vehicles, it loops forever).
--
-- The get_vehicle_access_users() function uses SECURITY DEFINER to bypass RLS
-- and can return all users with access to a vehicle.


-- ============================================
-- UPDATE RLS POLICY: Allow reading other users' profiles for vehicle access display
-- ============================================

-- Create policy to allow reading profiles of users who share vehicle access
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
