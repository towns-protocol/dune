-- part of a query repo
-- query name: Tip Events
-- query link: https://dune.com/queries/5630852


-- Materialized Table: Extract all tip events with complete event data
-- Table: dune.towns_protocol.result_tip_events
-- This stores all tip events for consistent use across tipping analysis queries

WITH towns_created AS (SELECT town_address
                       FROM dune.towns_protocol.result_towns_created)

SELECT l.block_time,
       l.block_number,
       l.tx_hash,
       l.index,
       tc.town_address,
       bytearray_to_uint256(l.topic1)                         AS token_id,
       SUBSTRING(l.topic2 FROM 13)                            AS currency,
       SUBSTRING(l.data FROM 13 FOR 20)                       AS sender,
       SUBSTRING(l.data FROM 45 FOR 20)                       AS receiver,
       bytearray_to_uint256(SUBSTRING(l.data FROM 65 FOR 32)) AS amount,
       SUBSTRING(l.data FROM 97 FOR 32)                       AS message_id,
       SUBSTRING(l.data FROM 129 FOR 32)                      AS channel_id
FROM base.logs l
         JOIN towns_created tc ON l.contract_address = tc.town_address
WHERE
  -- Tip(uint256 indexed tokenId, address indexed currency, address sender, address receiver, uint256 amount, bytes32 messageId, bytes32 channelId)
    l.topic0 = 0x854db29cbd1986b670c0d596bf56847152a0d66e5ddef710408c1fa4ada78f2b
  AND l.block_time > CAST('2024-12-01' AS timestamp)
ORDER BY l.block_number DESC, l.tx_index DESC, l.index DESC;
