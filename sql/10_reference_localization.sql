-- ============================================================================
-- Master Patient Index (MPI) - Reference Data and Localization
-- PostgreSQL 18
-- ============================================================================
-- Purpose: Reference tables and multi-language support
-- Supports: English, Welsh, Spanish, French, Mandarin, Arabic, Russian
-- ============================================================================

-- ============================================================================
-- Locale and Language Support
-- ============================================================================

CREATE TABLE reference.locale (
    locale_code VARCHAR(10) PRIMARY KEY, -- e.g., 'en', 'en-US', 'cy', 'es', 'fr', 'zh', 'ar', 'ru'
    locale_name VARCHAR(100) NOT NULL,
    language_code CHAR(2) NOT NULL, -- ISO 639-1
    country_code CHAR(2), -- ISO 3166-1 alpha-2
    is_rtl BOOLEAN DEFAULT FALSE, -- Right-to-left (Arabic)
    display_name_native VARCHAR(100), -- Name in native language
    enabled BOOLEAN DEFAULT TRUE,
    sort_order INTEGER,
    metadata JSONB
);

COMMENT ON TABLE reference.locale IS 'Supported locales for multi-language support';
COMMENT ON COLUMN reference.locale.is_rtl IS 'Right-to-left language (e.g., Arabic)';

-- Insert supported locales from plan.md
INSERT INTO reference.locale (locale_code, locale_name, language_code, country_code, is_rtl, display_name_native, sort_order) VALUES
('en', 'English', 'en', NULL, FALSE, 'English', 1),
('en-GB', 'English (United Kingdom)', 'en', 'GB', FALSE, 'English (UK)', 2),
('en-US', 'English (United States)', 'en', 'US', FALSE, 'English (US)', 3),
('cy', 'Welsh', 'cy', 'GB', FALSE, 'Cymraeg', 4),
('es', 'Spanish', 'es', NULL, FALSE, 'Español', 5),
('fr', 'French', 'fr', NULL, FALSE, 'Français', 6),
('zh', 'Mandarin Chinese', 'zh', NULL, FALSE, '中文', 7),
('ar', 'Arabic', 'ar', NULL, TRUE, 'العربية', 8),
('ru', 'Russian', 'ru', NULL, FALSE, 'Русский', 9);

-- ============================================================================
-- Translation Table (for UI text and reference data)
-- ============================================================================

CREATE TABLE reference.translation (
    translation_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    -- Translation key
    translation_key VARCHAR(255) NOT NULL, -- e.g., 'consent_type.treatment'
    locale_code VARCHAR(10) NOT NULL REFERENCES reference.locale(locale_code),
    -- Translation
    translated_text TEXT NOT NULL,
    translated_text_plural TEXT, -- For pluralization
    -- Context
    context VARCHAR(255), -- Additional context for translators
    table_name VARCHAR(100), -- Source table if translating reference data
    field_name VARCHAR(100), -- Source field
    -- Quality
    verified BOOLEAN DEFAULT FALSE,
    verified_by VARCHAR(255),
    verified_at TIMESTAMP WITH TIME ZONE,
    -- System fields
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_by VARCHAR(255) NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE,
    updated_by VARCHAR(255),
    metadata JSONB
);

COMMENT ON TABLE reference.translation IS 'Translations for multi-language support';
COMMENT ON COLUMN reference.translation.translation_key IS 'Unique key identifying text to translate';

-- Indexes
CREATE INDEX idx_translation_key ON reference.translation(translation_key);
CREATE INDEX idx_translation_locale ON reference.translation(locale_code);
CREATE INDEX idx_translation_table ON reference.translation(table_name, field_name) WHERE table_name IS NOT NULL;

-- Unique constraint
CREATE UNIQUE INDEX uniq_translation_key_locale ON reference.translation(translation_key, locale_code);

-- ============================================================================
-- Country Reference Data
-- ============================================================================

CREATE TABLE reference.country (
    country_code CHAR(2) PRIMARY KEY, -- ISO 3166-1 alpha-2
    country_code_3 CHAR(3) UNIQUE, -- ISO 3166-1 alpha-3
    country_name_en VARCHAR(255) NOT NULL,
    country_name_native VARCHAR(255),
    numeric_code CHAR(3), -- ISO 3166-1 numeric
    region VARCHAR(100), -- Geographic region
    subregion VARCHAR(100),
    phone_code VARCHAR(10), -- International dialing code
    currency_code CHAR(3), -- ISO 4217
    enabled BOOLEAN DEFAULT TRUE,
    metadata JSONB
);

COMMENT ON TABLE reference.country IS 'ISO 3166 country codes';

-- Insert key countries (add more as needed)
INSERT INTO reference.country (country_code, country_code_3, country_name_en, numeric_code, phone_code, currency_code) VALUES
('US', 'USA', 'United States', '840', '+1', 'USD'),
('GB', 'GBR', 'United Kingdom', '826', '+44', 'GBP'),
('ES', 'ESP', 'Spain', '724', '+34', 'EUR'),
('FR', 'FRA', 'France', '250', '+33', 'EUR'),
('CN', 'CHN', 'China', '156', '+86', 'CNY'),
('SA', 'SAU', 'Saudi Arabia', '682', '+966', 'SAR'),
('RU', 'RUS', 'Russian Federation', '643', '+7', 'RUB'),
('CA', 'CAN', 'Canada', '124', '+1', 'CAD'),
('AU', 'AUS', 'Australia', '036', '+61', 'AUD'),
('DE', 'DEU', 'Germany', '276', '+49', 'EUR');

-- ============================================================================
-- Identifier Type Reference
-- ============================================================================

CREATE TABLE reference.identifier_type (
    identifier_type_code VARCHAR(50) PRIMARY KEY,
    identifier_type_name VARCHAR(255) NOT NULL,
    identifier_category VARCHAR(50) NOT NULL, -- 'government', 'insurance', 'facility', 'federated'
    country_specific BOOLEAN DEFAULT FALSE,
    applicable_countries CHAR(2)[], -- Array of country codes where this ID type applies
    validation_regex VARCHAR(500), -- Regex for validation
    validation_function VARCHAR(255), -- Name of validation function if complex
    display_format VARCHAR(100), -- How to display (e.g., 'XXX-XX-XXXX' for SSN)
    description TEXT,
    enabled BOOLEAN DEFAULT TRUE,
    metadata JSONB
);

COMMENT ON TABLE reference.identifier_type IS 'Types of identifiers (SSN, NHS number, passport, etc.)';

-- Insert common identifier types
INSERT INTO reference.identifier_type (identifier_type_code, identifier_type_name, identifier_category, country_specific, applicable_countries, display_format, description) VALUES
('ssn', 'Social Security Number', 'government', TRUE, ARRAY['US'], 'XXX-XX-XXXX', 'US Social Security Number'),
('nhs_number', 'NHS Number', 'government', TRUE, ARRAY['GB'], 'XXX XXX XXXX', 'UK NHS Number'),
('passport', 'Passport', 'government', FALSE, NULL, NULL, 'International passport number'),
('drivers_license', 'Driver''s License', 'government', FALSE, NULL, NULL, 'Driver license or permit'),
('national_id', 'National ID', 'government', FALSE, NULL, NULL, 'National identity card'),
('medicare', 'Medicare Number', 'insurance', TRUE, ARRAY['US'], NULL, 'US Medicare beneficiary number'),
('medicaid', 'Medicaid Number', 'insurance', TRUE, ARRAY['US'], NULL, 'US Medicaid beneficiary number'),
('insurance_member', 'Insurance Member ID', 'insurance', FALSE, NULL, NULL, 'General health insurance member ID'),
('mrn', 'Medical Record Number', 'facility', FALSE, NULL, NULL, 'Facility medical record number');

-- ============================================================================
-- Phone and Address Type Reference
-- ============================================================================

CREATE TABLE reference.contact_type (
    contact_type_code VARCHAR(50) PRIMARY KEY,
    contact_type_name VARCHAR(255) NOT NULL,
    contact_category VARCHAR(50) NOT NULL, -- 'phone', 'email', 'address'
    description TEXT,
    sort_order INTEGER,
    enabled BOOLEAN DEFAULT TRUE
);

COMMENT ON TABLE reference.contact_type IS 'Types of contact information';

-- Insert contact types
INSERT INTO reference.contact_type (contact_type_code, contact_type_name, contact_category, sort_order) VALUES
-- Phone types
('mobile', 'Mobile Phone', 'phone', 1),
('home', 'Home Phone', 'phone', 2),
('work', 'Work Phone', 'phone', 3),
('fax', 'Fax', 'phone', 4),
('emergency', 'Emergency Contact', 'phone', 5),
-- Email types
('personal', 'Personal Email', 'email', 1),
('work_email', 'Work Email', 'email', 2),
('temporary', 'Temporary Email', 'email', 3),
-- Address types
('home_address', 'Home Address', 'address', 1),
('work_address', 'Work Address', 'address', 2),
('temporary_address', 'Temporary Address', 'address', 3),
('postal', 'Postal Address', 'address', 4),
('billing', 'Billing Address', 'address', 5);

-- ============================================================================
-- Name Type Reference
-- ============================================================================

CREATE TABLE reference.name_type (
    name_type_code VARCHAR(50) PRIMARY KEY,
    name_type_name VARCHAR(255) NOT NULL,
    description TEXT,
    sort_order INTEGER,
    enabled BOOLEAN DEFAULT TRUE
);

COMMENT ON TABLE reference.name_type IS 'Types of patient names';

-- Insert name types
INSERT INTO reference.name_type (name_type_code, name_type_name, description, sort_order) VALUES
('legal', 'Legal Name', 'Official legal name', 1),
('preferred', 'Preferred Name', 'Name patient prefers to be called', 2),
('maiden', 'Maiden Name', 'Birth surname before marriage', 3),
('alias', 'Alias', 'Alternative name or alias', 4),
('stage', 'Stage Name', 'Professional or stage name', 5),
('professional', 'Professional Name', 'Professional or business name', 6),
('nickname', 'Nickname', 'Informal nickname', 7),
('previous', 'Previous Name', 'Previously used name', 8);

-- ============================================================================
-- Provider Type and Specialty Reference
-- ============================================================================

CREATE TABLE reference.provider_type (
    provider_type_code VARCHAR(100) PRIMARY KEY,
    provider_type_name VARCHAR(255) NOT NULL,
    category VARCHAR(100), -- 'physician', 'nurse', 'allied_health', 'mental_health', etc.
    requires_license BOOLEAN DEFAULT TRUE,
    can_prescribe BOOLEAN DEFAULT FALSE,
    description TEXT,
    sort_order INTEGER,
    enabled BOOLEAN DEFAULT TRUE
);

COMMENT ON TABLE reference.provider_type IS 'Types of healthcare providers';

-- Insert provider types from plan.md
INSERT INTO reference.provider_type (provider_type_code, provider_type_name, category, requires_license, can_prescribe, sort_order) VALUES
('gp', 'General Practitioner', 'physician', TRUE, TRUE, 1),
('physician', 'Physician', 'physician', TRUE, TRUE, 2),
('specialist', 'Specialist Physician', 'physician', TRUE, TRUE, 3),
('surgeon', 'Surgeon', 'physician', TRUE, TRUE, 4),
('dentist', 'Dentist', 'dental', TRUE, TRUE, 5),
('optometrist', 'Optometrist', 'vision', TRUE, FALSE, 6),
('nutritionist', 'Nutritionist', 'allied_health', TRUE, FALSE, 7),
('psychologist', 'Psychologist', 'mental_health', TRUE, FALSE, 8),
('psychiatrist', 'Psychiatrist', 'mental_health', TRUE, TRUE, 9),
('acupuncturist', 'Acupuncturist', 'complementary', TRUE, FALSE, 10),
('nurse_practitioner', 'Nurse Practitioner', 'nurse', TRUE, TRUE, 11),
('registered_nurse', 'Registered Nurse', 'nurse', TRUE, FALSE, 12),
('pharmacist', 'Pharmacist', 'pharmacy', TRUE, TRUE, 13),
('physical_therapist', 'Physical Therapist', 'allied_health', TRUE, FALSE, 14),
('occupational_therapist', 'Occupational Therapist', 'allied_health', TRUE, FALSE, 15);

CREATE TABLE reference.medical_specialty (
    specialty_code VARCHAR(100) PRIMARY KEY,
    specialty_name VARCHAR(255) NOT NULL,
    specialty_category VARCHAR(100),
    description TEXT,
    enabled BOOLEAN DEFAULT TRUE
);

COMMENT ON TABLE reference.medical_specialty IS 'Medical specialties';

-- Insert common specialties
INSERT INTO reference.medical_specialty (specialty_code, specialty_name, specialty_category) VALUES
('cardiology', 'Cardiology', 'medicine'),
('neurology', 'Neurology', 'medicine'),
('oncology', 'Oncology', 'medicine'),
('pediatrics', 'Pediatrics', 'medicine'),
('obstetrics_gynecology', 'Obstetrics and Gynecology', 'surgery'),
('orthopedics', 'Orthopedics', 'surgery'),
('psychiatry', 'Psychiatry', 'mental_health'),
('radiology', 'Radiology', 'diagnostic'),
('anesthesiology', 'Anesthesiology', 'perioperative'),
('emergency_medicine', 'Emergency Medicine', 'emergency'),
('family_medicine', 'Family Medicine', 'primary_care'),
('internal_medicine', 'Internal Medicine', 'primary_care'),
('dermatology', 'Dermatology', 'medicine'),
('ophthalmology', 'Ophthalmology', 'surgery'),
('pathology', 'Pathology', 'diagnostic');

-- ============================================================================
-- Relationship Type Reference
-- ============================================================================

CREATE TABLE reference.relationship_type (
    relationship_type_code VARCHAR(100) PRIMARY KEY,
    relationship_type_name VARCHAR(255) NOT NULL,
    category VARCHAR(50), -- 'care', 'family', 'emergency'
    description TEXT,
    enabled BOOLEAN DEFAULT TRUE
);

COMMENT ON TABLE reference.relationship_type IS 'Types of relationships (patient-provider, family, emergency)';

-- Insert relationship types
INSERT INTO reference.relationship_type (relationship_type_code, relationship_type_name, category) VALUES
-- Provider relationships
('primary_care', 'Primary Care Provider', 'care'),
('specialist', 'Specialist', 'care'),
('consultant', 'Consultant', 'care'),
('referring', 'Referring Provider', 'care'),
('emergency', 'Emergency Contact Provider', 'care'),
-- Family relationships
('spouse', 'Spouse', 'family'),
('partner', 'Partner', 'family'),
('parent', 'Parent', 'family'),
('child', 'Child', 'family'),
('sibling', 'Sibling', 'family'),
('grandparent', 'Grandparent', 'family'),
('guardian', 'Legal Guardian', 'family'),
-- Emergency contacts
('emergency_contact', 'Emergency Contact', 'emergency'),
('next_of_kin', 'Next of Kin', 'emergency');

-- ============================================================================
-- Consent and Privacy Reference Data
-- ============================================================================

CREATE TABLE reference.consent_purpose (
    purpose_code VARCHAR(100) PRIMARY KEY,
    purpose_name VARCHAR(255) NOT NULL,
    purpose_category VARCHAR(50), -- 'treatment', 'payment', 'operations', 'research'
    description TEXT,
    requires_explicit_consent BOOLEAN DEFAULT FALSE,
    enabled BOOLEAN DEFAULT TRUE
);

COMMENT ON TABLE reference.consent_purpose IS 'Purposes for data use and consent';

-- Insert consent purposes (TPO + others)
INSERT INTO reference.consent_purpose (purpose_code, purpose_name, purpose_category, requires_explicit_consent) VALUES
('treatment', 'Treatment', 'treatment', FALSE),
('payment', 'Payment', 'payment', FALSE),
('operations', 'Healthcare Operations', 'operations', FALSE),
('research', 'Medical Research', 'research', TRUE),
('quality_improvement', 'Quality Improvement', 'operations', FALSE),
('public_health', 'Public Health', 'public_health', FALSE),
('marketing', 'Marketing', 'marketing', TRUE),
('third_party', 'Third Party Sharing', 'sharing', TRUE);

-- ============================================================================
-- Data Classification
-- ============================================================================

CREATE TABLE reference.data_classification (
    classification_code VARCHAR(50) PRIMARY KEY,
    classification_name VARCHAR(255) NOT NULL,
    sensitivity_level VARCHAR(50), -- 'public', 'internal', 'confidential', 'restricted'
    regulatory_category VARCHAR(100), -- 'phi', 'pii', 'special_category', 'financial'
    encryption_required BOOLEAN DEFAULT FALSE,
    audit_access BOOLEAN DEFAULT FALSE,
    retention_years INTEGER,
    description TEXT
);

COMMENT ON TABLE reference.data_classification IS 'Data classification for privacy and security';

-- Insert data classifications
INSERT INTO reference.data_classification (classification_code, classification_name, sensitivity_level, regulatory_category, encryption_required, audit_access) VALUES
('phi_general', 'Protected Health Information (General)', 'confidential', 'phi', FALSE, TRUE),
('phi_sensitive', 'Sensitive PHI (Mental Health, HIV, etc.)', 'restricted', 'phi', TRUE, TRUE),
('pii', 'Personally Identifiable Information', 'confidential', 'pii', TRUE, TRUE),
('financial', 'Financial Information', 'confidential', 'financial', TRUE, TRUE),
('special_category', 'Special Category (GDPR)', 'restricted', 'special_category', TRUE, TRUE),
('public', 'Public Information', 'public', NULL, FALSE, FALSE);

-- ============================================================================
-- Helper Functions for Translations
-- ============================================================================

-- Get translation for a key
CREATE OR REPLACE FUNCTION reference.get_translation(
    p_translation_key VARCHAR,
    p_locale_code VARCHAR DEFAULT 'en'
)
RETURNS TEXT AS $$
DECLARE
    v_translation TEXT;
BEGIN
    SELECT translated_text INTO v_translation
    FROM reference.translation
    WHERE translation_key = p_translation_key
        AND locale_code = p_locale_code;

    -- Fallback to English if translation not found
    IF v_translation IS NULL THEN
        SELECT translated_text INTO v_translation
        FROM reference.translation
        WHERE translation_key = p_translation_key
            AND locale_code = 'en';
    END IF;

    -- Fallback to key if still not found
    RETURN COALESCE(v_translation, p_translation_key);
END;
$$ LANGUAGE plpgsql STABLE;
COMMENT ON FUNCTION reference.get_translation IS 'Gets translation for key in specified locale';

-- ============================================================================
-- Grant Permissions
-- ============================================================================

GRANT SELECT ON ALL TABLES IN SCHEMA reference TO mpi_read_only, mpi_clinical_user, mpi_admin, mpi_integration;
GRANT INSERT, UPDATE ON ALL TABLES IN SCHEMA reference TO mpi_admin;

GRANT EXECUTE ON FUNCTION reference.get_translation TO mpi_read_only, mpi_clinical_user, mpi_admin, mpi_integration;

-- ============================================================================
-- Reference Data and Localization Complete
-- ============================================================================
