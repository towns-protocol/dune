# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Purpose

This is a Dune Analytics query management repository for analyzing the Towns Protocol. It synchronizes SQL queries
between local files and the Dune platform, with automated workflows for deployment.

## Key Commands

### Setup

```bash
# Install dependencies (use uv if available)
pip install -r requirements.txt
# or: uv pip install -r requirements.txt

# Environment setup required: DUNE_API_KEY in .env file
```

### Core Query Management

```bash
# Download queries from Dune (based on queries.yml)
python scripts/pull_from_dune.py

# Upload local query changes to Dune
python scripts/push_to_dune.py  

# Upload CSV files as Dune tables
python scripts/upload_to_dune.py

# Preview query results (uses API credits)
python scripts/preview_query.py <query_id>
```

### With uv

```bash
uv run python scripts/pull_from_dune.py
uv run python scripts/push_to_dune.py
uv run python scripts/upload_to_dune.py  
uv run python scripts/preview_query.py <query_id>
```

## Architecture

### File Structure

- `queries.yml` - Central configuration with query IDs (keep sorted numerically)
- `queries/` - SQL files with naming: `{name}___{query_id}.sql`
- `scripts/` - Python automation scripts for Dune sync
- `uploads/` - CSV files for Dune table creation
- `.github/workflows/` - Automated deployment on push to main

### Query Management Flow

1. **Adding Queries**: Create in Dune app → Add ID to `queries.yml` → Run `pull_from_dune.py`
2. **Editing Queries**: Modify local SQL files → Commit to main → Auto-sync via GitHub Actions
3. **File Naming**: NEVER change the `___<query_id>.sql` suffix or scripts will break

### Critical File Naming Convention

Query files must follow: `{descriptive_name}___{query_id}.sql`

- The `___<query_id>.sql` suffix is required for script functionality
- Example: `membership_revenue___5410943.sql`

### Query File Headers

Each SQL file contains standardized metadata:

```sql
-- part of a query repo
-- query name: {Query Name}  
-- query link: https://dune.com/queries/{query_id}
```

## Important Constraints

- Queries must be owned by the team associated with the API key
- DUNE_API_KEY requires Plus plan
- Query previews consume Dune API credits
- GitHub Actions auto-deploy changes to `queries/**` and `uploads/**` on main branch commits
- Query version history available in Dune app for rollbacks if needed

## Query Categories

This repository manages Towns Protocol analytics across:

- Membership (subscriptions, revenue)
- Staking (events, flows, delegation)
- Governance (voting, proxies)
- Revenue (protocol fees, tipping)
- Airdrops (claims, statistics)
- General protocol metrics

## Dune SQL Coding Patterns

### Table Naming Conventions

- Raw blockchain data: `[blockchain].[table_type]` (e.g., `base.logs`, `base.traces`)
- Materialized tables: `dune.[project_namespace].result_[table_name]`
- Example: `dune.towns_protocol.result_towns_created`

### Common Dune Functions

```sql
bytearray_to_uint256(field)        -- Convert bytes to uint256
bytearray_to_int256(field)         -- Convert bytes to int256
SUBSTRING(topic1 FROM 13)          -- Extract address from topic (remove first 12 bytes)
SUBSTRING(l.data FROM 1 FOR 32)    -- Extract first 32 bytes of data
```

### Event Processing Patterns

```sql
-- Standard event filtering
FROM base.logs l
WHERE l.contract_address = 0x[CONTRACT_ADDRESS]
  AND l.topic0 = 0x[EVENT_SIGNATURE_HASH]
  AND l.block_time > CAST('YYYY-MM-DD' AS timestamp)

-- Multi-event filtering
AND l.topic0 IN (0x[SIG1], 0x[SIG2], 0x[SIG3])
```

### ETH Amount Handling

```sql
amount / 1e18 AS eth_amount        -- Wei to ETH conversion
-- ETH placeholder address: 0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee

-- CRITICAL: Always divide before aggregating to prevent uint256 overflow
SUM(amount / 1e18) AS total_eth    -- ✅ Correct: divide first, then sum
SUM(amount) / 1e18 AS total_eth    -- ❌ Wrong: can overflow on large sums
```

### Date Patterns

```sql
-- Date range generation
SELECT CAST(day AS timestamp) AS day
FROM unnest(sequence (DATE ('2024-05-30'), CURRENT_DATE, INTERVAL '1' day)) AS t(day)

-- Date truncation for aggregation
DATE_TRUNC('day', block_time) AS day
```

### Performance Optimization

- Prefer materialized `result_*` tables over raw log parsing
- Always include time-based filtering: `block_time > CAST('date' AS timestamp)`
- Use `AND t.success` for trace queries
- Filter zero amounts: `WHERE amount > 0`
- Avoid multiple LEFT JOINs on base.logs - use IN clauses instead
- Prevent uint256 overflow: keep amounts in wei, convert only for display
- Single base.logs scan is better than multiple scans with UNION

## Dune SQL Query Optimization

### Partition Pruning & Filtering

- **Use `block_date` for partitioning**: Tables are partitioned by date - filter on `block_date >= DATE 'YYYY-MM-DD'` for best performance
- **Avoid functions on filter columns**: Use `block_time > '2024-01-01'` not `date_trunc('day', block_time) > '2024-01-01'`
- **Include block_number in joins**: When joining tables, include block_number alongside tx_hash for partition pruning
- **Filter early**: Apply WHERE filters before expensive joins/aggregations (predicate pushdown)

### Table Selection Strategy

- **Prefer decoded tables**: Use `[protocol]_[chain].[Contract]_evt_[EventName]` over raw `base.logs`
- **Raw logs/traces only when necessary**: If using raw tables, always filter by:
  - Contract address: `logs.address = 0x...`  
  - Event signature: `logs.topic0 = 0x...`
  - Time/block range: `block_date >= DATE 'YYYY-MM-DD'`
- **Never scan full logs/traces tables**: Without filters, queries will timeout on billions of records

### Query Writing Best Practices

- **Select only needed columns**: Avoid `SELECT *` on large tables
- **Use LIMIT for samples**: Add LIMIT when you only need top-N results
- **Only sort when necessary**: ORDER BY is expensive on large result sets - omit for materialized tables and intermediate results
- **UNION ALL over UNION**: Avoid deduplication overhead when combining results
- **Window functions over self-joins**: Use `OVER()` clauses for running totals and ranks
- **Approximate aggregates**: Use `approx_distinct()` for faster approximate counts when exact precision isn't critical

### CTE and Subquery Patterns

- **CTEs are inlined, not materialized**: Each CTE reference re-executes the query
- **Avoid reusing complex CTEs**: If referenced multiple times, consider materialized views
- **Join smaller tables first**: When joining, start with smaller tables to larger ones

### Data Type Optimization

- **Use VARBINARY for addresses/hashes**: More efficient than VARCHAR for hex data
- **Keep amounts in wei**: Convert to ETH only for final display to avoid precision loss
- **Direct comparisons over functions**: Compare raw values for better optimizer hints

### Debugging & Analysis

- **Use EXPLAIN**: Check query execution plan to identify bottlenecks
- **Review execution statistics**: Check which stages consume most time/data
- **Test with smaller date ranges first**: Validate query logic before full historical scans

## Materialized Views on Dune

### Key Limitations

- **Full refresh only**: No incremental/append mode - each refresh recomputes entire query
- **No dependency management**: Must manually coordinate refresh schedules for chained views
- **Cannot modify existing data**: Only full replacement supported

### When to Use Materialized Views

- **Heavy intermediate results**: Complex aggregations used by multiple queries
- **Timeout prevention**: Queries exceeding 30-minute limit when run directly
- **Dashboard optimization**: Pre-compute expensive calculations for faster dashboard loads

### Best Practices

- **Design for full refresh**: Structure queries knowing they'll be fully recomputed
- **Schedule appropriately**: Balance freshness needs vs. computation cost
- **Layer materialized views**: Build simpler views on top of complex base views
- **Document dependencies**: Track which views depend on others for manual refresh coordination

### Towns Protocol Specifics

### Key Contract Addresses

- TOWNS token: `0x00000000A22C618fd6b4D7E9A335C4B96B189a38`
- BaseRegistry: `0x7c0422b31401C936172C897802CF0373B35B7698`
- SpaceFactory: `0x9978c826d93883701522d2CA645d5436e5654252`

### Common Event Signatures

```sql
-- Use cast sig-event "EventName(address indexed from, uint256 value)" to generate
-- IMPORTANT: indexed parameters go to topics, non-indexed go to data field
-- Transfer(address indexed from, address indexed to, uint256 value)
--   topic0: signature, topic1: from, topic2: to, data: value
Transfer: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef

-- DelegateVotesChanged(address indexed delegate, uint256 previousBalance, uint256 newBalance)
--   topic0: signature, topic1: delegate, data: previousBalance + newBalance
DelegateVotesChanged: 0xdec2bacdd2f05b59de34da9b523dff8be42e5e38e818c82fdb0bae774387a724

-- DelegateChanged(address indexed delegator, address indexed fromDelegate, address indexed toDelegate)
--   topic0: signature, topic1: delegator, topic2: fromDelegate, topic3: toDelegate
DelegateChanged: 0x3134e8a2e6d97e929a7e54011ea5485d7d196dd5f0ba4d4ef95803e8e3fc257f

-- Stake(address indexed owner, address indexed delegatee, address indexed beneficiary, uint256 depositId, uint96 amount)
--   topic0: signature, topic1: owner, topic2: delegatee, topic3: beneficiary, data: depositId + amount
Stake: 0xfc8744d74019c166abf1c554364af2a3d067ea57fa6f635f4552411ea44d29c7

-- DelegationProxyDeployed(uint256 indexed depositId, address indexed delegatee, address proxy)
--   topic0: signature, topic1: depositId, topic2: delegatee, data: proxy
DelegationProxyDeployed: 0x9cc45a93930c8a80c99a1f194086c25c0e14b43109f4a5adfd9689aaa703ec4c
```

### Query Structure

- Use CTE-heavy patterns for complex transformations
- Standard ordering (deterministic for logs):
  `ORDER BY block_number DESC, tx_index DESC, log_index DESC`
  If tx_index unavailable in your dataset, fall back to (block_number, log_index)
- COALESCE for NULL handling: `COALESCE(daily_value, 0)`
- Window functions for cumulative: `SUM(amount) OVER (ORDER BY day)`
- Latest state pattern: `ROW_NUMBER() OVER (PARTITION BY id ORDER BY block_number DESC, tx_index DESC, log_index DESC) AS rn`

## Materialized Tables (dune.towns_protocol)

### Core Infrastructure Tables

- `result_towns_created` - All towns with creation metadata (town_address, creator, block_time)
- `result_membership_subscriptions` - Membership mints and renewals (token_id, owner, expiration)
- `result_towns_eth_flows` - ETH movements classified (town_in, town_out, protocol_fee)
- `result_staking_events` - All stake/unstake events with amounts and owners
- `result_delegate_votes_events` - Raw DelegateVotesChanged events for voting power

### Staking & Delegation Tables

- `result_delegation_proxies` - Maps deposit IDs to proxy addresses and owners
- `result_proxy_delegations` - Current delegation state per proxy
- `result_proxy_balances` - Current TOWNS token balance in each proxy
- `result_approved_operators` - Operators with Approved/Active status

### Airdrop Tables

- `result_airdrop_claims` - Individual airdrop claim events
- `result_airdrop_claim_statistics` - Aggregated airdrop analytics

### Towns Protocol Query Patterns

```sql
-- Prefer materialized tables over raw log parsing
FROM dune.towns_protocol.result_towns_created tc
JOIN dune.towns_protocol.result_membership_subscriptions ms
    ON tc.town_address = ms.town_address

-- Ensure valid town addresses (when using raw logs)
JOIN dune.towns_protocol.result_towns_created tc
    ON l.contract_address = tc.town_address

-- Transaction type classification
WHERE ef.flow_type IN ('town_in', 'town_out', 'protocol_fee')
```

## Staking Analytics Architecture

### Staking Flow

1. **User Stakes**: Calls stake() on BaseRegistry with TOWNS tokens
2. **Proxy Deployment**: BaseRegistry deploys a DelegationProxy for the deposit
3. **Token Transfer**: TOWNS tokens transferred to the proxy contract
4. **Auto-Delegation**: Proxy automatically delegates voting power to specified operator
5. **Redelegation**: User can change delegation through the proxy contract

### Core Components

1. **Delegation Proxies**: Maps depositId → proxy_address → owner wallet
2. **Proxy Delegations**: Tracks current delegation state using DelegateChanged events
3. **Proxy Balances**: Calculates actual token balances from Transfer events
4. **Stakes by Wallet**: Aggregates individual staking positions
5. **Staking Flows**: Daily aggregates with redelegation detection

### Redelegation Detection

```sql
-- Redelegations create two consecutive DelegateVotesChanged events in same transaction
v2.log_index = v1.log_index + 1 
AND v1.vote_delta < 0  -- First event: votes removed from old delegate
AND v2.vote_delta > 0  -- Second event: votes added to new delegate
AND ABS(v1.vote_delta) = v2.vote_delta  -- Same amount
```

### Important Notes

- Users stake through DelegationProxy contracts, not directly
- DelegateVotesChanged shows delegate's total voting power, not individual proxy balances
- Transfer event amount is in data field (non-indexed), not topic3
- Keep amounts in wei throughout calculations to avoid precision loss
- Proxy contracts hold the tokens and delegate on behalf of users
- One user can have multiple proxies (multiple deposits)
