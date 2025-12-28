-- Master Patient Index (MPI) Schema
-- PostgreSQL 14+
--
-- This schema provides a comprehensive master patient index for healthcare applications
-- with support for multiple identifiers, demographics, auditing, and HIPAA compliance.

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Create schema
CREATE SCHEMA IF NOT EXISTS mpi;

SET search_path TO mpi, public;

-- ============================================================================
-- CORE PATIENT TABLE
-- ============================================================================

CREATE TABLE patients (
    patient_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

    -- Master Patient Index Number (internal unique identifier)
    mpi_number VARCHAR(50) UNIQUE NOT NULL,

    -- Status and metadata
    status VARCHAR(20) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'merged', 'inactive', 'deceased')),
    merged_into_patient_id UUID REFERENCES patients(patient_id),

    -- Timestamps
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by VARCHAR(100) NOT NULL,
    updated_by VARCHAR(100) NOT NULL,

    -- Soft delete
    deleted_at TIMESTAMP WITH TIME ZONE,
    deleted_by VARCHAR(100)
);

COMMENT ON TABLE patients IS 'Core patient master index table containing unique patient records';
COMMENT ON COLUMN patients.mpi_number IS 'Master Patient Index number - permanent unique identifier';
COMMENT ON COLUMN patients.merged_into_patient_id IS 'References the patient record this was merged into';

-- ============================================================================
-- PATIENT IDENTIFIERS
-- ============================================================================

CREATE TABLE patient_identifiers (
    identifier_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    patient_id UUID NOT NULL REFERENCES patients(patient_id) ON DELETE CASCADE,

    -- Identifier details
    identifier_type VARCHAR(50) NOT NULL CHECK (identifier_type IN (
        'SSN', 'MRN', 'DRIVERS_LICENSE', 'PASSPORT',
        'NATIONAL_ID', 'INSURANCE_MEMBER_ID', 'OTHER'
    )),
    identifier_value VARCHAR(255) NOT NULL,

    -- Issuing authority
    issuing_authority VARCHAR(255),
    issuing_facility_id VARCHAR(100),

    -- Validity
    valid_from DATE,
    valid_to DATE,
    is_primary BOOLEAN DEFAULT false,

    -- Timestamps
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by VARCHAR(100) NOT NULL,
    updated_by VARCHAR(100) NOT NULL,

    -- Ensure one primary identifier per type per patient
    CONSTRAINT unique_patient_identifier UNIQUE (patient_id, identifier_type, identifier_value)
);

COMMENT ON TABLE patient_identifiers IS 'External identifiers for patients (SSN, MRN, etc.)';
COMMENT ON COLUMN patient_identifiers.is_primary IS 'Indicates if this is the primary identifier of this type';

CREATE INDEX idx_patient_identifiers_patient_id ON patient_identifiers(patient_id);
CREATE INDEX idx_patient_identifiers_type_value ON patient_identifiers(identifier_type, identifier_value);
CREATE INDEX idx_patient_identifiers_issuing_facility ON patient_identifiers(issuing_facility_id);

-- ============================================================================
-- PATIENT DEMOGRAPHICS
-- ============================================================================

CREATE TABLE patient_demographics (
    demographics_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    patient_id UUID NOT NULL REFERENCES patients(patient_id) ON DELETE CASCADE,

    -- Name information
    first_name VARCHAR(100) NOT NULL,
    middle_name VARCHAR(100),
    last_name VARCHAR(100) NOT NULL,
    name_suffix VARCHAR(20),
    name_prefix VARCHAR(20),
    preferred_name VARCHAR(100),
    maiden_name VARCHAR(100),

    -- Birth information
    date_of_birth DATE NOT NULL,
    birth_city VARCHAR(100),
    birth_state VARCHAR(50),
    birth_country VARCHAR(3), -- ISO 3166-1 alpha-3

    -- Demographics
    gender VARCHAR(20) CHECK (gender IN ('male', 'female', 'other', 'unknown')),
    sex_assigned_at_birth VARCHAR(20) CHECK (sex_assigned_at_birth IN ('male', 'female', 'intersex', 'unknown')),
    gender_identity VARCHAR(50),

    -- Race and ethnicity (can be multiple, stored as arrays or separate table)
    race VARCHAR(100),
    ethnicity VARCHAR(100),

    -- Language and culture
    primary_language VARCHAR(50),
    secondary_languages TEXT[],
    interpreter_required BOOLEAN DEFAULT false,

    -- Vital status
    is_deceased BOOLEAN DEFAULT false,
    death_date DATE,
    death_city VARCHAR(100),
    death_state VARCHAR(50),
    death_country VARCHAR(3),

    -- Religion and marital status
    religion VARCHAR(100),
    marital_status VARCHAR(30) CHECK (marital_status IN (
        'single', 'married', 'divorced', 'widowed',
        'separated', 'domestic_partner', 'unknown'
    )),

    -- Timestamps
    effective_from TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    effective_to TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by VARCHAR(100) NOT NULL,
    updated_by VARCHAR(100) NOT NULL,

    -- Ensure only one active demographic record per patient
    CONSTRAINT unique_active_demographics UNIQUE (patient_id, effective_to)
);

COMMENT ON TABLE patient_demographics IS 'Patient demographic information with history tracking';
COMMENT ON COLUMN patient_demographics.effective_from IS 'Start date for this demographic record version';
COMMENT ON COLUMN patient_demographics.effective_to IS 'End date for this demographic record version (NULL = current)';

CREATE INDEX idx_patient_demographics_patient_id ON patient_demographics(patient_id);
CREATE INDEX idx_patient_demographics_name ON patient_demographics(last_name, first_name, date_of_birth);
CREATE INDEX idx_patient_demographics_dob ON patient_demographics(date_of_birth);
CREATE INDEX idx_patient_demographics_effective ON patient_demographics(patient_id, effective_from, effective_to);

-- ============================================================================
-- PATIENT ADDRESSES
-- ============================================================================

CREATE TABLE patient_addresses (
    address_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    patient_id UUID NOT NULL REFERENCES patients(patient_id) ON DELETE CASCADE,

    -- Address type
    address_type VARCHAR(30) NOT NULL CHECK (address_type IN (
        'home', 'work', 'temporary', 'mailing', 'billing', 'other'
    )),

    -- Address components
    address_line_1 VARCHAR(255) NOT NULL,
    address_line_2 VARCHAR(255),
    city VARCHAR(100) NOT NULL,
    state VARCHAR(50),
    postal_code VARCHAR(20) NOT NULL,
    county VARCHAR(100),
    country VARCHAR(3) NOT NULL DEFAULT 'USA', -- ISO 3166-1 alpha-3

    -- Coordinates for geocoding
    latitude DECIMAL(10, 8),
    longitude DECIMAL(11, 8),

    -- Status
    is_primary BOOLEAN DEFAULT false,
    is_validated BOOLEAN DEFAULT false,
    validated_at TIMESTAMP WITH TIME ZONE,

    -- Validity period
    valid_from DATE NOT NULL DEFAULT CURRENT_DATE,
    valid_to DATE,

    -- Timestamps
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by VARCHAR(100) NOT NULL,
    updated_by VARCHAR(100) NOT NULL
);

COMMENT ON TABLE patient_addresses IS 'Patient address information with history and validation';

CREATE INDEX idx_patient_addresses_patient_id ON patient_addresses(patient_id);
CREATE INDEX idx_patient_addresses_postal_code ON patient_addresses(postal_code);
CREATE INDEX idx_patient_addresses_type ON patient_addresses(address_type, is_primary);
CREATE INDEX idx_patient_addresses_location ON patient_addresses(city, state, country);

-- ============================================================================
-- PATIENT CONTACT INFORMATION
-- ============================================================================

CREATE TABLE patient_contacts (
    contact_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    patient_id UUID NOT NULL REFERENCES patients(patient_id) ON DELETE CASCADE,

    -- Contact type
    contact_type VARCHAR(30) NOT NULL CHECK (contact_type IN (
        'phone_mobile', 'phone_home', 'phone_work',
        'email_personal', 'email_work', 'fax', 'other'
    )),

    -- Contact value
    contact_value VARCHAR(255) NOT NULL,

    -- Contact preferences
    is_primary BOOLEAN DEFAULT false,
    is_verified BOOLEAN DEFAULT false,
    verified_at TIMESTAMP WITH TIME ZONE,

    -- Communication preferences
    can_leave_message BOOLEAN DEFAULT true,
    preferred_contact_time VARCHAR(50),
    do_not_contact BOOLEAN DEFAULT false,

    -- Validity period
    valid_from DATE NOT NULL DEFAULT CURRENT_DATE,
    valid_to DATE,

    -- Timestamps
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by VARCHAR(100) NOT NULL,
    updated_by VARCHAR(100) NOT NULL,

    CONSTRAINT unique_patient_contact UNIQUE (patient_id, contact_type, contact_value)
);

COMMENT ON TABLE patient_contacts IS 'Patient contact information (phone, email, etc.)';

CREATE INDEX idx_patient_contacts_patient_id ON patient_contacts(patient_id);
CREATE INDEX idx_patient_contacts_type ON patient_contacts(contact_type, is_primary);
CREATE INDEX idx_patient_contacts_value ON patient_contacts(contact_value);

-- ============================================================================
-- PATIENT MERGE HISTORY
-- ============================================================================

CREATE TABLE patient_merge_history (
    merge_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

    -- Merged records
    source_patient_id UUID NOT NULL REFERENCES patients(patient_id),
    target_patient_id UUID NOT NULL REFERENCES patients(patient_id),

    -- Merge details
    merge_reason TEXT NOT NULL,
    merge_algorithm VARCHAR(100),
    confidence_score DECIMAL(5, 4) CHECK (confidence_score >= 0 AND confidence_score <= 1),

    -- Audit trail
    merged_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    merged_by VARCHAR(100) NOT NULL,

    -- Unmerge support
    is_unmerged BOOLEAN DEFAULT false,
    unmerged_at TIMESTAMP WITH TIME ZONE,
    unmerged_by VARCHAR(100),
    unmerge_reason TEXT,

    -- Store snapshot of source patient before merge
    source_patient_snapshot JSONB
);

COMMENT ON TABLE patient_merge_history IS 'Audit trail of patient record merges and unmerges';

CREATE INDEX idx_patient_merge_source ON patient_merge_history(source_patient_id);
CREATE INDEX idx_patient_merge_target ON patient_merge_history(target_patient_id);
CREATE INDEX idx_patient_merge_date ON patient_merge_history(merged_at);

-- ============================================================================
-- AUDIT LOGGING
-- ============================================================================

CREATE TABLE audit_log (
    audit_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

    -- What was changed
    table_name VARCHAR(100) NOT NULL,
    record_id UUID NOT NULL,
    operation VARCHAR(20) NOT NULL CHECK (operation IN ('INSERT', 'UPDATE', 'DELETE', 'MERGE', 'UNMERGE')),

    -- Patient context
    patient_id UUID REFERENCES patients(patient_id),

    -- Change details
    old_values JSONB,
    new_values JSONB,
    changed_fields TEXT[],

    -- Who and when
    changed_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    changed_by VARCHAR(100) NOT NULL,

    -- Session and application context
    session_id VARCHAR(255),
    application_name VARCHAR(100),
    ip_address INET,
    user_agent TEXT,

    -- Additional context
    notes TEXT
);

COMMENT ON TABLE audit_log IS 'Comprehensive audit trail for all MPI changes';

CREATE INDEX idx_audit_log_patient_id ON audit_log(patient_id);
CREATE INDEX idx_audit_log_table_record ON audit_log(table_name, record_id);
CREATE INDEX idx_audit_log_changed_at ON audit_log(changed_at DESC);
CREATE INDEX idx_audit_log_changed_by ON audit_log(changed_by);
CREATE INDEX idx_audit_log_operation ON audit_log(operation);

-- ============================================================================
-- PATIENT MATCHING CANDIDATES
-- ============================================================================

CREATE TABLE patient_match_candidates (
    candidate_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

    -- Potential duplicate patients
    patient_id_1 UUID NOT NULL REFERENCES patients(patient_id),
    patient_id_2 UUID NOT NULL REFERENCES patients(patient_id),

    -- Match details
    match_score DECIMAL(5, 4) NOT NULL CHECK (match_score >= 0 AND match_score <= 1),
    match_algorithm VARCHAR(100) NOT NULL,
    matched_fields TEXT[],

    -- Review status
    review_status VARCHAR(30) NOT NULL DEFAULT 'pending' CHECK (review_status IN (
        'pending', 'confirmed_match', 'confirmed_not_match', 'merged', 'dismissed'
    )),

    -- Resolution
    reviewed_at TIMESTAMP WITH TIME ZONE,
    reviewed_by VARCHAR(100),
    review_notes TEXT,

    -- Timestamps
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT unique_patient_pair UNIQUE (patient_id_1, patient_id_2),
    CONSTRAINT different_patients CHECK (patient_id_1 != patient_id_2)
);

COMMENT ON TABLE patient_match_candidates IS 'Potential duplicate patient records requiring review';

CREATE INDEX idx_patient_match_status ON patient_match_candidates(review_status, match_score DESC);
CREATE INDEX idx_patient_match_patients ON patient_match_candidates(patient_id_1, patient_id_2);
CREATE INDEX idx_patient_match_score ON patient_match_candidates(match_score DESC);

-- ============================================================================
-- SEQUENCES AND FUNCTIONS
-- ============================================================================

-- Function to generate MPI numbers
CREATE SEQUENCE mpi_number_seq START 1000000;

CREATE OR REPLACE FUNCTION generate_mpi_number()
RETURNS VARCHAR(50) AS $$
BEGIN
    RETURN 'MPI-' || LPAD(nextval('mpi_number_seq')::TEXT, 10, '0');
END;
$$ LANGUAGE plpgsql;

-- Trigger to auto-generate MPI number
CREATE OR REPLACE FUNCTION set_mpi_number()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.mpi_number IS NULL OR NEW.mpi_number = '' THEN
        NEW.mpi_number := generate_mpi_number();
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_set_mpi_number
    BEFORE INSERT ON patients
    FOR EACH ROW
    EXECUTE FUNCTION set_mpi_number();

-- ============================================================================
-- UPDATED_AT TRIGGERS
-- ============================================================================

CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_patients_updated_at BEFORE UPDATE ON patients
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_patient_identifiers_updated_at BEFORE UPDATE ON patient_identifiers
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_patient_demographics_updated_at BEFORE UPDATE ON patient_demographics
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_patient_addresses_updated_at BEFORE UPDATE ON patient_addresses
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_patient_contacts_updated_at BEFORE UPDATE ON patient_contacts
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================================
-- AUDIT TRIGGERS
-- ============================================================================

CREATE OR REPLACE FUNCTION audit_trigger_function()
RETURNS TRIGGER AS $$
DECLARE
    patient_id_value UUID;
    old_values_json JSONB;
    new_values_json JSONB;
BEGIN
    -- Try to extract patient_id from the record
    BEGIN
        IF TG_OP = 'DELETE' THEN
            patient_id_value := OLD.patient_id;
        ELSE
            patient_id_value := NEW.patient_id;
        END IF;
    EXCEPTION WHEN OTHERS THEN
        patient_id_value := NULL;
    END;

    -- Build JSON representations
    IF TG_OP = 'DELETE' THEN
        old_values_json := row_to_json(OLD)::JSONB;
        new_values_json := NULL;
    ELSIF TG_OP = 'UPDATE' THEN
        old_values_json := row_to_json(OLD)::JSONB;
        new_values_json := row_to_json(NEW)::JSONB;
    ELSE
        old_values_json := NULL;
        new_values_json := row_to_json(NEW)::JSONB;
    END IF;

    -- Insert audit record
    INSERT INTO audit_log (
        table_name,
        record_id,
        operation,
        patient_id,
        old_values,
        new_values,
        changed_by,
        application_name
    ) VALUES (
        TG_TABLE_NAME,
        COALESCE(NEW.patient_id, OLD.patient_id,
                 NEW.identifier_id, OLD.identifier_id,
                 NEW.demographics_id, OLD.demographics_id,
                 NEW.address_id, OLD.address_id,
                 NEW.contact_id, OLD.contact_id),
        TG_OP,
        patient_id_value,
        old_values_json,
        new_values_json,
        COALESCE(NEW.updated_by, NEW.created_by, OLD.updated_by, 'system'),
        current_setting('application_name', true)
    );

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    ELSE
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Apply audit triggers to main tables
CREATE TRIGGER audit_patients AFTER INSERT OR UPDATE OR DELETE ON patients
    FOR EACH ROW EXECUTE FUNCTION audit_trigger_function();

CREATE TRIGGER audit_patient_identifiers AFTER INSERT OR UPDATE OR DELETE ON patient_identifiers
    FOR EACH ROW EXECUTE FUNCTION audit_trigger_function();

CREATE TRIGGER audit_patient_demographics AFTER INSERT OR UPDATE OR DELETE ON patient_demographics
    FOR EACH ROW EXECUTE FUNCTION audit_trigger_function();

CREATE TRIGGER audit_patient_addresses AFTER INSERT OR UPDATE OR DELETE ON patient_addresses
    FOR EACH ROW EXECUTE FUNCTION audit_trigger_function();

CREATE TRIGGER audit_patient_contacts AFTER INSERT OR UPDATE OR DELETE ON patient_contacts
    FOR EACH ROW EXECUTE FUNCTION audit_trigger_function();
