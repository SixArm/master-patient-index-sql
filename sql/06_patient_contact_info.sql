-- ============================================================================
-- Master Patient Index (MPI) - Patient Contact Information
-- PostgreSQL 18
-- ============================================================================
-- Purpose: Phone numbers, emails, addresses with temporal tracking
-- HIPAA Compliant | UK DPA 2018 Compliant
-- ============================================================================

-- ============================================================================
-- Phone Numbers (Temporal)
-- ============================================================================

CREATE TABLE core.patient_phone (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    patient_id UUID NOT NULL REFERENCES core.patient(patient_id),
    -- Phone number (E.164 format recommended)
    phone_number VARCHAR(20) NOT NULL,
    phone_number_hash BYTEA NOT NULL,
    country_code VARCHAR(5), -- Phone country code (e.g., +1, +44, +86)
    -- Phone type and use
    phone_type VARCHAR(50) NOT NULL, -- 'mobile', 'home', 'work', 'fax', 'emergency'
    use_context VARCHAR(50), -- 'primary', 'secondary', 'temporary', 'old'
    -- Extension for work numbers
    extension VARCHAR(20),
    -- Preferences and consent
    is_preferred BOOLEAN DEFAULT FALSE,
    can_leave_message BOOLEAN DEFAULT TRUE,
    sms_consent BOOLEAN DEFAULT FALSE,
    voice_consent BOOLEAN DEFAULT TRUE,
    best_time_to_call VARCHAR(100), -- Free text or structured time range
    -- Verification
    verified BOOLEAN DEFAULT FALSE,
    verified_at TIMESTAMP WITH TIME ZONE,
    verification_method VARCHAR(100), -- 'sms_code', 'voice_call', 'document', etc.
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
    CONSTRAINT valid_phone_period CHECK (effective_from < effective_to),
    CONSTRAINT valid_phone_current CHECK (
        (is_current = TRUE AND effective_to = core.max_timestamp()) OR
        (is_current = FALSE AND effective_to < core.max_timestamp())
    )
);

COMMENT ON TABLE core.patient_phone IS 'Patient phone numbers with temporal tracking and consent management';
COMMENT ON COLUMN core.patient_phone.phone_number IS 'Phone number in E.164 format recommended';
COMMENT ON COLUMN core.patient_phone.sms_consent IS 'Consent to receive SMS messages';
COMMENT ON COLUMN core.patient_phone.voice_consent IS 'Consent to receive voice calls';

-- Indexes
CREATE INDEX idx_patient_phone_patient ON core.patient_phone(patient_id);
CREATE INDEX idx_patient_phone_current ON core.patient_phone(patient_id, is_current) WHERE is_current = TRUE;
CREATE INDEX idx_patient_phone_number ON core.patient_phone(phone_number);
CREATE INDEX idx_patient_phone_hash ON core.patient_phone USING hash(phone_number_hash);
CREATE INDEX idx_patient_phone_type ON core.patient_phone(phone_type);
CREATE INDEX idx_patient_phone_preferred ON core.patient_phone(patient_id, is_preferred) WHERE is_preferred = TRUE;
CREATE INDEX idx_patient_phone_effective ON core.patient_phone(effective_from, effective_to);

-- Trigger to generate phone hash
CREATE OR REPLACE FUNCTION core.generate_phone_hash()
RETURNS TRIGGER AS $$
BEGIN
    NEW.phone_number_hash := security.hash_value(NEW.phone_number);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_phone_hash
    BEFORE INSERT OR UPDATE ON core.patient_phone
    FOR EACH ROW
    WHEN (NEW.phone_number IS NOT NULL)
    EXECUTE FUNCTION core.generate_phone_hash();

-- Temporal triggers
CREATE TRIGGER trg_patient_phone_auto_current
    BEFORE INSERT ON core.patient_phone
    FOR EACH ROW
    EXECUTE FUNCTION core.auto_set_current();

-- ============================================================================
-- Email Addresses (Temporal)
-- ============================================================================

CREATE TABLE core.patient_email (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    patient_id UUID NOT NULL REFERENCES core.patient(patient_id),
    -- Email address
    email_address VARCHAR(255) NOT NULL,
    email_address_hash BYTEA NOT NULL,
    email_address_lower VARCHAR(255) GENERATED ALWAYS AS (LOWER(email_address)) STORED,
    -- Email type and use
    email_type VARCHAR(50) NOT NULL, -- 'personal', 'work', 'temporary'
    use_context VARCHAR(50), -- 'primary', 'secondary', 'temporary', 'old'
    -- Preferences and consent
    is_preferred BOOLEAN DEFAULT FALSE,
    can_send_notifications BOOLEAN DEFAULT TRUE,
    can_send_marketing BOOLEAN DEFAULT FALSE,
    email_consent BOOLEAN DEFAULT FALSE, -- Explicit consent to email
    -- Verification
    verified BOOLEAN DEFAULT FALSE,
    verified_at TIMESTAMP WITH TIME ZONE,
    verification_method VARCHAR(100), -- 'click_link', 'enter_code', 'document', etc.
    verification_token VARCHAR(255),
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
    CONSTRAINT valid_email_period CHECK (effective_from < effective_to),
    CONSTRAINT valid_email_current CHECK (
        (is_current = TRUE AND effective_to = core.max_timestamp()) OR
        (is_current = FALSE AND effective_to < core.max_timestamp())
    ),
    CONSTRAINT valid_email_format CHECK (email_address ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$')
);

COMMENT ON TABLE core.patient_email IS 'Patient email addresses with temporal tracking and consent management';
COMMENT ON COLUMN core.patient_email.email_consent IS 'Explicit consent to receive emails';
COMMENT ON COLUMN core.patient_email.can_send_marketing IS 'Consent to receive marketing communications';

-- Indexes
CREATE INDEX idx_patient_email_patient ON core.patient_email(patient_id);
CREATE INDEX idx_patient_email_current ON core.patient_email(patient_id, is_current) WHERE is_current = TRUE;
CREATE INDEX idx_patient_email_address ON core.patient_email(email_address_lower);
CREATE INDEX idx_patient_email_hash ON core.patient_email USING hash(email_address_hash);
CREATE INDEX idx_patient_email_type ON core.patient_email(email_type);
CREATE INDEX idx_patient_email_preferred ON core.patient_email(patient_id, is_preferred) WHERE is_preferred = TRUE;
CREATE INDEX idx_patient_email_verified ON core.patient_email(verified) WHERE verified = TRUE;
CREATE INDEX idx_patient_email_effective ON core.patient_email(effective_from, effective_to);

-- Trigger to generate email hash
CREATE OR REPLACE FUNCTION core.generate_email_hash()
RETURNS TRIGGER AS $$
BEGIN
    NEW.email_address_hash := security.hash_value(LOWER(NEW.email_address));
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_email_hash
    BEFORE INSERT OR UPDATE ON core.patient_email
    FOR EACH ROW
    WHEN (NEW.email_address IS NOT NULL)
    EXECUTE FUNCTION core.generate_email_hash();

-- Temporal triggers
CREATE TRIGGER trg_patient_email_auto_current
    BEFORE INSERT ON core.patient_email
    FOR EACH ROW
    EXECUTE FUNCTION core.auto_set_current();

-- ============================================================================
-- Postal Addresses (Temporal)
-- ============================================================================

CREATE TABLE core.patient_address (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    patient_id UUID NOT NULL REFERENCES core.patient(patient_id),
    -- Address components (flexible international support)
    address_line_1 VARCHAR(255) NOT NULL,
    address_line_2 VARCHAR(255),
    address_line_3 VARCHAR(255),
    city VARCHAR(100),
    district VARCHAR(100), -- County, province, state, etc.
    postal_code VARCHAR(20),
    country_code CHAR(2) NOT NULL, -- ISO 3166-1 alpha-2
    -- Full formatted address
    formatted_address TEXT,
    -- Address type and use
    address_type VARCHAR(50) NOT NULL, -- 'home', 'work', 'temporary', 'postal', 'billing'
    use_context VARCHAR(50), -- 'primary', 'secondary', 'temporary', 'old'
    -- Geocoding for validation and mapping
    latitude DECIMAL(10, 8),
    longitude DECIMAL(11, 8),
    geocode_accuracy VARCHAR(50), -- 'rooftop', 'street', 'city', 'approximate'
    geocoded_at TIMESTAMP WITH TIME ZONE,
    -- Address metadata
    is_preferred BOOLEAN DEFAULT FALSE,
    verified BOOLEAN DEFAULT FALSE,
    verified_at TIMESTAMP WITH TIME ZONE,
    verification_method VARCHAR(100), -- 'postal_service', 'document', 'visit', etc.
    -- Special flags
    is_confidential BOOLEAN DEFAULT FALSE, -- For protected addresses (e.g., domestic violence victims)
    do_not_visit BOOLEAN DEFAULT FALSE,
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
    CONSTRAINT valid_address_period CHECK (effective_from < effective_to),
    CONSTRAINT valid_address_current CHECK (
        (is_current = TRUE AND effective_to = core.max_timestamp()) OR
        (is_current = FALSE AND effective_to < core.max_timestamp())
    ),
    CONSTRAINT valid_geocode CHECK (
        (latitude IS NULL AND longitude IS NULL) OR
        (latitude IS NOT NULL AND longitude IS NOT NULL AND
         latitude BETWEEN -90 AND 90 AND longitude BETWEEN -180 AND 180)
    )
);

COMMENT ON TABLE core.patient_address IS 'Patient addresses with international support and temporal tracking';
COMMENT ON COLUMN core.patient_address.is_confidential IS 'Confidential address (protected from disclosure)';
COMMENT ON COLUMN core.patient_address.latitude IS 'Geocoded latitude for mapping and distance calculations';
COMMENT ON COLUMN core.patient_address.longitude IS 'Geocoded longitude for mapping and distance calculations';

-- Indexes
CREATE INDEX idx_patient_address_patient ON core.patient_address(patient_id);
CREATE INDEX idx_patient_address_current ON core.patient_address(patient_id, is_current) WHERE is_current = TRUE;
CREATE INDEX idx_patient_address_postal ON core.patient_address(postal_code, country_code);
CREATE INDEX idx_patient_address_city ON core.patient_address(city, country_code);
CREATE INDEX idx_patient_address_country ON core.patient_address(country_code);
CREATE INDEX idx_patient_address_type ON core.patient_address(address_type);
CREATE INDEX idx_patient_address_preferred ON core.patient_address(patient_id, is_preferred) WHERE is_preferred = TRUE;
CREATE INDEX idx_patient_address_geocode ON core.patient_address USING gist(
    ll_to_earth(latitude, longitude)
) WHERE latitude IS NOT NULL AND longitude IS NOT NULL; -- Requires earthdistance extension
CREATE INDEX idx_patient_address_effective ON core.patient_address(effective_from, effective_to);

-- Temporal triggers
CREATE TRIGGER trg_patient_address_auto_current
    BEFORE INSERT ON core.patient_address
    FOR EACH ROW
    EXECUTE FUNCTION core.auto_set_current();

-- Trigger to generate formatted address
CREATE OR REPLACE FUNCTION core.generate_formatted_address()
RETURNS TRIGGER AS $$
BEGIN
    NEW.formatted_address := trim(CONCAT_WS(', ',
        NEW.address_line_1,
        NEW.address_line_2,
        NEW.address_line_3,
        NEW.city,
        NEW.district,
        NEW.postal_code,
        NEW.country_code
    ));
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_address_format
    BEFORE INSERT OR UPDATE ON core.patient_address
    FOR EACH ROW
    EXECUTE FUNCTION core.generate_formatted_address();

-- ============================================================================
-- Contact Information Search Functions
-- ============================================================================

-- Find patient by phone number
CREATE OR REPLACE FUNCTION core.find_patient_by_phone(
    p_phone_number VARCHAR
)
RETURNS TABLE(
    patient_id UUID,
    phone_id UUID,
    phone_type VARCHAR,
    is_current BOOLEAN,
    effective_from TIMESTAMP WITH TIME ZONE,
    effective_to TIMESTAMP WITH TIME ZONE
) AS $$
DECLARE
    v_hash BYTEA;
BEGIN
    v_hash := security.hash_value(p_phone_number);

    RETURN QUERY
    SELECT
        ph.patient_id,
        ph.id,
        ph.phone_type,
        ph.is_current,
        ph.effective_from,
        ph.effective_to
    FROM core.patient_phone ph
    WHERE ph.phone_number_hash = v_hash
        AND ph.deleted_at IS NULL
    ORDER BY ph.is_current DESC, ph.effective_from DESC;
END;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION core.find_patient_by_phone IS 'Finds patients by phone number using hash lookup';

-- Find patient by email
CREATE OR REPLACE FUNCTION core.find_patient_by_email(
    p_email_address VARCHAR
)
RETURNS TABLE(
    patient_id UUID,
    email_id UUID,
    email_type VARCHAR,
    is_current BOOLEAN,
    verified BOOLEAN,
    effective_from TIMESTAMP WITH TIME ZONE,
    effective_to TIMESTAMP WITH TIME ZONE
) AS $$
DECLARE
    v_hash BYTEA;
BEGIN
    v_hash := security.hash_value(LOWER(p_email_address));

    RETURN QUERY
    SELECT
        e.patient_id,
        e.id,
        e.email_type,
        e.is_current,
        e.verified,
        e.effective_from,
        e.effective_to
    FROM core.patient_email e
    WHERE e.email_address_hash = v_hash
        AND e.deleted_at IS NULL
    ORDER BY e.is_current DESC, e.effective_from DESC;
END;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION core.find_patient_by_email IS 'Finds patients by email address using hash lookup';

-- Find patients by address
CREATE OR REPLACE FUNCTION core.find_patients_by_address(
    p_postal_code VARCHAR DEFAULT NULL,
    p_city VARCHAR DEFAULT NULL,
    p_country_code CHAR(2) DEFAULT NULL,
    p_current_only BOOLEAN DEFAULT TRUE
)
RETURNS TABLE(
    patient_id UUID,
    address_id UUID,
    formatted_address TEXT,
    address_type VARCHAR,
    is_current BOOLEAN
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        a.patient_id,
        a.id,
        a.formatted_address,
        a.address_type,
        a.is_current
    FROM core.patient_address a
    WHERE (p_postal_code IS NULL OR a.postal_code = p_postal_code)
        AND (p_city IS NULL OR a.city ILIKE p_city)
        AND (p_country_code IS NULL OR a.country_code = p_country_code)
        AND (NOT p_current_only OR a.is_current = TRUE)
        AND a.deleted_at IS NULL
    ORDER BY a.patient_id, a.is_current DESC, a.effective_from DESC;
END;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION core.find_patients_by_address IS 'Finds patients by address components';

-- ============================================================================
-- Grant Permissions
-- ============================================================================

GRANT SELECT ON core.patient_phone TO mpi_read_only, mpi_clinical_user, mpi_admin, mpi_integration;
GRANT INSERT ON core.patient_phone TO mpi_clinical_user, mpi_admin, mpi_integration;
GRANT UPDATE (effective_to, is_current, verified, verified_at, sms_consent, voice_consent) ON core.patient_phone TO mpi_clinical_user, mpi_admin;

GRANT SELECT ON core.patient_email TO mpi_read_only, mpi_clinical_user, mpi_admin, mpi_integration;
GRANT INSERT ON core.patient_email TO mpi_clinical_user, mpi_admin, mpi_integration;
GRANT UPDATE (effective_to, is_current, verified, verified_at, can_send_notifications, can_send_marketing, email_consent) ON core.patient_email TO mpi_clinical_user, mpi_admin;

GRANT SELECT ON core.patient_address TO mpi_read_only, mpi_clinical_user, mpi_admin, mpi_integration;
GRANT INSERT ON core.patient_address TO mpi_clinical_user, mpi_admin, mpi_integration;
GRANT UPDATE (effective_to, is_current, verified, verified_at) ON core.patient_address TO mpi_clinical_user, mpi_admin;

GRANT EXECUTE ON FUNCTION core.find_patient_by_phone TO mpi_clinical_user, mpi_admin, mpi_integration;
GRANT EXECUTE ON FUNCTION core.find_patient_by_email TO mpi_clinical_user, mpi_admin, mpi_integration;
GRANT EXECUTE ON FUNCTION core.find_patients_by_address TO mpi_clinical_user, mpi_admin, mpi_integration;

-- ============================================================================
-- Patient Contact Information Complete
-- ============================================================================
