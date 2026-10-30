-- =====================================================================
-- 07 KPI MARTS: small pre-aggregated tables for the dashboard.
-- Built FROM the semantic model, so dashboard numbers = AI answers.
-- Time marts are MONTHLY (the app can show them by month or roll them up to years),
-- clustered by their month column.
-- =====================================================================
USE SCHEMA {{DATABASE}}.{{MARTS}};
ALTER WAREHOUSE {{WAREHOUSE}} SET WAREHOUSE_SIZE = 'MEDIUM';

CREATE OR REPLACE TABLE KPI_PATIENT_SEGMENTS COMMENT = 'Patients by age group, gender, state and clinical category' AS
SELECT * FROM SEMANTIC_VIEW({{DATABASE}}.{{ANALYTICS}}.{{SEMANTIC_VIEW}}
  METRICS    patients.patient_count
  DIMENSIONS patients.age_group, patients.patient_gender, patients.home_state, patients.is_deceased,
             patients.bmi_category, patients.blood_pressure_category, patients.hba1c_category);

CREATE OR REPLACE TABLE KPI_VISITS_MONTHLY CLUSTER BY (VISIT_MONTH) COMMENT = 'Visits and claim amounts by month, care setting and insurer' AS
SELECT * FROM SEMANTIC_VIEW({{DATABASE}}.{{ANALYTICS}}.{{SEMANTIC_VIEW}}
  METRICS    visits.visit_count, visits.total_claim_amount, visits.total_insurer_paid
  DIMENSIONS visits.visit_month, visits.care_setting, insurers.insurer_name);

CREATE OR REPLACE TABLE KPI_HOSPITAL_MONTHLY CLUSTER BY (ADMISSION_MONTH) COMMENT = 'Admissions, readmissions and length of stay by month and age group' AS
SELECT * FROM SEMANTIC_VIEW({{DATABASE}}.{{ANALYTICS}}.{{SEMANTIC_VIEW}}
  METRICS    hospital_stays.admission_count, hospital_stays.readmission_count, hospital_stays.average_length_of_stay
  DIMENSIONS hospital_stays.admission_month, patients.age_group);

CREATE OR REPLACE TABLE KPI_DIAGNOSES COMMENT = 'Patients per active diagnosis (living patients)' AS
SELECT DIAGNOSIS_NAME, PATIENTS_WITH_DIAGNOSIS
FROM SEMANTIC_VIEW({{DATABASE}}.{{ANALYTICS}}.{{SEMANTIC_VIEW}}
  METRICS    diagnoses.patients_with_diagnosis
  DIMENSIONS diagnoses.diagnosis_name, diagnoses.is_active_diagnosis, patients.is_deceased)
WHERE IS_ACTIVE_DIAGNOSIS AND NOT IS_DECEASED;

CREATE OR REPLACE TABLE KPI_PRESCRIPTIONS COMMENT = 'Patients, prescriptions and cost per medication' AS
SELECT * FROM SEMANTIC_VIEW({{DATABASE}}.{{ANALYTICS}}.{{SEMANTIC_VIEW}}
  METRICS    prescriptions.patients_on_medication, prescriptions.prescription_count, prescriptions.total_medication_cost
  DIMENSIONS prescriptions.medication_name);

CREATE OR REPLACE TABLE KPI_VACCINATIONS_MONTHLY CLUSTER BY (VACCINATION_MONTH) COMMENT = 'Vaccine doses by month, flu and COVID flags' AS
SELECT * FROM SEMANTIC_VIEW({{DATABASE}}.{{ANALYTICS}}.{{SEMANTIC_VIEW}}
  METRICS    vaccinations.doses_given
  DIMENSIONS vaccinations.vaccination_month, vaccinations.is_flu_vaccine, vaccinations.is_covid_vaccine);

CREATE OR REPLACE TABLE KPI_ALLERGIES COMMENT = 'Patients per allergen' AS
SELECT * FROM SEMANTIC_VIEW({{DATABASE}}.{{ANALYTICS}}.{{SEMANTIC_VIEW}}
  METRICS    allergies.patients_with_allergy
  DIMENSIONS allergies.allergy_category, allergies.allergen_name);

CREATE OR REPLACE TABLE KPI_CLAIMS_MONTHLY CLUSTER BY (SERVICE_MONTH) COMMENT = 'Claims and open claims by month' AS
SELECT * FROM SEMANTIC_VIEW({{DATABASE}}.{{ANALYTICS}}.{{SEMANTIC_VIEW}}
  METRICS    claims.claim_count, claims.open_claim_count
  DIMENSIONS claims.service_month);

-- The old yearly marts are replaced by the monthly ones (the app rolls months up to years)
DROP TABLE IF EXISTS KPI_HOSPITAL_YEARLY;
DROP TABLE IF EXISTS KPI_VACCINATIONS_YEARLY;
DROP TABLE IF EXISTS KPI_CLAIMS_YEARLY;

ALTER WAREHOUSE {{WAREHOUSE}} SET WAREHOUSE_SIZE = 'XSMALL';