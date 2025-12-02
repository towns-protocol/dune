-- part of a query repo
-- query name: town_tip_leaderboard
-- query link: https://dune.com/queries/4843552

-- Top 100 tippers per town by total amount tipped
WITH aggregated_tips AS (SELECT sender       AS user_address,
                                town_address AS space_address,
                                SUM(amount)  AS total_tipped_wei
                         FROM dune.towns_protocol.result_tip_events
                         GROUP BY sender, town_address),
     ranked_tippers AS (SELECT *,
                               ROW_NUMBER() OVER (
                                   PARTITION BY space_address
                                   ORDER BY total_tipped_wei DESC
                                   ) AS tip_rank
                        FROM aggregated_tips)

SELECT user_address,
       space_address,
       total_tipped_wei
FROM ranked_tippers
WHERE tip_rank <= 100
