-- =====================================================================
-- 09 AUDIT LOG: who asked the agent what, the answer, time and tokens.
--   AGENT_EVENTS_RAW            permanent copy of the agent's monitoring events
--                               (the agent's own history resets when it is re-created)
--   LOAD_AGENT_EVENTS           daily task that copies new events (no duplicates)
--   AGENT_CONVERSATION_HISTORY  one row per question
-- =====================================================================
USE SCHEMA {{DATABASE}}.{{GOVERNANCE}};

CREATE TABLE IF NOT EXISTS AGENT_EVENTS_RAW COMMENT = 'Permanent copy of agent monitoring events (audit trail)' AS
SELECT *, CURRENT_TIMESTAMP() AS LOADED_AT
FROM TABLE(SNOWFLAKE.LOCAL.GET_AI_OBSERVABILITY_EVENTS('{{DATABASE}}', '{{ANALYTICS}}', '{{AGENT}}', 'CORTEX AGENT'))
WHERE 1 = 0;

-- Re-reads the last 2 days so late events are not missed; NOT EXISTS stops duplicates
CREATE OR REPLACE TASK LOAD_AGENT_EVENTS
  WAREHOUSE = {{WAREHOUSE}}
  SCHEDULE = 'USING CRON 0 6 * * * Europe/London'
AS
INSERT INTO {{DATABASE}}.{{GOVERNANCE}}.AGENT_EVENTS_RAW
SELECT s.*, CURRENT_TIMESTAMP()
FROM TABLE(SNOWFLAKE.LOCAL.GET_AI_OBSERVABILITY_EVENTS('{{DATABASE}}', '{{ANALYTICS}}', '{{AGENT}}', 'CORTEX AGENT')) s
WHERE s.TIMESTAMP >= DATEADD('day', -2, (SELECT COALESCE(MAX(TIMESTAMP), '1970-01-01'::TIMESTAMP_NTZ)
                                         FROM {{DATABASE}}.{{GOVERNANCE}}.AGENT_EVENTS_RAW))
  AND NOT EXISTS (SELECT 1 FROM {{DATABASE}}.{{GOVERNANCE}}.AGENT_EVENTS_RAW t
                  WHERE t.TIMESTAMP = s.TIMESTAMP AND t.RECORD:name = s.RECORD:name
                    AND EQUAL_NULL(t.RECORD_ATTRIBUTES['snow.ai.observability.agent.message_id'],
                                   s.RECORD_ATTRIBUTES['snow.ai.observability.agent.message_id']));

ALTER TASK LOAD_AGENT_EVENTS RESUME;

CREATE OR REPLACE VIEW AGENT_CONVERSATION_HISTORY COMMENT = 'One row per agent question: who, when, question, answer, time, tokens' AS
WITH events AS (
  SELECT RECORD_ATTRIBUTES['snow.ai.observability.agent.message_id']::STRING AS turn_id,
         RECORD_ATTRIBUTES AS a, RESOURCE_ATTRIBUTES AS r,
         COALESCE(START_TIMESTAMP, TIMESTAMP) AS started_at, TIMESTAMP AS ended_at
  FROM AGENT_EVENTS_RAW
  WHERE RECORD_ATTRIBUTES['snow.ai.observability.agent.message_id'] IS NOT NULL
),
turns AS (
  SELECT turn_id,
         MIN(started_at) AS asked_at,
         ROUND(DATEDIFF('millisecond', MIN(started_at), MAX(ended_at)) / 1000, 1) AS latency_seconds,
         MAX(r['snow.user.name']::STRING) AS user_name,
         MAX(a['ai.observability.record_root.input']::STRING) AS question,
         MAX(a['ai.observability.record_root.output']::STRING) AS answer
  FROM events GROUP BY turn_id
),
tokens AS (   -- token counts are stored as attributes ending in token_count.input / .output / .total
  SELECT e.turn_id,
         MAX(IFF(f.key ILIKE '%token_count.input',  TRY_TO_NUMBER(f.value::STRING), NULL)) AS input_tokens,
         MAX(IFF(f.key ILIKE '%token_count.output', TRY_TO_NUMBER(f.value::STRING), NULL)) AS output_tokens,
         MAX(IFF(f.key ILIKE '%token_count.total',  TRY_TO_NUMBER(f.value::STRING), NULL)) AS total_tokens
  FROM events e, LATERAL FLATTEN(input => e.a) f
  WHERE f.key ILIKE '%token_count%'
  GROUP BY e.turn_id
)
SELECT t.turn_id, t.asked_at, t.user_name, t.question, t.answer, t.latency_seconds,
       k.input_tokens, k.output_tokens, k.total_tokens
FROM turns t LEFT JOIN tokens k ON k.turn_id = t.turn_id;