# =====================================================================
# run.py: runs the numbered SQL files in order.
#   1. reads a .sql file
#   2. replaces every {{NAME}} with the value from config.py
#   3. runs each statement in Snowflake
# =====================================================================
import os
import re

import config
from snowflake.snowpark.context import get_active_session

session = get_active_session()
FOLDER = os.path.dirname(os.path.abspath(__file__))

SQL_FILES = [
    "01_setup.sql",
    "02_business_views.sql",
    "02b_masking_policies.sql",        # Enterprise only: skipped when config.EDITION = "STANDARD"
    "03_derived_tables.sql",
    "04_search.sql",
    "05_semantic_view.sql",
    "06_agent.sql",
    "07_marts.sql",
    "08_evaluation.sql",
    "09_audit_log.sql",
    "10_security.sql",
    "11_snowflake_intelligence.sql",   # optional: allowed to fail
]


def fill_names(sql):
    """{{DATABASE}} -> HEALTHCARE_INTELLIGENCE, using config.py"""
    return re.sub(r"\{\{(\w+)\}\}", lambda m: getattr(config, m.group(1)), sql)


def split_statements(sql):
    """Split on ';' but not inside quotes, $$ blocks or -- comments."""
    statements, current, i = [], "", 0
    in_quote = in_dollar = False
    while i < len(sql):
        if not in_quote and sql.startswith("$$", i):
            in_dollar = not in_dollar
            current += "$$"; i += 2; continue
        ch = sql[i]
        if not in_quote and not in_dollar and sql.startswith("--", i):   # skip comment to end of line
            end = sql.find("\n", i)
            i = len(sql) if end == -1 else end
            continue
        if ch == "'" and not in_dollar:
            in_quote = not in_quote
        if ch == ";" and not in_quote and not in_dollar:
            if current.strip():
                statements.append(current.strip())
            current = ""
        else:
            current += ch
        i += 1
    if current.strip():
        statements.append(current.strip())
    return statements


def run(files=SQL_FILES):
    """Build everything. To run just some files: run(["05_semantic_view.sql", "06_agent.sql"])"""
    session.sql("USE ROLE ACCOUNTADMIN").collect()
    for file in files:
        if file.startswith("02b") and getattr(config, "EDITION", "STANDARD").upper() != "ENTERPRISE":
            print(f"⏭️  {file} skipped (masking policies need Enterprise edition)")
            continue
        sql = fill_names(open(os.path.join(FOLDER, file)).read())
        for statement in split_statements(sql):
            try:
                session.sql(statement).collect()
            except Exception as error:
                if file == "11_snowflake_intelligence.sql":
                    print(f"⚠️  {file} skipped (add the agent in Snowsight instead): {error}")
                    break
                print(f"❌ {file} failed on:\n{statement[:500]}\n\n{error}")
                raise
        else:
            print(f"✅ {file}")


def create_app():
    """Upload the app files and create the Streamlit app."""
    stage = f"{config.DATABASE}.{config.ANALYTICS}.APP_FILES"
    app = f"{config.DATABASE}.{config.ANALYTICS}.{config.APP}"
    session.sql(f"CREATE STAGE IF NOT EXISTS {stage} ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE')").collect()

    # environment.yml tells the warehouse runtime which packages the app needs
    with open("/tmp/environment.yml", "w") as f:
        f.write("name: app_environment\nchannels:\n  - snowflake\ndependencies:\n  - pandas\n")
    for path in [os.path.join(FOLDER, "streamlit_app.py"), os.path.join(FOLDER, "config.py"), "/tmp/environment.yml"]:
        session.file.put(path, f"@{stage}", auto_compress=False, overwrite=True)

    session.sql(f"""CREATE OR REPLACE STREAMLIT {app}
                    FROM '@{stage}'
                    MAIN_FILE = 'streamlit_app.py'
                    QUERY_WAREHOUSE = {config.WAREHOUSE}
                    RUNTIME_NAME = 'SYSTEM$WAREHOUSE_RUNTIME'
                    TITLE = 'Healthcare Intelligence'""").collect()
    session.sql(f"GRANT USAGE ON STREAMLIT {app} TO ROLE {config.ANALYST_ROLE}").collect()
    print(f"✅ app created: Projects -> Streamlit -> Healthcare Intelligence")


def run_evaluation():
    """Ask the agent the 13 test questions and show the score (5-10 minutes)."""
    gov = f"{config.DATABASE}.{config.GOVERNANCE}"
    session.sql(f"USE WAREHOUSE {config.WAREHOUSE}").collect()
    session.sql(f"CALL {gov}.RUN_AGENT_EVAL()").collect()
    return session.sql(f"""SELECT question_id, result, reason, LEFT(answer_text, 120) AS answer
                           FROM {gov}.EVAL_SCORECARD
                           WHERE run_id = (SELECT run_id FROM {gov}.EVAL_RESULTS ORDER BY started_at DESC LIMIT 1)
                           ORDER BY question_id""").to_pandas()
