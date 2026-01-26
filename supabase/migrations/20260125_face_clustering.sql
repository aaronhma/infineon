-- Migration: Face Clustering for Unknown Face Matching
-- This enables grouping similar faces together even before they're assigned to a profile
-- When a profile is assigned to one face, all faces in the same cluster get linked

-- Enable pgvector extension for efficient face embedding storage and similarity search
CREATE EXTENSION IF NOT EXISTS vector;

-- Add face embedding column (128-dimensional vector from face_recognition library)
ALTER TABLE public.face_detections
ADD COLUMN IF NOT EXISTS face_embedding vector(128);

-- Add cluster ID to group similar unidentified faces
ALTER TABLE public.face_detections
ADD COLUMN IF NOT EXISTS face_cluster_id UUID;

-- Create index for efficient similarity search on embeddings
CREATE INDEX IF NOT EXISTS idx_face_detections_embedding
ON public.face_detections
USING ivfflat (face_embedding vector_cosine_ops)
WITH (lists = 100);

-- Create index for cluster lookups
CREATE INDEX IF NOT EXISTS idx_face_detections_cluster_id
ON public.face_detections(face_cluster_id)
WHERE face_cluster_id IS NOT NULL;

-- ============================================
-- FACE SIMILARITY MATCHING FUNCTION
-- ============================================

-- Function to find similar faces and return a cluster_id
-- If a similar face exists, returns its cluster_id
-- If no similar face exists, returns a new UUID
CREATE OR REPLACE FUNCTION public.find_or_create_face_cluster(
    p_vehicle_id TEXT,
    p_embedding vector(128),
    p_similarity_threshold FLOAT DEFAULT 0.6
)
RETURNS UUID AS $$
DECLARE
    v_cluster_id UUID;
    v_similar_face RECORD;
BEGIN
    -- Find the most similar unidentified face in the same vehicle
    -- Using cosine similarity (1 - cosine_distance)
    SELECT
        face_cluster_id,
        1 - (face_embedding <=> p_embedding) as similarity
    INTO v_similar_face
    FROM public.face_detections
    WHERE vehicle_id = p_vehicle_id
        AND face_embedding IS NOT NULL
        AND face_cluster_id IS NOT NULL
        -- Only compare with faces from the last 30 days for performance
        AND created_at > NOW() - INTERVAL '30 days'
    ORDER BY face_embedding <=> p_embedding ASC
    LIMIT 1;

    -- If found a similar face above threshold, use its cluster_id
    IF v_similar_face IS NOT NULL AND v_similar_face.similarity >= p_similarity_threshold THEN
        RETURN v_similar_face.face_cluster_id;
    END IF;

    -- No similar face found, generate new cluster_id
    RETURN uuid_generate_v4();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- PROFILE PROPAGATION TRIGGER
-- ============================================

-- Function to propagate driver_profile_id to all faces in the same cluster
CREATE OR REPLACE FUNCTION public.propagate_driver_profile_to_cluster()
RETURNS TRIGGER AS $$
BEGIN
    -- Only run when driver_profile_id is being set (not cleared)
    -- and when the face has a cluster_id
    IF NEW.driver_profile_id IS NOT NULL
        AND OLD.driver_profile_id IS NULL
        AND NEW.face_cluster_id IS NOT NULL THEN

        -- Update all faces in the same cluster that don't have a profile yet
        UPDATE public.face_detections
        SET driver_profile_id = NEW.driver_profile_id
        WHERE face_cluster_id = NEW.face_cluster_id
            AND vehicle_id = NEW.vehicle_id
            AND driver_profile_id IS NULL
            AND id != NEW.id;

        RAISE NOTICE 'Propagated driver_profile_id % to cluster %',
            NEW.driver_profile_id, NEW.face_cluster_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create trigger to automatically propagate profile assignments
DROP TRIGGER IF EXISTS trigger_propagate_driver_profile ON public.face_detections;
CREATE TRIGGER trigger_propagate_driver_profile
    AFTER UPDATE OF driver_profile_id ON public.face_detections
    FOR EACH ROW
    EXECUTE FUNCTION public.propagate_driver_profile_to_cluster();

-- ============================================
-- HELPER FUNCTIONS FOR iOS APP
-- ============================================

-- Function to get all unidentified face clusters for a vehicle
-- Returns one representative face per cluster for display in the app
CREATE OR REPLACE FUNCTION public.get_unidentified_face_clusters(p_vehicle_id TEXT)
RETURNS TABLE (
    cluster_id UUID,
    face_count BIGINT,
    first_seen TIMESTAMPTZ,
    last_seen TIMESTAMPTZ,
    representative_image_path TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        fd.face_cluster_id as cluster_id,
        COUNT(*) as face_count,
        MIN(fd.created_at) as first_seen,
        MAX(fd.created_at) as last_seen,
        (
            SELECT fd2.image_path
            FROM public.face_detections fd2
            WHERE fd2.face_cluster_id = fd.face_cluster_id
            ORDER BY fd2.created_at DESC
            LIMIT 1
        ) as representative_image_path
    FROM public.face_detections fd
    WHERE fd.vehicle_id = p_vehicle_id
        AND fd.driver_profile_id IS NULL
        AND fd.face_cluster_id IS NOT NULL
    GROUP BY fd.face_cluster_id
    ORDER BY last_seen DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to assign a profile to an entire cluster
CREATE OR REPLACE FUNCTION public.assign_profile_to_cluster(
    p_cluster_id UUID,
    p_profile_id UUID
)
RETURNS JSONB AS $$
DECLARE
    v_updated_count INTEGER;
BEGIN
    -- Update all faces in the cluster
    UPDATE public.face_detections
    SET driver_profile_id = p_profile_id
    WHERE face_cluster_id = p_cluster_id
        AND driver_profile_id IS NULL;

    GET DIAGNOSTICS v_updated_count = ROW_COUNT;

    RETURN jsonb_build_object(
        'success', true,
        'updated_count', v_updated_count,
        'cluster_id', p_cluster_id,
        'profile_id', p_profile_id
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permissions to authenticated users
GRANT EXECUTE ON FUNCTION public.find_or_create_face_cluster(TEXT, vector(128), FLOAT) TO service_role;
GRANT EXECUTE ON FUNCTION public.get_unidentified_face_clusters(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.assign_profile_to_cluster(UUID, UUID) TO authenticated;
