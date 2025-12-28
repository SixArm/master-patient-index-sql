-- ============================================================================
-- Master Patient Index (MPI) - Patient Identifiers
-- PostgreSQL 18
-- ============================================================================
-- Purpose: Government IDs, Insurance IDs, MRNs with encryption and temporal tracking
-- HIPAA Compliant | UK DPA 2018 Compliant
-- ============================================================================

-- ============================================================================
-- Government Identifiers (Encrypted, Temporal)
-- ============================================================================

CREATE TABLE core.patient_government_id (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    patient_id UUID NOT NULL REFERENCES core.patient(patient_id),
    -- Country and ID type
    country_code CHAR(2) NOT NULL, -- ISO 3166-1 alpha-2
    id_type VARCHAR(100) NOT NULL, -- 'ssn', 'nhs_number', 'passport', 'national_id', 'drivers_license', etc.
    -- Encrypted ID value
    id_value_encrypted BYTEA NOT NULL, -- Encrypted identifier
    id_value_hash BYTEA NOT NULL, -- SHA-256 hash for lookups
    -- Tokenized value for analytics
    id_token VARCHAR(255), -- Generated token for safe use in analytics
    -- ID metadata
    issuing_authority VARCHAR(255), -- Government agency that issued ID
    issue_date DATE,
    expiration_date DATE,
    document_number VARCHAR(100), -- Document/reference number if applicable
    -- Verification
    verification_status VARCHAR(50) DEFAULT 'unverified', -- 'verified', 'unverified', 'expired', 'invalid'
    verified_by VARCHAR(255),
    verified_at TIMESTAMP WITH TIME ZONE,
    verification_method VARCHAR(100), -- 'document', 'database', 'in_person', etc.
    -- Temporal fields
    effective_from TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    effective_to TIMESTAMP WITH TIME ZONE DEFAULT core.max_timestamp(),
    is_current BOOLEAN DEFAULT TRUE,
    -- System fields
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_by VARCHAR(255) NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE,
    updated_by VARCHAR(255),
    -- Soft delete
    deleted_at TIMESTAMP WITH TIME ZONE,
    deleted_by VARCHAR(255),
    deletion_reason TEXT,
    -- Metadata
    source_system VARCHAR(100),
    metadata JSONB,
    CONSTRAINT valid_govt_id_period CHECK (effective_from < effective_to),
    CONSTRAINT valid_govt_id_current CHECK (
        (is_current = TRUE AND effective_to = core.max_timestamp()) OR
        (is_current = FALSE AND effective_to < core.max_timestamp())
    ),
    CONSTRAINT valid_expiration CHECK (
        expiration_date IS NULL OR expiration_date >= issue_date
    )
);

COMMENT ON TABLE core.patient_government_id IS 'Government-issued identifiers with encryption and temporal tracking';
COMMENT ON COLUMN core.patient_government_id.id_value_encrypted IS 'AES-256 encrypted identifier value';
COMMENT ON COLUMN core.patient_government_id.id_value_hash IS 'SHA-256 hash for deterministic matching';
COMMENT ON COLUMN core.patient_government_id.id_token IS 'Tokenized value for safe use in analytics/reporting';
COMMENT ON COLUMN core.patient_government_id.country_code IS 'ISO 3166-1 alpha-2 country code';

-- Indexes
CREATE INDEX idx_govt_id_patient ON core.patient_government_id(patient_id);
CREATE INDEX idx_govt_id_current ON core.patient_government_id(patient_id, is_current) WHERE is_current = TRUE;
CREATE INDEX idx_govt_id_hash ON core.patient_government_id USING hash(id_value_hash); -- For deterministic matching
CREATE INDEX idx_govt_id_token ON core.patient_government_id(id_token) WHERE id_token IS NOT NULL;
CREATE INDEX idx_govt_id_country_type ON core.patient_government_id(country_code, id_type);
CREATE INDEX idx_govt_id_effective ON core.patient_government_id(effective_from, effective_to);
CREATE INDEX idx_govt_id_verification ON core.patient_government_id(verification_status);

-- Unique constraint: one current active ID per patient per country per type
CREATE UNIQUE INDEX uniq_govt_id_current ON core.patient_government_id(patient_id, country_code, id_type)
    WHERE is_current = TRUE AND deleted_at IS NULL;

-- Temporal triggers
CREATE TRIGGER trg_govt_id_auto_current
    BEFORE INSERT ON core.patient_government_id
    FOR EACH ROW
    EXECUTE FUNCTION core.auto_set_current();

-- ============================================================================
-- Insurance Identifiers (Encrypted, Temporal)
-- ============================================================================

CREATE TABLE core.patient_insurance_id (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    patient_id UUID NOT NULL REFERENCES core.patient(patient_id),
    -- Insurance company/vendor
    insurance_company_id UUID, -- Reference to insurance company (can be added later)
    insurance_company_name VARCHAR(255) NOT NULL,
    insurance_plan_name VARCHAR(255),
    insurance_plan_type VARCHAR(100), -- 'private', 'medicare', 'medicaid', 'nhs', 'commercial', etc.
    -- Encrypted member ID
    member_id_encrypted BYTEA NOT NULL,
    member_id_hash BYTEA NOT NULL,
    member_id_token VARCHAR(255),
    -- Group/policy information (may also be sensitive)
    group_number_encrypted BYTEA,
    policy_number_encrypted BYTEA,
    -- Coverage details
    coverage_type VARCHAR(100), -- 'primary', 'secondary', 'tertiary'
    coverage_start_date DATE,
    coverage_end_date DATE,
    subscriber_relationship VARCHAR(50), -- 'self', 'spouse', 'child', 'other'
    -- Subscriber information (if patient is dependent)
    subscriber_name VARCHAR(255),
    subscriber_dob DATE,
    subscriber_id_encrypted BYTEA,
    -- Verification
    verification_status VARCHAR(50) DEFAULT 'unverified',
    verified_by VARCHAR(255),
    verified_at TIMESTAMP WITH TIME ZONE,
    active BOOLEAN DEFAULT TRUE,
    -- Temporal fields
    effective_from TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    effective_to TIMESTAMP WITH TIME ZONE DEFAULT core.max_timestamp(),
    is_current BOOLEAN DEFAULT TRUE,
    -- System fields
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_by VARCHAR(255) NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE,
    updated_by VARCHAR(255),
    -- Soft delete
    deleted_at TIMESTAMP WITH TIME ZONE,
    deleted_by VARCHAR(255),
    deletion_reason TEXT,
    -- Metadata
    source_system VARCHAR(100),
    metadata JSONB,
    CONSTRAINT valid_insurance_id_period CHECK (effective_from < effective_to),
    CONSTRAINT valid_insurance_id_current CHECK (
        (is_current = TRUE AND effective_to = core.max_timestamp()) OR
        (is_current = FALSE AND effective_to < core.max_timestamp())
    ),
    CONSTRAINT valid_coverage_dates CHECK (
        coverage_end_date IS NULL OR coverage_end_date >= coverage_start_date
    )
);

COMMENT ON TABLE core.patient_insurance_id IS 'Insurance identifiers with encryption and temporal tracking';
COMMENT ON COLUMN core.patient_insurance_id.member_id_encrypted IS 'AES-256 encrypted member/subscriber ID';
COMMENT ON COLUMN core.patient_insurance_id.member_id_hash IS 'SHA-256 hash for deterministic matching';
COMMENT ON COLUMN core.patient_insurance_id.coverage_type IS 'Primary, secondary, or tertiary coverage';

-- Indexes
CREATE INDEX idx_insurance_id_patient ON core.patient_insurance_id(patient_id);
CREATE INDEX idx_insurance_id_current ON core.patient_insurance_id(patient_id, is_current) WHERE is_current = TRUE;
CREATE INDEX idx_insurance_id_hash ON core.patient_insurance_id USING hash(member_id_hash);
CREATE INDEX idx_insurance_id_token ON core.patient_insurance_id(member_id_token) WHERE member_id_token IS NOT NULL;
CREATE INDEX idx_insurance_id_company ON core.patient_insurance_id(insurance_company_name);
CREATE INDEX idx_insurance_id_type ON core.patient_insurance_id(insurance_plan_type);
CREATE INDEX idx_insurance_id_coverage ON core.patient_insurance_id(coverage_type);
CREATE INDEX idx_insurance_id_dates ON core.patient_insurance_id(coverage_start_date, coverage_end_date);
CREATE INDEX idx_insurance_id_active ON core.patient_insurance_id(patient_id, active) WHERE active = TRUE;

-- Temporal triggers
CREATE TRIGGER trg_insurance_id_auto_current
    BEFORE INSERT ON core.patient_insurance_id
    FOR EACH ROW
    EXECUTE FUNCTION core.auto_set_current();

-- ============================================================================
-- Medical Record Numbers (MRN) - Temporal
-- ============================================================================

CREATE TABLE core.patient_mrn (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    patient_id UUID NOT NULL REFERENCES core.patient(patient_id),
    -- Facility/system information
    facility_id UUID, -- Reference to facility table (can be added later)
    facility_name VARCHAR(255) NOT NULL,
    facility_type VARCHAR(100), -- 'hospital', 'clinic', 'laboratory', 'imaging_center', etc.
    organization_name VARCHAR(255),
    -- MRN value (not encrypted as it's facility-specific and often used for lookups)
    mrn VARCHAR(100) NOT NULL,
    mrn_hash BYTEA NOT NULL, -- Hash for faster lookups
    -- MRN metadata
    assigning_authority VARCHAR(255), -- Authority that assigned this MRN
    assignment_date DATE,
    status VARCHAR(50) DEFAULT 'active', -- 'active', 'inactive', 'merged', 'retired'
    -- Temporal fields
    effective_from TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    effective_to TIMESTAMP WITH TIME ZONE DEFAULT core.max_timestamp(),
    is_current BOOLEAN DEFAULT TRUE,
    -- System fields
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_by VARCHAR(255) NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE,
    updated_by VARCHAR(255),
    -- Soft delete
    deleted_at TIMESTAMP WITH TIME ZONE,
    deleted_by VARCHAR(255),
    deletion_reason TEXT,
    -- Metadata
    source_system VARCHAR(100),
    metadata JSONB,
    CONSTRAINT valid_mrn_period CHECK (effective_from < effective_to),
    CONSTRAINT valid_mrn_current CHECK (
        (is_current = TRUE AND effective_to = core.max_timestamp()) OR
        (is_current = FALSE AND effective_to < core.max_timestamp())
    )
);

COMMENT ON TABLE core.patient_mrn IS 'Medical Record Numbers from various healthcare facilities';
COMMENT ON COLUMN core.patient_mrn.mrn IS 'Medical Record Number assigned by facility';
COMMENT ON COLUMN core.patient_mrn.assigning_authority IS 'Organization that assigned the MRN';

-- Indexes
CREATE INDEX idx_mrn_patient ON core.patient_mrn(patient_id);
CREATE INDEX idx_mrn_current ON core.patient_mrn(patient_id, is_current) WHERE is_current = TRUE;
CREATE INDEX idx_mrn_value ON core.patient_mrn(mrn);
CREATE INDEX idx_mrn_hash ON core.patient_mrn USING hash(mrn_hash);
CREATE INDEX idx_mrn_facility ON core.patient_mrn(facility_name);
CREATE INDEX idx_mrn_status ON core.patient_mrn(status) WHERE status = 'active';
CREATE INDEX idx_mrn_effective ON core.patient_mrn(effective_from, effective_to);

-- Unique constraint: one MRN per facility (facility-scoped uniqueness)
CREATE UNIQUE INDEX uniq_mrn_facility ON core.patient_mrn(facility_name, mrn)
    WHERE is_current = TRUE AND deleted_at IS NULL;

-- Unique constraint: one current MRN per patient per facility
CREATE UNIQUE INDEX uniq_mrn_patient_facility ON core.patient_mrn(patient_id, facility_name)
    WHERE is_current = TRUE AND deleted_at IS NULL;

-- Trigger to auto-generate MRN hash
CREATE OR REPLACE FUNCTION core.generate_mrn_hash()
RETURNS TRIGGER AS $$
BEGIN
    NEW.mrn_hash := security.hash_value(NEW.mrn);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_mrn_hash
    BEFORE INSERT OR UPDATE ON core.patient_mrn
    FOR EACH ROW
    WHEN (NEW.mrn IS NOT NULL)
    EXECUTE FUNCTION core.generate_mrn_hash();

-- Temporal triggers
CREATE TRIGGER trg_mrn_auto_current
    BEFORE INSERT ON core.patient_mrn
    FOR EACH ROW
    EXECUTE FUNCTION core.auto_set_current();

-- ============================================================================
-- Federated Identities (OAuth, SAML, OpenID Connect)
-- ============================================================================

CREATE TABLE core.patient_federated_identity (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    patient_id UUID NOT NULL REFERENCES core.patient(patient_id),
    -- Identity provider
    provider_type VARCHAR(50) NOT NULL, -- 'oauth2', 'saml', 'openid_connect', 'ldap', etc.
    provider_name VARCHAR(255) NOT NULL, -- 'Google', 'Microsoft', 'NHS Login', etc.
    provider_url VARCHAR(500),
    -- Subject identifier (unique within provider)
    subject_id VARCHAR(500) NOT NULL, -- Provider's unique identifier for user
    subject_id_hash BYTEA NOT NULL,
    -- Identity metadata
    issuer VARCHAR(500), -- Token issuer
    authentication_method VARCHAR(100), -- 'password', 'mfa', 'biometric', 'smartcard'
    assurance_level VARCHAR(50), -- 'low', 'medium', 'high', 'very_high' (eIDAS, NIST AAL)
    -- Linking information
    linked_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    linked_by VARCHAR(255),
    linking_method VARCHAR(100), -- 'user_initiated', 'admin_linked', 'auto_matched'
    verified BOOLEAN DEFAULT FALSE,
    verified_at TIMESTAMP WITH TIME ZONE,
    -- Status
    status VARCHAR(50) DEFAULT 'active', -- 'active', 'inactive', 'revoked'
    last_used_at TIMESTAMP WITH TIME ZONE,
    -- Temporal fields
    effective_from TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    effective_to TIMESTAMP WITH TIME ZONE DEFAULT core.max_timestamp(),
    is_current BOOLEAN DEFAULT TRUE,
    -- System fields
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_by VARCHAR(255) NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE,
    updated_by VARCHAR(255),
    -- Soft delete
    deleted_at TIMESTAMP WITH TIME ZONE,
    deleted_by VARCHAR(255),
    deletion_reason TEXT,
    -- Metadata
    metadata JSONB,
    CONSTRAINT valid_federated_id_period CHECK (effective_from < effective_to),
    CONSTRAINT valid_federated_id_current CHECK (
        (is_current = TRUE AND effective_to = core.max_timestamp()) OR
        (is_current = FALSE AND effective_to < core.max_timestamp())
    )
);

COMMENT ON TABLE core.patient_federated_identity IS 'Federated identities from external identity providers';
COMMENT ON COLUMN core.patient_federated_identity.subject_id IS 'Provider-specific unique identifier';
COMMENT ON COLUMN core.patient_federated_identity.assurance_level IS 'Authentication assurance level (eIDAS/NIST)';

-- Indexes
CREATE INDEX idx_federated_id_patient ON core.patient_federated_identity(patient_id);
CREATE INDEX idx_federated_id_current ON core.patient_federated_identity(patient_id, is_current) WHERE is_current = TRUE;
CREATE INDEX idx_federated_id_provider ON core.patient_federated_identity(provider_name, subject_id);
CREATE INDEX idx_federated_id_hash ON core.patient_federated_identity USING hash(subject_id_hash);
CREATE INDEX idx_federated_id_status ON core.patient_federated_identity(status) WHERE status = 'active';
CREATE INDEX idx_federated_id_last_used ON core.patient_federated_identity(last_used_at DESC);

-- Unique constraint: one subject per provider
CREATE UNIQUE INDEX uniq_federated_id_provider ON core.patient_federated_identity(provider_name, subject_id)
    WHERE is_current = TRUE AND deleted_at IS NULL;

-- Trigger to generate subject hash
CREATE OR REPLACE FUNCTION core.generate_federated_id_hash()
RETURNS TRIGGER AS $$
BEGIN
    NEW.subject_id_hash := security.hash_value(NEW.provider_name || '||' || NEW.subject_id);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_federated_id_hash
    BEFORE INSERT OR UPDATE ON core.patient_federated_identity
    FOR EACH ROW
    WHEN (NEW.subject_id IS NOT NULL)
    EXECUTE FUNCTION core.generate_federated_id_hash();

-- Temporal triggers
CREATE TRIGGER trg_federated_id_auto_current
    BEFORE INSERT ON core.patient_federated_identity
    FOR EACH ROW
    EXECUTE FUNCTION core.auto_set_current();

-- ============================================================================
-- Identifier Management Functions
-- ============================================================================

-- Function to insert encrypted government ID
CREATE OR REPLACE FUNCTION core.insert_government_id(
    p_patient_id UUID,
    p_country_code CHAR(2),
    p_id_type VARCHAR,
    p_id_value TEXT,
    p_issuing_authority VARCHAR DEFAULT NULL,
    p_created_by VARCHAR DEFAULT CURRENT_USER
)
RETURNS UUID AS $$
DECLARE
    v_id UUID;
    v_encrypted BYTEA;
    v_hash BYTEA;
    v_token VARCHAR;
BEGIN
    -- Encrypt the ID value
    v_encrypted := security.encrypt_data(p_id_value);

    -- Hash the ID value for lookups
    v_hash := security.hash_value(p_id_value);

    -- Generate token
    v_token := security.generate_token(p_id_value, 'government_id', p_patient_id, p_created_by);

    -- Insert record
    INSERT INTO core.patient_government_id (
        patient_id,
        country_code,
        id_type,
        id_value_encrypted,
        id_value_hash,
        id_token,
        issuing_authority,
        created_by
    ) VALUES (
        p_patient_id,
        p_country_code,
        p_id_type,
        v_encrypted,
        v_hash,
        v_token,
        p_issuing_authority,
        p_created_by
    ) RETURNING id INTO v_id;

    RETURN v_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
COMMENT ON FUNCTION core.insert_government_id IS 'Inserts encrypted government identifier';

-- Function to lookup patient by government ID
CREATE OR REPLACE FUNCTION core.find_patient_by_government_id(
    p_country_code CHAR(2),
    p_id_type VARCHAR,
    p_id_value TEXT
)
RETURNS TABLE(
    patient_id UUID,
    id_record_id UUID,
    verification_status VARCHAR,
    effective_from TIMESTAMP WITH TIME ZONE,
    effective_to TIMESTAMP WITH TIME ZONE
) AS $$
DECLARE
    v_hash BYTEA;
BEGIN
    -- Hash the search value
    v_hash := security.hash_value(p_id_value);

    -- Find matching records
    RETURN QUERY
    SELECT
        g.patient_id,
        g.id,
        g.verification_status,
        g.effective_from,
        g.effective_to
    FROM core.patient_government_id g
    WHERE g.country_code = p_country_code
        AND g.id_type = p_id_type
        AND g.id_value_hash = v_hash
        AND g.is_current = TRUE
        AND g.deleted_at IS NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
COMMENT ON FUNCTION core.find_patient_by_government_id IS 'Finds patient by government ID using hash lookup';

-- ============================================================================
-- Grant Permissions
-- ============================================================================

GRANT SELECT ON core.patient_government_id TO mpi_clinical_user, mpi_admin, mpi_integration;
GRANT INSERT ON core.patient_government_id TO mpi_clinical_user, mpi_admin, mpi_integration;
GRANT UPDATE (effective_to, is_current, verification_status, verified_by, verified_at) ON core.patient_government_id TO mpi_clinical_user, mpi_admin;

GRANT SELECT ON core.patient_insurance_id TO mpi_clinical_user, mpi_admin, mpi_integration;
GRANT INSERT ON core.patient_insurance_id TO mpi_clinical_user, mpi_admin, mpi_integration;
GRANT UPDATE (effective_to, is_current, verification_status, verified_by, verified_at, active) ON core.patient_insurance_id TO mpi_clinical_user, mpi_admin;

GRANT SELECT ON core.patient_mrn TO mpi_read_only, mpi_clinical_user, mpi_admin, mpi_integration;
GRANT INSERT ON core.patient_mrn TO mpi_clinical_user, mpi_admin, mpi_integration;
GRANT UPDATE (effective_to, is_current, status) ON core.patient_mrn TO mpi_clinical_user, mpi_admin;

GRANT SELECT ON core.patient_federated_identity TO mpi_clinical_user, mpi_admin, mpi_integration;
GRANT INSERT ON core.patient_federated_identity TO mpi_clinical_user, mpi_admin, mpi_integration;
GRANT UPDATE (effective_to, is_current, status, last_used_at) ON core.patient_federated_identity TO mpi_clinical_user, mpi_admin;

GRANT EXECUTE ON FUNCTION core.insert_government_id TO mpi_clinical_user, mpi_admin, mpi_integration;
GRANT EXECUTE ON FUNCTION core.find_patient_by_government_id TO mpi_clinical_user, mpi_admin, mpi_integration;

-- ============================================================================
-- Patient Identifiers Complete
-- ============================================================================
