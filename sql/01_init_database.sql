-- ============================================================================
-- Master Patient Index (MPI) - Database Initialization
-- PostgreSQL 18
-- ============================================================================
-- Purpose: Initialize database, enable extensions, create schemas
-- HIPAA Compliant | UK DPA 2018 Compliant
-- ============================================================================

-- Database creation (run as superuser)
-- CREATE DATABASE mpi_database WITH ENCODING 'UTF8' LC_COLLATE = 'en_US.UTF-8' LC_CTYPE = 'en_US.UTF-8';

-- Connect to database
-- \c mpi_database

-- ============================================================================
-- Extensions
-- ============================================================================

-- UUID generation
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Cryptographic functions for encryption
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Fuzzy string matching for probabilistic matching
CREATE EXTENSION IF NOT EXISTS "fuzzystrmatch";

-- Trigram matching for text search
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- ============================================================================
-- Schemas
-- ============================================================================

-- Core patient data
CREATE SCHEMA IF NOT EXISTS core;
COMMENT ON SCHEMA core IS 'Core patient identity and demographic data';

-- Audit and compliance
CREATE SCHEMA IF NOT EXISTS audit;
COMMENT ON SCHEMA audit IS 'Audit trails and compliance logging';

-- Patient matching and linking
CREATE SCHEMA IF NOT EXISTS matching;
COMMENT ON SCHEMA matching IS 'Patient matching algorithms and duplicate management';

-- Security and encryption
CREATE SCHEMA IF NOT EXISTS security;
COMMENT ON SCHEMA security IS 'Security, encryption, and access control';

-- Reference data and lookups
CREATE SCHEMA IF NOT EXISTS reference;
COMMENT ON SCHEMA reference IS 'Reference data, code sets, and lookup tables';

-- Healthcare providers
CREATE SCHEMA IF NOT EXISTS provider;
COMMENT ON SCHEMA provider IS 'Healthcare providers, facilities, and organizations';

-- ============================================================================
-- Database Configuration
-- ============================================================================

-- Set timezone to UTC for consistency
ALTER DATABASE CURRENT_DATABASE() SET timezone TO 'UTC';

-- Enable row-level security
-- ALTER DATABASE CURRENT_DATABASE() SET row_security = on;

-- ============================================================================
-- Custom Types
-- ============================================================================

-- Gender identity (extensible for inclusivity)
CREATE TYPE core.gender_identity AS ENUM (
    'male',
    'female',
    'non_binary',
    'transgender_male',
    'transgender_female',
    'genderqueer',
    'agender',
    'other',
    'prefer_not_to_say',
    'unknown'
);
COMMENT ON TYPE core.gender_identity IS 'Gender identity types supporting diverse identification';

-- Biological sex (clinical use only)
CREATE TYPE core.biological_sex AS ENUM (
    'male',
    'female',
    'intersex',
    'unknown'
);
COMMENT ON TYPE core.biological_sex IS 'Biological sex for clinical purposes only';

-- Record status
CREATE TYPE core.record_status AS ENUM (
    'active',
    'inactive',
    'merged',
    'deleted',
    'error'
);
COMMENT ON TYPE core.record_status IS 'Patient record status';

-- Link type for patient relationships
CREATE TYPE matching.link_type AS ENUM (
    'duplicate',
    'possible_duplicate',
    'alias',
    'merged',
    'split',
    'family_member'
);
COMMENT ON TYPE matching.link_type IS 'Type of relationship between patient records';

-- Link status
CREATE TYPE matching.link_status AS ENUM (
    'proposed',
    'confirmed',
    'rejected',
    'auto_confirmed',
    'under_review'
);
COMMENT ON TYPE matching.link_status IS 'Status of patient record link';

-- Match confidence level
CREATE TYPE matching.confidence_level AS ENUM (
    'certain',
    'high',
    'medium',
    'low',
    'uncertain'
);
COMMENT ON TYPE matching.confidence_level IS 'Confidence level for patient matching';

-- Audit action types
CREATE TYPE audit.action_type AS ENUM (
    'insert',
    'update',
    'delete',
    'select',
    'merge',
    'unmerge',
    'link',
    'unlink',
    'access',
    'export',
    'emergency_access'
);
COMMENT ON TYPE audit.action_type IS 'Types of actions recorded in audit log';

-- Consent type
CREATE TYPE core.consent_type AS ENUM (
    'treatment',
    'research',
    'data_sharing',
    'marketing',
    'third_party_access'
);
COMMENT ON TYPE core.consent_type IS 'Types of patient consent';

-- Consent status
CREATE TYPE core.consent_status AS ENUM (
    'granted',
    'denied',
    'withdrawn',
    'expired',
    'pending'
);
COMMENT ON TYPE core.consent_status IS 'Status of patient consent';

-- ============================================================================
-- Utility Functions
-- ============================================================================

-- Function to generate current timestamp for audit trails
CREATE OR REPLACE FUNCTION core.current_timestamp_utc()
RETURNS TIMESTAMP WITH TIME ZONE AS $$
BEGIN
    RETURN CURRENT_TIMESTAMP AT TIME ZONE 'UTC';
END;
$$ LANGUAGE plpgsql IMMUTABLE;
COMMENT ON FUNCTION core.current_timestamp_utc() IS 'Returns current UTC timestamp';

-- Function to generate UUIDs (wrapper for uuid_generate_v4)
CREATE OR REPLACE FUNCTION core.generate_uuid()
RETURNS UUID AS $$
BEGIN
    RETURN uuid_generate_v4();
END;
$$ LANGUAGE plpgsql VOLATILE;
COMMENT ON FUNCTION core.generate_uuid() IS 'Generates UUID v4 for primary keys';

-- ============================================================================
-- Roles and Permissions (Basic Setup)
-- ============================================================================

-- Create basic roles (adjust based on organizational structure)
DO $$
BEGIN
    -- Clinical staff with read access
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'mpi_read_only') THEN
        CREATE ROLE mpi_read_only;
    END IF;

    -- Clinical staff with write access
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'mpi_clinical_user') THEN
        CREATE ROLE mpi_clinical_user;
    END IF;

    -- Administrators with full access
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'mpi_admin') THEN
        CREATE ROLE mpi_admin;
    END IF;

    -- Integration services (API access)
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'mpi_integration') THEN
        CREATE ROLE mpi_integration;
    END IF;

    -- Auditors (read-only audit access)
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'mpi_auditor') THEN
        CREATE ROLE mpi_auditor;
    END IF;
END
$$;

-- Grant schema usage
GRANT USAGE ON SCHEMA core TO mpi_read_only, mpi_clinical_user, mpi_admin, mpi_integration;
GRANT USAGE ON SCHEMA audit TO mpi_auditor, mpi_admin;
GRANT USAGE ON SCHEMA matching TO mpi_clinical_user, mpi_admin;
GRANT USAGE ON SCHEMA security TO mpi_admin;
GRANT USAGE ON SCHEMA reference TO mpi_read_only, mpi_clinical_user, mpi_admin, mpi_integration;
GRANT USAGE ON SCHEMA provider TO mpi_read_only, mpi_clinical_user, mpi_admin, mpi_integration;

-- ============================================================================
-- Initialization Complete
-- ============================================================================

-- Log initialization
DO $$
BEGIN
    RAISE NOTICE 'MPI Database Initialization Complete';
    RAISE NOTICE 'Extensions enabled: uuid-ossp, pgcrypto, fuzzystrmatch, pg_trgm';
    RAISE NOTICE 'Schemas created: core, audit, matching, security, reference, provider';
    RAISE NOTICE 'Custom types created';
    RAISE NOTICE 'Basic roles created';
END $$;
