-- measure-baseline.sql
-- What: tokens of the FIRST step of a main session with >=5 steps.
-- Why:  the first step includes instructions + tool schemas, so it is the
--       honest price of the configuration.
-- Cache: `input` is uncached only. Use `total` or `input + cache_read`.
-- How:  run read-only on a COPY of your session database (or use mode=ro).
--
-- Expected: sid | created_utc | steps | input | cache_read | total | model

WITH sf AS (
  SELECT session_id, data, time_created, id
  FROM part
  WHERE json_extract(data, '$.type') = 'step-finish'
),
agg AS (
  SELECT session_id, COUNT(*) AS steps
  FROM sf
  GROUP BY session_id
),
fs AS (
  SELECT session_id, data,
         ROW_NUMBER() OVER (PARTITION BY session_id ORDER BY time_created, id) AS rn
  FROM sf
)
SELECT
  substr(s.id, 5, 8)                                       AS sid,
  datetime(s.time_created / 1000, 'unixepoch')             AS created_utc,
  a.steps                                                  AS steps,
  CAST(json_extract(fs.data, '$.tokens.input') AS INTEGER) AS input,
  CAST(json_extract(fs.data, '$.tokens.cache.read') AS INTEGER) AS cache_read,
  CAST(json_extract(fs.data, '$.tokens.total') AS INTEGER) AS total,
  json_extract(s.model, '$.providerID') || '/' ||
  json_extract(s.model, '$.id')                            AS model
FROM session s
JOIN agg a  ON a.session_id = s.id
JOIN fs     ON fs.session_id = s.id AND fs.rn = 1
WHERE s.parent_id IS NULL
  AND a.steps >= 5
ORDER BY s.time_created DESC
LIMIT 10;

-- Reading the result:
--   Compare only runs with the SAME main-agent tool set and the SAME model.
--   A drop in `total` with an unchanged eval score = a good optimization.
--   A drop in `total` with a worse eval score = you economized on knowledge.
