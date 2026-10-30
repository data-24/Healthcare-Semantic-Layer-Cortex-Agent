-- =====================================================================
-- 10 SECURITY: who can see what
--   Analyst (and the 3 personas): business views, marts, semantic model, search, agent. PII masked.
--   Engineer: everything above + raw share + GOVERNANCE (audit log, evaluation).
--   App: which TABS and CHARTS each role sees (deny by default).
-- =====================================================================

-- Analyst baseline (personas and engineer inherit this)
GRANT USAGE ON WAREHOUSE {{WAREHOUSE}} TO ROLE {{ANALYST_ROLE}};
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE {{ANALYST_ROLE}};
GRANT USAGE ON DATABASE {{DATABASE}} TO ROLE {{ANALYST_ROLE}};
GRANT USAGE ON SCHEMA {{DATABASE}}.{{ANALYTICS}} TO ROLE {{ANALYST_ROLE}};
GRANT USAGE ON SCHEMA {{DATABASE}}.{{SEARCH}} TO ROLE {{ANALYST_ROLE}};
GRANT USAGE ON SCHEMA {{DATABASE}}.{{MARTS}} TO ROLE {{ANALYST_ROLE}};
GRANT SELECT ON ALL VIEWS  IN SCHEMA {{DATABASE}}.{{ANALYTICS}} TO ROLE {{ANALYST_ROLE}};
GRANT SELECT ON ALL TABLES IN SCHEMA {{DATABASE}}.{{ANALYTICS}} TO ROLE {{ANALYST_ROLE}};
GRANT SELECT ON ALL TABLES IN SCHEMA {{DATABASE}}.{{MARTS}} TO ROLE {{ANALYST_ROLE}};
GRANT SELECT ON SEMANTIC VIEW {{DATABASE}}.{{ANALYTICS}}.{{SEMANTIC_VIEW}} TO ROLE {{ANALYST_ROLE}};
GRANT USAGE ON CORTEX SEARCH SERVICE {{DATABASE}}.{{SEARCH}}.{{SEARCH_SERVICE}} TO ROLE {{ANALYST_ROLE}};
GRANT USAGE ON AGENT {{DATABASE}}.{{ANALYTICS}}.{{AGENT}} TO ROLE {{ANALYST_ROLE}};

-- Engineer only
GRANT IMPORTED PRIVILEGES ON DATABASE {{SOURCE_DATABASE}} TO ROLE {{ENGINEER_ROLE}};
GRANT USAGE ON SCHEMA {{DATABASE}}.{{GOVERNANCE}} TO ROLE {{ENGINEER_ROLE}};
GRANT SELECT ON ALL TABLES IN SCHEMA {{DATABASE}}.{{GOVERNANCE}} TO ROLE {{ENGINEER_ROLE}};
GRANT SELECT ON ALL VIEWS  IN SCHEMA {{DATABASE}}.{{GOVERNANCE}} TO ROLE {{ENGINEER_ROLE}};
GRANT MONITOR ON AGENT {{DATABASE}}.{{ANALYTICS}}.{{AGENT}} TO ROLE {{ENGINEER_ROLE}};

USE SCHEMA {{DATABASE}}.{{GOVERNANCE}};

-- Which role sees which tab / chart in the app
CREATE OR REPLACE TABLE APP_ROLE_PERMISSIONS (role_name STRING, permission STRING)
  COMMENT = 'Tab and chart access per role for the Streamlit app. Deny by default.';
INSERT INTO APP_ROLE_PERMISSIONS VALUES
  ('{{EXECUTIVE_ROLE}}', 'TAB.OVERVIEW'), ('{{EXECUTIVE_ROLE}}', 'CHART.COST'), ('{{EXECUTIVE_ROLE}}', 'TAB.CLAIMS_COST'),
  ('{{EXECUTIVE_ROLE}}', 'TAB.AI_INSIGHTS'),
  ('{{CLINICAL_ROLE}}', 'TAB.OVERVIEW'), ('{{CLINICAL_ROLE}}', 'TAB.CLINICAL'), ('{{CLINICAL_ROLE}}', 'TAB.HOSPITAL'),
  ('{{CLINICAL_ROLE}}', 'TAB.PHARMACY_VACCINES'), ('{{CLINICAL_ROLE}}', 'TAB.AI_INSIGHTS'),
  ('{{FINANCE_ROLE}}', 'TAB.OVERVIEW'), ('{{FINANCE_ROLE}}', 'CHART.COST'), ('{{FINANCE_ROLE}}', 'TAB.CLAIMS_COST'),
  ('{{FINANCE_ROLE}}', 'TAB.PHARMACY_VACCINES'), ('{{FINANCE_ROLE}}', 'TAB.AI_INSIGHTS'),
  ('{{ANALYST_ROLE}}', 'TAB.OVERVIEW'), ('{{ANALYST_ROLE}}', 'TAB.CLINICAL'), ('{{ANALYST_ROLE}}', 'TAB.HOSPITAL'),
  ('{{ANALYST_ROLE}}', 'TAB.PHARMACY_VACCINES'), ('{{ANALYST_ROLE}}', 'TAB.AI_INSIGHTS'),
  ('{{ENGINEER_ROLE}}', 'TAB.OVERVIEW'), ('{{ENGINEER_ROLE}}', 'CHART.COST'), ('{{ENGINEER_ROLE}}', 'TAB.CLINICAL'),
  ('{{ENGINEER_ROLE}}', 'TAB.HOSPITAL'), ('{{ENGINEER_ROLE}}', 'TAB.PHARMACY_VACCINES'), ('{{ENGINEER_ROLE}}', 'TAB.CLAIMS_COST'),
  ('{{ENGINEER_ROLE}}', 'TAB.AI_INSIGHTS'), ('{{ENGINEER_ROLE}}', 'TAB.GOVERNANCE'), ('{{ENGINEER_ROLE}}', 'TAB.QUALITY'),
  -- Patient lookup tab + how much personal data each role sees in it (no PII.* row = everything masked)
  ('{{ENGINEER_ROLE}}', 'TAB.PATIENTS'), ('{{ENGINEER_ROLE}}', 'PII.FULL'),
  ('{{CLINICAL_ROLE}}', 'TAB.PATIENTS'), ('{{CLINICAL_ROLE}}', 'PII.PARTIAL'),
  ('{{ANALYST_ROLE}}', 'TAB.PATIENTS');

-- Which user may use which role in the app
-- (the app runs with its owner's rights, where SHOW GRANTS can be blocked, so it reads this list)
CREATE OR REPLACE TABLE APP_USER_ROLES (user_name STRING, app_role STRING)
  COMMENT = 'Which user may use which role in the app';
INSERT INTO APP_USER_ROLES
  SELECT CURRENT_USER(), column1
  FROM VALUES ('{{ENGINEER_ROLE}}'), ('{{ANALYST_ROLE}}'), ('{{EXECUTIVE_ROLE}}'), ('{{CLINICAL_ROLE}}'), ('{{FINANCE_ROLE}}');

-- Questions asked in the app, stored ALREADY redacted by AI_REDACT
CREATE TABLE IF NOT EXISTS APP_QUESTION_LOG (
  asked_at TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP(), viewer_name STRING, persona_role STRING,
  question STRING, pii_removed BOOLEAN, answer STRING, latency_seconds FLOAT
) COMMENT = 'Questions asked through the app (already redacted)';
ALTER TABLE APP_QUESTION_LOG ADD COLUMN IF NOT EXISTS topic STRING COMMENT 'Question topic from AI_CLASSIFY';

-- Feedback users give on agent answers, with the sentiment found by AI_SENTIMENT
CREATE TABLE IF NOT EXISTS APP_ANSWER_FEEDBACK (
  given_at TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP(), viewer_name STRING, persona_role STRING,
  question STRING, feedback STRING, sentiment STRING
) COMMENT = 'Feedback on agent answers (already redacted) with AI_SENTIMENT result';