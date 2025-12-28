-- ============================================================================
-- Master Patient Index (MPI) - Security and Encryption Framework
-- PostgreSQL 18
-- ============================================================================
-- Purpose: Encryption key management, tokenization, audit functions
-- HIPAA Compliant | UK DPA 2018 Compliant
-- ============================================================================

-- ============================================================================
-- Encryption Key Management
-- ============================================================================

-- Table to store encryption key metadata (not the keys themselves)
-- Actual keys should be managed by external key management system (KMS)
CREATE TABLE security.encryption_key (
    key_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    key_name VARCHAR(255) NOT NULL UNIQUE,
    key_purpose VARCHAR(100) NOT NULL, -- 'pii', 'identifier', 'token'
    algorithm VARCHAR(50) NOT NULL DEFAULT 'AES-256',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_by VARCHAR(255) NOT NULL,
    rotated_at TIMESTAMP WITH TIME ZONE,
    is_active BOOLEAN DEFAULT TRUE,
    metadata JSONB
);
COMMENT ON TABLE security.encryption_key IS 'Encryption key metadata for key rotation and management';
COMMENT ON COLUMN security.encryption_key.key_purpose IS 'Purpose of encryption key (pii, identifier, token)';

CREATE INDEX idx_encryption_key_active ON security.encryption_key(is_active) WHERE is_active = TRUE;

-- ============================================================================
-- Tokenization Tables
-- ============================================================================

-- Token mapping for external identifiers (one-way mapping)
CREATE TABLE security.token_mapping (
    token_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    token_value VARCHAR(255) NOT NULL UNIQUE,
    original_value_hash BYTEA NOT NULL, -- SHA-256 hash of original value
    entity_type VARCHAR(50) NOT NULL, -- 'government_id', 'insurance_id', 'mrn'
    entity_id UUID NOT NULL, -- Reference to actual record
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_by VARCHAR(255) NOT NULL,
    accessed_count INTEGER DEFAULT 0,
    last_accessed_at TIMESTAMP WITH TIME ZONE,
    expires_at TIMESTAMP WITH TIME ZONE,
    is_active BOOLEAN DEFAULT TRUE
);
COMMENT ON TABLE security.token_mapping IS 'Tokenization mapping for safe use of identifiers in analytics';
COMMENT ON COLUMN security.token_mapping.token_value IS 'Generated token value (safe for analytics)';
COMMENT ON COLUMN security.token_mapping.original_value_hash IS 'Hash of original value for verification';

CREATE INDEX idx_token_mapping_entity ON security.token_mapping(entity_type, entity_id);
CREATE INDEX idx_token_mapping_active ON security.token_mapping(is_active) WHERE is_active = TRUE;
CREATE INDEX idx_token_mapping_hash ON security.token_mapping USING hash(original_value_hash);

-- ============================================================================
-- Encryption Functions
-- ============================================================================

-- Encrypt sensitive data (uses pgcrypto)
-- In production, integrate with external KMS for key management
CREATE OR REPLACE FUNCTION security.encrypt_data(
    p_plaintext TEXT,
    p_key_name VARCHAR DEFAULT 'default_pii_key'
)
RETURNS BYTEA AS $$
DECLARE
    v_key TEXT;
BEGIN
    -- In production, retrieve key from secure key store
    -- This is a placeholder - DO NOT use hardcoded keys in production
    v_key := current_setting('mpi.encryption_key', TRUE);

    IF v_key IS NULL THEN
        RAISE EXCEPTION 'Encryption key not configured. Set mpi.encryption_key parameter.';
    END IF;

    -- Encrypt using AES-256
    RETURN pgp_sym_encrypt(p_plaintext, v_key, 'cipher-algo=aes256');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
COMMENT ON FUNCTION security.encrypt_data IS 'Encrypts sensitive data using AES-256';

-- Decrypt sensitive data
CREATE OR REPLACE FUNCTION security.decrypt_data(
    p_ciphertext BYTEA,
    p_key_name VARCHAR DEFAULT 'default_pii_key'
)
RETURNS TEXT AS $$
DECLARE
    v_key TEXT;
BEGIN
    -- In production, retrieve key from secure key store
    v_key := current_setting('mpi.encryption_key', TRUE);

    IF v_key IS NULL THEN
        RAISE EXCEPTION 'Encryption key not configured. Set mpi.encryption_key parameter.';
    END IF;

    -- Decrypt
    RETURN pgp_sym_decrypt(p_ciphertext, v_key);
EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Decryption failed: %', SQLERRM;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
COMMENT ON FUNCTION security.decrypt_data IS 'Decrypts sensitive data';

-- Hash function for one-way hashing (for password-like data)
CREATE OR REPLACE FUNCTION security.hash_value(
    p_value TEXT,
    p_algorithm VARCHAR DEFAULT 'sha256'
)
RETURNS BYTEA AS $$
BEGIN
    RETURN CASE p_algorithm
        WHEN 'sha256' THEN digest(p_value, 'sha256')
        WHEN 'sha512' THEN digest(p_value, 'sha512')
        ELSE digest(p_value, 'sha256')
    END;
END;
$$ LANGUAGE plpgsql IMMUTABLE;
COMMENT ON FUNCTION security.hash_value IS 'One-way hash function for values';

-- ============================================================================
-- Tokenization Functions
-- ============================================================================

-- Generate token for external identifier
CREATE OR REPLACE FUNCTION security.generate_token(
    p_original_value TEXT,
    p_entity_type VARCHAR,
    p_entity_id UUID,
    p_user VARCHAR DEFAULT CURRENT_USER
)
RETURNS VARCHAR AS $$
DECLARE
    v_token VARCHAR;
    v_hash BYTEA;
    v_exists BOOLEAN;
BEGIN
    -- Hash the original value
    v_hash := security.hash_value(p_original_value);

    -- Check if token already exists for this value
    SELECT token_value INTO v_token
    FROM security.token_mapping
    WHERE original_value_hash = v_hash
        AND entity_type = p_entity_type
        AND entity_id = p_entity_id
        AND is_active = TRUE;

    IF FOUND THEN
        -- Update access tracking
        UPDATE security.token_mapping
        SET accessed_count = accessed_count + 1,
            last_accessed_at = CURRENT_TIMESTAMP
        WHERE token_value = v_token;

        RETURN v_token;
    END IF;

    -- Generate new token (prefix with entity type for readability)
    v_token := p_entity_type || '_' || encode(gen_random_bytes(16), 'hex');

    -- Store mapping
    INSERT INTO security.token_mapping (
        token_value,
        original_value_hash,
        entity_type,
        entity_id,
        created_by
    ) VALUES (
        v_token,
        v_hash,
        p_entity_type,
        p_entity_id,
        p_user
    );

    RETURN v_token;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
COMMENT ON FUNCTION security.generate_token IS 'Generates or retrieves token for identifier';

-- Verify token matches original value
CREATE OR REPLACE FUNCTION security.verify_token(
    p_token VARCHAR,
    p_original_value TEXT
)
RETURNS BOOLEAN AS $$
DECLARE
    v_stored_hash BYTEA;
    v_input_hash BYTEA;
BEGIN
    -- Get stored hash
    SELECT original_value_hash INTO v_stored_hash
    FROM security.token_mapping
    WHERE token_value = p_token
        AND is_active = TRUE;

    IF NOT FOUND THEN
        RETURN FALSE;
    END IF;

    -- Hash input value
    v_input_hash := security.hash_value(p_original_value);

    -- Compare hashes
    RETURN v_stored_hash = v_input_hash;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
COMMENT ON FUNCTION security.verify_token IS 'Verifies token matches original value';

-- ============================================================================
-- Access Control and Audit Functions
-- ============================================================================

-- Get current user context (for audit trails)
CREATE OR REPLACE FUNCTION security.get_user_context()
RETURNS JSONB AS $$
BEGIN
    RETURN jsonb_build_object(
        'user', CURRENT_USER,
        'session_user', SESSION_USER,
        'client_addr', inet_client_addr(),
        'client_port', inet_client_port(),
        'application_name', current_setting('application_name', TRUE),
        'timestamp', CURRENT_TIMESTAMP
    );
END;
$$ LANGUAGE plpgsql STABLE;
COMMENT ON FUNCTION security.get_user_context IS 'Returns current user context for audit trails';

-- Check if user has permission for action
CREATE OR REPLACE FUNCTION security.check_permission(
    p_user VARCHAR,
    p_action VARCHAR,
    p_resource VARCHAR
)
RETURNS BOOLEAN AS $$
DECLARE
    v_has_permission BOOLEAN;
BEGIN
    -- Placeholder for permission checking logic
    -- In production, integrate with your authorization system

    -- Check if user is admin (admins have all permissions)
    IF pg_has_role(p_user, 'mpi_admin', 'MEMBER') THEN
        RETURN TRUE;
    END IF;

    -- Check specific permissions based on action and resource
    -- This is simplified - implement full RBAC as needed
    v_has_permission := CASE
        WHEN p_action = 'SELECT' AND pg_has_role(p_user, 'mpi_read_only', 'MEMBER') THEN TRUE
        WHEN p_action IN ('INSERT', 'UPDATE', 'DELETE') AND pg_has_role(p_user, 'mpi_clinical_user', 'MEMBER') THEN TRUE
        ELSE FALSE
    END;

    RETURN v_has_permission;
END;
$$ LANGUAGE plpgsql STABLE;
COMMENT ON FUNCTION security.check_permission IS 'Checks if user has permission for action';

-- ============================================================================
-- Data Masking Functions
-- ============================================================================

-- Mask sensitive data for non-privileged users
CREATE OR REPLACE FUNCTION security.mask_identifier(
    p_value TEXT,
    p_visible_chars INTEGER DEFAULT 4
)
RETURNS TEXT AS $$
BEGIN
    IF p_value IS NULL THEN
        RETURN NULL;
    END IF;

    -- Show only last N characters
    IF length(p_value) <= p_visible_chars THEN
        RETURN repeat('*', length(p_value));
    ELSE
        RETURN repeat('*', length(p_value) - p_visible_chars) ||
               right(p_value, p_visible_chars);
    END IF;
END;
$$ LANGUAGE plpgsql IMMUTABLE;
COMMENT ON FUNCTION security.mask_identifier IS 'Masks identifier showing only last N characters';

-- Mask name (show only first initial and last name)
CREATE OR REPLACE FUNCTION security.mask_name(
    p_full_name TEXT
)
RETURNS TEXT AS $$
DECLARE
    v_parts TEXT[];
BEGIN
    IF p_full_name IS NULL THEN
        RETURN NULL;
    END IF;

    v_parts := string_to_array(trim(p_full_name), ' ');

    IF array_length(v_parts, 1) = 0 THEN
        RETURN NULL;
    ELSIF array_length(v_parts, 1) = 1 THEN
        RETURN left(v_parts[1], 1) || repeat('*', length(v_parts[1]) - 1);
    ELSE
        -- First initial + last name
        RETURN left(v_parts[1], 1) || '. ' || v_parts[array_length(v_parts, 1)];
    END IF;
END;
$$ LANGUAGE plpgsql IMMUTABLE;
COMMENT ON FUNCTION security.mask_name IS 'Masks name showing only first initial and last name';

-- Mask email (show only domain)
CREATE OR REPLACE FUNCTION security.mask_email(
    p_email TEXT
)
RETURNS TEXT AS $$
DECLARE
    v_at_pos INTEGER;
BEGIN
    IF p_email IS NULL THEN
        RETURN NULL;
    END IF;

    v_at_pos := position('@' in p_email);

    IF v_at_pos = 0 THEN
        RETURN '***';
    END IF;

    RETURN '***@' || substring(p_email from v_at_pos + 1);
END;
$$ LANGUAGE plpgsql IMMUTABLE;
COMMENT ON FUNCTION security.mask_email IS 'Masks email showing only domain';

-- ============================================================================
-- Break-Glass Emergency Access
-- ============================================================================

-- Table to track emergency access events
CREATE TABLE security.emergency_access_log (
    access_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_name VARCHAR(255) NOT NULL,
    patient_id UUID NOT NULL,
    reason TEXT NOT NULL,
    justification TEXT,
    accessed_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    approved_by VARCHAR(255),
    approved_at TIMESTAMP WITH TIME ZONE,
    reviewed BOOLEAN DEFAULT FALSE,
    reviewed_by VARCHAR(255),
    reviewed_at TIMESTAMP WITH TIME ZONE,
    review_outcome VARCHAR(50), -- 'justified', 'unjustified', 'pending'
    user_context JSONB,
    CONSTRAINT valid_review_outcome CHECK (review_outcome IN ('justified', 'unjustified', 'pending', NULL))
);
COMMENT ON TABLE security.emergency_access_log IS 'Audit log for break-glass emergency access to patient data';

CREATE INDEX idx_emergency_access_patient ON security.emergency_access_log(patient_id);
CREATE INDEX idx_emergency_access_user ON security.emergency_access_log(user_name);
CREATE INDEX idx_emergency_access_unreviewed ON security.emergency_access_log(reviewed) WHERE reviewed = FALSE;

-- Request emergency access
CREATE OR REPLACE FUNCTION security.request_emergency_access(
    p_patient_id UUID,
    p_reason TEXT,
    p_justification TEXT DEFAULT NULL
)
RETURNS UUID AS $$
DECLARE
    v_access_id UUID;
    v_user_context JSONB;
BEGIN
    -- Get user context
    v_user_context := security.get_user_context();

    -- Log emergency access request
    INSERT INTO security.emergency_access_log (
        user_name,
        patient_id,
        reason,
        justification,
        user_context,
        review_outcome
    ) VALUES (
        CURRENT_USER,
        p_patient_id,
        p_reason,
        p_justification,
        v_user_context,
        'pending'
    ) RETURNING access_id INTO v_access_id;

    -- Send alert (integrate with your alerting system)
    RAISE NOTICE 'EMERGENCY ACCESS REQUESTED: User % accessed patient % - Reason: %',
        CURRENT_USER, p_patient_id, p_reason;

    RETURN v_access_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
COMMENT ON FUNCTION security.request_emergency_access IS 'Requests emergency break-glass access to patient data';

-- ============================================================================
-- Grant Permissions
-- ============================================================================

-- Security functions accessible to authorized users
GRANT EXECUTE ON FUNCTION security.encrypt_data TO mpi_admin;
GRANT EXECUTE ON FUNCTION security.decrypt_data TO mpi_admin, mpi_clinical_user;
GRANT EXECUTE ON FUNCTION security.generate_token TO mpi_admin, mpi_integration;
GRANT EXECUTE ON FUNCTION security.verify_token TO mpi_admin, mpi_clinical_user, mpi_integration;
GRANT EXECUTE ON FUNCTION security.get_user_context TO mpi_clinical_user, mpi_admin, mpi_integration;
GRANT EXECUTE ON FUNCTION security.mask_identifier TO mpi_read_only, mpi_clinical_user, mpi_admin;
GRANT EXECUTE ON FUNCTION security.mask_name TO mpi_read_only, mpi_clinical_user, mpi_admin;
GRANT EXECUTE ON FUNCTION security.mask_email TO mpi_read_only, mpi_clinical_user, mpi_admin;
GRANT EXECUTE ON FUNCTION security.request_emergency_access TO mpi_clinical_user, mpi_admin;

-- Table permissions
GRANT SELECT ON security.emergency_access_log TO mpi_auditor, mpi_admin;
GRANT SELECT, INSERT ON security.emergency_access_log TO mpi_clinical_user;
GRANT UPDATE (reviewed, reviewed_by, reviewed_at, review_outcome) ON security.emergency_access_log TO mpi_admin;

-- ============================================================================
-- Security Framework Complete
-- ============================================================================
