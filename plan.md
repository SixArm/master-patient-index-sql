You are an expert database developer. Use plan mode. Use deep thinking.

Create a master-patient-index (MPI) for medical software.

A patient can have:
- multiple national government identification numbers from multiple countries
- multiple health insurance identification numbers from multiple vendors
- multiple medical providers from multiple systems such as public and private
- multiple contact information from phone numbers, emails, postal addresses
- multiple given names, multiple middle names, multiple family names
- multiple federated identities from many providers

Example medical providers
- general practitioner for primary care
- hospital team for secondary care
- dentist
- optomotrist
- nutritionist
- psychologist
- psychiatrist
- acupunturist

Enterprise system quality attibutes:
- Scalability: indexes, partitioning-ready, materialized view support
- Security: RBAC, encryption, tokenization, row-level security foundations
- Reliability: Temporal consistency validation, soft deletes, no data loss
- Auditability Comprehensive audit trails (who/what/when/where/why)
- Maintainability: Well-documented, modular schemas, temporal patterns

Compliance:
- United States (US) Health Insurance Portability and Accountability Act (HIPAA)
- United Kingdom (UK) Data Protection Act (DPA) 2018 
- United Kingdom (UK) Common Law Duty of Confidentiality
- United Kingdom (UK) National Health Service (NHS) Act 2006, Section 251 
- European Union (EU) General Data Protection Regulation (GDPR)
- HL7 Fast Healthcare Interoperability Resources (FHIR) Patient Resource

Auditing:
- audit trails
- access controls
- encryption
- break-glass
- consent

Data protection:
- right to access
- rectification
- erasure
- portability

Ensure patient health data (a "special category") is handled lawfully, fairly, and transparently, requiring strict rules for processing, access, and sharing, with rights for patients to access their records but allowing for necessary confidentiality breaks under specific legal frameworks like Section 251 of the NHS Act for public health purposes.

Create locales for multiple languages:
- English
- Welsh
- Spanish
- French
- Manadarin
- Arabic
- Russian

Create PostgresSQL version 18 SQL schema with tables, indexes, audits, soft deletes.

PostgreSQL extensions:
- pg_stat_statements: record execution statistics
- uuid-ossp: generate random UUID v4 identifiers
- pg_vector: for similarity search and RAG use case
- pgcrypto: cryptography securty, encryption, hashing
- pg_trgm: trigram search for autocomplete fuzzy matching
- postgis: geographic information system for map locations
- citext: case-insenstive text field for matching
- unaccent: helps text search by removing diacritics

Ask questions to make this better.

Create a file "todo.md" with steps.
