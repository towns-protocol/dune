-- part of a query repo
-- query name: protocol_treasury_income_per_space
-- query link: https://dune.com/queries/4218738

-- Protocol fee revenue per town (space)
SELECT ef."from"            AS space_address,
       SUM(ef.value / 1e18) AS income
FROM dune.towns_protocol.result_towns_eth_flows ef
WHERE ef.flow_type = 'protocol_fee'
  AND ef."from" IN (SELECT town_address FROM dune.towns_protocol.result_towns_created)
GROUP BY ef."from"
ORDER BY income DESC
