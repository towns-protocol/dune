-- part of a query repo
-- query name: Compare Tip Events vs Tip Traces
-- query link: https://dune.com/queries/5626819


-- Validation Query: Compare Tip Events vs Tip Traces
-- Verifies that function selector filtering correctly matches tip events with ETH traces
-- Used to validate the accuracy of vulnerability analysis filtering logic

-- Extract all Tip events for native ETH from materialized table
WITH tip_events AS (SELECT block_time,
                           block_number,
                           tx_hash,
                           town_address,
                           sender,
                           amount AS tip_amount_wei
                    FROM dune.towns_protocol.result_tip_events
                    WHERE currency = 0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
                      AND amount > 0),

-- Get ETH traces from materialized table (pre-filtered with function selectors)
     tip_traces AS (SELECT t.block_time,
                           t.block_number,
                           t.tx_hash,
                           t.sender,
                           t.town_address,
                           t.value AS msg_value_wei,
                           t.function_selector
                    FROM dune.towns_protocol.result_tip_traces t),

-- Count summary
     counts_summary AS (SELECT (SELECT COUNT(*) FROM tip_events)                AS total_tip_events,
                               (SELECT COUNT(*) FROM tip_traces)                AS total_tip_traces,
                               (SELECT COUNT(DISTINCT tx_hash) FROM tip_events) AS distinct_event_txs,
                               (SELECT COUNT(DISTINCT tx_hash) FROM tip_traces) AS distinct_trace_txs),

-- Events without matching traces
     events_without_traces AS (SELECT te.tx_hash,
                                      te.town_address,
                                      te.block_time,
                                      te.tip_amount_wei / 1e18 AS tip_amount_eth,
                                      'EVENT_NO_TRACE'         AS mismatch_type
                               FROM tip_events te
                                        LEFT JOIN tip_traces tt
                                                  ON te.tx_hash = tt.tx_hash
                                                      AND te.town_address = tt.town_address
                                                      AND te.sender = tt.sender
                               WHERE tt.tx_hash IS NULL),

-- Traces without matching events
     traces_without_events AS (SELECT tt.tx_hash,
                                      tt.town_address,
                                      tt.block_time,
                                      tt.msg_value_wei / 1e18 AS msg_value_eth,
                                      tt.function_selector,
                                      'TRACE_NO_EVENT'        AS mismatch_type
                               FROM tip_traces tt
                                        LEFT JOIN tip_events te
                                                  ON tt.tx_hash = te.tx_hash
                                                      AND tt.town_address = te.town_address
                                                      AND tt.sender = te.sender
                               WHERE te.tx_hash IS NULL),

-- Transaction-level analysis
     tx_level_analysis AS (SELECT COALESCE(te.tx_hash, tt.tx_hash)           AS tx_hash,
                                  COALESCE(te.town_address, tt.town_address) AS town_address,
                                  COUNT(te.tx_hash)                          AS event_count,
                                  COUNT(tt.tx_hash)                          AS trace_count,
                                  SUM(te.tip_amount_wei / 1e18)              AS total_event_eth,
                                  SUM(tt.msg_value_wei / 1e18)               AS total_trace_eth,
                                  (CASE
                                       WHEN COUNT(te.tx_hash) = COUNT(tt.tx_hash) AND COUNT(te.tx_hash) > 0 THEN 'MATCH'
                                       WHEN COUNT(te.tx_hash) > COUNT(tt.tx_hash) THEN 'MORE_EVENTS'
                                       WHEN COUNT(te.tx_hash) < COUNT(tt.tx_hash) THEN 'MORE_TRACES'
                                       ELSE 'NO_DATA'
                                      END)                                   AS match_status
                           FROM tip_events te
                                    FULL OUTER JOIN tip_traces tt
                                                    ON te.tx_hash = tt.tx_hash
                                                        AND te.town_address = tt.town_address
                                                        AND te.sender = tt.sender
                           GROUP BY COALESCE(te.tx_hash, tt.tx_hash), COALESCE(te.town_address, tt.town_address))

-- Combined validation report
SELECT 'SUMMARY'      AS report_type,
       'Total Events' AS metric,
       CAST(total_tip_events AS VARCHAR) AS value,
       'Total tip events found' AS description,
       0 AS sample_order
FROM counts_summary

UNION ALL

SELECT 'SUMMARY'      AS report_type,
       'Total Traces' AS metric,
       CAST(total_tip_traces AS VARCHAR) AS value,
       'Total tip traces with function selectors' AS description,
       0 AS sample_order
FROM counts_summary

UNION ALL

SELECT 'SUMMARY'            AS report_type,
       'Event Transactions' AS metric,
       CAST(distinct_event_txs AS VARCHAR) AS value,
       'Distinct transactions with tip events' AS description,
       0 AS sample_order
FROM counts_summary

UNION ALL

SELECT 'SUMMARY'            AS report_type,
       'Trace Transactions' AS metric,
       CAST(distinct_trace_txs AS VARCHAR) AS value,
       'Distinct transactions with tip traces' AS description,
       0 AS sample_order
FROM counts_summary

UNION ALL

SELECT 'SUMMARY'    AS report_type,
       'Match Rate' AS metric,
       CAST(ROUND(
               (CASE
                    WHEN total_tip_events > 0
                        THEN (total_tip_traces * 100.0 / total_tip_events)
                    ELSE 0
                   END), 2
            ) AS VARCHAR) || '%' AS value,
       'Percentage of events with matching traces' AS description,
       0 AS sample_order
FROM counts_summary

UNION ALL

SELECT 'MISMATCH'              AS report_type,
       'Events Without Traces' AS metric,
       CAST(COUNT(*) AS VARCHAR) AS value,
       'Tip events with no matching ETH traces' AS description,
       0 AS sample_order
FROM events_without_traces

UNION ALL

SELECT 'MISMATCH'              AS report_type,
       'Traces Without Events' AS metric,
       CAST(COUNT(*) AS VARCHAR) AS value,
       'ETH traces with no matching tip events' AS description,
       0 AS sample_order
FROM traces_without_events

UNION ALL

SELECT 'TX_ANALYSIS' AS report_type,
       match_status  AS metric,
       CAST(COUNT(*) AS VARCHAR) AS value,
       'Transactions by match status' AS description,
       0 AS sample_order
FROM tx_level_analysis
GROUP BY match_status

UNION ALL

-- Sample mismatched events (limited in outer query)
SELECT 'SAMPLE_EVENT_NO_TRACE'  AS report_type,
       CAST(tx_hash AS VARCHAR) AS metric,
       CAST(town_address AS VARCHAR) || ' | ' || CAST(tip_amount_eth AS VARCHAR) || ' ETH' AS value,
       'Sample tip event without matching trace' AS description,
       1 AS sample_order
FROM events_without_traces

UNION ALL

-- Sample mismatched traces (limited in outer query)
SELECT 'SAMPLE_TRACE_NO_EVENT'  AS report_type,
       CAST(tx_hash AS VARCHAR) AS metric,
       CAST(town_address AS VARCHAR) || ' | ' || CAST(msg_value_eth AS VARCHAR) || ' ETH | ' ||
       CAST(function_selector AS VARCHAR) AS value,
       'Sample tip trace without matching event' AS description,
       2 AS sample_order
FROM traces_without_events

ORDER BY
    report_type,
    CASE metric
    WHEN 'Total Events' THEN 1
    WHEN 'Total Traces' THEN 2
    WHEN 'Event Transactions' THEN 3
    WHEN 'Trace Transactions' THEN 4
    WHEN 'Match Rate' THEN 5
    ELSE 6
END;
