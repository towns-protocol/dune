# Towns Protocol - Dune Analytics

This repository manages Dune Analytics queries for [Towns Protocol](https://www.towns.com/), tracking on-chain activity
on the Base blockchain. It synchronizes SQL queries between local files and the Dune platform with automated deployment
workflows.

## Query Categories

This repo tracks 26+ queries across:

- **Membership & Revenue**: Subscriptions, renewals, revenue tracking
- **Staking & Delegation**: TOWNS token staking, voting power, proxy contracts
- **Protocol Fees & Tipping**: Fee collection, tipping events and revenue
- **Governance & Voting**: Delegation, operator approvals, voting power
- **Airdrops & Campaigns**: Claim events, withdrawal analysis, snapshot queries

For detailed SQL patterns and optimization techniques, see [CLAUDE.md](CLAUDE.md).

## Key Resources

- **GitHub Repository**: [towns-protocol/dune](https://github.com/towns-protocol/dune)
- **Towns Protocol**: [www.towns.com](https://www.towns.com/)
- **Dune Dashboard**: View analytics at Dune (query IDs in `queries.yml`)
- **Technical Docs**: [CLAUDE.md](CLAUDE.md) for SQL patterns and optimization

## Quick Start

### Setup

1. **Install dependencies**
   ```bash
   pip install -r requirements.txt
   # or using uv: uv pip install -r requirements.txt
   ```

2. **Configure API key**
    - Copy `.env.test` to `.env` and add your `DUNE_API_KEY`
    - Generate a key from your Dune team settings (requires Plus plan)
    - For GitHub Actions, add the key
      to [repository secrets](https://docs.github.com/en/actions/security-guides/using-secrets-in-github-actions#creating-secrets-for-a-repository)

3. **Pull existing queries**
   ```bash
   python scripts/pull_from_dune.py
   ```
   This downloads all queries listed in `queries.yml` into the `/queries` folder.

### Making Changes

1. **Edit queries**: Modify `.sql` files in the `/queries` folder locally
2. **Push to Dune**: Run `python scripts/push_to_dune.py` or push to main branch (auto-deploys via GitHub Actions)
3. **Add new queries**: Create in Dune first, then add the query ID to `queries.yml` and pull

---

### Query Management Scripts

You'll need python and pip installed to run the script commands. If you don't have a package manager set up, then use
either [conda](https://www.anaconda.com/download) or [poetry](https://python-poetry.org/) . Then install the required
packages:

```
pip install -r requirements.txt
```

| Script              | Action                                                                                                                            | Command                                   |
|---------------------|-----------------------------------------------------------------------------------------------------------------------------------|-------------------------------------------|
| `pull_from_dune.py` | updates/adds queries to your repo based on ids in `queries.yml`                                                                   | `python scripts/pull_from_dune.py`        |
| `push_to_dune.py`   | updates queries to Dune based on files in your `/queries` folder                                                                  | `python scripts/push_to_dune.py`          |
| `preview_query.py`  | gives you the first 20 rows of results by running a query from your `/queries` folder. Specify the id. This uses Dune API credits | `python scripts/preview_query.py 4223614` |
| `upload_to_dune.py` | uploads/updates any tables from your `/uploads` folder. Must be in CSV format, and under 200MB.                                   | `python scripts/upload_to_dune.py`        |

---

### Things to be aware of

💡: Names of queries are pulled into the file name the first time `pull_from_dune.py` is run. Changing the file name in
app or in folder will not affect each other (they aren't synced). **Make sure you leave the `___id.sql` at the end of
the file, otherwise the scripts will break!**

🟧: Make sure to leave in the comment `-- part of a query repo` at the top of your file. This will hopefully help prevent
others from using it in more than one repo.

🔒: Queries must be owned by the team the API key was created under - otherwise you won't be able to update them from the
repo.

➕: If you want to add a query, add it in Dune app first then pull the query id (from URL
`dune.com/queries/{id}/other_stuff`) into `queries.yml`

🛑: If you accidently merge a PR or push a commit that messes up your query in Dune, you can roll back any changes
using [query version history](https://dune.com/docs/app/query-editor/version-history).

---

### For Contributors

Contributions to Towns Protocol analytics are welcome! Issue types:

- `bugs`: Data quality issues like miscalculations or broken queries
- `chart improvements`: Suggestions for visualization improvements
- `query improvements`: Enhancements to queries (additional columns, tables, optimizations)
- `generic questions`: General questions or suggestions about the analytics

To contribute:

1. Open an issue or create a PR with appropriate labels
2. For new queries: Create in Dune first, test thoroughly, then add to `queries.yml`
3. For query edits: Test with `preview_query.py` before pushing
4. Once merged, queries auto-deploy to Dune via GitHub Actions

See [CLAUDE.md](CLAUDE.md) for SQL optimization patterns specific to Towns Protocol on Base.
