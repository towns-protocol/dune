-- part of a query repo
-- query name: gross revenue over time
-- query link: https://dune.com/queries/4218906


with space_created AS (SELECT town_address AS space_address
                       FROM dune.towns_protocol.result_towns_created),
     member_added AS (SELECT town_address   AS space_address,
                             member_address AS space_member_address,
                             token_id       AS space_member_token_id,
                             tx_hash
                      FROM dune.towns_protocol.result_membership_subscriptions
                      WHERE event_type = 'mint'),
     spaces_with_num_members AS (SELECT space_address,
                                        COUNT(space_member_address) AS num_memberships
                                 FROM member_added
                                 GROUP BY space_address),
     space_traces AS (SELECT swm.space_address,
                             swm.num_memberships,
                             ef.block_time,
                             ef.value
                      FROM spaces_with_num_members swm
                               JOIN dune.towns_protocol.result_towns_eth_flows ef
                                    ON swm.space_address = ef.to
                      WHERE ef.flow_type = 'town_in'),
-- TODO: make sure only specific function calls are included
space_transactions AS (
    SELECT *
    FROM spaces_with_num_members
    INNER JOIN base.transactions ON spaces_with_num_members.space_address = base.transactions.to
    WHERE success = true AND value > 0
),
space_payments AS (
    SELECT space_address, block_time, value FROM space_traces
    UNION ALL
    SELECT space_address, block_time, value FROM space_transactions
),
-- Get current ETH price
current_eth_price AS (
    SELECT price as eth_price_usd
    FROM prices.usd
    WHERE blockchain = 'ethereum'
    AND contract_address = 0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2 -- WETH address
    ORDER BY minute DESC
    LIMIT 1
),
summary as (
    select
    date_trunc('day',block_time) as day,
    SUM(COALESCE(value, 0)) / 1e18 as daily_revenue_eth,
    SUM(COALESCE(value, 0)) / 1e18 * (SELECT eth_price_usd FROM current_eth_price) as daily_revenue_usd
    from space_payments
    group by 1
),
days AS (
    select cast(day as timestamp) as day
    from unnest(sequence(date('2024-05-30'), cast(now() as date), interval '1' day)) as t(day)
)
select
    d.day,
    s.daily_revenue_eth,
    s.daily_revenue_usd,
    sum(coalesce(daily_revenue_usd,0)) over (order by d.day) as total_revenue_usd
from days d
left join summary s on d.day = s.day
order by 1 desc
