-- Utility Views and Functions for Master Patient Index (MPI)
-- This file provides helpful views and functions for common MPI operations

SET search_path TO mpi, public;

-- ============================================================================
-- VIEWS
-- ============================================================================

-- Complete patient view with current demographics
CREATE OR REPLACE VIEW v_patient_complete AS
SELECT
    p.patient_id,
    p.mpi_number,
    p.status,
    pd.first_name,
    pd.middle_name,
    pd.last_name,
    pd.name_suffix,
    pd.preferred_name,
    pd.date_of_birth,
    pd.gender,
    pd.sex_assigned_at_birth,
    pd.race,
    pd.ethnicity,
    pd.primary_language,
    pd.marital_status,
    pd.is_deceased,
    pd.death_date,
    p.created_at,
    p.updated_at
FROM patients p
LEFT JOIN patient_demographics pd ON p.patient_id = pd.patient_id
    AND pd.effective_to IS NULL  -- Current demographics only
WHERE p.deleted_at IS NULL;

COMMENT ON VIEW v_patient_complete IS 'Complete patient view with current active demographics';

-- Patient with primary identifiers
CREATE OR REPLACE VIEW v_patient_with_identifiers AS
SELECT
    vpc.*,
    jsonb_object_agg(
        pi.identifier_type,
        pi.identifier_value
    ) FILTER (WHERE pi.identifier_type IS NOT NULL) AS identifiers
FROM v_patient_complete vpc
LEFT JOIN patient_identifiers pi ON vpc.patient_id = pi.patient_id
GROUP BY
    vpc.patient_id, vpc.mpi_number, vpc.status,
    vpc.first_name, vpc.middle_name, vpc.last_name,
    vpc.name_suffix, vpc.preferred_name, vpc.date_of_birth,
    vpc.gender, vpc.sex_assigned_at_birth, vpc.race,
    vpc.ethnicity, vpc.primary_language, vpc.marital_status,
    vpc.is_deceased, vpc.death_date, vpc.created_at, vpc.updated_at;

COMMENT ON VIEW v_patient_with_identifiers IS 'Patient view with all identifiers as JSONB';

-- Active patient contacts view
CREATE OR REPLACE VIEW v_patient_primary_contact AS
SELECT
    p.patient_id,
    p.mpi_number,
    pd.first_name,
    pd.last_name,
    MAX(CASE WHEN pc.contact_type = 'phone_mobile' AND pc.is_primary THEN pc.contact_value END) AS primary_phone,
    MAX(CASE WHEN pc.contact_type = 'email_personal' AND pc.is_primary THEN pc.contact_value END) AS primary_email,
    MAX(CASE WHEN pa.address_type = 'home' AND pa.is_primary THEN
        pa.address_line_1 || ', ' ||
        COALESCE(pa.address_line_2 || ', ', '') ||
        pa.city || ', ' || pa.state || ' ' || pa.postal_code
    END) AS primary_address
FROM patients p
LEFT JOIN patient_demographics pd ON p.patient_id = pd.patient_id
    AND pd.effective_to IS NULL
LEFT JOIN patient_contacts pc ON p.patient_id = pc.patient_id
    AND pc.is_primary = true
LEFT JOIN patient_addresses pa ON p.patient_id = pa.patient_id
    AND pa.is_primary = true
WHERE p.deleted_at IS NULL
GROUP BY p.patient_id, p.mpi_number, pd.first_name, pd.last_name;

COMMENT ON VIEW v_patient_primary_contact IS 'Patient primary contact information consolidated';

-- Audit trail view
CREATE OR REPLACE VIEW v_audit_trail AS
SELECT
    al.audit_id,
    al.table_name,
    al.operation,
    p.mpi_number,
    pd.first_name || ' ' || pd.last_name AS patient_name,
    al.changed_at,
    al.changed_by,
    al.changed_fields,
    al.application_name
FROM audit_log al
LEFT JOIN patients p ON al.patient_id = p.patient_id
LEFT JOIN patient_demographics pd ON p.patient_id = pd.patient_id
    AND pd.effective_to IS NULL
ORDER BY al.changed_at DESC;

COMMENT ON VIEW v_audit_trail IS 'Human-readable audit trail with patient information';

-- Pending match candidates view
CREATE OR REPLACE VIEW v_pending_matches AS
SELECT
    pmc.candidate_id,
    pmc.match_score,
    p1.mpi_number AS patient_1_mpi,
    pd1.first_name || ' ' || pd1.last_name AS patient_1_name,
    pd1.date_of_birth AS patient_1_dob,
    p2.mpi_number AS patient_2_mpi,
    pd2.first_name || ' ' || pd2.last_name AS patient_2_name,
    pd2.date_of_birth AS patient_2_dob,
    pmc.matched_fields,
    pmc.match_algorithm,
    pmc.created_at
FROM patient_match_candidates pmc
JOIN patients p1 ON pmc.patient_id_1 = p1.patient_id
JOIN patient_demographics pd1 ON p1.patient_id = pd1.patient_id
    AND pd1.effective_to IS NULL
JOIN patients p2 ON pmc.patient_id_2 = p2.patient_id
JOIN patient_demographics pd2 ON p2.patient_id = pd2.patient_id
    AND pd2.effective_to IS NULL
WHERE pmc.review_status = 'pending'
ORDER BY pmc.match_score DESC;

COMMENT ON VIEW v_pending_matches IS 'Pending patient match candidates for review';

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

-- Search patients by name and date of birth
CREATE OR REPLACE FUNCTION search_patients(
    p_first_name VARCHAR DEFAULT NULL,
    p_last_name VARCHAR DEFAULT NULL,
    p_date_of_birth DATE DEFAULT NULL,
    p_fuzzy BOOLEAN DEFAULT FALSE
)
RETURNS TABLE (
    patient_id UUID,
    mpi_number VARCHAR,
    first_name VARCHAR,
    last_name VARCHAR,
    date_of_birth DATE,
    match_score DECIMAL
) AS $$
BEGIN
    IF p_fuzzy THEN
        -- Fuzzy search using similarity
        RETURN QUERY
        SELECT
            p.patient_id,
            p.mpi_number,
            pd.first_name,
            pd.last_name,
            pd.date_of_birth,
            (
                COALESCE(similarity(pd.first_name, p_first_name), 0) * 0.3 +
                COALESCE(similarity(pd.last_name, p_last_name), 0) * 0.5 +
                CASE WHEN pd.date_of_birth = p_date_of_birth THEN 0.2 ELSE 0 END
            )::DECIMAL(5,4) AS match_score
        FROM patients p
        JOIN patient_demographics pd ON p.patient_id = pd.patient_id
            AND pd.effective_to IS NULL
        WHERE p.deleted_at IS NULL
            AND (p_first_name IS NULL OR pd.first_name % p_first_name)
            AND (p_last_name IS NULL OR pd.last_name % p_last_name)
            AND (p_date_of_birth IS NULL OR pd.date_of_birth = p_date_of_birth)
        ORDER BY match_score DESC;
    ELSE
        -- Exact search
        RETURN QUERY
        SELECT
            p.patient_id,
            p.mpi_number,
            pd.first_name,
            pd.last_name,
            pd.date_of_birth,
            1.0::DECIMAL(5,4) AS match_score
        FROM patients p
        JOIN patient_demographics pd ON p.patient_id = pd.patient_id
            AND pd.effective_to IS NULL
        WHERE p.deleted_at IS NULL
            AND (p_first_name IS NULL OR LOWER(pd.first_name) = LOWER(p_first_name))
            AND (p_last_name IS NULL OR LOWER(pd.last_name) = LOWER(p_last_name))
            AND (p_date_of_birth IS NULL OR pd.date_of_birth = p_date_of_birth)
        ORDER BY pd.last_name, pd.first_name;
    END IF;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION search_patients IS 'Search for patients by name and DOB with optional fuzzy matching';

-- Get patient summary
CREATE OR REPLACE FUNCTION get_patient_summary(p_patient_id UUID)
RETURNS TABLE (
    mpi_number VARCHAR,
    full_name VARCHAR,
    date_of_birth DATE,
    age INTEGER,
    gender VARCHAR,
    status VARCHAR,
    identifiers JSONB,
    primary_phone VARCHAR,
    primary_email VARCHAR,
    primary_address TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        p.mpi_number,
        CONCAT_WS(' ',
            pd.first_name,
            pd.middle_name,
            pd.last_name,
            pd.name_suffix
        ) AS full_name,
        pd.date_of_birth,
        EXTRACT(YEAR FROM AGE(CURRENT_DATE, pd.date_of_birth))::INTEGER AS age,
        pd.gender,
        p.status,
        (
            SELECT jsonb_object_agg(identifier_type, identifier_value)
            FROM patient_identifiers
            WHERE patient_id = p_patient_id
        ) AS identifiers,
        (
            SELECT contact_value
            FROM patient_contacts
            WHERE patient_id = p_patient_id
                AND contact_type = 'phone_mobile'
                AND is_primary = true
            LIMIT 1
        ) AS primary_phone,
        (
            SELECT contact_value
            FROM patient_contacts
            WHERE patient_id = p_patient_id
                AND contact_type = 'email_personal'
                AND is_primary = true
            LIMIT 1
        ) AS primary_email,
        (
            SELECT address_line_1 || ', ' ||
                   COALESCE(address_line_2 || ', ', '') ||
                   city || ', ' || state || ' ' || postal_code
            FROM patient_addresses
            WHERE patient_id = p_patient_id
                AND is_primary = true
            LIMIT 1
        ) AS primary_address
    FROM patients p
    JOIN patient_demographics pd ON p.patient_id = pd.patient_id
        AND pd.effective_to IS NULL
    WHERE p.patient_id = p_patient_id;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION get_patient_summary IS 'Get comprehensive summary for a single patient';

-- Merge two patient records
CREATE OR REPLACE FUNCTION merge_patients(
    p_source_patient_id UUID,
    p_target_patient_id UUID,
    p_merge_reason TEXT,
    p_merged_by VARCHAR,
    p_confidence_score DECIMAL DEFAULT 1.0
)
RETURNS UUID AS $$
DECLARE
    v_merge_id UUID;
    v_source_snapshot JSONB;
BEGIN
    -- Validate patients exist and are different
    IF p_source_patient_id = p_target_patient_id THEN
        RAISE EXCEPTION 'Cannot merge a patient with itself';
    END IF;

    -- Create snapshot of source patient
    SELECT row_to_json(p.*)::JSONB INTO v_source_snapshot
    FROM patients p
    WHERE patient_id = p_source_patient_id;

    IF v_source_snapshot IS NULL THEN
        RAISE EXCEPTION 'Source patient does not exist';
    END IF;

    -- Record merge in history
    INSERT INTO patient_merge_history (
        source_patient_id,
        target_patient_id,
        merge_reason,
        merged_by,
        confidence_score,
        source_patient_snapshot
    ) VALUES (
        p_source_patient_id,
        p_target_patient_id,
        p_merge_reason,
        p_merged_by,
        p_confidence_score,
        v_source_snapshot
    ) RETURNING merge_id INTO v_merge_id;

    -- Update source patient status
    UPDATE patients
    SET status = 'merged',
        merged_into_patient_id = p_target_patient_id,
        updated_by = p_merged_by,
        updated_at = CURRENT_TIMESTAMP
    WHERE patient_id = p_source_patient_id;

    -- Move identifiers to target patient
    UPDATE patient_identifiers
    SET patient_id = p_target_patient_id,
        updated_by = p_merged_by
    WHERE patient_id = p_source_patient_id
    ON CONFLICT (patient_id, identifier_type, identifier_value) DO NOTHING;

    -- Move addresses to target patient
    UPDATE patient_addresses
    SET patient_id = p_target_patient_id,
        is_primary = false,  -- Preserve target's primary address
        updated_by = p_merged_by
    WHERE patient_id = p_source_patient_id;

    -- Move contacts to target patient
    UPDATE patient_contacts
    SET patient_id = p_target_patient_id,
        is_primary = false,  -- Preserve target's primary contacts
        updated_by = p_merged_by
    WHERE patient_id = p_source_patient_id
    ON CONFLICT (patient_id, contact_type, contact_value) DO NOTHING;

    -- Close out source demographics
    UPDATE patient_demographics
    SET effective_to = CURRENT_TIMESTAMP,
        updated_by = p_merged_by
    WHERE patient_id = p_source_patient_id
        AND effective_to IS NULL;

    RETURN v_merge_id;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION merge_patients IS 'Merge source patient into target patient with full audit trail';

-- Calculate patient age
CREATE OR REPLACE FUNCTION calculate_age(p_date_of_birth DATE)
RETURNS INTEGER AS $$
BEGIN
    RETURN EXTRACT(YEAR FROM AGE(CURRENT_DATE, p_date_of_birth))::INTEGER;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

COMMENT ON FUNCTION calculate_age IS 'Calculate patient age from date of birth';

-- Validate SSN format
CREATE OR REPLACE FUNCTION validate_ssn(p_ssn VARCHAR)
RETURNS BOOLEAN AS $$
BEGIN
    -- Basic SSN format validation (XXX-XX-XXXX)
    RETURN p_ssn ~ '^\d{3}-\d{2}-\d{4}$';
END;
$$ LANGUAGE plpgsql IMMUTABLE;

COMMENT ON FUNCTION validate_ssn IS 'Validate SSN format (XXX-XX-XXXX)';

-- ============================================================================
-- STATISTICS FUNCTIONS
-- ============================================================================

-- Get MPI statistics
CREATE OR REPLACE FUNCTION get_mpi_statistics()
RETURNS TABLE (
    total_patients BIGINT,
    active_patients BIGINT,
    deceased_patients BIGINT,
    merged_patients BIGINT,
    pending_matches BIGINT,
    total_identifiers BIGINT,
    audit_log_entries BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        COUNT(*) FILTER (WHERE deleted_at IS NULL),
        COUNT(*) FILTER (WHERE status = 'active'),
        COUNT(*) FILTER (WHERE status = 'deceased'),
        COUNT(*) FILTER (WHERE status = 'merged'),
        (SELECT COUNT(*) FROM patient_match_candidates WHERE review_status = 'pending'),
        (SELECT COUNT(*) FROM patient_identifiers),
        (SELECT COUNT(*) FROM audit_log)
    FROM patients;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION get_mpi_statistics IS 'Get comprehensive MPI system statistics';

-- ============================================================================
-- EXAMPLE USAGE
-- ============================================================================

/*
-- Search for patients
SELECT * FROM search_patients('John', 'Smith', '1985-06-15', false);

-- Fuzzy search
SELECT * FROM search_patients('Jon', 'Smyth', NULL, true);

-- Get patient summary
SELECT * FROM get_patient_summary('patient-uuid-here');

-- Get MPI statistics
SELECT * FROM get_mpi_statistics();

-- View all patients with identifiers
SELECT * FROM v_patient_with_identifiers;

-- View pending duplicate matches
SELECT * FROM v_pending_matches;

-- Merge patients (use with caution!)
SELECT merge_patients(
    'source-patient-uuid',
    'target-patient-uuid',
    'Duplicate record found during data quality review',
    'admin_user',
    0.95
);
*/
