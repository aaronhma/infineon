-- Migration: Add distracted gaze tracking
-- is_distracted_gaze on face_detections records when the driver's gaze was off-road.
-- distracted_gaze_event_count on vehicle_trips tracks transitions into that state per trip.
-- phone_distraction_event_count was already in the model but never persisted from main.py —
-- add it here as a safety net so it is always present.

ALTER TABLE public.face_detections
  ADD COLUMN IF NOT EXISTS is_distracted_gaze BOOLEAN DEFAULT FALSE;

ALTER TABLE public.vehicle_trips
  ADD COLUMN IF NOT EXISTS distracted_gaze_event_count INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS phone_distraction_event_count INTEGER DEFAULT 0;
