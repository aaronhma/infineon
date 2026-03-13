-- Add gyroscope data columns to face_detections
ALTER TABLE public.face_detections
  ADD COLUMN IF NOT EXISTS acc_mag REAL DEFAULT NULL;
ALTER TABLE public.face_detections
  ADD COLUMN IF NOT EXISTS acc_delta REAL DEFAULT NULL;
ALTER TABLE public.face_detections
  ADD COLUMN IF NOT EXISTS gyro_mag REAL DEFAULT NULL;
ALTER TABLE public.face_detections
  ADD COLUMN IF NOT EXISTS gyrox REAL DEFAULT NULL;
ALTER TABLE public.face_detections
  ADD COLUMN IF NOT EXISTS gyroy REAL DEFAULT NULL;
ALTER TABLE public.face_detections
  ADD COLUMN IF NOT EXISTS gyroz REAL DEFAULT NULL;
