-- =====================================================================
-- 11 SNOWFLAKE INTELLIGENCE (optional): show the agent in Snowflake's own chat screen.
-- If this fails on your account, add the agent in Snowsight instead:
--   AI & ML -> Agents -> open the agent -> add it to Snowflake Intelligence.
-- =====================================================================
CREATE SNOWFLAKE INTELLIGENCE IF NOT EXISTS SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT;
GRANT USAGE ON SNOWFLAKE INTELLIGENCE SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT TO ROLE {{ANALYST_ROLE}};
ALTER SNOWFLAKE INTELLIGENCE SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT ADD AGENT {{DATABASE}}.{{ANALYTICS}}.{{AGENT}};