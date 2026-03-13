-- Migration: Add gyroscope, accelerometer, and crash fields to vehicle_realtime
-- Sent by main.py on every realtime update tick; crash fields set immediately on impact.

ALTER TABLE public.vehicle_realtime
  ADD COLUMN IF NOT EXISTS acc_mag REAL,
  ADD COLUMN IF NOT EXISTS gyro_mag REAL,
  ADD COLUMN IF NOT EXISTS gyrox REAL,
  ADD COLUMN IF NOT EXISTS gyroy REAL,
  ADD COLUMN IF NOT EXISTS gyroz REAL,
  ADD COLUMN IF NOT EXISTS crash_detected BOOLEAN DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS crash_severity TEXT,
  ADD COLUMN IF NOT EXISTS crash_peak_g REAL;
