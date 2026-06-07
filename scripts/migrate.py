"""Apply pending SQL migrations and record them so they never run twice.

Reads the ordered `migrations/v*.sql` files and applies only the versions not yet
recorded in the `schema_migrations` bookkeeping table (created on first run). Each
migration runs in its own transaction; on success its version is recorded. Safe to
run repeatedly — already-applied versions are skipped.

Usage:
    .venv/bin/python3 scripts/migrate.py
"""

import os
import glob
import psycopg2
from dotenv import load_dotenv

load_dotenv()

DB_URL = os.environ.get(
    "DATABASE_URL",
    "postgresql://football:football_pass@localhost:5432/football_prediction",
)

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MIGRATIONS_DIR = os.path.join(PROJECT_ROOT, "migrations")


def ensure_bookkeeping(cur):
    cur.execute(
        """
        CREATE TABLE IF NOT EXISTS schema_migrations (
            version    TEXT PRIMARY KEY,
            filename   TEXT NOT NULL,
            applied_at TIMESTAMPTZ DEFAULT NOW()
        )
        """
    )


def applied_versions(cur) -> set[str]:
    cur.execute("SELECT version FROM schema_migrations")
    return {row[0] for row in cur.fetchall()}


def discover_migrations() -> list[tuple[str, str]]:
    """Return [(version, path), ...] sorted by filename (v001, v002, ...)."""
    paths = sorted(glob.glob(os.path.join(MIGRATIONS_DIR, "v*.sql")))
    return [(os.path.basename(p).split("_", 1)[0], p) for p in paths]


def main():
    conn = psycopg2.connect(DB_URL)
    try:
        with conn, conn.cursor() as cur:
            ensure_bookkeeping(cur)

        with conn.cursor() as cur:
            done = applied_versions(cur)

        pending = [(v, p) for v, p in discover_migrations() if v not in done]
        if not pending:
            print("Database is up to date — no pending migrations.")
            return

        for version, path in pending:
            name = os.path.basename(path)
            print(f"Applying {name} ...")
            with open(path, encoding="utf-8") as f:
                sql = f.read()
            with conn, conn.cursor() as cur:
                cur.execute(sql)
                cur.execute(
                    "INSERT INTO schema_migrations (version, filename) VALUES (%s, %s)",
                    (version, name),
                )
            print(f"  recorded {version}")

        print(f"Done. Applied {len(pending)} migration(s).")
    finally:
        conn.close()


if __name__ == "__main__":
    main()
