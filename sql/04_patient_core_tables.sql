-- ============================================================================
-- Master Patient Index (MPI) - Core Patient Tables
-- PostgreSQL 18
-- ============================================================================
-- Purpose: Patient master record and core demographic data with temporal tracking
-- HIPAA Compliant | UK DPA 2018 Compliant
-- ============================================================================

-- ============================================================================
-- Patient Master Record
-- ============================================================================

-- Main patient table (immutable core attributes only)
CREATE TABLE core.patient (
    patient_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    -- Immutable attributes
    date_of_birth DATE NOT NULL,
    biological_sex core.biological_sex NOT NULL,
    birth_plurality INTEGER DEFAULT 1 CHECK (birth_plurality >= 1), -- 1=singleton, 2=twin, etc.
    birth_order INTEGER CHECK (birth_order >= 1), -- Birth order for multiples
    deceased BOOLEAN DEFAULT FALSE,
    date_of_death DATE,
    -- System fields
    record_status core.record_status DEFAULT 'active',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_by VARCHAR(255) NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE,
    updated_by VARCHAR(255),
    -- Soft delete
    deleted_at TIMESTAMP WITH TIME ZONE,
    deleted_by VARCHAR(255),
    deletion_reason TEXT,
    -- Metadata
    source_system VARCHAR(100), -- Original system that created the record
    external_id VARCHAR(255), -- External system identifier
    data_quality_score DECIMAL(3,2) CHECK (data_quality_score >= 0 AND data_quality_score <= 1),
    notes TEXT,
    metadata JSONB,
    CONSTRAINT valid_death_date CHECK (
        (deceased = FALSE AND date_of_death IS NULL) OR
        (deceased = TRUE AND date_of_death IS NOT NULL)
    ),
    CONSTRAINT valid_birth_order CHECK (
        (birth_plurality = 1 AND birth_order IS NULL) OR
        (birth_plurality > 1 AND birth_order IS NOT NULL AND birth_order <= birth_plurality)
    ),
    CONSTRAINT valid_dob_dod CHECK (
        date_of_death IS NULL OR date_of_death >= date_of_birth
    )
);

COMMENT ON TABLE core.patient IS 'Master patient record with immutable core attributes';
COMMENT ON COLUMN core.patient.patient_id IS 'Unique patient identifier (UUID)';
COMMENT ON COLUMN core.patient.date_of_birth IS 'Patient date of birth (immutable)';
COMMENT ON COLUMN core.patient.biological_sex IS 'Biological sex for clinical purposes';
COMMENT ON COLUMN core.patient.birth_plurality IS 'Number in birth set (1=singleton, 2=twin, 3=triplet, etc.)';
COMMENT ON COLUMN core.patient.birth_order IS 'Birth order for multiples (1st born, 2nd born, etc.)';
COMMENT ON COLUMN core.patient.deceased IS 'Deceased flag';
COMMENT ON COLUMN core.patient.date_of_death IS 'Date of death if deceased';
COMMENT ON COLUMN core.patient.data_quality_score IS 'Data quality score 0.0-1.0';
COMMENT ON COLUMN core.patient.metadata IS 'Additional metadata in JSON format';

-- Indexes
CREATE INDEX idx_patient_dob ON core.patient(date_of_birth);
CREATE INDEX idx_patient_status ON core.patient(record_status) WHERE record_status = 'active';
CREATE INDEX idx_patient_deceased ON core.patient(deceased) WHERE deceased = TRUE;
CREATE INDEX idx_patient_created ON core.patient(created_at DESC);
CREATE INDEX idx_patient_source ON core.patient(source_system);
CREATE INDEX idx_patient_external_id ON core.patient(source_system, external_id);
CREATE INDEX idx_patient_deleted ON core.patient(deleted_at) WHERE deleted_at IS NOT NULL;

-- ============================================================================
-- Patient Names (Temporal)
-- ============================================================================

CREATE TABLE core.patient_name (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    patient_id UUID NOT NULL REFERENCES core.patient(patient_id),
    -- Name components (supporting multiple of each)
    given_names TEXT[] NOT NULL, -- Array of given names
    middle_names TEXT[], -- Array of middle names
    family_names TEXT[] NOT NULL, -- Array of family names
    prefix VARCHAR(50), -- Dr., Mr., Mrs., Ms., etc.
    suffix VARCHAR(50), -- Jr., Sr., III, etc.
    -- Full name variants
    full_name TEXT GENERATED ALWAYS AS (
        COALESCE(prefix || ' ', '') ||
        array_to_string(given_names, ' ') ||
        COALESCE(' ' || array_to_string(middle_names, ' '), '') ||
        ' ' || array_to_string(family_names, ' ') ||
        COALESCE(' ' || suffix, '')
    ) STORED,
    -- Name type and usage
    name_type VARCHAR(50) NOT NULL, -- 'legal', 'preferred', 'maiden', 'alias', 'stage', 'professional'
    use_context VARCHAR(50), -- 'official', 'usual', 'temp', 'nickname', 'anonymous', 'old', 'maiden'
    locale VARCHAR(10), -- Language/locale code (en, es, fr, etc.)
    -- Phonetic representations for matching
    soundex_given VARCHAR(10),
    soundex_family VARCHAR(10),
    metaphone_given VARCHAR(20),
    metaphone_family VARCHAR(20),
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
    verification_status VARCHAR(50), -- 'verified', 'unverified', 'document_verified'
    verified_by VARCHAR(255),
    verified_at TIMESTAMP WITH TIME ZONE,
    metadata JSONB,
    CONSTRAINT valid_name_period CHECK (effective_from < effective_to),
    CONSTRAINT valid_current_flag CHECK (
        (is_current = TRUE AND effective_to = core.max_timestamp()) OR
        (is_current = FALSE AND effective_to < core.max_timestamp())
    )
);

COMMENT ON TABLE core.patient_name IS 'Patient names with full temporal tracking and multiple name support';
COMMENT ON COLUMN core.patient_name.given_names IS 'Array of given names (first names)';
COMMENT ON COLUMN core.patient_name.middle_names IS 'Array of middle names';
COMMENT ON COLUMN core.patient_name.family_names IS 'Array of family names (surnames)';
COMMENT ON COLUMN core.patient_name.name_type IS 'Type of name (legal, preferred, maiden, alias, etc.)';
COMMENT ON COLUMN core.patient_name.use_context IS 'Usage context from HL7 FHIR';
COMMENT ON COLUMN core.patient_name.soundex_given IS 'Soundex encoding of first given name for fuzzy matching';
COMMENT ON COLUMN core.patient_name.metaphone_given IS 'Metaphone encoding of first given name';

-- Indexes
CREATE INDEX idx_patient_name_patient ON core.patient_name(patient_id);
CREATE INDEX idx_patient_name_current ON core.patient_name(patient_id, is_current) WHERE is_current = TRUE;
CREATE INDEX idx_patient_name_effective ON core.patient_name(effective_from, effective_to);
CREATE INDEX idx_patient_name_family_gin ON core.patient_name USING gin(family_names);
CREATE INDEX idx_patient_name_given_gin ON core.patient_name USING gin(given_names);
CREATE INDEX idx_patient_name_full_name ON core.patient_name(full_name);
CREATE INDEX idx_patient_name_soundex ON core.patient_name(soundex_family, soundex_given);
CREATE INDEX idx_patient_name_metaphone ON core.patient_name(metaphone_family, metaphone_given);
CREATE INDEX idx_patient_name_type ON core.patient_name(patient_id, name_type) WHERE is_current = TRUE;
CREATE INDEX idx_patient_name_locale ON core.patient_name(locale);

-- Unique constraint: only one current record per patient per name type
CREATE UNIQUE INDEX uniq_patient_name_current ON core.patient_name(patient_id, name_type)
    WHERE is_current = TRUE AND deleted_at IS NULL;

-- Trigger to auto-generate phonetic codes
CREATE OR REPLACE FUNCTION core.generate_name_phonetics()
RETURNS TRIGGER AS $$
BEGIN
    -- Generate Soundex codes (first given name and first family name)
    IF array_length(NEW.given_names, 1) > 0 THEN
        NEW.soundex_given := soundex(NEW.given_names[1]);
    END IF;
    IF array_length(NEW.family_names, 1) > 0 THEN
        NEW.soundex_family := soundex(NEW.family_names[1]);
    END IF;

    -- Generate Metaphone codes
    IF array_length(NEW.given_names, 1) > 0 THEN
        NEW.metaphone_given := metaphone(NEW.given_names[1], 10);
    END IF;
    IF array_length(NEW.family_names, 1) > 0 THEN
        NEW.metaphone_family := metaphone(NEW.family_names[1], 10);
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_patient_name_phonetics
    BEFORE INSERT OR UPDATE ON core.patient_name
    FOR EACH ROW
    EXECUTE FUNCTION core.generate_name_phonetics();

-- Temporal triggers
CREATE TRIGGER trg_patient_name_auto_current
    BEFORE INSERT ON core.patient_name
    FOR EACH ROW
    EXECUTE FUNCTION core.auto_set_current();

-- ============================================================================
-- Patient Demographics (Temporal)
-- ============================================================================

CREATE TABLE core.patient_demographic (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    patient_id UUID NOT NULL REFERENCES core.patient(patient_id),
    -- Demographics
    gender_identity core.gender_identity,
    gender_identity_text VARCHAR(100), -- Free text if 'other'
    sexual_orientation VARCHAR(50),
    marital_status VARCHAR(50), -- 'single', 'married', 'divorced', 'widowed', 'domestic_partner', etc.
    -- Ethnicity and race (can be multiple)
    ethnicity VARCHAR(100),
    race TEXT[], -- Array to support multiple races
    -- Language and communication
    primary_language VARCHAR(10), -- ISO 639 code
    spoken_languages TEXT[], -- Array of language codes
    written_languages TEXT[], -- Array of language codes
    interpreter_required BOOLEAN DEFAULT FALSE,
    communication_preferences JSONB, -- Preferred contact method, times, etc.
    -- Religion and cultural
    religion VARCHAR(100),
    cultural_background TEXT[],
    -- Occupation and education
    occupation VARCHAR(255),
    education_level VARCHAR(100),
    -- Emergency contact preferences
    emergency_contact_relationship VARCHAR(100),
    -- Accessibility needs
    disabilities TEXT[],
    accessibility_needs TEXT[],
    special_accommodations TEXT,
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
    CONSTRAINT valid_demographic_period CHECK (effective_from < effective_to),
    CONSTRAINT valid_demographic_current CHECK (
        (is_current = TRUE AND effective_to = core.max_timestamp()) OR
        (is_current = FALSE AND effective_to < core.max_timestamp())
    )
);

COMMENT ON TABLE core.patient_demographic IS 'Patient demographics with full temporal tracking';
COMMENT ON COLUMN core.patient_demographic.gender_identity IS 'Self-identified gender';
COMMENT ON COLUMN core.patient_demographic.primary_language IS 'Primary language ISO 639 code';
COMMENT ON COLUMN core.patient_demographic.interpreter_required IS 'Interpreter required for medical communication';
COMMENT ON COLUMN core.patient_demographic.race IS 'Array of race categories (supports multiple)';

-- Indexes
CREATE INDEX idx_patient_demographic_patient ON core.patient_demographic(patient_id);
CREATE INDEX idx_patient_demographic_current ON core.patient_demographic(patient_id, is_current) WHERE is_current = TRUE;
CREATE INDEX idx_patient_demographic_effective ON core.patient_demographic(effective_from, effective_to);
CREATE INDEX idx_patient_demographic_language ON core.patient_demographic(primary_language);
CREATE INDEX idx_patient_demographic_race_gin ON core.patient_demographic USING gin(race);

-- Unique constraint: only one current record per patient
CREATE UNIQUE INDEX uniq_patient_demographic_current ON core.patient_demographic(patient_id)
    WHERE is_current = TRUE AND deleted_at IS NULL;

-- Temporal triggers
CREATE TRIGGER trg_patient_demographic_auto_current
    BEFORE INSERT ON core.patient_demographic
    FOR EACH ROW
    EXECUTE FUNCTION core.auto_set_current();

-- ============================================================================
-- Patient Views (Current Data Only)
-- ============================================================================

-- View for current patient data with names and demographics
CREATE OR REPLACE VIEW core.v_patient_current AS
SELECT
    p.patient_id,
    p.date_of_birth,
    p.biological_sex,
    p.deceased,
    p.date_of_death,
    p.record_status,
    -- Current legal name
    n_legal.full_name as legal_name,
    n_legal.given_names as legal_given_names,
    n_legal.family_names as legal_family_names,
    -- Current preferred name (if different from legal)
    n_pref.full_name as preferred_name,
    -- Demographics
    d.gender_identity,
    d.primary_language,
    d.ethnicity,
    d.race,
    d.marital_status,
    -- System
    p.created_at,
    p.created_by,
    p.data_quality_score
FROM core.patient p
LEFT JOIN core.patient_name n_legal ON p.patient_id = n_legal.patient_id
    AND n_legal.name_type = 'legal'
    AND n_legal.is_current = TRUE
    AND n_legal.deleted_at IS NULL
LEFT JOIN core.patient_name n_pref ON p.patient_id = n_pref.patient_id
    AND n_pref.name_type = 'preferred'
    AND n_pref.is_current = TRUE
    AND n_pref.deleted_at IS NULL
LEFT JOIN core.patient_demographic d ON p.patient_id = d.patient_id
    AND d.is_current = TRUE
    AND d.deleted_at IS NULL
WHERE p.deleted_at IS NULL
    AND p.record_status = 'active';

COMMENT ON VIEW core.v_patient_current IS 'Current view of patient with legal name, preferred name, and demographics';

-- ============================================================================
-- Grant Permissions
-- ============================================================================

GRANT SELECT ON core.patient TO mpi_read_only, mpi_clinical_user, mpi_admin, mpi_integration;
GRANT INSERT, UPDATE ON core.patient TO mpi_clinical_user, mpi_admin, mpi_integration;
GRANT DELETE ON core.patient TO mpi_admin;

GRANT SELECT ON core.patient_name TO mpi_read_only, mpi_clinical_user, mpi_admin, mpi_integration;
GRANT INSERT ON core.patient_name TO mpi_clinical_user, mpi_admin, mpi_integration;
GRANT UPDATE (effective_to, is_current, updated_at, updated_by) ON core.patient_name TO mpi_clinical_user, mpi_admin;

GRANT SELECT ON core.patient_demographic TO mpi_read_only, mpi_clinical_user, mpi_admin, mpi_integration;
GRANT INSERT ON core.patient_demographic TO mpi_clinical_user, mpi_admin, mpi_integration;
GRANT UPDATE (effective_to, is_current, updated_at, updated_by) ON core.patient_demographic TO mpi_clinical_user, mpi_admin;

GRANT SELECT ON core.v_patient_current TO mpi_read_only, mpi_clinical_user, mpi_admin, mpi_integration;

-- ============================================================================
-- Core Patient Tables Complete
-- ============================================================================
