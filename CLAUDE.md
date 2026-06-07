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
docker compose up -d        # Postgres 16 on localhost:5432; a fresh volume runs migrations/v*.sql in order
docker compose down
```

Apply pending DB migrations (tracked via `schema_migrations`; safe to re-run):
```bash
.venv/bin/python3 scripts/migrate.py
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

2. **Schema** (`migrations/`). Versioned, idempotent SQL migrations (`v001`, `v002`, …) are the single source of truth — see `migrations/README.md` for the convention. Docker mounts the directory into `/docker-entrypoint-initdb.d`, so a fresh `data/postgres/` volume replays every `v*.sql` in order on first boot. Core tables: `competitions`, `seasons`, `teams`, `matches`, `team_standings`, `players`, `team_players`. `team_players` links players to teams *per season* (`season_year`, e.g. 2024 = 2024/25 season) because players change clubs.

   **"Store everything" pattern** (introduced in `v003`): every ingested table keeps typed columns for the useful flat API fields *plus* a `raw JSONB` column holding the complete API object, so nothing is lost — including nested arrays (`goals`, `lineup`, `bookings`, `substitutions`) and paid-tier fields that come back `null`/empty on the free tier. When adding a field, prefer reading it out of an existing `raw` column over re-fetching.

   **Applying migrations**: `scripts/migrate.py` is the tracked runner — it applies only the `vNNN` files not yet recorded in the `schema_migrations` table and records each, so nothing runs twice. To change the schema, add the next `vNNN_*.sql` file (never edit an applied one) and run:
   ```bash
   .venv/bin/python3 scripts/migrate.py
   ```
   Docker also auto-runs the `v*.sql` files on a *fresh* volume (fast bootstrap, but doesn't populate `schema_migrations`); the first `migrate.py` run then baselines it idempotently.

3. **Views** (defined in `migrations/v003_expand_full_payload.sql`):
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
