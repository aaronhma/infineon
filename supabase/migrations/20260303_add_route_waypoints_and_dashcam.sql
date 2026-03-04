-- Add GPS route waypoints to vehicle_trips
ALTER TABLE public.vehicle_trips
  ADD COLUMN IF NOT EXISTS route_waypoints JSONB DEFAULT '[]'::jsonb;

-- Add dashcam feature toggle to vehicles
ALTER TABLE public.vehicles
  ADD COLUMN IF NOT EXISTS enable_dashcam BOOLEAN NOT NULL DEFAULT FALSE;
