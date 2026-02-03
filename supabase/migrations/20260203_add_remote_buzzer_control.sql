-- Migration: Add remote buzzer control to vehicle_realtime table
-- This allows iOS app to remotely trigger the buzzer on the Raspberry Pi

-- Add buzzer control columns to vehicle_realtime table
ALTER TABLE public.vehicle_realtime
ADD COLUMN IF NOT EXISTS buzzer_active BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS buzzer_type TEXT DEFAULT 'alert',
ADD COLUMN IF NOT EXISTS buzzer_updated_at TIMESTAMPTZ;

-- Add comment to explain buzzer_type values
COMMENT ON COLUMN public.vehicle_realtime.buzzer_type IS 'Type of buzzer alert: alert, emergency, warning';

-- Create policy to allow authenticated users to update buzzer control
-- for vehicles they have access to
CREATE POLICY "vehicle_realtime_update_buzzer_with_access" ON public.vehicle_realtime
    FOR UPDATE TO authenticated
    USING (
        vehicle_id IN (
            SELECT vehicle_id FROM public.vehicle_access
            WHERE user_id = auth.uid()
        )
    )
    WITH CHECK (
        vehicle_id IN (
            SELECT vehicle_id FROM public.vehicle_access
            WHERE user_id = auth.uid()
        )
    );

-- Helper function to activate buzzer remotely
CREATE OR REPLACE FUNCTION public.activate_vehicle_buzzer(
    p_vehicle_id TEXT,
    p_buzzer_type TEXT DEFAULT 'alert'
)
RETURNS JSONB AS $$
DECLARE
    v_has_access BOOLEAN;
BEGIN
    -- Check if user has access to this vehicle
    SELECT EXISTS (
        SELECT 1 FROM public.vehicle_access
        WHERE user_id = auth.uid() AND vehicle_id = p_vehicle_id
    ) INTO v_has_access;

    IF NOT v_has_access THEN
        RETURN jsonb_build_object('success', false, 'error', 'Access denied');
    END IF;

    -- Activate buzzer
    UPDATE public.vehicle_realtime
    SET
        buzzer_active = TRUE,
        buzzer_type = p_buzzer_type,
        buzzer_updated_at = NOW()
    WHERE vehicle_id = p_vehicle_id;

    RETURN jsonb_build_object(
        'success', true,
        'vehicle_id', p_vehicle_id,
        'buzzer_type', p_buzzer_type
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Helper function to deactivate buzzer remotely
CREATE OR REPLACE FUNCTION public.deactivate_vehicle_buzzer(p_vehicle_id TEXT)
RETURNS JSONB AS $$
DECLARE
    v_has_access BOOLEAN;
BEGIN
    -- Check if user has access to this vehicle
    SELECT EXISTS (
        SELECT 1 FROM public.vehicle_access
        WHERE user_id = auth.uid() AND vehicle_id = p_vehicle_id
    ) INTO v_has_access;

    IF NOT v_has_access THEN
        RETURN jsonb_build_object('success', false, 'error', 'Access denied');
    END IF;

    -- Deactivate buzzer
    UPDATE public.vehicle_realtime
    SET
        buzzer_active = FALSE,
        buzzer_updated_at = NOW()
    WHERE vehicle_id = p_vehicle_id;

    RETURN jsonb_build_object(
        'success', true,
        'vehicle_id', p_vehicle_id
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permissions to authenticated users
GRANT EXECUTE ON FUNCTION public.activate_vehicle_buzzer(TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.deactivate_vehicle_buzzer(TEXT) TO authenticated;
