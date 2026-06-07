# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

ML side project that predicts Arsenal FC match results (Win / Draw / Loss, 3-class) from historical match data. Data comes from the [football-data.org](https://www.football-data.org) v4 API, lands in a local PostgreSQL database (run via Docker), and is analyzed/modeled in Jupyter notebooks.

## Environment

Always use the project virtualenv — never system `python3`/`pip3`:

- `.venv/bin/python3`
- `.venv/bin/pip`

Secrets and connection settings live in `.env` (copy from `.env.example`). Required: `FOOTBALL_DATA_API_KEY` (free tier) and `DATABASE_URL`. Scripts and notebooks load these via `python-dotenv`; notebooks call `load_dotenv('../.env')`.

## Common commands

Start / stop the database:
```bash
docker compose up -d        # Postgres 16 on localhost:5432, initialized from scripts/init.sql
docker compose down
```

Populate the database (order matters — matches first, then squads):
```bash
.venv/bin/python3 scripts/fetch_arsenal.py   # Arsenal matches + competitions/seasons/teams
.venv/bin/python3 scripts/fetch_squads.py    # players for Arsenal + every opponent faced
```

Run the notebooks headless (produces the `*_executed.ipynb` files and writes PNGs to `data/`):
```bash
.venv/bin/jupyter nbconvert --to notebook --execute notebooks/01_eda_arsenal.ipynb \
  --output 01_eda_arsenal_executed.ipynb
.venv/bin/jupyter nbconvert --to notebook --execute notebooks/02_model_arsenal.ipynb \
  --output 02_model_arsenal_executed.ipynb
```

## Architecture

The pipeline is a one-directional flow: **API → Postgres → notebooks → model artifact**.

1. **Ingestion** (`scripts/`). `fetch_arsenal.py` and `fetch_squads.py` use raw `psycopg2` and `INSERT ... ON CONFLICT DO UPDATE` upserts, so they are idempotent and safe to re-run. Every API call goes through a `get()` helper that sleeps 6s afterward to respect the free tier's 10 req/min limit. Arsenal is hardcoded as team id `57`; `fetch_squads.py` derives the opponent set by querying which teams appear in Arsenal's matches.

2. **Schema** (`scripts/init.sql`). Applied automatically by Docker on first DB creation (mounted into `/docker-entrypoint-initdb.d/`). Core tables: `competitions`, `seasons`, `teams`, `matches`, `team_standings`, `players`, `team_players`. `team_players` links players to teams *per season* (`season_year`, e.g. 2024 = 2024/25 season) because players change clubs.

   **"Store everything" pattern**: every ingested table keeps typed columns for the useful flat API fields *plus* a `raw JSONB` column holding the complete API object, so nothing is lost — including nested arrays (`goals`, `lineup`, `bookings`, `substitutions`) and paid-tier fields that come back `null`/empty on the free tier. When adding a field, prefer reading it out of an existing `raw` column over re-fetching.

   **Migrations**: `init.sql` only runs on a *fresh* `data/postgres/` volume, so schema changes to a live DB need an `ALTER` migration applied manually:
   ```bash
   docker exec -i football_db psql -U football -d football_prediction < scripts/migrate_expand_schema.sql
   ```
   `migrate_expand_schema.sql` (idempotent `ADD COLUMN IF NOT EXISTS` + the views) is the migration that introduced the full-payload columns and views; `migrate_add_players.sql` is the older players/team_players DDL. Keep `init.sql` and the migrations in sync when changing the schema.

3. **Views** (defined in both `init.sql` and `migrate_expand_schema.sql`):
   - `vw_match_details` — general readable view of any match (team/competition names resolved, `score` text like `'2-1'`, venue, attendance).
   - `vw_arsenal_matches` — Arsenal-centric (team id 57): one row per match with `opponent`, `venue_side`, `arsenal_goals`/`opponent_goals`, `result` (Win/Draw/Loss), and `points` (3/1/0). This mirrors the result/points derivation the notebooks currently do in pandas and can replace that logic.

4. **Modeling** (`notebooks/`). `01_eda_arsenal.ipynb` is exploratory analysis; `02_model_arsenal.ipynb` is the model pipeline. Key conventions to preserve when editing model code:
   - **No data leakage**: all rolling features use `.shift(1)` so a match only ever sees *past* matches.
   - **Chronological split**, never shuffle — the last 10 matches are the test set.
   - Compares Baseline / LogisticRegression / RandomForest / GradientBoosting (sklearn `Pipeline` with `StandardScaler`); selects the best by cross-validated F1-macro.

5. **Artifacts** (`models/`). The notebook saves the winning model as `models/<name>.joblib` plus `models/features.json` (the ordered feature list + model name) used for inference. The feature set is currently: `is_home`, `is_ucl`, `form_last5`, `goals_scored_avg5`, `goals_conceded_avg5`, `goal_diff_avg5`, `win_streak`, `days_rest`, `match_number`. If you change features in the notebook, `features.json` must stay in sync.

## Notes

- `data/postgres/` is the live Postgres data volume — do not edit or commit it (gitignored). PNGs in `data/` are notebook outputs.
- `src/` is currently empty (placeholder for future inference/app code).
