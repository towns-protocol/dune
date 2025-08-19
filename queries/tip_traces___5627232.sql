-- part of a query repo
-- query name: Tip Traces
-- query link: https://dune.com/queries/5627232


-- Materialized Table: Extract tip traces with function selector filtering
-- Table: dune.towns_protocol.result_tip_traces
-- This eliminates duplication across tipping analysis queries

WITH towns_created AS (SELECT town_address
                       FROM dune.towns_protocol.result_towns_created)

SELECT t.block_time,
       t.block_number,
       t.tx_hash,
       t."from"                        AS sender,
       t.to                            AS town_address,
       t.value,
       SUBSTRING(t.input FROM 1 FOR 4) AS function_selector
FROM base.traces t
WHERE t.block_date >= DATE '2024-12-01'
  AND t.success
  AND t.call_type = 'call'
  AND t.value > 0
  AND t.to IN (SELECT town_address FROM towns_created)
  AND SUBSTRING(t.input FROM 1 FOR 4) IN (0x89b10db8, 0xc46be00e)
