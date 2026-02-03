-- Migration: Add GPS satellites and distraction detection columns
-- Created: 2026-02-02

-- ============================================
-- ADD SATELLITES COLUMN TO VEHICLE_REALTIME
-- ============================================

-- Add satellites column for GPS fix quality
ALTER TABLE public.vehicle_realtime
ADD COLUMN IF NOT EXISTS satellites INTEGER DEFAULT 0;

-- Add comment
COMMENT ON COLUMN public.vehicle_realtime.satellites IS 'Number of GPS satellites in view (0 = no GPS fix or simulated)';

-- ============================================
-- ADD DISTRACTION DETECTION COLUMNS
-- ============================================

-- Add distraction status columns to vehicle_realtime
ALTER TABLE public.vehicle_realtime
ADD COLUMN IF NOT EXISTS is_phone_detected BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS is_drinking_detected BOOLEAN DEFAULT FALSE;

COMMENT ON COLUMN public.vehicle_realtime.is_phone_detected IS 'YOLO detected phone near driver face';
COMMENT ON COLUMN public.vehicle_realtime.is_drinking_detected IS 'YOLO detected bottle/cup near driver face';

-- ============================================
-- ADD DISTRACTION COLUMNS TO FACE_DETECTIONS
-- ============================================

-- Add distraction flags to face_detections for historical tracking
ALTER TABLE public.face_detections
ADD COLUMN IF NOT EXISTS is_phone_detected BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS is_drinking_detected BOOLEAN DEFAULT FALSE;

-- ============================================
-- ADD DISTRACTION EVENT COUNTS TO VEHICLE_TRIPS
-- ============================================

-- Add distraction event counters to vehicle_trips
ALTER TABLE public.vehicle_trips
ADD COLUMN IF NOT EXISTS phone_distraction_event_count INTEGER DEFAULT 0,
ADD COLUMN IF NOT EXISTS drinking_event_count INTEGER DEFAULT 0;

-- ============================================
-- UPDATE DRIVER_STATUS CHECK CONSTRAINT (if exists)
-- ============================================

-- The driver_status column now supports additional values for distraction
-- Values: 'alert', 'drowsy', 'impaired', 'distracted_phone', 'distracted_drinking', 'unknown'
-- Note: We don't add a CHECK constraint since it was not defined originally

-- ============================================
-- DONE
-- ============================================
