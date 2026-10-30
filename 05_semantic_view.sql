-- =====================================================================
-- 05 SEMANTIC MODEL: explains the data in business language to Cortex Analyst
--   12 tables · 12 relationships (one path between any two tables)
--   facts · dimensions · metrics · official definitions · 14 verified queries
-- =====================================================================

CREATE OR REPLACE SEMANTIC VIEW {{DATABASE}}.{{ANALYTICS}}.{{SEMANTIC_VIEW}}

TABLES (
  patients AS {{DATABASE}}.{{ANALYTICS}}.PATIENT_PROFILE PRIMARY KEY (PATIENT_NUMBER)
    WITH SYNONYMS ('people', 'members', 'population')
    COMMENT = 'One row per patient: demographics plus latest clinical measurements. No personal identifiers.',
  visits AS {{DATABASE}}.{{ANALYTICS}}.VISITS PRIMARY KEY (VISIT_NUMBER)
    WITH SYNONYMS ('encounters', 'appointments') COMMENT = 'One row per patient visit.',
  diagnoses AS {{DATABASE}}.{{ANALYTICS}}.DIAGNOSES PRIMARY KEY (DIAGNOSIS_NUMBER)
    WITH SYNONYMS ('conditions', 'diseases') COMMENT = 'One row per diagnosis recorded for a patient.',
  prescriptions AS {{DATABASE}}.{{ANALYTICS}}.PRESCRIPTIONS PRIMARY KEY (PRESCRIPTION_NUMBER)
    WITH SYNONYMS ('medications', 'drugs', 'meds') COMMENT = 'One row per prescription.',
  procedures AS {{DATABASE}}.{{ANALYTICS}}.PROCEDURES PRIMARY KEY (PROCEDURE_NUMBER)
    WITH SYNONYMS ('treatments', 'operations') COMMENT = 'One row per procedure performed.',
  vaccinations AS {{DATABASE}}.{{ANALYTICS}}.VACCINATIONS PRIMARY KEY (VACCINATION_NUMBER)
    WITH SYNONYMS ('immunizations', 'vaccines', 'shots') COMMENT = 'One row per vaccine dose given.',
  allergies AS {{DATABASE}}.{{ANALYTICS}}.ALLERGIES PRIMARY KEY (ALLERGY_NUMBER)
    WITH SYNONYMS ('intolerances') COMMENT = 'One row per recorded allergy or intolerance.',
  claims AS {{DATABASE}}.{{ANALYTICS}}.CLAIMS PRIMARY KEY (CLAIM_NUMBER)
    WITH SYNONYMS ('bills', 'insurance claims') COMMENT = 'One row per billing claim. Dollar balances are all 0 in this dataset.',
  hospital_stays AS {{DATABASE}}.{{ANALYTICS}}.HOSPITAL_STAYS PRIMARY KEY (VISIT_NUMBER)
    WITH SYNONYMS ('hospital admissions', 'hospitalizations', 'admissions')
    COMMENT = 'One row per inpatient admission, with length of stay and 30-day readmission flag.',
  clinicians AS {{DATABASE}}.{{ANALYTICS}}.CLINICIANS PRIMARY KEY (CLINICIAN_NUMBER)
    WITH SYNONYMS ('doctors', 'providers') COMMENT = 'One row per clinician (synthetic).',
  facilities AS {{DATABASE}}.{{ANALYTICS}}.FACILITIES PRIMARY KEY (FACILITY_NUMBER)
    WITH SYNONYMS ('hospitals', 'clinics', 'organizations') COMMENT = 'One row per healthcare facility.',
  insurers AS {{DATABASE}}.{{ANALYTICS}}.INSURERS PRIMARY KEY (INSURER_NUMBER)
    WITH SYNONYMS ('payers', 'insurance companies', 'health plans') COMMENT = 'One row per insurer per region. Group by INSURER_NAME.'
)

RELATIONSHIPS (
  visits_to_patients            AS visits (PATIENT_NUMBER) REFERENCES patients,
  visits_to_clinicians          AS visits (CLINICIAN_NUMBER) REFERENCES clinicians,
  visits_to_facilities          AS visits (FACILITY_NUMBER) REFERENCES facilities,
  visits_to_insurers            AS visits (INSURER_NUMBER) REFERENCES insurers,
  diagnoses_to_patients         AS diagnoses (PATIENT_NUMBER) REFERENCES patients,
  prescriptions_to_patients     AS prescriptions (PATIENT_NUMBER) REFERENCES patients,
  prescriptions_to_insurers     AS prescriptions (INSURER_NUMBER) REFERENCES insurers,
  procedures_to_patients        AS procedures (PATIENT_NUMBER) REFERENCES patients,
  vaccinations_to_patients      AS vaccinations (PATIENT_NUMBER) REFERENCES patients,
  allergies_to_patients         AS allergies (PATIENT_NUMBER) REFERENCES patients,
  claims_to_visits              AS claims (VISIT_NUMBER) REFERENCES visits,
  hospital_stays_to_visits      AS hospital_stays (VISIT_NUMBER) REFERENCES visits
)

FACTS (
  patients.bmi_value          AS LATEST_BMI COMMENT = 'Most recent BMI of one patient (kg/m2)',
  patients.systolic_value     AS LATEST_SYSTOLIC_BP COMMENT = 'Most recent systolic blood pressure (mm[Hg])',
  patients.diastolic_value    AS LATEST_DIASTOLIC_BP COMMENT = 'Most recent diastolic blood pressure (mm[Hg])',
  patients.hba1c_value        AS LATEST_HBA1C_PCT COMMENT = 'Most recent HbA1c (%)',
  patients.ldl_value          AS LATEST_LDL COMMENT = 'Most recent LDL cholesterol (mg/dL)',
  patients.glucose_value      AS LATEST_GLUCOSE COMMENT = 'Most recent blood glucose (mg/dL)',
  patients.cholesterol_value  AS LATEST_TOTAL_CHOLESTEROL COMMENT = 'Most recent total cholesterol (mg/dL)',
  patients.egfr_value         AS LATEST_EGFR COMMENT = 'Most recent eGFR kidney function (mL/min/1.73m2)',
  visits.visit_length_value   AS VISIT_MINUTES COMMENT = 'Length of one visit in minutes',
  visits.claim_value          AS CLAIM_AMOUNT_USD COMMENT = 'Claim amount of one visit (USD)',
  visits.insurer_paid_value   AS INSURER_PAID_USD COMMENT = 'Amount of one visit paid by the insurer (USD)',
  prescriptions.prescription_cost_value AS PRESCRIPTION_COST_USD COMMENT = 'Total cost of one prescription (USD)',
  prescriptions.dispense_value AS TIMES_DISPENSED COMMENT = 'Times one prescription was dispensed',
  procedures.procedure_cost_value AS PROCEDURE_COST_USD COMMENT = 'Cost of one procedure (USD)',
  vaccinations.vaccine_cost_value AS VACCINE_COST_USD COMMENT = 'Cost of one vaccine dose (USD)',
  hospital_stays.stay_length_value AS LENGTH_OF_STAY_DAYS COMMENT = 'Length of one hospital stay in days'
)

DIMENSIONS (
  patients.patient_gender AS PATIENT_GENDER WITH SYNONYMS = ('sex', 'gender') COMMENT = 'Patient gender: M or F',
  patients.patient_race AS PATIENT_RACE COMMENT = 'Patient race',
  patients.patient_ethnicity AS PATIENT_ETHNICITY COMMENT = 'Patient ethnicity',
  patients.marital_status AS MARITAL_STATUS COMMENT = 'Marital status code: M, S, D, W',
  patients.age_in_years AS AGE_IN_YEARS WITH SYNONYMS = ('age') COMMENT = 'Age in years (at death if deceased, otherwise today)',
  patients.age_group AS
    CASE WHEN AGE_IN_YEARS < 18 THEN '0-17' WHEN AGE_IN_YEARS < 35 THEN '18-34' WHEN AGE_IN_YEARS < 50 THEN '35-49'
         WHEN AGE_IN_YEARS < 65 THEN '50-64' ELSE '65+' END
    WITH SYNONYMS = ('age band') COMMENT = 'Age band: 0-17, 18-34, 35-49, 50-64, 65+',
  patients.is_deceased AS IS_DECEASED WITH SYNONYMS = ('dead', 'died') COMMENT = 'TRUE if the patient has a recorded death date',
  patients.home_state AS HOME_STATE COMMENT = 'State where the patient lives',
  patients.home_city AS HOME_CITY COMMENT = 'City or town where the patient lives',
  patients.home_county AS HOME_COUNTY COMMENT = 'County where the patient lives',
  patients.bmi_category AS
    CASE WHEN LATEST_BMI IS NULL THEN 'No measurement' WHEN LATEST_BMI < 18.5 THEN 'Underweight'
         WHEN LATEST_BMI < 25 THEN 'Normal weight' WHEN LATEST_BMI < 30 THEN 'Overweight' ELSE 'Obese' END
    WITH SYNONYMS = ('weight category', 'obesity status')
    COMMENT = 'Official BMI category from the most recent BMI (adult WHO thresholds). Use adults for BMI questions.',
  patients.blood_pressure_category AS
    CASE WHEN LATEST_SYSTOLIC_BP IS NULL THEN 'No measurement'
         WHEN LATEST_SYSTOLIC_BP >= 140 OR LATEST_DIASTOLIC_BP >= 90 THEN 'Stage 2 hypertension range'
         WHEN LATEST_SYSTOLIC_BP >= 130 OR LATEST_DIASTOLIC_BP >= 80 THEN 'Stage 1 hypertension range'
         WHEN LATEST_SYSTOLIC_BP >= 120 THEN 'Elevated' ELSE 'Normal' END
    WITH SYNONYMS = ('BP category') COMMENT = 'Official category of the most recent blood pressure reading (ACC/AHA).',
  patients.hba1c_category AS
    CASE WHEN LATEST_HBA1C_PCT IS NULL THEN 'No measurement' WHEN LATEST_HBA1C_PCT >= 6.5 THEN 'Diabetic range'
         WHEN LATEST_HBA1C_PCT >= 5.7 THEN 'Prediabetic range' ELSE 'Normal' END
    WITH SYNONYMS = ('blood sugar control') COMMENT = 'Official category of the most recent HbA1c.',
  patients.smoking_status AS SMOKING_STATUS WITH SYNONYMS = ('tobacco use') COMMENT = 'Most recent smoking status',
  patients.has_high_bp_reading AS COALESCE(LATEST_SYSTOLIC_BP >= 140 OR LATEST_DIASTOLIC_BP >= 90, FALSE)
    COMMENT = 'TRUE if the most recent reading is 140/90 or higher',

  visits.care_setting AS CARE_SETTING WITH SYNONYMS = ('visit category', 'encounter class')
    COMMENT = 'Care setting of the visit'
    SAMPLE_VALUES ('ambulatory', 'wellness', 'outpatient', 'urgentcare', 'emergency',
                   'inpatient', 'home', 'hospice', 'virtual', 'snf') IS_ENUM,
  visits.visit_type AS VISIT_TYPE COMMENT = 'Description of the type of visit',
  visits.visit_reason AS VISIT_REASON WITH SYNONYMS = ('reason for visit')
    COMMENT = 'Clinical reason for the visit. Use exact values from search.' 
    WITH CORTEX SEARCH SERVICE {{DATABASE}}.{{SEARCH}}.{{SEARCH_SERVICE}} USING CLINICAL_TERM,
  visits.visit_date AS DATE(VISIT_START_TIME) COMMENT = 'Date the visit started',
  visits.visit_month AS DATE_TRUNC('month', VISIT_START_TIME)::DATE COMMENT = 'Month the visit started',
  visits.visit_year AS YEAR(VISIT_START_TIME) COMMENT = 'Year the visit started',

  diagnoses.diagnosis_name AS DIAGNOSIS_NAME WITH SYNONYMS = ('diagnosis', 'condition', 'disease')
    COMMENT = 'Clinical name of the diagnosis. Use exact values from search.' 
    WITH CORTEX SEARCH SERVICE {{DATABASE}}.{{SEARCH}}.{{SEARCH_SERVICE}} USING CLINICAL_TERM,
  diagnoses.onset_year AS YEAR(ONSET_DATE) COMMENT = 'Year the condition started',
  diagnoses.onset_month AS DATE_TRUNC('month', ONSET_DATE)::DATE COMMENT = 'Month the condition started',
  diagnoses.is_active_diagnosis AS IS_ACTIVE_DIAGNOSIS COMMENT = 'TRUE if the condition has not resolved',
  diagnoses.is_heart_attack AS DIAGNOSIS_NAME IN ('Myocardial infarction (disorder)', 'Acute ST segment elevation myocardial infarction (disorder)', 'Acute non-ST segment elevation myocardial infarction (disorder)', 'Postoperative myocardial infarction (disorder)', 'History of myocardial infarction (situation)')
    WITH SYNONYMS = ('heart attack', 'MI', 'AMI', 'myocardial infarction', 'STEMI', 'NSTEMI')
    COMMENT = 'OFFICIAL heart attack definition: Myocardial infarction (disorder), Acute ST segment elevation myocardial infarction (disorder), Acute non-ST segment elevation myocardial infarction (disorder), Postoperative myocardial infarction (disorder), History of myocardial infarction (situation). ALWAYS use it for heart attack / MI questions.',

  prescriptions.medication_name AS MEDICATION_NAME WITH SYNONYMS = ('drug name')
    COMMENT = 'Drug name, strength and form. Use exact values from search.' 
    WITH CORTEX SEARCH SERVICE {{DATABASE}}.{{SEARCH}}.{{SEARCH_SERVICE}} USING CLINICAL_TERM,
  prescriptions.prescription_reason AS PRESCRIPTION_REASON COMMENT = 'Condition it was prescribed for',
  prescriptions.prescription_year AS YEAR(PRESCRIPTION_START_TIME) COMMENT = 'Year the prescription started',
  prescriptions.prescription_month AS DATE_TRUNC('month', PRESCRIPTION_START_TIME)::DATE COMMENT = 'Month the prescription started',
  prescriptions.is_active_prescription AS IS_ACTIVE_PRESCRIPTION COMMENT = 'TRUE if the prescription is still ongoing',
  prescriptions.is_bp_medication AS (MEDICATION_NAME ILIKE ANY ('%lisinopril%', '%enalapril%', '%ramipril%', '%benazepril%', '%quinapril%', '%losartan%', '%valsartan%', '%irbesartan%', '%telmisartan%', '%amlodipine%', '%verapamil%', '%hydrochlorothiazide%', '%metoprolol%', '%atenolol%', '%carvedilol%', '%propranolol%', '%bisoprolol%', '%nebivolol%', '%labetalol%') AND MEDICATION_NAME NOT ILIKE '%sacubitril%')
    WITH SYNONYMS = ('blood pressure medication', 'blood pressure pills', 'antihypertensive', 'BP meds')
    COMMENT = 'OFFICIAL blood pressure medication definition: lisinopril, enalapril, ramipril, benazepril, quinapril, losartan, valsartan, irbesartan, telmisartan, amlodipine, verapamil, hydrochlorothiazide, metoprolol, atenolol, carvedilol, propranolol, bisoprolol, nebivolol, labetalol; excludes sacubitril. ALWAYS use it.',

  procedures.procedure_name AS PROCEDURE_NAME COMMENT = 'Clinical name of the procedure. Use exact values from search.' 
    WITH CORTEX SEARCH SERVICE {{DATABASE}}.{{SEARCH}}.{{SEARCH_SERVICE}} USING CLINICAL_TERM,
  procedures.procedure_reason AS PROCEDURE_REASON COMMENT = 'Condition the procedure was performed for',
  procedures.procedure_year AS YEAR(PROCEDURE_START_TIME) COMMENT = 'Year the procedure was performed',
  procedures.procedure_month AS DATE_TRUNC('month', PROCEDURE_START_TIME)::DATE COMMENT = 'Month the procedure was performed',

  vaccinations.vaccine_name AS VACCINE_NAME WITH SYNONYMS = ('vaccine', 'shot')
    COMMENT = 'Vaccine given. Use exact values from search.' 
    WITH CORTEX SEARCH SERVICE {{DATABASE}}.{{SEARCH}}.{{SEARCH_SERVICE}} USING CLINICAL_TERM,
  vaccinations.vaccination_year AS YEAR(VACCINATED_AT) COMMENT = 'Year the vaccine was given',
  vaccinations.vaccination_month AS DATE_TRUNC('month', VACCINATED_AT)::DATE COMMENT = 'Month the vaccine was given',
  vaccinations.is_flu_vaccine AS VACCINE_NAME ILIKE '%influenza%'
    WITH SYNONYMS = ('flu shot', 'flu vaccine', 'influenza vaccine') COMMENT = 'OFFICIAL flu vaccine definition',
  vaccinations.is_covid_vaccine AS VACCINE_NAME ILIKE 'COVID-19%'
    WITH SYNONYMS = ('covid shot', 'covid vaccine') COMMENT = 'OFFICIAL COVID-19 vaccine definition',

  allergies.allergen_name AS ALLERGEN_NAME WITH SYNONYMS = ('allergic to')
    COMMENT = 'What the patient is allergic to. Use exact values from search.' 
    WITH CORTEX SEARCH SERVICE {{DATABASE}}.{{SEARCH}}.{{SEARCH_SERVICE}} USING CLINICAL_TERM,
  allergies.allergy_category AS ALLERGY_CATEGORY COMMENT = 'food, medication or environment',
  allergies.allergy_type AS ALLERGY_TYPE COMMENT = 'allergy or intolerance',
  allergies.is_active_allergy AS IS_ACTIVE_ALLERGY COMMENT = 'TRUE if the allergy is still active',
  allergies.reaction AS REACTION COMMENT = 'First recorded reaction',
  allergies.reaction_severity AS REACTION_SEVERITY COMMENT = 'MILD, MODERATE or SEVERE',

  claims.service_year AS YEAR(SERVICE_DATE) COMMENT = 'Year the billed service was provided',
  claims.service_month AS DATE_TRUNC('month', SERVICE_DATE)::DATE COMMENT = 'Month the billed service was provided',
  claims.insurer_claim_status AS INSURER_CLAIM_STATUS COMMENT = 'Status with the primary insurer'
    SAMPLE_VALUES ('CLOSED', 'BILLED'),
  claims.patient_claim_status AS PATIENT_CLAIM_STATUS COMMENT = 'Status of the patient portion'
    SAMPLE_VALUES ('CLOSED', 'BILLED'),
  claims.is_open_claim AS COALESCE(INSURER_CLAIM_STATUS = 'BILLED' OR PATIENT_CLAIM_STATUS = 'BILLED', FALSE)
    WITH SYNONYMS = ('open claim', 'unpaid claim', 'pending claim')
    COMMENT = 'OFFICIAL open-claim definition: status BILLED with the insurer or the patient',

  hospital_stays.admission_year AS YEAR(ADMITTED_AT) COMMENT = 'Year of hospital admission',
  hospital_stays.admission_month AS DATE_TRUNC('month', ADMITTED_AT)::DATE COMMENT = 'Month of hospital admission',
  hospital_stays.admission_reason AS ADMISSION_REASON COMMENT = 'Reason for the admission. Use exact values from search.' 
    WITH CORTEX SEARCH SERVICE {{DATABASE}}.{{SEARCH}}.{{SEARCH_SERVICE}} USING CLINICAL_TERM,
  hospital_stays.is_readmitted AS IS_READMITTED_30D WITH SYNONYMS = ('readmitted', 'readmission')
    COMMENT = 'OFFICIAL readmission definition: admitted again within 30 days of discharge',
  hospital_stays.length_of_stay_band AS
    CASE WHEN LENGTH_OF_STAY_DAYS < 1 THEN 'Under 1 day' WHEN LENGTH_OF_STAY_DAYS < 4 THEN '1-3 days'
         WHEN LENGTH_OF_STAY_DAYS < 8 THEN '4-7 days' ELSE '8+ days' END
    COMMENT = 'Length-of-stay band',

  clinicians.clinician_name AS CLINICIAN_NAME COMMENT = 'Clinician name (synthetic)',
  clinicians.specialty AS SPECIALTY WITH SYNONYMS = ('speciality', 'provider specialty') COMMENT = 'Clinical specialty',
  clinicians.clinician_gender AS CLINICIAN_GENDER COMMENT = 'Clinician gender',
  clinicians.practice_state AS PRACTICE_STATE COMMENT = 'State where the clinician practices',
  facilities.facility_name AS FACILITY_NAME WITH SYNONYMS = ('hospital name') COMMENT = 'Hospital or clinic name',
  facilities.facility_city AS FACILITY_CITY COMMENT = 'City of the facility',
  facilities.facility_state AS FACILITY_STATE COMMENT = 'State of the facility',
  insurers.insurer_name AS INSURER_NAME WITH SYNONYMS = ('insurer', 'insurance', 'health plan', 'payer')
    COMMENT = 'Insurer name. NO_INSURANCE means uninsured patients. Always group by this, never by insurer number.',
  insurers.headquarters_state AS HEADQUARTERS_STATE COMMENT = 'State where the insurer is headquartered'
)

METRICS (
  patients.patient_count AS COUNT(DISTINCT PATIENT_NUMBER) WITH SYNONYMS = ('number of patients') COMMENT = 'Number of distinct patients',
  patients.deceased_patient_count AS COUNT_IF(IS_DECEASED) COMMENT = 'Patients with a recorded death date',
  patients.average_age AS AVG(AGE_IN_YEARS) COMMENT = 'Average age in years',
  patients.average_income AS AVG(HOUSEHOLD_INCOME_USD) COMMENT = 'Average annual household income (USD)',
  patients.average_bmi AS AVG(patients.bmi_value) COMMENT = 'Average most recent BMI',
  patients.average_systolic_bp AS AVG(patients.systolic_value) COMMENT = 'Average most recent systolic blood pressure',
  patients.average_hba1c AS AVG(patients.hba1c_value) COMMENT = 'Average most recent HbA1c',
  patients.average_ldl AS AVG(patients.ldl_value) COMMENT = 'Average most recent LDL cholesterol',
  patients.obesity_rate AS DIV0(COUNT_IF(LATEST_BMI >= 30), COUNT(LATEST_BMI)) COMMENT = 'Share (0-1) of measured patients with BMI 30+',
  patients.high_bp_reading_rate AS DIV0(COUNT_IF(LATEST_SYSTOLIC_BP >= 140 OR LATEST_DIASTOLIC_BP >= 90), COUNT(LATEST_SYSTOLIC_BP))
    COMMENT = 'Share (0-1) of measured patients whose latest reading is 140/90 or higher',

  visits.visit_count AS COUNT(VISIT_NUMBER) WITH SYNONYMS = ('number of visits', 'encounter count') COMMENT = 'Number of visits',
  visits.patients_seen AS COUNT(DISTINCT PATIENT_NUMBER) COMMENT = 'Distinct patients with at least one visit',
  visits.total_claim_amount AS SUM(visits.claim_value) WITH SYNONYMS = ('total cost', 'spend', 'total claim cost') COMMENT = 'Total claim amount (USD)',
  visits.average_claim_per_visit AS AVG(visits.claim_value) COMMENT = 'Average claim amount per visit (USD)',
  visits.total_insurer_paid AS SUM(visits.insurer_paid_value) COMMENT = 'Total paid by insurers (USD)',
  visits.insurer_coverage_rate AS DIV0(SUM(visits.insurer_paid_value), SUM(visits.claim_value)) COMMENT = 'Share (0-1) of claim amount paid by insurers',
  visits.total_uncovered_amount AS SUM(visits.claim_value - visits.insurer_paid_value)
    WITH SYNONYMS = ('out of pocket', 'uncovered amount') COMMENT = 'Total claim amount not paid by insurers (USD)',
  visits.average_visit_minutes AS AVG(visits.visit_length_value) COMMENT = 'Average visit length in minutes',

  diagnoses.patients_with_diagnosis AS COUNT(DISTINCT PATIENT_NUMBER) WITH SYNONYMS = ('patients diagnosed') COMMENT = 'Distinct patients with the diagnosis',
  diagnoses.diagnosis_record_count AS COUNT(DIAGNOSIS_NUMBER) COMMENT = 'Number of diagnosis records',
  prescriptions.prescription_count AS COUNT(PRESCRIPTION_NUMBER) COMMENT = 'Number of prescriptions',
  prescriptions.patients_on_medication AS COUNT(DISTINCT PATIENT_NUMBER) COMMENT = 'Distinct patients prescribed the medication(s)',
  prescriptions.total_medication_cost AS SUM(prescriptions.prescription_cost_value) WITH SYNONYMS = ('drug spend', 'pharmacy cost') COMMENT = 'Total prescription cost (USD)',
  prescriptions.total_dispenses AS SUM(prescriptions.dispense_value) COMMENT = 'Total number of dispenses',
  procedures.procedure_count AS COUNT(PROCEDURE_NUMBER) COMMENT = 'Number of procedures',
  procedures.patients_with_procedure AS COUNT(DISTINCT PATIENT_NUMBER) COMMENT = 'Distinct patients who had the procedure(s)',
  procedures.total_procedure_cost AS SUM(procedures.procedure_cost_value) COMMENT = 'Total procedure cost (USD)',
  vaccinations.doses_given AS COUNT(VACCINATION_NUMBER) COMMENT = 'Number of vaccine doses',
  vaccinations.patients_vaccinated AS COUNT(DISTINCT PATIENT_NUMBER) COMMENT = 'Distinct patients vaccinated',
  vaccinations.total_vaccine_cost AS SUM(vaccinations.vaccine_cost_value) COMMENT = 'Total cost of vaccines given (USD)',
  allergies.patients_with_allergy AS COUNT(DISTINCT PATIENT_NUMBER) COMMENT = 'Distinct patients with the allergy',
  allergies.allergy_record_count AS COUNT(ALLERGY_NUMBER) COMMENT = 'Number of allergy records',
  claims.claim_count AS COUNT(CLAIM_NUMBER) COMMENT = 'Number of claims',
  claims.open_claim_count AS COUNT_IF(COALESCE(INSURER_CLAIM_STATUS = 'BILLED' OR PATIENT_CLAIM_STATUS = 'BILLED', FALSE)) WITH SYNONYMS = ('open claims', 'unpaid claims')
    COMMENT = 'Number of open claims (official definition). Dollar balances are 0 in this dataset.',
  claims.open_claim_rate AS DIV0(COUNT_IF(COALESCE(INSURER_CLAIM_STATUS = 'BILLED' OR PATIENT_CLAIM_STATUS = 'BILLED', FALSE)), COUNT(CLAIM_NUMBER)) COMMENT = 'Share (0-1) of claims still open',
  hospital_stays.admission_count AS COUNT(VISIT_NUMBER) WITH SYNONYMS = ('number of admissions') COMMENT = 'Number of hospital admissions',
  hospital_stays.readmission_count AS COUNT_IF(IS_READMITTED_30D) COMMENT = 'Admissions followed by another within 30 days',
  hospital_stays.readmission_rate AS DIV0(COUNT_IF(IS_READMITTED_30D), COUNT(VISIT_NUMBER))
    WITH SYNONYMS = ('30-day readmission rate') COMMENT = 'OFFICIAL 30-day readmission rate (0-1)',
  hospital_stays.average_length_of_stay AS AVG(hospital_stays.stay_length_value) WITH SYNONYMS = ('ALOS') COMMENT = 'Average stay in days'
)

COMMENT = 'Healthcare semantic model: 12 tables of synthetic Synthea data, business names only, no personal identifiers.'

AI_SQL_GENERATION 'All money is in US dollars: round money to 2 decimals and averages to 1 decimal. Show rates as percentages with 2 decimals (multiply 0-1 rates by 100). To count people always use COUNT(DISTINCT patient number). Adults means age_in_years >= 18; living means NOT is_deceased. For heart attack / MI questions ALWAYS filter diagnoses.is_heart_attack, and for blood pressure medication ALWAYS filter prescriptions.is_bp_medication; never build your own lists for these. For flu and COVID vaccines use vaccinations.is_flu_vaccine and is_covid_vaccine. For open claims use claims.is_open_claim. For readmission use hospital_stays.is_readmitted (another inpatient admission within 30 days of discharge). For other diagnosis, medication, procedure, vaccine, allergen or reason names, use exact values from the Cortex Search Service and include all clinically equivalent values with IN (...). BMI, blood pressure, HbA1c, glucose, cholesterol, LDL and eGFR are the MOST RECENT value per patient (not history). Currently on a medication means is_active_prescription and the patient is not deceased. For insurer questions group by insurer_name, never by insurer number. To combine a patient measurement with a diagnosis, filter patients with patient number IN (SELECT patient number FROM diagnoses WHERE ...). Years refer to the start date of the event; the data ends in 2024, so the last year may be partial. Never return personal identifiers or individual patient records.'HEALTHCARE_INTELLIGENCE

AI_QUESTION_CATEGORIZATION 'If a question asks for patient names, SSNs, addresses, contact details, birth dates, or to identify or list individual patients, decline and offer an aggregated answer. If a question cannot be answered from this model, say so.'

AI_VERIFIED_QUERIES (
  vq_patients_by_gender AS (
    QUESTION 'How many patients are there by gender?'
    VERIFIED_AT 1792800000
    ONBOARDING_QUESTION TRUE
    SQL 'SELECT p.patient_gender, COUNT(DISTINCT p.PATIENT_NUMBER) AS patient_count FROM patients AS p GROUP BY 1 ORDER BY 2 DESC'
  ),
  vq_top_active_diagnoses AS (
    QUESTION 'What are the 10 most common active diagnoses?'
    VERIFIED_AT 1792800000
    ONBOARDING_QUESTION TRUE
    SQL 'SELECT d.diagnosis_name, COUNT(DISTINCT d.PATIENT_NUMBER) AS patients_with_diagnosis FROM diagnoses AS d WHERE d.is_active_diagnosis GROUP BY 1 ORDER BY 2 DESC LIMIT 10'
  ),
  vq_heart_attack AS (
    QUESTION 'How many patients have had a heart attack?'
    VERIFIED_AT 1792800000
    ONBOARDING_QUESTION FALSE
    SQL 'SELECT COUNT(DISTINCT d.PATIENT_NUMBER) AS patients_with_diagnosis FROM diagnoses AS d WHERE d.is_heart_attack'
  ),
  vq_bp_current AS (
    QUESTION 'How many patients are currently on blood pressure medication?'
    VERIFIED_AT 1792800000
    ONBOARDING_QUESTION FALSE
    SQL 'SELECT COUNT(DISTINCT r.PATIENT_NUMBER) AS patients_on_medication FROM prescriptions AS r JOIN patients AS p ON r.PATIENT_NUMBER = p.PATIENT_NUMBER WHERE r.is_bp_medication AND r.is_active_prescription AND NOT p.is_deceased'
  ),
  vq_cost_by_insurer AS (
    QUESTION 'What is the total claim amount by insurer?'
    VERIFIED_AT 1792800000
    ONBOARDING_QUESTION TRUE
    SQL 'SELECT i.insurer_name, ROUND(SUM(v.claim_value), 2) AS total_claim_amount FROM visits AS v JOIN insurers AS i ON v.INSURER_NUMBER = i.INSURER_NUMBER GROUP BY 1 ORDER BY 2 DESC'
  ),
  vq_cost_by_setting AS (
    QUESTION 'What is the average claim amount per visit by care setting?'
    VERIFIED_AT 1792800000
    ONBOARDING_QUESTION FALSE
    SQL 'SELECT v.care_setting, COUNT(*) AS visit_count, ROUND(AVG(v.claim_value), 2) AS average_claim_per_visit FROM visits AS v GROUP BY 1 ORDER BY 3 DESC'
  ),
  vq_bmi_categories AS (
    QUESTION 'How many living adult patients are in each BMI category?'
    VERIFIED_AT 1792800000
    ONBOARDING_QUESTION TRUE
    SQL 'SELECT p.bmi_category, COUNT(DISTINCT p.PATIENT_NUMBER) AS patient_count FROM patients AS p WHERE NOT p.is_deceased AND p.age_in_years >= 18 GROUP BY 1 ORDER BY 2 DESC'
  ),
  vq_high_bp_rate AS (
    QUESTION 'What percentage of living patients have a high blood pressure reading?'
    VERIFIED_AT 1792800000
    ONBOARDING_QUESTION FALSE
    SQL 'SELECT ROUND(100 * COUNT_IF(p.systolic_value >= 140 OR p.diastolic_value >= 90) / NULLIF(COUNT(p.systolic_value), 0), 1) AS pct_high_bp_reading FROM patients AS p WHERE NOT p.is_deceased'
  ),
  vq_bmi_diabetic AS (
    QUESTION 'What is the average BMI of patients with type 2 diabetes?'
    VERIFIED_AT 1792800000
    ONBOARDING_QUESTION FALSE
    SQL 'SELECT ROUND(AVG(p.bmi_value), 1) AS average_bmi FROM patients AS p WHERE p.PATIENT_NUMBER IN (SELECT d.PATIENT_NUMBER FROM diagnoses AS d WHERE d.diagnosis_name ILIKE ''%diabetes mellitus type 2%'')'
  ),
  vq_flu_by_year AS (
    QUESTION 'How many patients received a flu vaccine each year?'
    VERIFIED_AT 1792800000
    ONBOARDING_QUESTION FALSE
    SQL 'SELECT v.vaccination_year, COUNT(DISTINCT v.PATIENT_NUMBER) AS patients_vaccinated FROM vaccinations AS v WHERE v.is_flu_vaccine GROUP BY 1 ORDER BY 1'
  ),
  vq_food_allergies AS (
    QUESTION 'What are the most common food allergies?'
    VERIFIED_AT 1792800000
    ONBOARDING_QUESTION FALSE
    SQL 'SELECT a.allergen_name, COUNT(DISTINCT a.PATIENT_NUMBER) AS patients_with_allergy FROM allergies AS a WHERE a.allergy_category = ''food'' GROUP BY 1 ORDER BY 2 DESC LIMIT 10'
  ),
  vq_readmission_by_year AS (
    QUESTION 'What is the 30-day readmission rate by year?'
    VERIFIED_AT 1792800000
    ONBOARDING_QUESTION TRUE
    SQL 'SELECT s.admission_year, COUNT(*) AS admission_count, ROUND(100 * COUNT_IF(s.is_readmitted) / COUNT(*), 1) AS readmission_rate_pct FROM hospital_stays AS s GROUP BY 1 ORDER BY 1'
  ),
  vq_open_claims AS (
    QUESTION 'How many claims are still open?'
    VERIFIED_AT 1792800000
    ONBOARDING_QUESTION FALSE
    SQL 'SELECT COUNT_IF(c.is_open_claim) AS open_claim_count, COUNT(*) AS claim_count, ROUND(100 * COUNT_IF(c.is_open_claim) / COUNT(*), 1) AS open_claim_rate_pct FROM claims AS c'
  ),
  vq_open_claims_by_insurer AS (
    QUESTION 'How many claims are still open, by insurer?'
    VERIFIED_AT 1792800000
    ONBOARDING_QUESTION FALSE
    SQL 'SELECT i.insurer_name, COUNT_IF(c.is_open_claim) AS open_claim_count FROM claims AS c JOIN visits AS v ON c.VISIT_NUMBER = v.VISIT_NUMBER JOIN insurers AS i ON v.INSURER_NUMBER = i.INSURER_NUMBER GROUP BY 1 ORDER BY 2 DESC'
  )
);