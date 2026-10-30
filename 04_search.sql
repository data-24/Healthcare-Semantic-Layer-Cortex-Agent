-- =====================================================================
-- 04 CORTEX SEARCH: a dictionary of every clinical term in the data,
-- so the agent can turn "peanuts" into the exact value "Peanut (substance)".
-- =====================================================================
USE SCHEMA {{DATABASE}}.{{SEARCH}};
ALTER WAREHOUSE {{WAREHOUSE}} SET WAREHOUSE_SIZE = 'MEDIUM';

CREATE OR REPLACE TABLE CLINICAL_TERMS COMMENT = 'Every distinct clinical term used in the data.' AS
          SELECT DISTINCT DIAGNOSIS_NAME   AS CLINICAL_TERM, 'diagnosis'    AS TERM_TYPE FROM {{DATABASE}}.{{ANALYTICS}}.DIAGNOSES     WHERE DIAGNOSIS_NAME IS NOT NULL
UNION ALL SELECT DISTINCT MEDICATION_NAME,                   'medication'                FROM {{DATABASE}}.{{ANALYTICS}}.PRESCRIPTIONS WHERE MEDICATION_NAME IS NOT NULL
UNION ALL SELECT DISTINCT PROCEDURE_NAME,                    'procedure'                 FROM {{DATABASE}}.{{ANALYTICS}}.PROCEDURES    WHERE PROCEDURE_NAME IS NOT NULL
UNION ALL SELECT DISTINCT MEASUREMENT_NAME,                  'measurement'               FROM {{DATABASE}}.{{ANALYTICS}}.OBSERVATIONS  WHERE MEASUREMENT_NAME IS NOT NULL
UNION ALL SELECT DISTINCT VACCINE_NAME,                      'vaccine'                   FROM {{DATABASE}}.{{ANALYTICS}}.VACCINATIONS  WHERE VACCINE_NAME IS NOT NULL
UNION ALL SELECT DISTINCT ALLERGEN_NAME,                     'allergen'                  FROM {{DATABASE}}.{{ANALYTICS}}.ALLERGIES     WHERE ALLERGEN_NAME IS NOT NULL
UNION ALL SELECT DISTINCT VISIT_TYPE,                        'visit_type'                FROM {{DATABASE}}.{{ANALYTICS}}.VISITS        WHERE VISIT_TYPE IS NOT NULL
UNION ALL SELECT DISTINCT VISIT_REASON,                      'visit_reason'              FROM {{DATABASE}}.{{ANALYTICS}}.VISITS        WHERE VISIT_REASON IS NOT NULL;

ALTER WAREHOUSE {{WAREHOUSE}} SET WAREHOUSE_SIZE = 'XSMALL';

CREATE OR REPLACE CORTEX SEARCH SERVICE {{SEARCH_SERVICE}}
  ON CLINICAL_TERM
  ATTRIBUTES TERM_TYPE
  WAREHOUSE = {{WAREHOUSE}}
  TARGET_LAG = '1 day'
  COMMENT = 'Finds the exact clinical term for everyday wording'
AS (SELECT CLINICAL_TERM, TERM_TYPE FROM CLINICAL_TERMS);


