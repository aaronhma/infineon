-- Migration: Add current song fields to vehicle_realtime
-- These columns were in setup.sql but missing from migrations.
-- Realtime is already enabled on vehicle_realtime, so iOS apps will
-- receive live updates whenever main.py upserts a new song.

ALTER TABLE public.vehicle_realtime
  ADD COLUMN IF NOT EXISTS current_song_title TEXT,
  ADD COLUMN IF NOT EXISTS current_song_artist TEXT,
  ADD COLUMN IF NOT EXISTS current_song_detected_at TIMESTAMPTZ;
