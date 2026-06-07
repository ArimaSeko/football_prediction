# Database migrations

Ordered, idempotent SQL migrations for the project's PostgreSQL database. This
directory is the **single source of truth** for the schema.

## Convention

- One file per migration, named `vNNN_short_description.sql` (`v001`, `v002`, …).
- Files are applied in **ascending version order** (the `vNNN` prefix sorts correctly).
- Migrations are **idempotent** — they use `CREATE TABLE IF NOT EXISTS`,
  `ADD COLUMN IF NOT EXISTS`, `CREATE OR REPLACE VIEW`, etc., so re-running them is safe.
- Never edit a migration that has already been applied to a real database. To change
  the schema, add a new `vNNN` file with the next number.

## Migration history

| Version | File | What it does |
|---------|------|--------------|
| v001 | `v001_initial_schema.sql` | Core tables: `competitions`, `seasons`, `teams`, `matches`, `team_standings`, indexes, Arsenal (id 57) seed row. |
| v002 | `v002_add_players.sql` | `players` catalogue and the per-season `team_players` link table. |
| v003 | `v003_expand_full_payload.sql` | Full football-data.org v4 payload — typed columns for flat fields + a `raw JSONB` column per table — and the `vw_match_details` / `vw_arsenal_matches` views. |

## Applying

### Recommended: the migration runner

`scripts/migrate.py` applies only the migrations not yet recorded in the
`schema_migrations` bookkeeping table, then records each one — so the same file is
never run twice. Safe to run repeatedly; run it after adding any new `vNNN` file:

```bash
.venv/bin/python3 scripts/migrate.py
```

`schema_migrations` (created automatically on first run) holds one row per applied
version: `version`, `filename`, `applied_at`.

### Fresh database (Docker)

`docker-compose.yml` also mounts this directory into `/docker-entrypoint-initdb.d`, so
on a **brand-new** `data/postgres/` volume Postgres runs every `*.sql` here in order on
first boot (`README.md` is ignored — only `*.sql` / `*.sh` execute). That bootstraps the
schema fast but does not populate `schema_migrations`; the first `scripts/migrate.py`
run then baselines it (re-running the idempotent files is harmless) so later runs skip
them.

### By hand

If you need to apply a single file directly (every migration is idempotent):

```bash
docker exec -i football_db psql -U football -d football_prediction -v ON_ERROR_STOP=1 \
  < migrations/v003_expand_full_payload.sql
```

## Views

- **`vw_match_details`** — readable view of any match (team/competition names resolved,
  `score` text like `'2-1'`, venue, attendance).
- **`vw_arsenal_matches`** — Arsenal-centric (team id 57): one row per match with
  `opponent`, `venue_side`, `arsenal_goals`/`opponent_goals`, `result` (Win/Draw/Loss),
  and `points` (3/1/0).
