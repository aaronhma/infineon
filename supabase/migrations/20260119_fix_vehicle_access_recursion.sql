-- Migration: Fix infinite recursion in vehicle_access RLS policy
-- Created: 2026-01-19
-- This fixes the policy that was causing "infinite recursion detected in policy for relation vehicle_access"

-- Drop the problematic policies that cause infinite recursion
DROP POLICY IF EXISTS "vehicle_access_select_same_vehicle" ON public.vehicle_access;
DROP POLICY IF EXISTS "vehicle_access_select_owner" ON public.vehicle_access;

-- The cross-table recursion happens because:
-- 1. vehicle_access_select_owner queries vehicles table
-- 2. vehicles RLS policy (vehicles_select_with_access) queries vehicle_access table
-- 3. This creates an infinite loop

-- Solution: Keep only the simple "vehicle_access_select_own" policy from setup.sql
-- which just checks user_id = auth.uid() with no subqueries.
-- The get_vehicle_access_users() function uses SECURITY DEFINER to bypass RLS
-- and can return all users with access to a vehicle.
