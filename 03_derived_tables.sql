-- =====================================================================
-- 03 DERIVED TABLES: make questions fast and simple
--   PATIENT_LATEST_MEASUREMENTS  763M measurements -> 1 row per patient
--   PATIENT_PROFILE              patient + latest measurements, NO personal data
--   HOSPITAL_STAYS               inpatient admissions + 30-day readmission flag
-- =====================================================================
USE SCHEMA {{DATABASE}}.{{ANALYTICS}};
ALTER WAREHOUSE {{WAREHOUSE}} SET WAREHOUSE_SIZE = 'MEDIUM';   -- big build: bigger warehouse, back to XSMALL at the end

CREATE OR REPLACE TABLE PATIENT_LATEST_MEASUREMENTS
  COMMENT = 'One row per patient: most recent value of key clinical measurements.' AS
WITH key_measurements AS (
  SELECT PATIENT_NUMBER, OBSERVED_AT, RESULT_NUMBER, RESULT_TEXT,
         CASE
           WHEN MEASUREMENT_NAME = 'Body mass index (BMI) [Ratio]'           THEN 'BMI'
           WHEN MEASUREMENT_NAME = 'Systolic Blood Pressure'                 THEN 'SYSTOLIC'
           WHEN MEASUREMENT_NAME = 'Diastolic Blood Pressure'                THEN 'DIASTOLIC'
           WHEN MEASUREMENT_NAME = 'Glucose [Mass/volume] in Blood'          THEN 'GLUCOSE'
           WHEN MEASUREMENT_NAME = 'Tobacco smoking status'                  THEN 'SMOKING'
           WHEN MEASUREMENT_NAME ILIKE '%A1c%'                               THEN 'HBA1C'
           WHEN MEASUREMENT_NAME ILIKE 'Cholesterol [Mass/volume]%'          THEN 'CHOLESTEROL'
           WHEN MEASUREMENT_NAME ILIKE 'Low Density Lipoprotein Cholesterol%' THEN 'LDL'
           WHEN MEASUREMENT_NAME ILIKE 'Glomerular filtration rate%'         THEN 'EGFR'
         END AS MEASURE
  FROM OBSERVATIONS
  WHERE MEASUREMENT_NAME IN ('Body mass index (BMI) [Ratio]', 'Systolic Blood Pressure', 'Diastolic Blood Pressure',
                             'Glucose [Mass/volume] in Blood', 'Tobacco smoking status')
     OR MEASUREMENT_NAME ILIKE '%A1c%'
     OR MEASUREMENT_NAME ILIKE 'Cholesterol [Mass/volume]%'
     OR MEASUREMENT_NAME ILIKE 'Low Density Lipoprotein Cholesterol%'
     OR MEASUREMENT_NAME ILIKE 'Glomerular filtration rate%'
),
latest AS (
  SELECT * FROM key_measurements
  WHERE MEASURE IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (PARTITION BY PATIENT_NUMBER, MEASURE ORDER BY OBSERVED_AT DESC) = 1
)
SELECT PATIENT_NUMBER,
       MAX(IFF(MEASURE = 'BMI',         RESULT_NUMBER, NULL)) AS LATEST_BMI,
       MAX(IFF(MEASURE = 'SYSTOLIC',    RESULT_NUMBER, NULL)) AS LATEST_SYSTOLIC_BP,
       MAX(IFF(MEASURE = 'DIASTOLIC',   RESULT_NUMBER, NULL)) AS LATEST_DIASTOLIC_BP,
       MAX(IFF(MEASURE = 'HBA1C',       RESULT_NUMBER, NULL)) AS LATEST_HBA1C_PCT,
       MAX(IFF(MEASURE = 'GLUCOSE',     RESULT_NUMBER, NULL)) AS LATEST_GLUCOSE,
       MAX(IFF(MEASURE = 'CHOLESTEROL', RESULT_NUMBER, NULL)) AS LATEST_TOTAL_CHOLESTEROL,
       MAX(IFF(MEASURE = 'LDL',         RESULT_NUMBER, NULL)) AS LATEST_LDL,
       MAX(IFF(MEASURE = 'EGFR',        RESULT_NUMBER, NULL)) AS LATEST_EGFR,
       MAX(IFF(MEASURE = 'SMOKING',     RESULT_TEXT,   NULL)) AS SMOKING_STATUS
FROM latest
GROUP BY PATIENT_NUMBER;

-- What the AI sees about a patient: demographics + measurements, no names / SSN / address / birth date
CREATE OR REPLACE VIEW PATIENT_PROFILE
  COMMENT = 'One row per patient: demographics plus latest measurements. No personal identifiers.' AS
SELECT p.PATIENT_NUMBER, p.IS_DECEASED, p.AGE_IN_YEARS, p.PATIENT_GENDER, p.PATIENT_RACE, p.PATIENT_ETHNICITY,
       p.MARITAL_STATUS, p.HOME_CITY, p.HOME_COUNTY, p.HOME_STATE, p.HOUSEHOLD_INCOME_USD,
       m.LATEST_BMI, m.LATEST_SYSTOLIC_BP, m.LATEST_DIASTOLIC_BP, m.LATEST_HBA1C_PCT, m.LATEST_GLUCOSE,
       m.LATEST_TOTAL_CHOLESTEROL, m.LATEST_LDL, m.LATEST_EGFR, m.SMOKING_STATUS
FROM PATIENTS p
LEFT JOIN PATIENT_LATEST_MEASUREMENTS m ON m.PATIENT_NUMBER = p.PATIENT_NUMBER;

-- Hospital admissions with length of stay and a 30-day readmission flag
CREATE OR REPLACE TABLE HOSPITAL_STAYS
  CLUSTER BY (TO_DATE(ADMITTED_AT))
  COMMENT = 'One row per inpatient admission, with length of stay and 30-day readmission flag.' AS
WITH stays AS (
  SELECT VISIT_NUMBER, PATIENT_NUMBER,
         VISIT_START_TIME AS ADMITTED_AT,
         VISIT_END_TIME   AS DISCHARGED_AT,
         VISIT_REASON     AS ADMISSION_REASON,
         LEAD(VISIT_START_TIME) OVER (PARTITION BY PATIENT_NUMBER ORDER BY VISIT_START_TIME) AS NEXT_ADMITTED_AT
  FROM VISITS
  WHERE CARE_SETTING = 'inpatient'
)
SELECT VISIT_NUMBER, PATIENT_NUMBER, ADMITTED_AT, DISCHARGED_AT, ADMISSION_REASON,
       DATEDIFF('day', ADMITTED_AT, DISCHARGED_AT) AS LENGTH_OF_STAY_DAYS,
       COALESCE(DATEDIFF('day', DISCHARGED_AT, NEXT_ADMITTED_AT) BETWEEN 0 AND 30, FALSE) AS IS_READMITTED_30D
FROM stays;

ALTER WAREHOUSE {{WAREHOUSE}} SET WAREHOUSE_SIZE = 'XSMALL';