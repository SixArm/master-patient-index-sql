-- ============================================================================
-- Master Patient Index (MPI) - Patient Matching and Linking
-- PostgreSQL 18
-- ============================================================================
-- Purpose: Deterministic and probabilistic matching, soft merge linking
-- HIPAA Compliant | UK DPA 2018 Compliant
-- ============================================================================

-- ============================================================================
-- Matching Algorithm Configuration
-- ============================================================================

CREATE TABLE matching.algorithm_config (
    config_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    algorithm_name VARCHAR(100) NOT NULL UNIQUE,
    algorithm_type VARCHAR(50) NOT NULL, -- 'deterministic', 'probabilistic', 'hybrid'
    algorithm_version VARCHAR(50) NOT NULL,
    -- Configuration
    enabled BOOLEAN DEFAULT TRUE,
    priority INTEGER DEFAULT 100, -- Lower = higher priority
    min_confidence_threshold DECIMAL(3,2) DEFAULT 0.80 CHECK (min_confidence_threshold BETWEEN 0 AND 1),
    auto_link_threshold DECIMAL(3,2) DEFAULT 0.95 CHECK (auto_link_threshold BETWEEN 0 AND 1),
    -- Rules and weights in JSON
    matching_rules JSONB NOT NULL,
    field_weights JSONB, -- Weights for different fields in scoring
    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_by VARCHAR(255) NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE,
    updated_by VARCHAR(255),
    metadata JSONB
);

COMMENT ON TABLE matching.algorithm_config IS 'Configuration for patient matching algorithms';
COMMENT ON COLUMN matching.algorithm_config.min_confidence_threshold IS 'Minimum score to consider a potential match';
COMMENT ON COLUMN matching.algorithm_config.auto_link_threshold IS 'Minimum score to automatically link records';

-- Insert default configurations
INSERT INTO matching.algorithm_config (algorithm_name, algorithm_type, algorithm_version, matching_rules, field_weights, created_by)
VALUES
-- Deterministic matching on government ID
('govt_id_exact', 'deterministic', '1.0',
 '{"fields": ["government_id"], "match_type": "exact"}',
 '{"government_id": 1.0}', 'system'),
-- Deterministic matching on insurance ID
('insurance_id_exact', 'deterministic', '1.0',
 '{"fields": ["insurance_id"], "match_type": "exact"}',
 '{"insurance_id": 1.0}', 'system'),
-- Deterministic matching on MRN + facility
('mrn_facility_exact', 'deterministic', '1.0',
 '{"fields": ["mrn", "facility"], "match_type": "exact"}',
 '{"mrn": 1.0}', 'system'),
-- Probabilistic matching
('probabilistic_standard', 'probabilistic', '1.0',
 '{"fields": ["name", "dob", "phone", "address"], "match_type": "fuzzy"}',
 '{"name": 0.35, "dob": 0.30, "phone": 0.20, "address": 0.15}', 'system');

-- ============================================================================
-- Potential Duplicates Table
-- ============================================================================

CREATE TABLE matching.potential_duplicate (
    potential_duplicate_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    -- Patient records being compared
    patient_id_1 UUID NOT NULL REFERENCES core.patient(patient_id),
    patient_id_2 UUID NOT NULL REFERENCES core.patient(patient_id),
    -- Matching details
    algorithm_used VARCHAR(100) REFERENCES matching.algorithm_config(algorithm_name),
    confidence_score DECIMAL(5,4) CHECK (confidence_score BETWEEN 0 AND 1),
    confidence_level matching.confidence_level,
    -- Matching attributes breakdown
    match_details JSONB, -- Detailed breakdown of which fields matched and scores
    -- Status and review
    status VARCHAR(50) DEFAULT 'pending_review', -- 'pending_review', 'confirmed_duplicate', 'rejected', 'auto_linked'
    reviewed BOOLEAN DEFAULT FALSE,
    reviewed_by VARCHAR(255),
    reviewed_at TIMESTAMP WITH TIME ZONE,
    review_notes TEXT,
    -- Action taken
    action_taken VARCHAR(50), -- 'linked', 'rejected', 'needs_review', null
    action_by VARCHAR(255),
    action_at TIMESTAMP WITH TIME ZONE,
    -- System fields
    detected_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    detected_by VARCHAR(255) DEFAULT 'system',
    expires_at TIMESTAMP WITH TIME ZONE, -- Auto-expire old potential duplicates
    metadata JSONB,
    CONSTRAINT different_patients CHECK (patient_id_1 != patient_id_2),
    CONSTRAINT ordered_patient_ids CHECK (patient_id_1 < patient_id_2) -- Ensure consistent ordering
);

COMMENT ON TABLE matching.potential_duplicate IS 'Potential duplicate patient records detected by matching algorithms';
COMMENT ON COLUMN matching.potential_duplicate.confidence_score IS 'Match confidence score 0.0-1.0';
COMMENT ON COLUMN matching.potential_duplicate.match_details IS 'Detailed breakdown of matching fields and scores';

-- Indexes
CREATE INDEX idx_potential_dup_patient1 ON matching.potential_duplicate(patient_id_1);
CREATE INDEX idx_potential_dup_patient2 ON matching.potential_duplicate(patient_id_2);
CREATE INDEX idx_potential_dup_status ON matching.potential_duplicate(status) WHERE status = 'pending_review';
CREATE INDEX idx_potential_dup_score ON matching.potential_duplicate(confidence_score DESC);
CREATE INDEX idx_potential_dup_unreviewed ON matching.potential_duplicate(reviewed) WHERE reviewed = FALSE;
CREATE INDEX idx_potential_dup_detected ON matching.potential_duplicate(detected_at DESC);

-- Unique constraint: one potential duplicate per pair
CREATE UNIQUE INDEX uniq_potential_dup_pair ON matching.potential_duplicate(patient_id_1, patient_id_2);

-- ============================================================================
-- Patient Links (Soft Merge)
-- ============================================================================

CREATE TABLE matching.patient_link (
    link_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    -- Master and child records
    master_patient_id UUID NOT NULL REFERENCES core.patient(patient_id),
    child_patient_id UUID NOT NULL REFERENCES core.patient(patient_id),
    -- Link details
    link_type matching.link_type NOT NULL DEFAULT 'duplicate',
    link_status matching.link_status NOT NULL DEFAULT 'proposed',
    confidence_level matching.confidence_level,
    -- Link hierarchy (prevent circular links)
    link_level INTEGER DEFAULT 1, -- 1 = direct link, 2+ = transitive
    root_patient_id UUID, -- Ultimate master in chain
    -- Reason and evidence
    link_reason TEXT,
    evidence JSONB, -- Evidence supporting the link (matching fields, scores, etc.)
    potential_duplicate_id UUID REFERENCES matching.potential_duplicate(potential_duplicate_id),
    -- Link management
    linked_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    linked_by VARCHAR(255) NOT NULL,
    linking_method VARCHAR(100), -- 'auto', 'manual', 'admin_override'
    -- Unlink information
    unlinked BOOLEAN DEFAULT FALSE,
    unlinked_at TIMESTAMP WITH TIME ZONE,
    unlinked_by VARCHAR(255),
    unlink_reason TEXT,
    -- Approval workflow
    requires_approval BOOLEAN DEFAULT FALSE,
    approved BOOLEAN,
    approved_by VARCHAR(255),
    approved_at TIMESTAMP WITH TIME ZONE,
    -- System fields
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_by VARCHAR(255) NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE,
    updated_by VARCHAR(255),
    metadata JSONB,
    CONSTRAINT different_patient_link CHECK (master_patient_id != child_patient_id),
    CONSTRAINT valid_approval CHECK (
        requires_approval = FALSE OR
        (requires_approval = TRUE AND (approved IS NOT NULL))
    )
);

COMMENT ON TABLE matching.patient_link IS 'Patient record links (soft merge) with hierarchical support';
COMMENT ON COLUMN matching.patient_link.master_patient_id IS 'Master patient record in the link';
COMMENT ON COLUMN matching.patient_link.child_patient_id IS 'Child patient record (linked to master)';
COMMENT ON COLUMN matching.patient_link.link_level IS 'Link level in hierarchy (1=direct, 2+=transitive)';
COMMENT ON COLUMN matching.patient_link.root_patient_id IS 'Ultimate master patient in link chain';

-- Indexes
CREATE INDEX idx_patient_link_master ON matching.patient_link(master_patient_id) WHERE unlinked = FALSE;
CREATE INDEX idx_patient_link_child ON matching.patient_link(child_patient_id) WHERE unlinked = FALSE;
CREATE INDEX idx_patient_link_root ON matching.patient_link(root_patient_id) WHERE unlinked = FALSE;
CREATE INDEX idx_patient_link_type ON matching.patient_link(link_type);
CREATE INDEX idx_patient_link_status ON matching.patient_link(link_status);
CREATE INDEX idx_patient_link_unlinked ON matching.patient_link(unlinked) WHERE unlinked = FALSE;
CREATE INDEX idx_patient_link_approval ON matching.patient_link(requires_approval, approved) WHERE requires_approval = TRUE;
CREATE INDEX idx_patient_link_created ON matching.patient_link(created_at DESC);

-- Unique constraint: one active link per child
CREATE UNIQUE INDEX uniq_patient_link_child ON matching.patient_link(child_patient_id)
    WHERE unlinked = FALSE AND link_status IN ('confirmed', 'auto_confirmed');

-- ============================================================================
-- Deterministic Matching Functions
-- ============================================================================

-- Match by government ID
CREATE OR REPLACE FUNCTION matching.match_by_government_id(
    p_country_code CHAR(2),
    p_id_type VARCHAR,
    p_id_value TEXT,
    p_exclude_patient_id UUID DEFAULT NULL
)
RETURNS TABLE(
    patient_id UUID,
    confidence_score DECIMAL,
    match_details JSONB
) AS $$
DECLARE
    v_hash BYTEA;
BEGIN
    v_hash := security.hash_value(p_id_value);

    RETURN QUERY
    SELECT
        g.patient_id,
        1.00::DECIMAL as confidence_score,
        jsonb_build_object(
            'match_type', 'deterministic',
            'match_field', 'government_id',
            'country_code', p_country_code,
            'id_type', p_id_type
        ) as match_details
    FROM core.patient_government_id g
    WHERE g.country_code = p_country_code
        AND g.id_type = p_id_type
        AND g.id_value_hash = v_hash
        AND g.is_current = TRUE
        AND g.deleted_at IS NULL
        AND (p_exclude_patient_id IS NULL OR g.patient_id != p_exclude_patient_id);
END;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION matching.match_by_government_id IS 'Deterministic matching by government ID';

-- Match by MRN + Facility
CREATE OR REPLACE FUNCTION matching.match_by_mrn(
    p_facility_name VARCHAR,
    p_mrn VARCHAR,
    p_exclude_patient_id UUID DEFAULT NULL
)
RETURNS TABLE(
    patient_id UUID,
    confidence_score DECIMAL,
    match_details JSONB
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        m.patient_id,
        1.00::DECIMAL as confidence_score,
        jsonb_build_object(
            'match_type', 'deterministic',
            'match_field', 'mrn',
            'facility', p_facility_name,
            'mrn', p_mrn
        ) as match_details
    FROM core.patient_mrn m
    WHERE m.facility_name = p_facility_name
        AND m.mrn = p_mrn
        AND m.is_current = TRUE
        AND m.deleted_at IS NULL
        AND (p_exclude_patient_id IS NULL OR m.patient_id != p_exclude_patient_id);
END;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION matching.match_by_mrn IS 'Deterministic matching by MRN and facility';

-- ============================================================================
-- Probabilistic Matching Functions
-- ============================================================================

-- Calculate Jaro-Winkler distance (fuzzy string matching)
-- Note: In production, use pg_similarity extension or implement more sophisticated algorithms
CREATE OR REPLACE FUNCTION matching.jaro_winkler_distance(
    p_string1 TEXT,
    p_string2 TEXT
)
RETURNS DECIMAL AS $$
DECLARE
    v_len1 INTEGER;
    v_len2 INTEGER;
    v_match_distance INTEGER;
    v_matches INTEGER := 0;
    v_transpositions INTEGER := 0;
    v_jaro DECIMAL;
    v_prefix INTEGER := 0;
BEGIN
    -- Handle null or empty strings
    IF p_string1 IS NULL OR p_string2 IS NULL THEN
        RETURN 0;
    END IF;

    IF p_string1 = p_string2 THEN
        RETURN 1.0;
    END IF;

    v_len1 := length(p_string1);
    v_len2 := length(p_string2);

    IF v_len1 = 0 OR v_len2 = 0 THEN
        RETURN 0;
    END IF;

    -- Simplified implementation - in production use pg_similarity or more complete implementation
    -- This is a placeholder
    -- Calculate similarity using Levenshtein as approximation
    v_jaro := 1.0 - (levenshtein(p_string1, p_string2)::DECIMAL / GREATEST(v_len1, v_len2));

    RETURN GREATEST(0, LEAST(1, v_jaro));
END;
$$ LANGUAGE plpgsql IMMUTABLE;
COMMENT ON FUNCTION matching.jaro_winkler_distance IS 'Calculates Jaro-Winkler distance for fuzzy matching';

-- Probabilistic match by demographics
CREATE OR REPLACE FUNCTION matching.probabilistic_match(
    p_patient_id UUID,
    p_min_confidence DECIMAL DEFAULT 0.80
)
RETURNS TABLE(
    matched_patient_id UUID,
    confidence_score DECIMAL,
    match_details JSONB
) AS $$
DECLARE
    v_patient RECORD;
    v_name RECORD;
    v_demographic RECORD;
BEGIN
    -- Get patient details
    SELECT * INTO v_patient FROM core.patient WHERE patient_id = p_patient_id;
    SELECT * INTO v_name FROM core.patient_name WHERE patient_id = p_patient_id AND is_current = TRUE AND name_type = 'legal' LIMIT 1;
    SELECT * INTO v_demographic FROM core.patient_demographic WHERE patient_id = p_patient_id AND is_current = TRUE LIMIT 1;

    IF NOT FOUND THEN
        RETURN;
    END IF;

    -- Find potential matches based on soundex/metaphone and DOB
    RETURN QUERY
    SELECT
        n.patient_id as matched_patient_id,
        (
            -- Name match score (35% weight)
            (CASE
                WHEN n.soundex_family = v_name.soundex_family AND n.soundex_given = v_name.soundex_given THEN 0.35
                WHEN n.soundex_family = v_name.soundex_family THEN 0.25
                WHEN n.metaphone_family = v_name.metaphone_family THEN 0.20
                ELSE 0.10 * matching.jaro_winkler_distance(
                    array_to_string(n.family_names, ' '),
                    array_to_string(v_name.family_names, ' ')
                )
            END) +
            -- DOB match score (30% weight)
            (CASE
                WHEN p.date_of_birth = v_patient.date_of_birth THEN 0.30
                WHEN ABS(EXTRACT(YEAR FROM p.date_of_birth) - EXTRACT(YEAR FROM v_patient.date_of_birth)) <= 1 THEN 0.10
                ELSE 0.00
            END) +
            -- Gender match score (10% weight)
            (CASE
                WHEN p.biological_sex = v_patient.biological_sex THEN 0.10
                ELSE 0.00
            END) +
            -- Additional fuzzy matching could be added for phone, address, etc. (25% weight available)
            0.00
        )::DECIMAL(5,4) as confidence_score,
        jsonb_build_object(
            'match_type', 'probabilistic',
            'name_match', n.soundex_family = v_name.soundex_family,
            'dob_match', p.date_of_birth = v_patient.date_of_birth,
            'sex_match', p.biological_sex = v_patient.biological_sex
        ) as match_details
    FROM core.patient p
    JOIN core.patient_name n ON p.patient_id = n.patient_id
    WHERE p.patient_id != p_patient_id
        AND n.is_current = TRUE
        AND n.name_type = 'legal'
        AND (
            -- Soundex match on family name
            n.soundex_family = v_name.soundex_family
            -- OR DOB match with similar name
            OR (p.date_of_birth = v_patient.date_of_birth AND
                matching.jaro_winkler_distance(
                    array_to_string(n.family_names, ' '),
                    array_to_string(v_name.family_names, ' ')
                ) > 0.8)
        )
    HAVING confidence_score >= p_min_confidence
    ORDER BY confidence_score DESC
    LIMIT 100;
END;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION matching.probabilistic_match IS 'Probabilistic matching based on demographics and fuzzy matching';

-- ============================================================================
-- Patient Linking Functions
-- ============================================================================

-- Link two patient records (soft merge)
CREATE OR REPLACE FUNCTION matching.link_patients(
    p_master_patient_id UUID,
    p_child_patient_id UUID,
    p_link_type matching.link_type,
    p_link_reason TEXT DEFAULT NULL,
    p_evidence JSONB DEFAULT NULL,
    p_linked_by VARCHAR DEFAULT CURRENT_USER,
    p_auto_approve BOOLEAN DEFAULT FALSE
)
RETURNS UUID AS $$
DECLARE
    v_link_id UUID;
    v_root_patient_id UUID;
    v_link_level INTEGER;
    v_requires_approval BOOLEAN;
BEGIN
    -- Validate that patients exist and are not already linked
    IF NOT EXISTS (SELECT 1 FROM core.patient WHERE patient_id = p_master_patient_id) THEN
        RAISE EXCEPTION 'Master patient % does not exist', p_master_patient_id;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM core.patient WHERE patient_id = p_child_patient_id) THEN
        RAISE EXCEPTION 'Child patient % does not exist', p_child_patient_id;
    END IF;

    -- Check for existing link
    IF EXISTS (SELECT 1 FROM matching.patient_link
               WHERE child_patient_id = p_child_patient_id
               AND unlinked = FALSE
               AND link_status IN ('confirmed', 'auto_confirmed')) THEN
        RAISE EXCEPTION 'Patient % is already linked to another record', p_child_patient_id;
    END IF;

    -- Check for circular link
    IF EXISTS (SELECT 1 FROM matching.patient_link
               WHERE master_patient_id = p_child_patient_id
               AND child_patient_id = p_master_patient_id
               AND unlinked = FALSE) THEN
        RAISE EXCEPTION 'Circular link detected between % and %', p_master_patient_id, p_child_patient_id;
    END IF;

    -- Determine root patient (if master is already a child, use its master)
    SELECT COALESCE(root_patient_id, master_patient_id), link_level + 1
    INTO v_root_patient_id, v_link_level
    FROM matching.patient_link
    WHERE child_patient_id = p_master_patient_id
        AND unlinked = FALSE
        AND link_status IN ('confirmed', 'auto_confirmed')
    LIMIT 1;

    IF v_root_patient_id IS NULL THEN
        v_root_patient_id := p_master_patient_id;
        v_link_level := 1;
    END IF;

    -- Determine if approval is required (auto-approve for high confidence or if specified)
    v_requires_approval := NOT p_auto_approve;

    -- Create link
    INSERT INTO matching.patient_link (
        master_patient_id,
        child_patient_id,
        link_type,
        link_status,
        link_level,
        root_patient_id,
        link_reason,
        evidence,
        linked_by,
        linking_method,
        requires_approval,
        approved,
        approved_by,
        approved_at,
        created_by
    ) VALUES (
        p_master_patient_id,
        p_child_patient_id,
        p_link_type,
        CASE WHEN p_auto_approve THEN 'auto_confirmed'::matching.link_status ELSE 'proposed'::matching.link_status END,
        v_link_level,
        v_root_patient_id,
        p_link_reason,
        p_evidence,
        p_linked_by,
        CASE WHEN p_auto_approve THEN 'auto' ELSE 'manual' END,
        v_requires_approval,
        CASE WHEN p_auto_approve THEN TRUE ELSE NULL END,
        CASE WHEN p_auto_approve THEN p_linked_by ELSE NULL END,
        CASE WHEN p_auto_approve THEN CURRENT_TIMESTAMP ELSE NULL END,
        p_linked_by
    ) RETURNING link_id INTO v_link_id;

    -- Update child patient record status
    UPDATE core.patient
    SET record_status = 'merged',
        updated_at = CURRENT_TIMESTAMP,
        updated_by = p_linked_by
    WHERE patient_id = p_child_patient_id;

    RETURN v_link_id;
END;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION matching.link_patients IS 'Links two patient records (soft merge)';

-- Unlink patient records
CREATE OR REPLACE FUNCTION matching.unlink_patients(
    p_link_id UUID,
    p_unlink_reason TEXT,
    p_unlinked_by VARCHAR DEFAULT CURRENT_USER
)
RETURNS BOOLEAN AS $$
DECLARE
    v_child_patient_id UUID;
BEGIN
    -- Get child patient ID
    SELECT child_patient_id INTO v_child_patient_id
    FROM matching.patient_link
    WHERE link_id = p_link_id AND unlinked = FALSE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Link % not found or already unlinked', p_link_id;
    END IF;

    -- Mark link as unlinked
    UPDATE matching.patient_link
    SET unlinked = TRUE,
        unlinked_at = CURRENT_TIMESTAMP,
        unlinked_by = p_unlinked_by,
        unlink_reason = p_unlink_reason,
        updated_at = CURRENT_TIMESTAMP,
        updated_by = p_unlinked_by
    WHERE link_id = p_link_id;

    -- Restore child patient record status
    UPDATE core.patient
    SET record_status = 'active',
        updated_at = CURRENT_TIMESTAMP,
        updated_by = p_unlinked_by
    WHERE patient_id = v_child_patient_id;

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION matching.unlink_patients IS 'Unlinks previously linked patient records';

-- Get all linked records for a patient (traverses hierarchy)
CREATE OR REPLACE FUNCTION matching.get_linked_patients(
    p_patient_id UUID
)
RETURNS TABLE(
    patient_id UUID,
    link_id UUID,
    relationship VARCHAR,
    link_level INTEGER,
    link_status matching.link_status
) AS $$
BEGIN
    RETURN QUERY
    WITH RECURSIVE link_tree AS (
        -- Direct links where patient is master
        SELECT
            l.child_patient_id as patient_id,
            l.link_id,
            'child'::VARCHAR as relationship,
            l.link_level,
            l.link_status
        FROM matching.patient_link l
        WHERE l.master_patient_id = p_patient_id
            AND l.unlinked = FALSE

        UNION ALL

        -- Direct link where patient is child (get master)
        SELECT
            l.master_patient_id as patient_id,
            l.link_id,
            'master'::VARCHAR as relationship,
            l.link_level,
            l.link_status
        FROM matching.patient_link l
        WHERE l.child_patient_id = p_patient_id
            AND l.unlinked = FALSE

        UNION ALL

        -- Transitive links (siblings through same master)
        SELECT
            l2.child_patient_id as patient_id,
            l2.link_id,
            'sibling'::VARCHAR as relationship,
            l2.link_level,
            l2.link_status
        FROM link_tree lt
        JOIN matching.patient_link l2 ON lt.patient_id = l2.master_patient_id
        WHERE l2.unlinked = FALSE
            AND l2.child_patient_id != p_patient_id
    )
    SELECT DISTINCT * FROM link_tree;
END;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION matching.get_linked_patients IS 'Returns all linked patients (recursive traversal)';

-- ============================================================================
-- Grant Permissions
-- ============================================================================

GRANT SELECT ON matching.algorithm_config TO mpi_clinical_user, mpi_admin, mpi_integration;
GRANT UPDATE ON matching.algorithm_config TO mpi_admin;

GRANT SELECT ON matching.potential_duplicate TO mpi_clinical_user, mpi_admin;
GRANT INSERT ON matching.potential_duplicate TO mpi_clinical_user, mpi_admin, mpi_integration;
GRANT UPDATE (status, reviewed, reviewed_by, reviewed_at, review_notes, action_taken, action_by, action_at) ON matching.potential_duplicate TO mpi_clinical_user, mpi_admin;

GRANT SELECT ON matching.patient_link TO mpi_clinical_user, mpi_admin, mpi_integration;
GRANT INSERT ON matching.patient_link TO mpi_clinical_user, mpi_admin;
GRANT UPDATE (approved, approved_by, approved_at, unlinked, unlinked_at, unlinked_by, unlink_reason) ON matching.patient_link TO mpi_clinical_user, mpi_admin;

GRANT EXECUTE ON FUNCTION matching.match_by_government_id TO mpi_clinical_user, mpi_admin, mpi_integration;
GRANT EXECUTE ON FUNCTION matching.match_by_mrn TO mpi_clinical_user, mpi_admin, mpi_integration;
GRANT EXECUTE ON FUNCTION matching.probabilistic_match TO mpi_clinical_user, mpi_admin, mpi_integration;
GRANT EXECUTE ON FUNCTION matching.link_patients TO mpi_clinical_user, mpi_admin;
GRANT EXECUTE ON FUNCTION matching.unlink_patients TO mpi_clinical_user, mpi_admin;
GRANT EXECUTE ON FUNCTION matching.get_linked_patients TO mpi_clinical_user, mpi_admin, mpi_integration;

-- ============================================================================
-- Matching and Linking Complete
-- ============================================================================
