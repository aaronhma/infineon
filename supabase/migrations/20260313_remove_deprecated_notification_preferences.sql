-- Migration: Remove deprecated keys from notification_preferences
-- Removed: unidentified_face, drunk_driving, fsd
-- Remaining: collision, driver_drowsiness, speed_limit

-- Update the column default to drop the removed keys
ALTER TABLE public.user_profiles
  ALTER COLUMN notification_preferences SET DEFAULT '{
    "collision": true,
    "driver_drowsiness": true,
    "speed_limit": true
  }'::jsonb;

-- Strip the deprecated keys from all existing rows
UPDATE public.user_profiles
SET notification_preferences = notification_preferences
  - 'unidentified_face'
  - 'drunk_driving'
  - 'fsd';
