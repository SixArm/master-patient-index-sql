# Master Patient Index (MPI) Implementation Plan

## Phase 1: Foundation & Core Infrastructure

### 1.1 Database Setup
- [ ] Create database initialization script with PostgreSQL 18 settings
- [ ] Enable required extensions (uuid-ossp, pgcrypto)
- [ ] Configure database parameters for performance and security
- [ ] Set up schema namespaces (core, audit, matching, security)

### 1.2 Security & Encryption Framework
- [ ] Create encryption key management tables
- [ ] Implement tokenization tables and functions for external IDs
- [ ] Create column-level encryption functions using pgcrypto
- [ ] Design role-based access control (RBAC) structure
- [ ] Create audit logging infrastructure

### 1.3 Temporal Framework
- [ ] Design temporal table pattern (effective_from, effective_to, is_current)
- [ ] Create temporal management functions (insert, update, invalidate)
- [ ] Build temporal query helper views
- [ ] Implement temporal consistency triggers

## Phase 2: Core Patient Identity Tables

### 2.1 Patient Master Record
- [ ] Create `patient` table (master record with UUID primary key)
- [ ] Add core immutable fields (date_of_birth, biological_sex, etc.)
- [ ] Implement temporal tracking for mutable attributes
- [ ] Create indexes for performance (UUID, active records)
- [ ] Add row-level security policies

### 2.2 Patient Names (Temporal)
- [ ] Create `patient_name` table with full temporal support
- [ ] Support multiple name types (legal, preferred, alias, maiden)
- [ ] Handle multiple given names, middle names, family names
- [ ] Add phonetic encoding fields for fuzzy matching (Soundex, Metaphone)
- [ ] Create locale-specific collation indexes

### 2.3 Patient Demographics (Temporal)
- [ ] Create `patient_demographic` table
- [ ] Track gender identity, ethnicity, preferred language
- [ ] Support multiple languages and locales
- [ ] Implement temporal versioning

## Phase 3: Identification & Contact Information

### 3.1 Government Identifiers (Temporal, Encrypted)
- [ ] Create `patient_government_id` table
- [ ] Support multiple countries and ID types (SSN, NHS number, passport, etc.)
- [ ] Implement column-level encryption for ID values
- [ ] Add tokenization for reporting/analytics
- [ ] Create unique constraints preventing duplicate active IDs
- [ ] Build country-specific validation functions

### 3.2 Insurance Identifiers (Temporal, Encrypted)
- [ ] Create `patient_insurance_id` table
- [ ] Support multiple vendors and policy types
- [ ] Encrypt member IDs and policy numbers
- [ ] Track policy effective dates and coverage periods
- [ ] Link to insurance provider reference table

### 3.3 Medical Record Numbers (MRN) (Temporal)
- [ ] Create `patient_mrn` table for facility-specific identifiers
- [ ] Link to healthcare facility/system reference table
- [ ] Support multiple MRNs per patient across different facilities
- [ ] Ensure uniqueness within facility scope
- [ ] Track MRN assignment and retirement dates

### 3.4 Contact Information (Temporal)
- [ ] Create `patient_phone` table with temporal tracking
- [ ] Create `patient_email` table with temporal tracking
- [ ] Create `patient_address` table with temporal tracking
- [ ] Support international address formats
- [ ] Add geocoding fields for address verification
- [ ] Implement contact preference and consent tracking

### 3.5 Federated Identities
- [ ] Create `patient_federated_identity` table
- [ ] Support multiple identity providers (OAuth, SAML, OpenID)
- [ ] Store provider-specific subject identifiers
- [ ] Track authentication method and assurance level
- [ ] Implement temporal tracking for identity lifecycle

## Phase 4: Healthcare Provider Relationships

### 4.1 Provider Reference Tables
- [ ] Create `healthcare_provider` table
- [ ] Create `provider_type` lookup table (GP, hospital, dentist, etc.)
- [ ] Create `healthcare_facility` table
- [ ] Create `healthcare_organization` table
- [ ] Add NPI (National Provider Identifier) and other professional IDs

### 4.2 Patient-Provider Relationships (Temporal)
- [ ] Create `patient_provider_relationship` table
- [ ] Support multiple concurrent providers of different types
- [ ] Track relationship type (primary, secondary, specialist)
- [ ] Implement care team hierarchies
- [ ] Add relationship status (active, inactive, transferred)
- [ ] Track assignment and discharge dates

## Phase 5: Patient Matching & Linking

### 5.1 Deterministic Matching
- [ ] Create unique indexes on government IDs for exact matching
- [ ] Build deterministic matching rules table
- [ ] Implement matching functions for exact ID lookups
- [ ] Create matching confidence scoring system

### 5.2 Probabilistic Matching
- [ ] Create `matching_algorithm_config` table
- [ ] Implement Jaro-Winkler distance functions for names
- [ ] Implement Levenshtein distance for fuzzy matching
- [ ] Create phonetic matching functions (Soundex, Metaphone, Double Metaphone)
- [ ] Build composite matching score calculator
- [ ] Create `potential_duplicate` table for match candidates
- [ ] Implement threshold-based auto-linking rules

### 5.3 Patient Linking (Soft Merge)
- [ ] Create `patient_link` table for master-child relationships
- [ ] Support link types (duplicate, alias, merged, split)
- [ ] Implement link confidence scores
- [ ] Create link hierarchy management (prevent circular links)
- [ ] Build link/unlink audit trail
- [ ] Create views that traverse link relationships
- [ ] Implement link status workflow (proposed, confirmed, rejected)

### 5.4 Golden Record Management
- [ ] Create `golden_record` table for consolidated patient view
- [ ] Implement golden record generation rules
- [ ] Build survivorship rules (which source wins for each attribute)
- [ ] Create materialized views for performance
- [ ] Implement golden record refresh triggers

## Phase 6: Audit & Compliance

### 6.1 HIPAA Audit Trail
- [ ] Create `audit_log` table with comprehensive change tracking
- [ ] Track who, what, when, where, why for all changes
- [ ] Capture before/after values for all modifications
- [ ] Log access attempts (successful and failed)
- [ ] Implement tamper-proof audit mechanisms (append-only, signed)
- [ ] Create audit retention policies

### 6.2 Consent & Privacy Management
- [ ] Create `patient_consent` table
- [ ] Support consent types (treatment, research, data sharing)
- [ ] Track consent granularity (opt-in, opt-out, specific purposes)
- [ ] Implement consent effective dates
- [ ] Create consent audit trail
- [ ] Build consent enforcement functions

### 6.3 Data Access Controls
- [ ] Create `data_access_policy` table
- [ ] Implement row-level security policies by user role
- [ ] Create break-glass emergency access mechanism
- [ ] Log all emergency access events
- [ ] Implement data masking for non-privileged users

### 6.4 Data Retention & Deletion
- [ ] Create retention policy tables
- [ ] Implement anonymization functions for aged data
- [ ] Create right-to-be-forgotten workflows
- [ ] Build data deletion audit trail
- [ ] Ensure deletion cascades properly across linked records

## Phase 7: Reference Data & Localization

### 7.1 Locale & Language Support
- [ ] Create `locale` reference table (en, cy, es, fr, zh, ar, ru)
- [ ] Create `language` reference table
- [ ] Create `translation` table for multi-language field values
- [ ] Implement locale-aware sorting and searching
- [ ] Create locale-specific validation rules

### 7.2 Reference Data Tables
- [ ] Create `country` reference table
- [ ] Create `id_type` lookup table (passport, driver's license, etc.)
- [ ] Create `phone_type` lookup table (mobile, home, work)
- [ ] Create `email_type` lookup table
- [ ] Create `address_type` lookup table
- [ ] Create `name_type` lookup table
- [ ] Create `relationship_type` lookup table
- [ ] Populate reference tables with standard values

### 7.3 Code Sets & Standards
- [ ] Create tables for HL7 FHIR patient resource mappings
- [ ] Create tables for ICD coding systems
- [ ] Create tables for SNOMED CT concepts (as needed)
- [ ] Implement ISO 3166 country codes
- [ ] Implement ISO 639 language codes

## Phase 8: Performance Optimization

### 8.1 Indexing Strategy
- [ ] Create B-tree indexes on frequently queried columns
- [ ] Create GiST indexes for fuzzy matching operations
- [ ] Create partial indexes for active records only
- [ ] Implement covering indexes for common queries
- [ ] Add indexes on foreign keys
- [ ] Create trigram indexes for text search

### 8.2 Partitioning Strategy
- [ ] Evaluate partitioning needs for audit tables (by date)
- [ ] Consider partitioning large tables by date ranges
- [ ] Implement partition maintenance procedures

### 8.3 Views & Materialized Views
- [ ] Create `current_patient_view` (active temporal records only)
- [ ] Create `patient_master_view` (golden record with all current attributes)
- [ ] Create `patient_search_view` optimized for matching
- [ ] Create materialized views for reporting
- [ ] Implement refresh strategies for materialized views

## Phase 9: Data Integrity & Validation

### 9.1 Constraints & Triggers
- [ ] Implement check constraints for data validation
- [ ] Create triggers for temporal consistency
- [ ] Create triggers for audit logging
- [ ] Implement cascade behaviors for deletes
- [ ] Add triggers for golden record updates

### 9.2 Validation Functions
- [ ] Create email validation function
- [ ] Create phone number validation functions (international formats)
- [ ] Create government ID validation (country-specific)
- [ ] Create address validation functions
- [ ] Implement checksum validators (Luhn algorithm for IDs)

### 9.3 Data Quality Functions
- [ ] Create duplicate detection functions
- [ ] Implement data completeness scoring
- [ ] Create data quality metrics tables
- [ ] Build data quality reporting views

## Phase 10: API & Integration Layer

### 10.1 Stored Procedures
- [ ] Create patient registration procedure
- [ ] Create patient update procedure (temporal-aware)
- [ ] Create patient search procedures (deterministic and probabilistic)
- [ ] Create patient merge/link procedures
- [ ] Create patient unlink procedure
- [ ] Create consent management procedures

### 10.2 API Functions
- [ ] Create RESTful API-style functions returning JSON
- [ ] Implement FHIR Patient resource serialization
- [ ] Create bulk export functions
- [ ] Implement paginated search results

### 10.3 Integration Tables
- [ ] Create `integration_source` table for external systems
- [ ] Create `integration_log` for tracking data feeds
- [ ] Create staging tables for ETL processes
- [ ] Implement idempotent upsert procedures

## Phase 11: Monitoring & Maintenance

### 11.1 Database Monitoring
- [ ] Create monitoring tables for performance metrics
- [ ] Implement query performance logging
- [ ] Create slow query alerting
- [ ] Monitor index usage and health

### 11.2 Maintenance Procedures
- [ ] Create vacuum and analyze schedules
- [ ] Implement index rebuild procedures
- [ ] Create backup and restore procedures
- [ ] Implement point-in-time recovery testing

## Phase 12: Documentation & Testing

### 12.1 Schema Documentation
- [ ] Document all tables with COMMENT statements
- [ ] Document all columns with descriptions
- [ ] Create entity-relationship diagrams (ERD)
- [ ] Create data dictionary document

### 12.2 Testing
- [ ] Create test data generation scripts
- [ ] Write unit tests for validation functions
- [ ] Write integration tests for matching algorithms
- [ ] Test temporal query accuracy
- [ ] Test encryption/decryption functions
- [ ] Perform security penetration testing
- [ ] Load testing for scalability validation

### 12.3 Migration & Deployment
- [ ] Create versioned migration scripts
- [ ] Implement rollback procedures
- [ ] Create deployment checklist
- [ ] Document deployment procedures

---

## Implementation Notes

### Architecture Decisions

**Hybrid Matching**: Deterministic matching on exact IDs first, fallback to probabilistic for cases without reliable identifiers.

**Full Temporal Tracking**: All patient attributes maintain complete history with effective dates, supporting compliance and data lineage requirements.

**Soft Merge**: Patient records are linked but retained separately, allowing for unmerging if duplicates were incorrectly identified.

**Encryption**: PII fields use pgcrypto column-level encryption. External IDs are tokenized for safe use in analytics.

### Key Design Patterns

1. **Temporal Pattern**: Every versioned table has `effective_from`, `effective_to`, `is_current` columns
2. **Soft Delete**: Use `deleted_at` instead of hard deletes for recoverability
3. **Audit Pattern**: All changes logged to audit table with user, timestamp, old/new values
4. **UUID Primary Keys**: Using UUIDs for distributed system compatibility
5. **Surrogate Keys**: Internal IDs separate from business identifiers

### Compliance Considerations

- HIPAA: Comprehensive audit trail, access controls, encryption at rest and in transit
- UK DPA 2018: Right to access, right to rectification, right to erasure, data minimization
- Common Law Duty of Confidentiality: Role-based access, need-to-know principle, break-glass auditing

### Localization Strategy

- All user-facing text stored in translation tables
- Locale-specific formatting for names, addresses, dates
- Collation-aware sorting and searching
- Support for RTL languages (Arabic)
- Character set considerations (UTF-8 throughout)

### Scalability Considerations

- Horizontal scaling via read replicas
- Partitioning for time-series data (audit logs)
- Materialized views for complex queries
- Connection pooling recommendations
- Query optimization via appropriate indexing

### Security Layers

1. Network: SSL/TLS for connections
2. Authentication: Strong password policies, MFA support
3. Authorization: Role-based access control (RBAC)
4. Data: Column-level encryption for PII
5. Audit: Comprehensive logging of all access
6. Monitoring: Anomaly detection for suspicious access patterns
