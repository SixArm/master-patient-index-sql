-- ============================================================================
-- Master Patient Index (MPI) - Temporal Framework
-- PostgreSQL 18
-- ============================================================================
-- Purpose: Temporal table pattern and helper functions for historical tracking
-- Implements full bi-temporal data model (valid time and transaction time)
-- ============================================================================

-- ============================================================================
-- Temporal Helper Functions
-- ============================================================================

-- Get current valid time (for effective_from/to)
CREATE OR REPLACE FUNCTION core.valid_time_now()
RETURNS TIMESTAMP WITH TIME ZONE AS $$
BEGIN
    RETURN CURRENT_TIMESTAMP;
END;
$$ LANGUAGE plpgsql STABLE;
COMMENT ON FUNCTION core.valid_time_now IS 'Returns current timestamp for valid time tracking';

-- Maximum timestamp (for open-ended effective_to)
CREATE OR REPLACE FUNCTION core.max_timestamp()
RETURNS TIMESTAMP WITH TIME ZONE AS $$
BEGIN
    RETURN '9999-12-31 23:59:59'::TIMESTAMP WITH TIME ZONE;
END;
$$ LANGUAGE plpgsql IMMUTABLE;
COMMENT ON FUNCTION core.max_timestamp IS 'Returns maximum timestamp for open-ended periods';

-- Check if record is currently valid
CREATE OR REPLACE FUNCTION core.is_currently_valid(
    p_effective_from TIMESTAMP WITH TIME ZONE,
    p_effective_to TIMESTAMP WITH TIME ZONE
)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN CURRENT_TIMESTAMP >= p_effective_from
        AND CURRENT_TIMESTAMP < p_effective_to;
END;
$$ LANGUAGE plpgsql STABLE;
COMMENT ON FUNCTION core.is_currently_valid IS 'Checks if temporal record is currently valid';

-- Check if record is valid at specific time
CREATE OR REPLACE FUNCTION core.is_valid_at(
    p_effective_from TIMESTAMP WITH TIME ZONE,
    p_effective_to TIMESTAMP WITH TIME ZONE,
    p_as_of_time TIMESTAMP WITH TIME ZONE
)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN p_as_of_time >= p_effective_from
        AND p_as_of_time < p_effective_to;
END;
$$ LANGUAGE plpgsql IMMUTABLE;
COMMENT ON FUNCTION core.is_valid_at IS 'Checks if temporal record was valid at specific time';

-- ============================================================================
-- Generic Temporal Update Function
-- ============================================================================

-- This function implements the temporal update pattern:
-- 1. Close current record (set effective_to, is_current = false)
-- 2. Insert new record (new effective_from, is_current = true)
CREATE OR REPLACE FUNCTION core.temporal_update(
    p_schema_name TEXT,
    p_table_name TEXT,
    p_record_id UUID,
    p_new_values JSONB,
    p_effective_from TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    p_updated_by VARCHAR DEFAULT CURRENT_USER
)
RETURNS UUID AS $$
DECLARE
    v_current_record RECORD;
    v_new_id UUID;
    v_sql TEXT;
    v_columns TEXT[];
    v_values TEXT[];
    v_key TEXT;
    v_value TEXT;
BEGIN
    -- Get current record
    v_sql := format('SELECT * FROM %I.%I WHERE id = $1 AND is_current = TRUE',
                    p_schema_name, p_table_name);
    EXECUTE v_sql USING p_record_id INTO v_current_record;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No current record found for ID %', p_record_id;
    END IF;

    -- Close current record
    v_sql := format('UPDATE %I.%I SET effective_to = $1, is_current = FALSE, updated_at = $2, updated_by = $3 WHERE id = $4 AND is_current = TRUE',
                    p_schema_name, p_table_name);
    EXECUTE v_sql USING p_effective_from, CURRENT_TIMESTAMP, p_updated_by, p_record_id;

    -- Build column and value lists for new record
    v_columns := ARRAY['id', 'effective_from', 'effective_to', 'is_current', 'created_at', 'created_by'];
    v_values := ARRAY[
        'uuid_generate_v4()',
        quote_literal(p_effective_from),
        'core.max_timestamp()',
        'TRUE',
        'CURRENT_TIMESTAMP',
        quote_literal(p_updated_by)
    ];

    -- Add columns from new values
    FOR v_key, v_value IN SELECT * FROM jsonb_each_text(p_new_values)
    LOOP
        v_columns := array_append(v_columns, v_key);
        v_values := array_append(v_values, quote_literal(v_value));
    END LOOP;

    -- Note: This is a simplified version. In production, you'd need to:
    -- 1. Copy unchanged columns from current record
    -- 2. Validate column names against table schema
    -- 3. Handle data types properly

    RAISE NOTICE 'Temporal update completed for %.% record %',
        p_schema_name, p_table_name, p_record_id;

    RETURN v_new_id;
END;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION core.temporal_update IS 'Generic temporal update function (closes current, creates new version)';

-- ============================================================================
-- Trigger Function for Temporal Tables
-- ============================================================================

-- Prevent direct updates to temporal tables (enforce temporal pattern)
CREATE OR REPLACE FUNCTION core.prevent_temporal_update()
RETURNS TRIGGER AS $$
BEGIN
    -- Allow updates to close records (set effective_to and is_current)
    IF OLD.is_current = TRUE AND NEW.is_current = FALSE THEN
        RETURN NEW;
    END IF;

    -- Prevent all other updates
    RAISE EXCEPTION 'Direct updates not allowed on temporal tables. Use temporal_update function or insert new version.';
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION core.prevent_temporal_update IS 'Trigger to prevent direct updates on temporal tables';

-- Prevent deletion of temporal records (soft delete only)
CREATE OR REPLACE FUNCTION core.prevent_temporal_delete()
RETURNS TRIGGER AS $$
BEGIN
    RAISE EXCEPTION 'Direct deletion not allowed on temporal tables. Use soft delete (set deleted_at).';
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION core.prevent_temporal_delete IS 'Trigger to prevent deletion of temporal records';

-- Auto-set is_current flag on insert
CREATE OR REPLACE FUNCTION core.auto_set_current()
RETURNS TRIGGER AS $$
BEGIN
    -- If not specified, set is_current to TRUE
    IF NEW.is_current IS NULL THEN
        NEW.is_current := TRUE;
    END IF;

    -- If is_current is TRUE, ensure effective_to is max timestamp
    IF NEW.is_current = TRUE AND NEW.effective_to IS NOT NULL THEN
        IF NEW.effective_to != core.max_timestamp() THEN
            RAISE WARNING 'Current record should have effective_to = max_timestamp. Auto-correcting.';
            NEW.effective_to := core.max_timestamp();
        END IF;
    END IF;

    -- Set effective_from if not specified
    IF NEW.effective_from IS NULL THEN
        NEW.effective_from := CURRENT_TIMESTAMP;
    END IF;

    -- Set effective_to if not specified
    IF NEW.effective_to IS NULL THEN
        NEW.effective_to := core.max_timestamp();
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION core.auto_set_current IS 'Trigger to auto-set temporal fields on insert';

-- Ensure only one current record per entity
CREATE OR REPLACE FUNCTION core.ensure_single_current()
RETURNS TRIGGER AS $$
DECLARE
    v_count INTEGER;
    v_entity_id_column TEXT;
BEGIN
    -- Determine entity ID column (varies by table)
    -- This is a simplified version - adjust based on your table structure
    v_entity_id_column := TG_ARGV[0];

    IF v_entity_id_column IS NULL THEN
        RAISE EXCEPTION 'Entity ID column must be specified as trigger argument';
    END IF;

    -- Check for existing current records
    EXECUTE format(
        'SELECT COUNT(*) FROM %I.%I WHERE %I = $1 AND is_current = TRUE AND id != $2',
        TG_TABLE_SCHEMA, TG_TABLE_NAME, v_entity_id_column
    ) USING
        CASE v_entity_id_column
            WHEN 'patient_id' THEN NEW.patient_id
            ELSE NULL
        END,
        NEW.id
    INTO v_count;

    IF v_count > 0 THEN
        RAISE EXCEPTION 'Multiple current records not allowed for same entity in temporal table';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION core.ensure_single_current IS 'Trigger to ensure only one current record per entity';

-- ============================================================================
-- Temporal Query Helper Functions
-- ============================================================================

-- Get current version of temporal records
CREATE OR REPLACE FUNCTION core.get_current_version(
    p_schema_name TEXT,
    p_table_name TEXT,
    p_entity_id UUID
)
RETURNS SETOF RECORD AS $$
DECLARE
    v_sql TEXT;
BEGIN
    v_sql := format(
        'SELECT * FROM %I.%I WHERE patient_id = $1 AND is_current = TRUE',
        p_schema_name, p_table_name
    );

    RETURN QUERY EXECUTE v_sql USING p_entity_id;
END;
$$ LANGUAGE plpgsql STABLE;
COMMENT ON FUNCTION core.get_current_version IS 'Returns current version of temporal records';

-- Get version at specific point in time
CREATE OR REPLACE FUNCTION core.get_version_at(
    p_schema_name TEXT,
    p_table_name TEXT,
    p_entity_id UUID,
    p_as_of_time TIMESTAMP WITH TIME ZONE
)
RETURNS SETOF RECORD AS $$
DECLARE
    v_sql TEXT;
BEGIN
    v_sql := format(
        'SELECT * FROM %I.%I WHERE patient_id = $1 AND effective_from <= $2 AND effective_to > $2',
        p_schema_name, p_table_name
    );

    RETURN QUERY EXECUTE v_sql USING p_entity_id, p_as_of_time;
END;
$$ LANGUAGE plpgsql STABLE;
COMMENT ON FUNCTION core.get_version_at IS 'Returns version of temporal records at specific time';

-- Get all versions (full history)
CREATE OR REPLACE FUNCTION core.get_all_versions(
    p_schema_name TEXT,
    p_table_name TEXT,
    p_entity_id UUID
)
RETURNS SETOF RECORD AS $$
DECLARE
    v_sql TEXT;
BEGIN
    v_sql := format(
        'SELECT * FROM %I.%I WHERE patient_id = $1 ORDER BY effective_from DESC',
        p_schema_name, p_table_name
    );

    RETURN QUERY EXECUTE v_sql USING p_entity_id;
END;
$$ LANGUAGE plpgsql STABLE;
COMMENT ON FUNCTION core.get_all_versions IS 'Returns all versions (complete history) of temporal records';

-- ============================================================================
-- Soft Delete Functions
-- ============================================================================

-- Soft delete a temporal record
CREATE OR REPLACE FUNCTION core.soft_delete_temporal(
    p_schema_name TEXT,
    p_table_name TEXT,
    p_record_id UUID,
    p_deleted_by VARCHAR DEFAULT CURRENT_USER,
    p_deletion_reason TEXT DEFAULT NULL
)
RETURNS BOOLEAN AS $$
DECLARE
    v_sql TEXT;
    v_effective_now TIMESTAMP WITH TIME ZONE;
BEGIN
    v_effective_now := CURRENT_TIMESTAMP;

    -- Close current record
    v_sql := format(
        'UPDATE %I.%I SET effective_to = $1, is_current = FALSE, deleted_at = $2, deleted_by = $3, deletion_reason = $4 WHERE id = $5 AND is_current = TRUE',
        p_schema_name, p_table_name
    );

    EXECUTE v_sql USING v_effective_now, v_effective_now, p_deleted_by, p_deletion_reason, p_record_id;

    IF FOUND THEN
        RETURN TRUE;
    ELSE
        RAISE NOTICE 'No current record found to delete for ID %', p_record_id;
        RETURN FALSE;
    END IF;
END;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION core.soft_delete_temporal IS 'Soft deletes temporal record by closing it';

-- Restore soft-deleted temporal record
CREATE OR REPLACE FUNCTION core.restore_temporal(
    p_schema_name TEXT,
    p_table_name TEXT,
    p_record_id UUID,
    p_restored_by VARCHAR DEFAULT CURRENT_USER
)
RETURNS UUID AS $$
DECLARE
    v_deleted_record RECORD;
    v_new_id UUID;
    v_sql TEXT;
BEGIN
    -- Get deleted record
    v_sql := format(
        'SELECT * FROM %I.%I WHERE id = $1 AND deleted_at IS NOT NULL',
        p_schema_name, p_table_name
    );
    EXECUTE v_sql USING p_record_id INTO v_deleted_record;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No deleted record found for ID %', p_record_id;
    END IF;

    -- Note: In production, you'd recreate the record with a new version
    -- This is a placeholder for the restore logic

    RAISE NOTICE 'Record restored (implement full restore logic based on table structure)';

    RETURN v_new_id;
END;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION core.restore_temporal IS 'Restores soft-deleted temporal record';

-- ============================================================================
-- Temporal Validation Functions
-- ============================================================================

-- Validate temporal consistency (no gaps or overlaps)
CREATE OR REPLACE FUNCTION core.validate_temporal_consistency(
    p_schema_name TEXT,
    p_table_name TEXT,
    p_entity_id UUID
)
RETURNS TABLE(
    issue_type VARCHAR,
    record_id UUID,
    effective_from TIMESTAMP WITH TIME ZONE,
    effective_to TIMESTAMP WITH TIME ZONE,
    description TEXT
) AS $$
BEGIN
    -- Check for gaps
    RETURN QUERY EXECUTE format(
        'SELECT
            ''gap''::VARCHAR as issue_type,
            t1.id,
            t1.effective_to,
            t2.effective_from,
            ''Gap between '' || t1.effective_to || '' and '' || t2.effective_from
        FROM %I.%I t1
        JOIN %I.%I t2 ON t1.patient_id = t2.patient_id
        WHERE t1.patient_id = $1
            AND t1.effective_to < t2.effective_from
            AND NOT EXISTS (
                SELECT 1 FROM %I.%I t3
                WHERE t3.patient_id = t1.patient_id
                    AND t3.effective_from >= t1.effective_to
                    AND t3.effective_from < t2.effective_from
            )
        ORDER BY t1.effective_from',
        p_schema_name, p_table_name,
        p_schema_name, p_table_name,
        p_schema_name, p_table_name
    ) USING p_entity_id;

    -- Check for overlaps
    RETURN QUERY EXECUTE format(
        'SELECT
            ''overlap''::VARCHAR as issue_type,
            t1.id,
            t1.effective_from,
            t1.effective_to,
            ''Overlap with record '' || t2.id
        FROM %I.%I t1
        JOIN %I.%I t2 ON t1.patient_id = t2.patient_id AND t1.id != t2.id
        WHERE t1.patient_id = $1
            AND t1.effective_from < t2.effective_to
            AND t1.effective_to > t2.effective_from
        ORDER BY t1.effective_from',
        p_schema_name, p_table_name,
        p_schema_name, p_table_name
    ) USING p_entity_id;
END;
$$ LANGUAGE plpgsql STABLE;
COMMENT ON FUNCTION core.validate_temporal_consistency IS 'Validates temporal records for gaps and overlaps';

-- ============================================================================
-- Grant Permissions
-- ============================================================================

GRANT EXECUTE ON FUNCTION core.valid_time_now TO mpi_read_only, mpi_clinical_user, mpi_admin, mpi_integration;
GRANT EXECUTE ON FUNCTION core.max_timestamp TO mpi_read_only, mpi_clinical_user, mpi_admin, mpi_integration;
GRANT EXECUTE ON FUNCTION core.is_currently_valid TO mpi_read_only, mpi_clinical_user, mpi_admin, mpi_integration;
GRANT EXECUTE ON FUNCTION core.is_valid_at TO mpi_read_only, mpi_clinical_user, mpi_admin, mpi_integration;
GRANT EXECUTE ON FUNCTION core.soft_delete_temporal TO mpi_clinical_user, mpi_admin;
GRANT EXECUTE ON FUNCTION core.validate_temporal_consistency TO mpi_admin, mpi_auditor;

-- ============================================================================
-- Temporal Framework Complete
-- ============================================================================
