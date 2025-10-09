-- part of a query repo
-- query name: Campaign 250
-- query link: https://dune.com/queries/5935527


-- Snapshot Query: Top 250 Staked Towns and User Stakes
-- Timestamp: 1759775762 (Mon Oct 06 2025 18:36:02 GMT+0000)
-- Finds the top 250 towns by voting power at snapshot, then shows all users staking to those towns

WITH snapshot_timestamp AS (SELECT CAST(FROM_UNIXTIME(1759775762) AS timestamp) AS cutoff_time),

-- Proxy addresses (static, doesn't change over time)
     proxy_addresses AS (SELECT DISTINCT proxy_address
                         FROM dune.towns_protocol.result_delegation_proxies),

-- Proxy balances at snapshot - recalculate from Transfer events
     proxy_transfers_snapshot AS (SELECT bytearray_to_uint256(l.data) AS amount,
                                         CASE
                                             WHEN substring(l.topic1 FROM 13) IN
                                                  (SELECT proxy_address FROM proxy_addresses)
                                                 THEN substring(l.topic1 FROM 13)
                                             ELSE substring(l.topic2 FROM 13)
                                             END                      AS proxy_address,
                                         CASE
                                             WHEN substring(l.topic1 FROM 13) IN
                                                  (SELECT proxy_address FROM proxy_addresses)
                                                 THEN 'outflow'
                                             ELSE 'inflow'
                                             END                      AS flow_type
                                  FROM base.logs l
                                           CROSS JOIN snapshot_timestamp st
                                  WHERE l.contract_address = 0x00000000A22C618fd6b4D7E9A335C4B96B189a38    -- TOWNS token
                                    AND l.topic0 =
                                        0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef -- Transfer
                                    AND l.block_date >= DATE '2024-12-17'
                                    AND l.block_time <= st.cutoff_time
                                    AND (substring(l.topic1 FROM 13) IN (SELECT proxy_address FROM proxy_addresses)
                                      OR substring(l.topic2 FROM 13) IN (SELECT proxy_address FROM proxy_addresses))),

     proxy_balances_snapshot AS (SELECT proxy_address,
                                        (SUM(CASE WHEN flow_type = 'inflow' THEN amount ELSE 0 END) -
                                         SUM(CASE WHEN flow_type = 'outflow' THEN amount ELSE 0 END)) AS current_balance
                                 FROM proxy_transfers_snapshot
                                 GROUP BY proxy_address),

-- Proxy delegations at snapshot - get latest delegation state before cutoff
     delegation_changes_snapshot AS (SELECT substring(l.topic1 FROM 13) AS delegator,
                                            substring(l.topic3 FROM 13) AS to_delegate,
                                            ROW_NUMBER()                   OVER (
            PARTITION BY substring(l.topic1 FROM 13)
            ORDER BY l.block_number DESC, l.tx_index DESC, l.index DESC
        ) AS rn
                                     FROM base.logs l
                                              CROSS JOIN snapshot_timestamp st
                                              JOIN proxy_addresses pa ON substring(l.topic1 FROM 13) = pa.proxy_address
                                     WHERE l.contract_address = 0x00000000A22C618fd6b4D7E9A335C4B96B189a38    -- TOWNS token
                                       AND l.topic0 =
                                           0x3134e8a2e6d97e929a7e54011ea5485d7d196dd5f0ba4d4ef95803e8e3fc257f -- DelegateChanged
                                       AND l.block_date >= DATE '2024-12-17'
                                       AND l.block_time <= st.cutoff_time),

     proxy_delegations_snapshot AS (SELECT delegator AS proxy_address,
                                           to_delegate
                                    FROM delegation_changes_snapshot
                                    WHERE rn = 1 -- Latest delegation state only
     ),

-- Get voting power at snapshot - using DelegateVotesChanged events
     latest_voting_power_snapshot AS (SELECT substring(l.topic1 FROM 13)                            AS delegate,
                                             bytearray_to_uint256(substring(l.data FROM 33 FOR 32)) AS new_votes,
                                             ROW_NUMBER()                                              OVER (
            PARTITION BY substring(l.topic1 FROM 13)
            ORDER BY l.block_number DESC, l.tx_index DESC, l.index DESC
        ) AS rn
                                      FROM base.logs l
                                               CROSS JOIN snapshot_timestamp st
                                      WHERE l.contract_address = 0x00000000A22C618fd6b4D7E9A335C4B96B189a38    -- TOWNS token
                                        AND l.topic0 =
                                            0xdec2bacdd2f05b59de34da9b523dff8be42e5e38e818c82fdb0bae774387a724 -- DelegateVotesChanged
                                        AND l.block_date >= DATE '2024-12-17'
                                        AND l.block_time <= st.cutoff_time),

     voting_power_snapshot AS (SELECT delegate,
                                      new_votes / 1e18 AS current_voting_power
                               FROM latest_voting_power_snapshot
                               WHERE rn = 1
                                 AND new_votes > 0),

-- Top 250 towns by voting power
     top_250_towns AS (SELECT tc.town_address,
                              vp.current_voting_power,
                              RANK() OVER (ORDER BY vp.current_voting_power DESC) AS rank_by_voting_power
                       FROM dune.towns_protocol.result_towns_created tc
                                INNER JOIN voting_power_snapshot vp ON tc.town_address = vp.delegate
                       ORDER BY vp.current_voting_power DESC
    LIMIT 250
    ),

-- Get all users staking to the top 250 towns
    user_stakes_to_towns AS (
SELECT
    dp.owner AS user_wallet, pd.to_delegate AS town_address, COUNT (DISTINCT dp.proxy_address) AS proxy_count, SUM (COALESCE (pb.current_balance, 0) / 1e18) AS total_staked_amount
FROM dune.towns_protocol.result_delegation_proxies dp
    LEFT JOIN proxy_balances_snapshot pb
ON dp.proxy_address = pb.proxy_address
    LEFT JOIN proxy_delegations_snapshot pd ON dp.proxy_address = pd.proxy_address
WHERE pd.to_delegate IN (SELECT town_address FROM top_250_towns)
  AND pb.current_balance
    > 0
GROUP BY dp.owner, pd.to_delegate
    )

SELECT t250.rank_by_voting_power                                           AS town_rank,
       ust.town_address,
       ust.user_wallet,
       ROUND(ust.total_staked_amount, 2)                                   AS user_staked_to_town,
       ROUND(t250.current_voting_power, 2)                                 AS town_total_voting_power,
       ust.proxy_count                                                     AS user_proxy_count,
       ROUND(ust.total_staked_amount / t250.current_voting_power * 100, 2) AS percentage_of_town_power
FROM user_stakes_to_towns ust
         INNER JOIN top_250_towns t250 ON ust.town_address = t250.town_address
ORDER BY t250.rank_by_voting_power, ust.total_staked_amount DESC;
