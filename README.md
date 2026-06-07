# Arsenal FC — Match Result Prediction

A small ML project that predicts Arsenal FC match results (**Win / Draw / Loss**) from
historical data. Match and squad data is pulled from the
[football-data.org](https://www.football-data.org) v4 API into a local PostgreSQL
database, explored and modelled in Jupyter notebooks, and the best model is saved for
inference.

```
football-data.org API  ──▶  PostgreSQL  ──▶  notebooks (EDA + model)  ──▶  models/*.joblib
       (scripts/)            (Docker)           (notebooks/)
```

## Requirements

- Docker (for PostgreSQL)
- Python 3.9+ with a virtualenv at `.venv`
- A free football-data.org API key — register at
  <https://www.football-data.org/client/register>

## Setup

```bash
# 1. Python deps
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt

# 2. Configure secrets
cp .env.example .env
#    edit .env and set FOOTBALL_DATA_API_KEY

# 3. Start PostgreSQL (a fresh volume auto-runs the migrations in migrations/)
docker compose up -d

# 4. Apply / record DB migrations (tracked, safe to re-run)
.venv/bin/python3 scripts/migrate.py

# 5. Populate the database (order matters — matches first, then squads)
.venv/bin/python3 scripts/fetch_arsenal.py
.venv/bin/python3 scripts/fetch_squads.py
```

> The fetch scripts sleep 6s between API calls to respect the free tier's 10 req/min
> limit, so `fetch_squads.py` takes a few minutes. Both scripts upsert and are safe to
> re-run.

## Notebooks

```bash
.venv/bin/jupyter notebook            # interactive
# or run headless:
.venv/bin/jupyter nbconvert --to notebook --execute notebooks/01_eda_arsenal.ipynb \
  --output 01_eda_arsenal_executed.ipynb
.venv/bin/jupyter nbconvert --to notebook --execute notebooks/02_model_arsenal.ipynb \
  --output 02_model_arsenal_executed.ipynb
```

- **`01_eda_arsenal.ipynb`** — exploratory analysis (results, goals over time, results
  by competition, toughest opponents, squad profile). Charts are written to `data/*.png`.
- **`02_model_arsenal.ipynb`** — feature engineering and modelling. Compares a baseline,
  Logistic Regression, Random Forest and Gradient Boosting, picks the best by
  cross-validated F1-macro, and saves it to `models/`. Key rules: rolling features use
  `.shift(1)` to avoid leakage, and the train/test split is chronological (never shuffled).

## Database

PostgreSQL runs in Docker (see `docker-compose.yml`). The schema stores the **full**
football-data.org payload: typed columns for the useful flat fields plus a `raw JSONB`
column on every ingested table holding the complete API object, so nothing is lost —
including nested data (`goals`, `lineup`, `bookings`) and paid-tier fields.

Tables: `competitions`, `seasons`, `teams`, `matches`, `team_standings`, `players`,
`team_players` (links players to teams per season). Plus the bookkeeping table
`schema_migrations`.

### Migrations

Versioned, idempotent SQL lives in [`migrations/`](migrations/README.md) (`v001`,
`v002`, …). `scripts/migrate.py` applies only the versions not yet recorded in
`schema_migrations` and records each, so the same migration never runs twice. To change
the schema, add the next `vNNN_*.sql` file and run the runner — never edit an applied one.

### Views

- **`vw_match_details`** — readable view of any match (team/competition names resolved,
  `score` text like `'2-1'`, venue, attendance).
- **`vw_arsenal_matches`** — Arsenal-centric: one row per match with `opponent`,
  `venue_side`, `arsenal_goals`/`opponent_goals`, `result` (Win/Draw/Loss) and `points`.

```sql
SELECT utc_date::date, competition, venue_side, opponent,
       arsenal_goals, opponent_goals, result, points
FROM vw_arsenal_matches ORDER BY utc_date DESC LIMIT 10;
```

## Project layout

```
.
├── docker-compose.yml      # PostgreSQL service
├── requirements.txt
├── .env.example            # copy to .env and fill in the API key
├── migrations/             # versioned SQL migrations (vNNN_*.sql) + README
├── scripts/
│   ├── migrate.py          # tracked migration runner
│   ├── fetch_arsenal.py    # matches + competitions/seasons/teams
│   └── fetch_squads.py     # players for Arsenal + every opponent
├── notebooks/              # EDA + modelling
├── models/                 # saved model + features.json
└── data/                   # Postgres volume (gitignored) + exported charts
```

## Notes

- `.env`, `.venv/` and `data/postgres/` are gitignored.
- Arsenal is team id `57` in football-data.org (hardcoded in the scripts and the
  `vw_arsenal_matches` view).
