# =====================================================================
# config.py: every platform name in ONE place.
# The SQL files use these as {{NAME}}. Change a name here, run again, done.
# =====================================================================

# Snowflake edition: "ENTERPRISE" turns on masking policies (02b). Use "STANDARD" on a Standard account.
EDITION = "ENTERPRISE"

# Where the raw data comes from (read-only Marketplace share)
SOURCE = "SYNTHETIC_HEALTHCARE_DATA_CLINICAL_AND_CLAIMS.SILVER"
SOURCE_DATABASE = "SYNTHETIC_HEALTHCARE_DATA_CLINICAL_AND_CLAIMS"

# Where we build everything
DATABASE = "HEALTHCARE_INTELLIGENCE"
WAREHOUSE = "HEALTHCARE_INTELLIGENCE_WH"

# Schemas inside the database
ANALYTICS = "ANALYTICS"      # business views, semantic model, agent, app
SEARCH = "SEARCH"            # clinical dictionary + Cortex Search
MARTS = "MARTS"              # small KPI tables for the dashboard
GOVERNANCE = "GOVERNANCE"    # audit log, evaluation, app permissions (engineer only)

# Roles
ENGINEER_ROLE = "DATA_ENGINEER"          # sees real PII and governance data
ANALYST_ROLE = "DATA_ANALYST"            # PII masked
EXECUTIVE_ROLE = "HC_EXECUTIVE"          # app persona
CLINICAL_ROLE = "HC_CLINICAL_ANALYST"    # app persona
FINANCE_ROLE = "HC_FINANCE_ANALYST"      # app persona

# AI objects and the app
SEMANTIC_VIEW = "HEALTHCARE_SEMANTIC_MODEL"
SEARCH_SERVICE = "CLINICAL_TERMS_SEARCH"
AGENT = "HEALTHCARE_AGENT"
APP = "HEALTHCARE_APP"
AI_MODEL = "claude-sonnet-4-5"      # model used by AI_COMPLETE in the app
