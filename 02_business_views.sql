-- =====================================================================
-- 02 BUSINESS VIEWS: raw source columns -> business names
-- This is the ONLY file where raw column names appear.
-- Everything after this (semantic model, agent, app) sees business names only.
-- =====================================================================
USE SCHEMA {{DATABASE}}.{{ANALYTICS}};
-- PATIENTS: business names only. The masking is done by ROLE-BASED MASKING POLICIES (Enterprise), below.
CREATE OR REPLACE SECURE VIEW PATIENTS COPY GRANTS
COMMENT = 'One row per patient. PII protected by role-based masking policies.' AS
SELECT
  PATIENT_ID                                                       AS PATIENT_NUMBER,
  FIRST                                                            AS FIRST_NAME,
  LAST                                                             AS LAST_NAME,
  SSN                                                              AS SOCIAL_SECURITY_NUMBER,
  ADDRESS                                                          AS STREET_ADDRESS,
  BIRTHDATE::DATE                                                  AS DATE_OF_BIRTH,
  DEATHDATE::DATE                                                  AS DATE_OF_DEATH,
  DEATHDATE IS NOT NULL                                            AS IS_DECEASED,
  DATEDIFF('year', BIRTHDATE, COALESCE(DEATHDATE, CURRENT_DATE())) AS AGE_IN_YEARS,
  GENDER                                                           AS PATIENT_GENDER,
  RACE                                                             AS PATIENT_RACE,
  ETHNICITY                                                        AS PATIENT_ETHNICITY,
  MARITAL                                                          AS MARITAL_STATUS,
  CITY                                                             AS HOME_CITY,
  COUNTY                                                           AS HOME_COUNTY,
  STATE                                                            AS HOME_STATE,
  INCOME                                                           AS HOUSEHOLD_INCOME_USD,
  SYNTHEA_CITY                                                     AS DATA_REGION
FROM {{SOURCE}}.PATIENTS;

-- ---------------------------------------------------------------------
-- ROLE-BASED MASKING POLICIES (Enterprise feature)
--   Column            DATA_ENGINEER   HC_CLINICAL_ANALYST   every other role
--   First/last name   real            real                  ***MASKED***
--   SSN               real            XXX-XX-1234           XXX-XX-XXXX
--   Street address    real            ***MASKED***          ***MASKED***
--   Birth/death date  real            real                  year only (1 Jan)
-- ---------------------------------------------------------------------
CREATE OR REPLACE MASKING POLICY {{DATABASE}}.{{GOVERNANCE}}.MASK_NAME AS (val STRING) RETURNS STRING ->
  CASE WHEN CURRENT_ROLE() IN ('{{ENGINEER_ROLE}}', '{{CLINICAL_ROLE}}') THEN val ELSE '***MASKED***' END
  COMMENT = 'Names: engineer and clinical analyst see them';

CREATE OR REPLACE MASKING POLICY {{DATABASE}}.{{GOVERNANCE}}.MASK_SSN AS (val STRING) RETURNS STRING ->
  CASE WHEN CURRENT_ROLE() = '{{ENGINEER_ROLE}}' THEN val
       WHEN CURRENT_ROLE() = '{{CLINICAL_ROLE}}' THEN 'XXX-XX-' || RIGHT(val, 4)
       ELSE 'XXX-XX-XXXX' END
  COMMENT = 'SSN: engineer full, clinical analyst last 4 digits, others nothing';

CREATE OR REPLACE MASKING POLICY {{DATABASE}}.{{GOVERNANCE}}.MASK_ADDRESS AS (val STRING) RETURNS STRING ->
  CASE WHEN CURRENT_ROLE() = '{{ENGINEER_ROLE}}' THEN val ELSE '***MASKED***' END
  COMMENT = 'Street address: engineer only';

CREATE OR REPLACE MASKING POLICY {{DATABASE}}.{{GOVERNANCE}}.MASK_DATE AS (val DATE) RETURNS DATE ->
  CASE WHEN CURRENT_ROLE() IN ('{{ENGINEER_ROLE}}', '{{CLINICAL_ROLE}}') THEN val
       ELSE DATE_FROM_PARTS(YEAR(val), 1, 1) END
  COMMENT = 'Birth and death dates: engineer and clinical analyst see the full date, others the year';

ALTER VIEW PATIENTS MODIFY COLUMN FIRST_NAME             SET MASKING POLICY {{DATABASE}}.{{GOVERNANCE}}.MASK_NAME;
ALTER VIEW PATIENTS MODIFY COLUMN LAST_NAME              SET MASKING POLICY {{DATABASE}}.{{GOVERNANCE}}.MASK_NAME;
ALTER VIEW PATIENTS MODIFY COLUMN SOCIAL_SECURITY_NUMBER SET MASKING POLICY {{DATABASE}}.{{GOVERNANCE}}.MASK_SSN;
ALTER VIEW PATIENTS MODIFY COLUMN STREET_ADDRESS         SET MASKING POLICY {{DATABASE}}.{{GOVERNANCE}}.MASK_ADDRESS;
ALTER VIEW PATIENTS MODIFY COLUMN DATE_OF_BIRTH          SET MASKING POLICY {{DATABASE}}.{{GOVERNANCE}}.MASK_DATE;
ALTER VIEW PATIENTS MODIFY COLUMN DATE_OF_DEATH          SET MASKING POLICY {{DATABASE}}.{{GOVERNANCE}}.MASK_DATE;


-- ---------------------------------------------------------------------
-- ROLE-BASED PII FOR THE APP
-- The app runs as its owner, so masking by CURRENT_ROLE() cannot see the app user's role.
-- The app therefore asks for a PII level (from APP_ROLE_PERMISSIONS) and this function applies it:
--   FULL    -> everything (engineer)
--   PARTIAL -> names and date of birth, SSN last 4 digits, address hidden (clinical analyst)
--   NONE    -> everything masked, year of birth only (all other roles)
-- ---------------------------------------------------------------------
CREATE OR REPLACE SECURE FUNCTION {{DATABASE}}.{{GOVERNANCE}}.PATIENTS_WITH_PII(PII_LEVEL STRING)
RETURNS TABLE (PATIENT_NUMBER STRING, FIRST_NAME STRING, LAST_NAME STRING, SOCIAL_SECURITY_NUMBER STRING,
               STREET_ADDRESS STRING, DATE_OF_BIRTH DATE, AGE_IN_YEARS NUMBER, PATIENT_GENDER STRING,
               HOME_CITY STRING, HOME_STATE STRING)
COMMENT = 'Patients with PII shown by level: FULL, PARTIAL or NONE'
AS $$
SELECT
  PATIENT_ID::STRING,
  CASE WHEN PII_LEVEL IN ('FULL', 'PARTIAL') THEN FIRST ELSE '***MASKED***' END,
  CASE WHEN PII_LEVEL IN ('FULL', 'PARTIAL') THEN LAST  ELSE '***MASKED***' END,
  CASE WHEN PII_LEVEL = 'FULL' THEN SSN WHEN PII_LEVEL = 'PARTIAL' THEN 'XXX-XX-' || RIGHT(SSN, 4) ELSE 'XXX-XX-XXXX' END,
  CASE WHEN PII_LEVEL = 'FULL' THEN ADDRESS ELSE '***MASKED***' END,
  CASE WHEN PII_LEVEL IN ('FULL', 'PARTIAL') THEN BIRTHDATE::DATE ELSE DATE_FROM_PARTS(YEAR(BIRTHDATE), 1, 1) END,
  DATEDIFF('year', BIRTHDATE, COALESCE(DEATHDATE, CURRENT_DATE())),
  GENDER, CITY, STATE
FROM {{SOURCE}}.PATIENTS
$$;

CREATE OR REPLACE VIEW VISITS COMMENT = 'One row per patient visit.' AS
SELECT
  ENCOUNTER_ID                                      AS VISIT_NUMBER,
  PATIENT_ID                                        AS PATIENT_NUMBER,
  PROVIDER_ID                                       AS CLINICIAN_NUMBER,
  ORGANIZATION_ID                                   AS FACILITY_NUMBER,
  PAYER_ID                                          AS INSURER_NUMBER,
  ENCOUNTER_START                                   AS VISIT_START_TIME,
  ENCOUNTER_STOP                                    AS VISIT_END_TIME,
  DATEDIFF('minute', ENCOUNTER_START, ENCOUNTER_STOP) AS VISIT_MINUTES,
  ENCOUNTERCLASS                                    AS CARE_SETTING,
  DESCRIPTION                                       AS VISIT_TYPE,
  REASONDESCRIPTION                                 AS VISIT_REASON,
  TOTAL_CLAIM_COST                                  AS CLAIM_AMOUNT_USD,
  PAYER_COVERAGE                                    AS INSURER_PAID_USD
FROM {{SOURCE}}.ENCOUNTERS;

CREATE OR REPLACE VIEW DIAGNOSES COMMENT = 'One row per diagnosis recorded for a patient.' AS
SELECT
  CONDITION_ID           AS DIAGNOSIS_NUMBER,
  PATIENT_ID             AS PATIENT_NUMBER,
  ENCOUNTER_ID           AS VISIT_NUMBER,
  CONDITION_START        AS ONSET_DATE,
  CONDITION_STOP         AS RESOLVED_DATE,
  CONDITION_STOP IS NULL AS IS_ACTIVE_DIAGNOSIS,
  DESCRIPTION            AS DIAGNOSIS_NAME
FROM {{SOURCE}}.CONDITIONS;

CREATE OR REPLACE VIEW PRESCRIPTIONS COMMENT = 'One row per prescription.' AS
SELECT
  MEDICATION_ID     AS PRESCRIPTION_NUMBER,
  PATIENT_ID        AS PATIENT_NUMBER,
  ENCOUNTER_ID      AS VISIT_NUMBER,
  PAYER_ID          AS INSURER_NUMBER,
  MED_START         AS PRESCRIPTION_START_TIME,
  MED_STOP          AS PRESCRIPTION_END_TIME,
  MED_STOP IS NULL  AS IS_ACTIVE_PRESCRIPTION,
  DESCRIPTION       AS MEDICATION_NAME,
  REASONDESCRIPTION AS PRESCRIPTION_REASON,
  DISPENSES         AS TIMES_DISPENSED,
  TOTALCOST         AS PRESCRIPTION_COST_USD
FROM {{SOURCE}}.MEDICATIONS;

CREATE OR REPLACE VIEW PROCEDURES COMMENT = 'One row per procedure performed.' AS
SELECT
  PROCEDURE_ID      AS PROCEDURE_NUMBER,
  PATIENT_ID        AS PATIENT_NUMBER,
  ENCOUNTER_ID      AS VISIT_NUMBER,
  PROC_START        AS PROCEDURE_START_TIME,
  DESCRIPTION       AS PROCEDURE_NAME,
  REASONDESCRIPTION AS PROCEDURE_REASON,
  BASE_COST         AS PROCEDURE_COST_USD
FROM {{SOURCE}}.PROCEDURES;

CREATE OR REPLACE VIEW OBSERVATIONS COMMENT = 'One row per clinical measurement (about 763M rows).' AS
SELECT
  OBSERVATION_ID       AS OBSERVATION_NUMBER,
  PATIENT_ID           AS PATIENT_NUMBER,
  OBSERVATION_DATE     AS OBSERVED_AT,
  DESCRIPTION          AS MEASUREMENT_NAME,
  TRY_TO_DOUBLE(VALUE) AS RESULT_NUMBER,
  VALUE                AS RESULT_TEXT,
  UNITS                AS RESULT_UNITS
FROM {{SOURCE}}.OBSERVATIONS;

CREATE OR REPLACE VIEW VACCINATIONS COMMENT = 'One row per vaccine dose given.' AS
SELECT
  IMMUNIZATION_ID   AS VACCINATION_NUMBER,
  PATIENT_ID        AS PATIENT_NUMBER,
  ENCOUNTER_ID      AS VISIT_NUMBER,
  IMMUNIZATION_DATE AS VACCINATED_AT,
  DESCRIPTION       AS VACCINE_NAME,
  BASE_COST         AS VACCINE_COST_USD
FROM {{SOURCE}}.IMMUNIZATIONS;

CREATE OR REPLACE VIEW ALLERGIES COMMENT = 'One row per recorded allergy or intolerance.' AS
SELECT
  ALLERGY_ID           AS ALLERGY_NUMBER,
  PATIENT_ID           AS PATIENT_NUMBER,
  ALLERGY_START        AS ALLERGY_START_DATE,
  ALLERGY_STOP IS NULL AS IS_ACTIVE_ALLERGY,
  DESCRIPTION          AS ALLERGEN_NAME,
  TYPE                 AS ALLERGY_TYPE,
  CATEGORY             AS ALLERGY_CATEGORY,
  DESCRIPTION1         AS REACTION,
  SEVERITY1            AS REACTION_SEVERITY
FROM {{SOURCE}}.ALLERGIES;

CREATE OR REPLACE VIEW CLINICIANS COMMENT = 'One row per clinician (synthetic).' AS
SELECT
  PROVIDER_ID     AS CLINICIAN_NUMBER,
  ORGANIZATION_ID AS FACILITY_NUMBER,
  NAME            AS CLINICIAN_NAME,
  GENDER          AS CLINICIAN_GENDER,
  SPECIALITY      AS SPECIALTY,
  STATE           AS PRACTICE_STATE
FROM {{SOURCE}}.PROVIDERS;

CREATE OR REPLACE VIEW FACILITIES COMMENT = 'One row per healthcare facility.' AS
SELECT
  ORGANIZATION_ID AS FACILITY_NUMBER,
  NAME            AS FACILITY_NAME,
  CITY            AS FACILITY_CITY,
  STATE           AS FACILITY_STATE
FROM {{SOURCE}}.ORGANIZATIONS;

CREATE OR REPLACE VIEW INSURERS COMMENT = 'One row per insurer per region. Group by INSURER_NAME.' AS
SELECT
  PAYER_ID            AS INSURER_NUMBER,
  NAME                AS INSURER_NAME,
  STATE_HEADQUARTERED AS HEADQUARTERS_STATE
FROM {{SOURCE}}.PAYERS;

CREATE OR REPLACE VIEW CLAIMS COMMENT = 'One row per billing claim. Dollar balances are all 0 in this dataset.' AS
SELECT
  CLAIM_ID     AS CLAIM_NUMBER,
  PATIENT_ID   AS PATIENT_NUMBER,
  ENCOUNTER_ID AS VISIT_NUMBER,
  SERVICEDATE  AS SERVICE_DATE,
  STATUS1      AS INSURER_CLAIM_STATUS,
  STATUSP      AS PATIENT_CLAIM_STATUS
FROM {{SOURCE}}.CLAIMS;

