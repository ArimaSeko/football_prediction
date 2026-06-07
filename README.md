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

## Notebooks — learning polygon

The notebooks are **empty, guided scaffolds** for learning ML by doing. Each section's
markdown states *what* to achieve; the code cells are `# TODO`s for you to implement —
search, read docs, experiment. Nothing is solved for you.

```bash
.venv/bin/jupyter notebook
```

- **`01_eda_arsenal.ipynb`** — explore the data and look for signals (result
  distribution, home/away, goals over time, opponents, form, squad).
- **`02_model_arsenal.ipynb`** — frame the problem, engineer features (mind data
  leakage!), split for time series, train and compare models, evaluate, and save your
  best model to `models/`.

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
├── notebooks/              # learning scaffolds (EDA + modelling)
├── models/                 # where you save your trained model (empty until then)
└── data/                   # Postgres volume (gitignored) + any charts you export
```

## Notes

- `.env`, `.venv/` and `data/postgres/` are gitignored.
- Arsenal is team id `57` in football-data.org (hardcoded in the scripts and the
  `vw_arsenal_matches` view).
