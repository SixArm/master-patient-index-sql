-- ============================================================================
-- Master Patient Index (MPI) - Healthcare Providers and Relationships
-- PostgreSQL 18
-- ============================================================================
-- Purpose: Healthcare providers, facilities, organizations, and patient relationships
-- HIPAA Compliant | UK DPA 2018 Compliant
-- ============================================================================

-- ============================================================================
-- Healthcare Organizations
-- ============================================================================

CREATE TABLE provider.organization (
    organization_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    -- Organization details
    organization_name VARCHAR(255) NOT NULL,
    organization_type VARCHAR(100), -- 'hospital_system', 'clinic_network', 'insurance', 'government'
    parent_organization_id UUID REFERENCES provider.organization(organization_id),
    -- Identifiers
    npi VARCHAR(20), -- National Provider Identifier (US)
    organization_code VARCHAR(100), -- Internal or national code
    tax_id VARCHAR(50),
    -- Contact information
    website VARCHAR(500),
    primary_phone VARCHAR(20),
    primary_email VARCHAR(255),
    -- Address
    address_line_1 VARCHAR(255),
    address_line_2 VARCHAR(255),
    city VARCHAR(100),
    district VARCHAR(100),
    postal_code VARCHAR(20),
    country_code CHAR(2),
    -- Status
    active BOOLEAN DEFAULT TRUE,
    accreditation_status VARCHAR(100),
    accreditation_body VARCHAR(255),
    accreditation_expiry DATE,
    -- System fields
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_by VARCHAR(255) NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE,
    updated_by VARCHAR(255),
    -- Metadata
    metadata JSONB
);

COMMENT ON TABLE provider.organization IS 'Healthcare organizations (hospital systems, networks, etc.)';
COMMENT ON COLUMN provider.organization.npi IS 'National Provider Identifier (US) for organizations';

-- Indexes
CREATE INDEX idx_organization_name ON provider.organization(organization_name);
CREATE INDEX idx_organization_type ON provider.organization(organization_type);
CREATE INDEX idx_organization_parent ON provider.organization(parent_organization_id);
CREATE INDEX idx_organization_npi ON provider.organization(npi) WHERE npi IS NOT NULL;
CREATE INDEX idx_organization_active ON provider.organization(active) WHERE active = TRUE;

-- ============================================================================
-- Healthcare Facilities
-- ============================================================================

CREATE TABLE provider.facility (
    facility_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID REFERENCES provider.organization(organization_id),
    -- Facility details
    facility_name VARCHAR(255) NOT NULL,
    facility_type VARCHAR(100) NOT NULL, -- 'hospital', 'clinic', 'urgent_care', 'laboratory', 'imaging_center'
    specialty_services TEXT[], -- Array of specialties offered
    -- Identifiers
    npi VARCHAR(20), -- National Provider Identifier
    facility_code VARCHAR(100),
    license_number VARCHAR(100),
    -- Contact information
    website VARCHAR(500),
    primary_phone VARCHAR(20),
    primary_email VARCHAR(255),
    -- Address
    address_line_1 VARCHAR(255) NOT NULL,
    address_line_2 VARCHAR(255),
    city VARCHAR(100) NOT NULL,
    district VARCHAR(100),
    postal_code VARCHAR(20),
    country_code CHAR(2) NOT NULL,
    -- Geocoding
    latitude DECIMAL(10, 8),
    longitude DECIMAL(11, 8),
    -- Operating hours
    operating_hours JSONB, -- Structured hours of operation
    emergency_services BOOLEAN DEFAULT FALSE,
    -- Status
    active BOOLEAN DEFAULT TRUE,
    license_status VARCHAR(50), -- 'active', 'suspended', 'expired', 'pending'
    license_expiry DATE,
    -- System fields
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_by VARCHAR(255) NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE,
    updated_by VARCHAR(255),
    -- Metadata
    metadata JSONB
);

COMMENT ON TABLE provider.facility IS 'Healthcare facilities (hospitals, clinics, etc.)';
COMMENT ON COLUMN provider.facility.facility_type IS 'Type of facility (hospital, clinic, laboratory, etc.)';
COMMENT ON COLUMN provider.facility.emergency_services IS 'Facility provides emergency services';

-- Indexes
CREATE INDEX idx_facility_name ON provider.facility(facility_name);
CREATE INDEX idx_facility_type ON provider.facility(facility_type);
CREATE INDEX idx_facility_organization ON provider.facility(organization_id);
CREATE INDEX idx_facility_npi ON provider.facility(npi) WHERE npi IS NOT NULL;
CREATE INDEX idx_facility_postal ON provider.facility(postal_code, country_code);
CREATE INDEX idx_facility_city ON provider.facility(city, country_code);
CREATE INDEX idx_facility_active ON provider.facility(active) WHERE active = TRUE;
CREATE INDEX idx_facility_geocode ON provider.facility USING gist(
    ll_to_earth(latitude, longitude)
) WHERE latitude IS NOT NULL AND longitude IS NOT NULL;

-- ============================================================================
-- Healthcare Providers (Individual Practitioners)
-- ============================================================================

CREATE TABLE provider.healthcare_provider (
    provider_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    -- Provider details
    title VARCHAR(50), -- Dr., Prof., etc.
    given_names TEXT[] NOT NULL,
    family_names TEXT[] NOT NULL,
    full_name TEXT,
    suffix VARCHAR(50), -- MD, PhD, RN, etc.
    -- Provider type and specialty
    provider_type VARCHAR(100) NOT NULL, -- 'physician', 'nurse', 'dentist', 'psychologist', etc.
    specialties TEXT[], -- Array of specialties
    sub_specialties TEXT[],
    -- Identifiers
    npi VARCHAR(20), -- National Provider Identifier (US)
    provider_code VARCHAR(100), -- Internal code
    license_numbers TEXT[], -- Array to support multiple licenses
    dea_number VARCHAR(20), -- DEA number for prescribers (US)
    -- Contact information
    primary_phone VARCHAR(20),
    primary_email VARCHAR(255),
    -- Qualifications
    medical_school VARCHAR(255),
    graduation_year INTEGER,
    board_certifications TEXT[],
    languages_spoken TEXT[], -- ISO language codes
    -- Employment/affiliation
    primary_facility_id UUID REFERENCES provider.facility(facility_id),
    additional_facilities UUID[], -- Array of facility IDs
    employment_status VARCHAR(50), -- 'employed', 'contracted', 'privileged', 'inactive'
    -- Status
    active BOOLEAN DEFAULT TRUE,
    license_status VARCHAR(50) DEFAULT 'active',
    license_expiry DATE,
    accepting_new_patients BOOLEAN DEFAULT TRUE,
    -- System fields
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_by VARCHAR(255) NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE,
    updated_by VARCHAR(255),
    -- Metadata
    metadata JSONB,
    CONSTRAINT valid_graduation_year CHECK (graduation_year >= 1900 AND graduation_year <= EXTRACT(YEAR FROM CURRENT_DATE))
);

COMMENT ON TABLE provider.healthcare_provider IS 'Individual healthcare providers (physicians, nurses, etc.)';
COMMENT ON COLUMN provider.healthcare_provider.npi IS 'National Provider Identifier (US) for individual providers';
COMMENT ON COLUMN provider.healthcare_provider.provider_type IS 'Type of provider (physician, nurse, dentist, etc.)';

-- Indexes
CREATE INDEX idx_provider_name_gin ON provider.healthcare_provider USING gin(family_names);
CREATE INDEX idx_provider_type ON provider.healthcare_provider(provider_type);
CREATE INDEX idx_provider_npi ON provider.healthcare_provider(npi) WHERE npi IS NOT NULL;
CREATE INDEX idx_provider_facility ON provider.healthcare_provider(primary_facility_id);
CREATE INDEX idx_provider_specialties_gin ON provider.healthcare_provider USING gin(specialties);
CREATE INDEX idx_provider_active ON provider.healthcare_provider(active) WHERE active = TRUE;
CREATE INDEX idx_provider_accepting ON provider.healthcare_provider(accepting_new_patients) WHERE accepting_new_patients = TRUE;

-- Trigger to generate full name
CREATE OR REPLACE FUNCTION provider.generate_provider_full_name()
RETURNS TRIGGER AS $$
BEGIN
    NEW.full_name := trim(CONCAT_WS(' ',
        NEW.title,
        array_to_string(NEW.given_names, ' '),
        array_to_string(NEW.family_names, ' '),
        NEW.suffix
    ));
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_provider_full_name
    BEFORE INSERT OR UPDATE ON provider.healthcare_provider
    FOR EACH ROW
    EXECUTE FUNCTION provider.generate_provider_full_name();

-- ============================================================================
-- Patient-Provider Relationships (Temporal)
-- ============================================================================

CREATE TABLE provider.patient_provider_relationship (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    patient_id UUID NOT NULL REFERENCES core.patient(patient_id),
    provider_id UUID REFERENCES provider.healthcare_provider(provider_id),
    facility_id UUID REFERENCES provider.facility(facility_id),
    -- At least one of provider_id or facility_id must be provided
    -- Relationship details
    relationship_type VARCHAR(100) NOT NULL, -- 'primary_care', 'specialist', 'consultant', 'emergency', 'surgical', 'dental', etc.
    care_level VARCHAR(50), -- 'primary', 'secondary', 'tertiary', 'quaternary'
    is_primary BOOLEAN DEFAULT FALSE, -- Primary provider of this type
    -- Specific provider types (from plan.md examples)
    provider_category VARCHAR(100), -- 'gp', 'hospital_team', 'dentist', 'optometrist', 'nutritionist', 'psychologist', 'psychiatrist', 'acupuncturist', etc.
    -- Period of care
    care_start_date DATE NOT NULL,
    care_end_date DATE,
    status VARCHAR(50) DEFAULT 'active', -- 'active', 'inactive', 'transferred', 'discharged'
    -- Referral information
    referred_by_provider_id UUID REFERENCES provider.healthcare_provider(provider_id),
    referral_reason TEXT,
    referral_date DATE,
    -- Care team information
    care_team_role VARCHAR(100), -- Role in care team if part of multi-disciplinary team
    is_care_coordinator BOOLEAN DEFAULT FALSE,
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
    notes TEXT,
    metadata JSONB,
    CONSTRAINT valid_relationship_period CHECK (effective_from < effective_to),
    CONSTRAINT valid_relationship_current CHECK (
        (is_current = TRUE AND effective_to = core.max_timestamp()) OR
        (is_current = FALSE AND effective_to < core.max_timestamp())
    ),
    CONSTRAINT valid_care_dates CHECK (
        care_end_date IS NULL OR care_end_date >= care_start_date
    ),
    CONSTRAINT require_provider_or_facility CHECK (
        provider_id IS NOT NULL OR facility_id IS NOT NULL
    )
);

COMMENT ON TABLE provider.patient_provider_relationship IS 'Patient relationships with healthcare providers and facilities';
COMMENT ON COLUMN provider.patient_provider_relationship.relationship_type IS 'Type of relationship (primary_care, specialist, consultant, etc.)';
COMMENT ON COLUMN provider.patient_provider_relationship.provider_category IS 'Specific provider category (gp, dentist, psychologist, etc.)';
COMMENT ON COLUMN provider.patient_provider_relationship.is_primary IS 'Primary provider of this type for this patient';

-- Indexes
CREATE INDEX idx_patient_provider_patient ON provider.patient_provider_relationship(patient_id);
CREATE INDEX idx_patient_provider_provider ON provider.patient_provider_relationship(provider_id);
CREATE INDEX idx_patient_provider_facility ON provider.patient_provider_relationship(facility_id);
CREATE INDEX idx_patient_provider_current ON provider.patient_provider_relationship(patient_id, is_current) WHERE is_current = TRUE;
CREATE INDEX idx_patient_provider_type ON provider.patient_provider_relationship(relationship_type);
CREATE INDEX idx_patient_provider_category ON provider.patient_provider_relationship(provider_category);
CREATE INDEX idx_patient_provider_primary ON provider.patient_provider_relationship(patient_id, is_primary) WHERE is_primary = TRUE;
CREATE INDEX idx_patient_provider_status ON provider.patient_provider_relationship(status) WHERE status = 'active';
CREATE INDEX idx_patient_provider_dates ON provider.patient_provider_relationship(care_start_date, care_end_date);
CREATE INDEX idx_patient_provider_effective ON provider.patient_provider_relationship(effective_from, effective_to);

-- Temporal triggers
CREATE TRIGGER trg_patient_provider_auto_current
    BEFORE INSERT ON provider.patient_provider_relationship
    FOR EACH ROW
    EXECUTE FUNCTION core.auto_set_current();

-- ============================================================================
-- Provider Search Functions
-- ============================================================================

-- Find providers by name
CREATE OR REPLACE FUNCTION provider.find_providers_by_name(
    p_search_name VARCHAR
)
RETURNS TABLE(
    provider_id UUID,
    full_name TEXT,
    provider_type VARCHAR,
    specialties TEXT[],
    primary_facility_id UUID,
    active BOOLEAN
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        p.provider_id,
        p.full_name,
        p.provider_type,
        p.specialties,
        p.primary_facility_id,
        p.active
    FROM provider.healthcare_provider p
    WHERE p.full_name ILIKE '%' || p_search_name || '%'
        OR EXISTS (
            SELECT 1 FROM unnest(p.family_names) fn
            WHERE fn ILIKE '%' || p_search_name || '%'
        )
    ORDER BY p.full_name;
END;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION provider.find_providers_by_name IS 'Searches providers by name';

-- Get patient care team
CREATE OR REPLACE FUNCTION provider.get_patient_care_team(
    p_patient_id UUID,
    p_current_only BOOLEAN DEFAULT TRUE
)
RETURNS TABLE(
    relationship_id UUID,
    provider_id UUID,
    provider_name TEXT,
    provider_type VARCHAR,
    facility_id UUID,
    facility_name VARCHAR,
    relationship_type VARCHAR,
    provider_category VARCHAR,
    is_primary BOOLEAN,
    care_start_date DATE,
    status VARCHAR
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        r.id,
        r.provider_id,
        pr.full_name,
        pr.provider_type,
        r.facility_id,
        f.facility_name,
        r.relationship_type,
        r.provider_category,
        r.is_primary,
        r.care_start_date,
        r.status
    FROM provider.patient_provider_relationship r
    LEFT JOIN provider.healthcare_provider pr ON r.provider_id = pr.provider_id
    LEFT JOIN provider.facility f ON r.facility_id = f.facility_id
    WHERE r.patient_id = p_patient_id
        AND (NOT p_current_only OR r.is_current = TRUE)
        AND r.deleted_at IS NULL
    ORDER BY r.is_primary DESC, r.care_start_date DESC;
END;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION provider.get_patient_care_team IS 'Returns patient care team (all providers and facilities)';

-- ============================================================================
-- Grant Permissions
-- ============================================================================

GRANT SELECT ON provider.organization TO mpi_read_only, mpi_clinical_user, mpi_admin, mpi_integration;
GRANT INSERT, UPDATE ON provider.organization TO mpi_admin;

GRANT SELECT ON provider.facility TO mpi_read_only, mpi_clinical_user, mpi_admin, mpi_integration;
GRANT INSERT, UPDATE ON provider.facility TO mpi_admin;

GRANT SELECT ON provider.healthcare_provider TO mpi_read_only, mpi_clinical_user, mpi_admin, mpi_integration;
GRANT INSERT, UPDATE ON provider.healthcare_provider TO mpi_admin;

GRANT SELECT ON provider.patient_provider_relationship TO mpi_read_only, mpi_clinical_user, mpi_admin, mpi_integration;
GRANT INSERT ON provider.patient_provider_relationship TO mpi_clinical_user, mpi_admin, mpi_integration;
GRANT UPDATE (effective_to, is_current, status, care_end_date) ON provider.patient_provider_relationship TO mpi_clinical_user, mpi_admin;

GRANT EXECUTE ON FUNCTION provider.find_providers_by_name TO mpi_read_only, mpi_clinical_user, mpi_admin, mpi_integration;
GRANT EXECUTE ON FUNCTION provider.get_patient_care_team TO mpi_read_only, mpi_clinical_user, mpi_admin, mpi_integration;

-- ============================================================================
-- Providers Complete
-- ============================================================================
