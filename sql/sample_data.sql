-- Sample Data for Master Patient Index (MPI)
-- This file provides test data to demonstrate the MPI schema

SET search_path TO mpi, public;

-- ============================================================================
-- SAMPLE PATIENTS
-- ============================================================================

-- Patient 1: John Smith
INSERT INTO patients (mpi_number, status, created_by, updated_by)
VALUES ('MPI-1000001', 'active', 'system', 'system')
RETURNING patient_id;

-- Store patient_id for use in subsequent inserts
DO $$
DECLARE
    patient_1_id UUID;
    patient_2_id UUID;
    patient_3_id UUID;
BEGIN
    -- Patient 1: John Smith
    INSERT INTO patients (mpi_number, status, created_by, updated_by)
    VALUES ('MPI-1000001', 'active', 'system', 'system')
    RETURNING patient_id INTO patient_1_id;

    INSERT INTO patient_demographics (
        patient_id, first_name, middle_name, last_name,
        date_of_birth, gender, sex_assigned_at_birth,
        primary_language, marital_status,
        birth_city, birth_state, birth_country,
        created_by, updated_by
    ) VALUES (
        patient_1_id, 'John', 'Michael', 'Smith',
        '1985-06-15', 'male', 'male',
        'English', 'married',
        'Boston', 'MA', 'USA',
        'system', 'system'
    );

    INSERT INTO patient_identifiers (
        patient_id, identifier_type, identifier_value,
        issuing_authority, is_primary, created_by, updated_by
    ) VALUES
        (patient_1_id, 'SSN', '123-45-6789', 'SSA', true, 'system', 'system'),
        (patient_1_id, 'MRN', 'MRN-2024-001', 'General Hospital', true, 'system', 'system'),
        (patient_1_id, 'DRIVERS_LICENSE', 'D123456789', 'MA DMV', false, 'system', 'system');

    INSERT INTO patient_addresses (
        patient_id, address_type, address_line_1, city,
        state, postal_code, country, is_primary,
        created_by, updated_by
    ) VALUES (
        patient_1_id, 'home', '123 Main Street',
        'Boston', 'MA', '02101', 'USA', true,
        'system', 'system'
    );

    INSERT INTO patient_contacts (
        patient_id, contact_type, contact_value, is_primary,
        created_by, updated_by
    ) VALUES
        (patient_1_id, 'phone_mobile', '617-555-1234', true, 'system', 'system'),
        (patient_1_id, 'email_personal', 'john.smith@email.com', true, 'system', 'system');

    -- Patient 2: Maria Garcia
    INSERT INTO patients (mpi_number, status, created_by, updated_by)
    VALUES ('MPI-1000002', 'active', 'system', 'system')
    RETURNING patient_id INTO patient_2_id;

    INSERT INTO patient_demographics (
        patient_id, first_name, last_name,
        date_of_birth, gender, sex_assigned_at_birth,
        primary_language, secondary_languages, interpreter_required,
        marital_status, race, ethnicity,
        birth_city, birth_country,
        created_by, updated_by
    ) VALUES (
        patient_2_id, 'Maria', 'Garcia',
        '1990-03-22', 'female', 'female',
        'Spanish', ARRAY['English'], false,
        'single', 'Hispanic or Latino', 'Hispanic or Latino',
        'San Juan', 'PRI',
        'system', 'system'
    );

    INSERT INTO patient_identifiers (
        patient_id, identifier_type, identifier_value,
        issuing_authority, is_primary, created_by, updated_by
    ) VALUES
        (patient_2_id, 'SSN', '987-65-4321', 'SSA', true, 'system', 'system'),
        (patient_2_id, 'MRN', 'MRN-2024-002', 'City Medical Center', true, 'system', 'system');

    INSERT INTO patient_addresses (
        patient_id, address_type, address_line_1, address_line_2,
        city, state, postal_code, country, is_primary,
        created_by, updated_by
    ) VALUES (
        patient_2_id, 'home', '456 Oak Avenue', 'Apt 3B',
        'Miami', 'FL', '33101', 'USA', true,
        'system', 'system'
    );

    INSERT INTO patient_contacts (
        patient_id, contact_type, contact_value, is_primary,
        created_by, updated_by
    ) VALUES
        (patient_2_id, 'phone_mobile', '305-555-9876', true, 'system', 'system'),
        (patient_2_id, 'email_personal', 'maria.garcia@email.com', true, 'system', 'system');

    -- Patient 3: Robert Johnson (Deceased)
    INSERT INTO patients (mpi_number, status, created_by, updated_by)
    VALUES ('MPI-1000003', 'deceased', 'system', 'system')
    RETURNING patient_id INTO patient_3_id;

    INSERT INTO patient_demographics (
        patient_id, first_name, middle_name, last_name,
        date_of_birth, gender, sex_assigned_at_birth,
        primary_language, marital_status,
        is_deceased, death_date, death_city, death_state,
        birth_city, birth_state, birth_country,
        created_by, updated_by
    ) VALUES (
        patient_3_id, 'Robert', 'James', 'Johnson',
        '1945-12-10', 'male', 'male',
        'English', 'widowed',
        true, '2023-11-15', 'Chicago', 'IL',
        'Chicago', 'IL', 'USA',
        'system', 'system'
    );

    INSERT INTO patient_identifiers (
        patient_id, identifier_type, identifier_value,
        issuing_authority, is_primary, created_by, updated_by
    ) VALUES
        (patient_3_id, 'SSN', '555-12-3456', 'SSA', true, 'system', 'system'),
        (patient_3_id, 'MRN', 'MRN-2020-789', 'Northwestern Memorial', true, 'system', 'system');

    INSERT INTO patient_addresses (
        patient_id, address_type, address_line_1,
        city, state, postal_code, country, is_primary,
        valid_to, created_by, updated_by
    ) VALUES (
        patient_3_id, 'home', '789 Elm Street',
        'Chicago', 'IL', '60601', 'USA', true,
        '2023-11-15', 'system', 'system'
    );

    -- Sample potential duplicate match
    -- For demonstration, let's create a similar patient that might be flagged
    INSERT INTO patient_match_candidates (
        patient_id_1, patient_id_2,
        match_score, match_algorithm, matched_fields,
        review_status
    ) VALUES (
        patient_1_id, patient_2_id,
        0.65, 'Levenshtein', ARRAY['last_name', 'date_of_birth'],
        'confirmed_not_match'
    );

END $$;

-- ============================================================================
-- VERIFICATION QUERIES
-- ============================================================================

-- View all active patients
SELECT
    p.mpi_number,
    pd.first_name,
    pd.last_name,
    pd.date_of_birth,
    pd.gender,
    p.status
FROM patients p
JOIN patient_demographics pd ON p.patient_id = pd.patient_id
WHERE p.status = 'active'
ORDER BY p.created_at;

-- View patient identifiers
SELECT
    p.mpi_number,
    pd.first_name,
    pd.last_name,
    pi.identifier_type,
    pi.identifier_value,
    pi.is_primary
FROM patients p
JOIN patient_demographics pd ON p.patient_id = pd.patient_id
JOIN patient_identifiers pi ON p.patient_id = pi.patient_id
ORDER BY p.mpi_number, pi.identifier_type;

-- View patient contact information
SELECT
    p.mpi_number,
    pd.first_name,
    pd.last_name,
    pc.contact_type,
    pc.contact_value
FROM patients p
JOIN patient_demographics pd ON p.patient_id = pd.patient_id
JOIN patient_contacts pc ON p.patient_id = pc.patient_id
WHERE pc.is_primary = true
ORDER BY p.mpi_number;
