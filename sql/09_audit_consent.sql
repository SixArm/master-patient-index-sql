-- ============================================================================
-- Master Patient Index (MPI) - Audit Trail and Consent Management
-- PostgreSQL 18
-- ============================================================================
-- Purpose: HIPAA-compliant audit trail and privacy/consent management
-- HIPAA Compliant | UK DPA 2018 Compliant
-- ============================================================================

-- ============================================================================
-- Comprehensive Audit Log
-- ============================================================================

CREATE TABLE audit.audit_log (
    audit_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    -- Who (user information)
    user_name VARCHAR(255) NOT NULL,
    user_role VARCHAR(100),
    session_id VARCHAR(255),
    -- What (action details)
    action_type audit.action_type NOT NULL,
    table_schema VARCHAR(100) NOT NULL,
    table_name VARCHAR(100) NOT NULL,
    record_id UUID, -- Primary key of affected record
    -- What changed (before/after values)
    old_values JSONB,
    new_values JSONB,
    changed_fields TEXT[], -- Array of field names that changed
    -- When
    action_timestamp TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    transaction_id BIGINT DEFAULT txid_current(),
    -- Where (network/system information)
    client_ip_address INET,
    client_port INTEGER,
    application_name VARCHAR(255),
    database_name VARCHAR(100),
    -- Why (business reason)
    business_reason TEXT,
    -- Additional context
    patient_id UUID, -- For easier querying of patient-related audits
    related_entity_type VARCHAR(100), -- 'patient', 'provider', 'facility', etc.
    related_entity_id UUID,
    -- Request context
    request_id VARCHAR(255), -- For tracing across multiple operations
    parent_audit_id UUID REFERENCES audit.audit_log(audit_id), -- For hierarchical operations
    -- Metadata
    additional_context JSONB,
    -- Tamper detection (optional signed hash)
    record_hash VARCHAR(64), -- SHA-256 hash of record for integrity
    CONSTRAINT valid_action_data CHECK (
        (action_type = 'select' AND old_values IS NULL AND new_values IS NULL) OR
        (action_type = 'insert' AND old_values IS NULL AND new_values IS NOT NULL) OR
        (action_type = 'update' AND old_values IS NOT NULL AND new_values IS NOT NULL) OR
        (action_type = 'delete' AND old_values IS NOT NULL AND new_values IS NULL) OR
        (action_type IN ('merge', 'unmerge', 'link', 'unlink', 'access', 'export', 'emergency_access'))
    )
);

COMMENT ON TABLE audit.audit_log IS 'Comprehensive HIPAA-compliant audit trail';
COMMENT ON COLUMN audit.audit_log.user_name IS 'User who performed the action';
COMMENT ON COLUMN audit.audit_log.action_type IS 'Type of action (insert, update, delete, select, etc.)';
COMMENT ON COLUMN audit.audit_log.old_values IS 'Values before change (UPDATE/DELETE)';
COMMENT ON COLUMN audit.audit_log.new_values IS 'Values after change (INSERT/UPDATE)';
COMMENT ON COLUMN audit.audit_log.transaction_id IS 'PostgreSQL transaction ID';
COMMENT ON COLUMN audit.audit_log.record_hash IS 'SHA-256 hash for tamper detection';

-- Indexes (partitioning recommended for production)
CREATE INDEX idx_audit_log_timestamp ON audit.audit_log(action_timestamp DESC);
CREATE INDEX idx_audit_log_user ON audit.audit_log(user_name, action_timestamp DESC);
CREATE INDEX idx_audit_log_table ON audit.audit_log(table_schema, table_name, action_timestamp DESC);
CREATE INDEX idx_audit_log_patient ON audit.audit_log(patient_id, action_timestamp DESC) WHERE patient_id IS NOT NULL;
CREATE INDEX idx_audit_log_action ON audit.audit_log(action_type, action_timestamp DESC);
CREATE INDEX idx_audit_log_record ON audit.audit_log(record_id, action_timestamp DESC) WHERE record_id IS NOT NULL;
CREATE INDEX idx_audit_log_transaction ON audit.audit_log(transaction_id);
CREATE INDEX idx_audit_log_request ON audit.audit_log(request_id) WHERE request_id IS NOT NULL;

-- ============================================================================
-- Generic Audit Trigger Function
-- ============================================================================

CREATE OR REPLACE FUNCTION audit.log_audit_event()
RETURNS TRIGGER AS $$
DECLARE
    v_old_values JSONB;
    v_new_values JSONB;
    v_changed_fields TEXT[];
    v_action_type audit.action_type;
    v_patient_id UUID;
    v_user_context JSONB;
BEGIN
    -- Determine action type
    v_action_type := CASE TG_OP
        WHEN 'INSERT' THEN 'insert'::audit.action_type
        WHEN 'UPDATE' THEN 'update'::audit.action_type
        WHEN 'DELETE' THEN 'delete'::audit.action_type
    END;

    -- Get user context
    v_user_context := security.get_user_context();

    -- Build old/new values
    IF TG_OP = 'DELETE' THEN
        v_old_values := to_jsonb(OLD);
        v_new_values := NULL;
        -- Try to get patient_id if column exists
        v_patient_id := (to_jsonb(OLD) ->> 'patient_id')::UUID;
    ELSIF TG_OP = 'INSERT' THEN
        v_old_values := NULL;
        v_new_values := to_jsonb(NEW);
        v_patient_id := (to_jsonb(NEW) ->> 'patient_id')::UUID;
    ELSE -- UPDATE
        v_old_values := to_jsonb(OLD);
        v_new_values := to_jsonb(NEW);
        v_patient_id := (to_jsonb(NEW) ->> 'patient_id')::UUID;

        -- Determine which fields changed
        SELECT array_agg(key)
        INTO v_changed_fields
        FROM jsonb_each(v_new_values)
        WHERE v_new_values -> key IS DISTINCT FROM v_old_values -> key;
    END IF;

    -- Insert audit record
    INSERT INTO audit.audit_log (
        user_name,
        user_role,
        action_type,
        table_schema,
        table_name,
        record_id,
        old_values,
        new_values,
        changed_fields,
        client_ip_address,
        client_port,
        application_name,
        database_name,
        patient_id,
        related_entity_type,
        additional_context
    ) VALUES (
        v_user_context ->> 'user',
        CASE
            WHEN pg_has_role(CURRENT_USER, 'mpi_admin', 'MEMBER') THEN 'admin'
            WHEN pg_has_role(CURRENT_USER, 'mpi_clinical_user', 'MEMBER') THEN 'clinical'
            WHEN pg_has_role(CURRENT_USER, 'mpi_integration', 'MEMBER') THEN 'integration'
            ELSE 'unknown'
        END,
        v_action_type,
        TG_TABLE_SCHEMA,
        TG_TABLE_NAME,
        COALESCE(
            (v_new_values ->> 'id')::UUID,
            (v_new_values ->> 'patient_id')::UUID,
            (v_old_values ->> 'id')::UUID,
            (v_old_values ->> 'patient_id')::UUID
        ),
        v_old_values,
        v_new_values,
        v_changed_fields,
        (v_user_context ->> 'client_addr')::INET,
        (v_user_context ->> 'client_port')::INTEGER,
        v_user_context ->> 'application_name',
        current_database(),
        v_patient_id,
        TG_TABLE_NAME,
        v_user_context
    );

    RETURN CASE TG_OP
        WHEN 'DELETE' THEN OLD
        ELSE NEW
    END;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
COMMENT ON FUNCTION audit.log_audit_event IS 'Generic trigger function for audit logging';

-- ============================================================================
-- Data Access Audit
-- ============================================================================

CREATE TABLE audit.data_access_log (
    access_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    -- Who accessed
    user_name VARCHAR(255) NOT NULL,
    user_role VARCHAR(100),
    session_id VARCHAR(255),
    -- What was accessed
    patient_id UUID NOT NULL,
    access_type VARCHAR(50) NOT NULL, -- 'view', 'search', 'export', 'print'
    data_elements_accessed TEXT[], -- Which fields were viewed
    purpose VARCHAR(255), -- Purpose of access (treatment, payment, operations, research)
    -- When
    access_timestamp TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    -- Where
    client_ip_address INET,
    application_name VARCHAR(255),
    -- Context
    query_used TEXT, -- SQL query or API endpoint
    num_records_accessed INTEGER,
    success BOOLEAN DEFAULT TRUE,
    failure_reason TEXT,
    -- Emergency access
    is_emergency_access BOOLEAN DEFAULT FALSE,
    emergency_access_id UUID REFERENCES security.emergency_access_log(access_id),
    -- Metadata
    metadata JSONB
);

COMMENT ON TABLE audit.data_access_log IS 'Log of all patient data access for HIPAA compliance';
COMMENT ON COLUMN audit.data_access_log.purpose IS 'Purpose of access (TPO - Treatment, Payment, Operations)';

-- Indexes
CREATE INDEX idx_data_access_timestamp ON audit.data_access_log(access_timestamp DESC);
CREATE INDEX idx_data_access_user ON audit.data_access_log(user_name, access_timestamp DESC);
CREATE INDEX idx_data_access_patient ON audit.data_access_log(patient_id, access_timestamp DESC);
CREATE INDEX idx_data_access_type ON audit.data_access_log(access_type);
CREATE INDEX idx_data_access_emergency ON audit.data_access_log(is_emergency_access) WHERE is_emergency_access = TRUE;

-- Function to log data access
CREATE OR REPLACE FUNCTION audit.log_data_access(
    p_patient_id UUID,
    p_access_type VARCHAR,
    p_data_elements TEXT[] DEFAULT NULL,
    p_purpose VARCHAR DEFAULT 'treatment',
    p_is_emergency BOOLEAN DEFAULT FALSE
)
RETURNS UUID AS $$
DECLARE
    v_access_id UUID;
    v_user_context JSONB;
BEGIN
    v_user_context := security.get_user_context();

    INSERT INTO audit.data_access_log (
        user_name,
        user_role,
        patient_id,
        access_type,
        data_elements_accessed,
        purpose,
        client_ip_address,
        application_name,
        is_emergency_access
    ) VALUES (
        v_user_context ->> 'user',
        CASE
            WHEN pg_has_role(CURRENT_USER, 'mpi_admin', 'MEMBER') THEN 'admin'
            WHEN pg_has_role(CURRENT_USER, 'mpi_clinical_user', 'MEMBER') THEN 'clinical'
            ELSE 'unknown'
        END,
        p_patient_id,
        p_access_type,
        p_data_elements,
        p_purpose,
        (v_user_context ->> 'client_addr')::INET,
        v_user_context ->> 'application_name',
        p_is_emergency
    ) RETURNING access_id INTO v_access_id;

    RETURN v_access_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
COMMENT ON FUNCTION audit.log_data_access IS 'Logs patient data access for HIPAA compliance';

-- ============================================================================
-- Patient Consent Management
-- ============================================================================

CREATE TABLE core.patient_consent (
    consent_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    patient_id UUID NOT NULL REFERENCES core.patient(patient_id),
    -- Consent details
    consent_type core.consent_type NOT NULL,
    consent_status core.consent_status NOT NULL DEFAULT 'pending',
    -- Specific consent scope
    consent_scope VARCHAR(255), -- Specific scope within type
    data_categories TEXT[], -- Categories of data covered
    permitted_purposes TEXT[], -- Permitted uses
    permitted_recipients TEXT[], -- Who can access
    -- Consent period
    effective_from TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    effective_to TIMESTAMP WITH TIME ZONE,
    -- Consent capture
    consent_given_by VARCHAR(255), -- Patient or authorized representative
    consent_method VARCHAR(100) NOT NULL, -- 'written', 'verbal', 'electronic', 'implied'
    consent_form_version VARCHAR(50),
    consent_language VARCHAR(10), -- ISO language code
    consent_document_url VARCHAR(500), -- Link to scanned consent form
    witness_name VARCHAR(255),
    witness_signature VARCHAR(255),
    -- Status changes
    granted_at TIMESTAMP WITH TIME ZONE,
    granted_by VARCHAR(255),
    withdrawn_at TIMESTAMP WITH TIME ZONE,
    withdrawn_by VARCHAR(255),
    withdrawal_reason TEXT,
    expired_at TIMESTAMP WITH TIME ZONE,
    -- Review and renewal
    review_required_by DATE,
    last_reviewed_at TIMESTAMP WITH TIME ZONE,
    -- System fields
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_by VARCHAR(255) NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE,
    updated_by VARCHAR(255),
    -- Metadata
    metadata JSONB,
    CONSTRAINT valid_consent_period CHECK (
        effective_to IS NULL OR effective_to > effective_from
    )
);

COMMENT ON TABLE core.patient_consent IS 'Patient consent tracking for privacy compliance';
COMMENT ON COLUMN core.patient_consent.consent_type IS 'Type of consent (treatment, research, data_sharing, etc.)';
COMMENT ON COLUMN core.patient_consent.consent_method IS 'How consent was obtained';
COMMENT ON COLUMN core.patient_consent.data_categories IS 'Categories of data covered by consent';

-- Indexes
CREATE INDEX idx_patient_consent_patient ON core.patient_consent(patient_id);
CREATE INDEX idx_patient_consent_type ON core.patient_consent(consent_type, consent_status);
CREATE INDEX idx_patient_consent_status ON core.patient_consent(consent_status);
CREATE INDEX idx_patient_consent_effective ON core.patient_consent(effective_from, effective_to);
CREATE INDEX idx_patient_consent_review ON core.patient_consent(review_required_by)
    WHERE consent_status = 'granted' AND review_required_by IS NOT NULL;

-- ============================================================================
-- Data Access Policy
-- ============================================================================

CREATE TABLE core.data_access_policy (
    policy_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    policy_name VARCHAR(255) NOT NULL UNIQUE,
    policy_description TEXT,
    -- Policy scope
    applies_to_role VARCHAR(100), -- Which role this policy applies to
    applies_to_user VARCHAR(255), -- Or specific user
    -- Access rules
    allowed_tables TEXT[], -- Tables this role/user can access
    denied_tables TEXT[], -- Explicitly denied tables
    row_filter_condition TEXT, -- SQL condition for row-level filtering
    column_restrictions JSONB, -- Column-level restrictions
    -- Purpose restrictions
    allowed_purposes TEXT[], -- Allowed purposes (treatment, payment, research, etc.)
    -- Time restrictions
    effective_from TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    effective_to TIMESTAMP WITH TIME ZONE,
    allowed_hours JSONB, -- Time-of-day restrictions
    -- Status
    enabled BOOLEAN DEFAULT TRUE,
    -- System fields
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_by VARCHAR(255) NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE,
    updated_by VARCHAR(255),
    -- Metadata
    metadata JSONB,
    CONSTRAINT policy_target CHECK (
        (applies_to_role IS NOT NULL AND applies_to_user IS NULL) OR
        (applies_to_role IS NULL AND applies_to_user IS NOT NULL)
    )
);

COMMENT ON TABLE core.data_access_policy IS 'Data access policies for privacy and security';
COMMENT ON COLUMN core.data_access_policy.row_filter_condition IS 'SQL condition for row-level security';

-- Indexes
CREATE INDEX idx_data_access_policy_role ON core.data_access_policy(applies_to_role) WHERE applies_to_role IS NOT NULL;
CREATE INDEX idx_data_access_policy_user ON core.data_access_policy(applies_to_user) WHERE applies_to_user IS NOT NULL;
CREATE INDEX idx_data_access_policy_enabled ON core.data_access_policy(enabled) WHERE enabled = TRUE;

-- ============================================================================
-- Privacy Preferences
-- ============================================================================

CREATE TABLE core.patient_privacy_preference (
    preference_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    patient_id UUID NOT NULL REFERENCES core.patient(patient_id),
    -- Privacy settings
    restrict_directory_listing BOOLEAN DEFAULT FALSE, -- Exclude from patient directories
    restrict_family_access BOOLEAN DEFAULT FALSE, -- Restrict family member access
    vip_confidential BOOLEAN DEFAULT FALSE, -- VIP/celebrity protection
    sensitive_diagnosis BOOLEAN DEFAULT FALSE, -- Extra protection for sensitive conditions
    -- Communication preferences (privacy-related)
    allow_sms BOOLEAN DEFAULT TRUE,
    allow_email BOOLEAN DEFAULT TRUE,
    allow_phone_call BOOLEAN DEFAULT TRUE,
    allow_postal_mail BOOLEAN DEFAULT TRUE,
    allow_automated_reminders BOOLEAN DEFAULT TRUE,
    -- Sharing preferences
    allow_research_data_use BOOLEAN DEFAULT FALSE,
    allow_quality_improvement_use BOOLEAN DEFAULT TRUE,
    allow_third_party_sharing BOOLEAN DEFAULT FALSE,
    third_party_restrictions TEXT[], -- Specific restrictions on third-party sharing
    -- System fields
    effective_from TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_by VARCHAR(255) NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE,
    updated_by VARCHAR(255),
    -- Metadata
    metadata JSONB
);

COMMENT ON TABLE core.patient_privacy_preference IS 'Patient privacy preferences beyond basic consent';
COMMENT ON COLUMN core.patient_privacy_preference.vip_confidential IS 'Extra confidentiality for VIP/celebrity patients';
COMMENT ON COLUMN core.patient_privacy_preference.sensitive_diagnosis IS 'Extra protection for sensitive conditions';

-- Indexes
CREATE INDEX idx_privacy_pref_patient ON core.patient_privacy_preference(patient_id);
CREATE INDEX idx_privacy_pref_vip ON core.patient_privacy_preference(vip_confidential) WHERE vip_confidential = TRUE;

-- Unique constraint: one active preference per patient
CREATE UNIQUE INDEX uniq_privacy_pref_patient ON core.patient_privacy_preference(patient_id);

-- ============================================================================
-- Consent Checking Functions
-- ============================================================================

-- Check if patient has granted consent for specific purpose
CREATE OR REPLACE FUNCTION core.check_consent(
    p_patient_id UUID,
    p_consent_type core.consent_type,
    p_purpose VARCHAR DEFAULT NULL
)
RETURNS BOOLEAN AS $$
DECLARE
    v_has_consent BOOLEAN;
BEGIN
    SELECT EXISTS(
        SELECT 1
        FROM core.patient_consent
        WHERE patient_id = p_patient_id
            AND consent_type = p_consent_type
            AND consent_status = 'granted'
            AND CURRENT_TIMESTAMP >= effective_from
            AND (effective_to IS NULL OR CURRENT_TIMESTAMP < effective_to)
            AND (p_purpose IS NULL OR p_purpose = ANY(permitted_purposes))
    ) INTO v_has_consent;

    RETURN v_has_consent;
END;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION core.check_consent IS 'Checks if patient has granted consent for specific purpose';

-- ============================================================================
-- Grant Permissions
-- ============================================================================

-- Audit tables - read-only for auditors
GRANT SELECT ON audit.audit_log TO mpi_auditor, mpi_admin;
GRANT INSERT ON audit.audit_log TO mpi_admin; -- Only admin can manually insert
GRANT SELECT ON audit.data_access_log TO mpi_auditor, mpi_admin;

GRANT SELECT ON core.patient_consent TO mpi_clinical_user, mpi_admin;
GRANT INSERT, UPDATE ON core.patient_consent TO mpi_clinical_user, mpi_admin;

GRANT SELECT ON core.data_access_policy TO mpi_admin;
GRANT INSERT, UPDATE ON core.data_access_policy TO mpi_admin;

GRANT SELECT ON core.patient_privacy_preference TO mpi_clinical_user, mpi_admin;
GRANT INSERT, UPDATE ON core.patient_privacy_preference TO mpi_clinical_user, mpi_admin;

GRANT EXECUTE ON FUNCTION audit.log_data_access TO mpi_clinical_user, mpi_admin, mpi_integration;
GRANT EXECUTE ON FUNCTION core.check_consent TO mpi_clinical_user, mpi_admin, mpi_integration;

-- ============================================================================
-- Audit and Consent Complete
-- ============================================================================
