-- part of a query repo
-- query name: Membership Subscriptions
-- query link: https://dune.com/queries/5521952
-- materialized table: dune.towns_protocol.result_membership_subscriptions

WITH towns_created AS (SELECT town_address
                       FROM dune.towns_protocol.result_towns_created),

-- MembershipTokenIssued events
     membership_mints AS (SELECT l.contract_address             AS town_address,
                                 l.tx_hash,
                                 l.block_time,
                                 l.block_number,
                                 l.tx_index,
                                 l.index                        AS log_index,
                                 substring(l.topic1 FROM 13)    AS member_address,
                                 bytearray_to_uint256(l.topic2) AS token_id,
                                 'mint'                         AS event_type
                          FROM base.logs l
                                   JOIN towns_created tc ON l.contract_address = tc.town_address
                          -- MembershipTokenIssued(address indexed recipient, uint256 indexed tokenId)
                          WHERE l.topic0 = 0x2f40b0474996b72a4251e00fb9170cdd960deea1dc749772cbbab61395b9b576
                            AND l.block_date >= DATE '2024-05-31'),

-- SubscriptionUpdate events
     subscription_updates AS (SELECT l.contract_address                                    AS town_address,
                                     l.tx_hash,
                                     l.block_time,
                                     l.block_number,
                                     l.tx_index,
                                     l.index                                               AS log_index,
                                     bytearray_to_uint256(l.topic1)                        AS token_id,
                                     bytearray_to_uint256(substring(l.data FROM 1 FOR 32)) AS expiration
                              FROM base.logs l
                                       JOIN towns_created tc ON l.contract_address = tc.town_address
                              -- SubscriptionUpdate(uint256 indexed tokenId, uint64 expiration)
                              WHERE l.topic0 = 0x2ec2be2c4b90c2cf13ecb6751a24daed6bb741ae5ed3f7371aabf9402f6d62e8
                                AND l.block_date >= DATE '2024-05-31'),

-- Mints with expiration data
     mint_events AS (SELECT mm.block_time,
                            mm.block_number,
                            mm.tx_index,
                            mm.event_type,
                            mm.town_address,
                            mm.token_id,
                            mm.member_address,
                            su.expiration,
                            mm.tx_hash,
                            mm.log_index
                     FROM membership_mints mm
                              JOIN subscription_updates su
                                   ON mm.tx_hash = su.tx_hash
                                       AND mm.token_id = su.token_id
                                       AND mm.town_address = su.town_address),

-- Renewals only (no corresponding mint)
     renewal_events AS (SELECT su.block_time,
                               su.block_number,
                               su.tx_index,
                               'renewal' AS event_type,
                               su.town_address,
                               su.token_id,
                               NULL      AS member_address, -- Unknown from renewal events
                               su.expiration,
                               su.tx_hash,
                               su.log_index
                        FROM subscription_updates su
                                 LEFT JOIN membership_mints mm
                                           ON su.tx_hash = mm.tx_hash
                                               AND su.token_id = mm.token_id
                                               AND su.town_address = mm.town_address
                        WHERE mm.tx_hash IS NULL),

-- All subscription events
     all_subscription_events AS (SELECT *
                                 FROM mint_events
                                 UNION ALL
                                 SELECT *
                                 FROM renewal_events)

SELECT block_time,
       block_number,
       event_type,
       town_address,
       token_id,
       member_address,
       expiration,
       tx_hash,
       tx_index,
       log_index
FROM all_subscription_events
