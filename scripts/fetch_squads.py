"""
Fetch squads (players) for Arsenal and all opponents from football-data.org.

Run fetch_arsenal.py first to populate the matches table, then run this script.
Free tier limit: 10 req/min → 6s sleep between requests.
"""

import os
import time
import psycopg2
from psycopg2.extras import Json
from datetime import date
import requests
from dotenv import load_dotenv

load_dotenv()

API_KEY = os.environ["FOOTBALL_DATA_API_KEY"]
DB_URL = os.environ.get(
    "DATABASE_URL",
    "postgresql://football:football_pass@localhost:5432/football_prediction",
)

BASE_URL = "https://api.football-data.org/v4"
ARSENAL_ID = 57
HEADERS = {"X-Auth-Token": API_KEY}

# Current season year (2024 = 2024/25)
CURRENT_SEASON_YEAR = date.today().year if date.today().month >= 7 else date.today().year - 1


def get(path: str) -> dict:
    resp = requests.get(f"{BASE_URL}{path}", headers=HEADERS, timeout=10)
    resp.raise_for_status()
    time.sleep(6)
    return resp.json()


def get_opponent_team_ids(conn) -> list[int]:
    """Return all unique team IDs that Arsenal faced, excluding Arsenal itself."""
    with conn.cursor() as cur:
        cur.execute(
            """
            SELECT DISTINCT unnest(ARRAY[home_team_id, away_team_id]) AS team_id
            FROM matches
            WHERE home_team_id = %s OR away_team_id = %s
            """,
            (ARSENAL_ID, ARSENAL_ID),
        )
        rows = cur.fetchall()
    return [r[0] for r in rows]


def upsert_player(cur, player: dict):
    dob = player.get("dateOfBirth")
    contract = player.get("contract") or {}
    cur.execute(
        """
        INSERT INTO players (
            id, name, first_name, last_name, position, nationality, date_of_birth,
            market_value, contract_start, contract_until, raw, updated_at
        )
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, NOW())
        ON CONFLICT (id) DO UPDATE SET
            name           = EXCLUDED.name,
            first_name     = EXCLUDED.first_name,
            last_name      = EXCLUDED.last_name,
            position       = EXCLUDED.position,
            nationality    = EXCLUDED.nationality,
            date_of_birth  = EXCLUDED.date_of_birth,
            market_value   = EXCLUDED.market_value,
            contract_start = EXCLUDED.contract_start,
            contract_until = EXCLUDED.contract_until,
            raw            = EXCLUDED.raw,
            updated_at     = NOW()
        """,
        (
            player["id"],
            player["name"],
            player.get("firstName"),
            player.get("lastName"),
            player.get("position"),
            player.get("nationality"),
            dob[:10] if dob else None,
            player.get("marketValue"),
            contract.get("start"),
            contract.get("until"),
            Json(player),
        ),
    )


def upsert_team_player(cur, team_id: int, player: dict, season_year: int):
    contract = player.get("contract") or {}
    cur.execute(
        """
        INSERT INTO team_players (
            team_id, player_id, shirt_number, season_year,
            contract_start, contract_until, raw
        )
        VALUES (%s, %s, %s, %s, %s, %s, %s)
        ON CONFLICT (team_id, player_id, season_year) DO UPDATE SET
            shirt_number   = EXCLUDED.shirt_number,
            contract_start = EXCLUDED.contract_start,
            contract_until = EXCLUDED.contract_until,
            raw            = EXCLUDED.raw,
            fetched_at     = NOW()
        """,
        (
            team_id,
            player["id"],
            player.get("shirtNumber"),
            season_year,
            contract.get("start"),
            contract.get("until"),
            Json(player),
        ),
    )


def fetch_and_store_squad(conn, team_id: int, team_name: str):
    print(f"  Fetching squad for {team_name} (id={team_id})...")
    try:
        data = get(f"/teams/{team_id}")
    except requests.HTTPError as e:
        print(f"    Skipped (HTTP {e.response.status_code})")
        return 0

    squad = data.get("squad", [])
    if not squad:
        print(f"    No squad data returned (may require higher API tier)")
        return 0

    with conn:
        cur = conn.cursor()

        # Upsert team with full details
        area = data.get("area", {})
        running = data.get("runningCompetitions")
        coach = data.get("coach")
        cur.execute(
            """
            INSERT INTO teams (
                id, name, short_name, tla, crest_url, founded, venue,
                area_id, area_name, address, website, club_colors, market_value,
                last_updated, running_competitions, coach, raw
            )
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
            ON CONFLICT (id) DO UPDATE SET
                name                 = EXCLUDED.name,
                short_name           = EXCLUDED.short_name,
                tla                  = EXCLUDED.tla,
                crest_url            = EXCLUDED.crest_url,
                founded              = EXCLUDED.founded,
                venue                = EXCLUDED.venue,
                area_id              = EXCLUDED.area_id,
                area_name            = EXCLUDED.area_name,
                address              = EXCLUDED.address,
                website              = EXCLUDED.website,
                club_colors          = EXCLUDED.club_colors,
                market_value         = EXCLUDED.market_value,
                last_updated         = EXCLUDED.last_updated,
                running_competitions = EXCLUDED.running_competitions,
                coach                = EXCLUDED.coach,
                raw                  = EXCLUDED.raw
            """,
            (
                data["id"],
                data["name"],
                data.get("shortName"),
                data.get("tla"),
                data.get("crest"),
                data.get("founded"),
                data.get("venue"),
                area.get("id"),
                area.get("name"),
                data.get("address"),
                data.get("website"),
                data.get("clubColors"),
                data.get("marketValue"),
                data.get("lastUpdated"),
                Json(running) if running is not None else None,
                Json(coach) if coach is not None else None,
                Json(data),
            ),
        )

        for player in squad:
            upsert_player(cur, player)
            upsert_team_player(cur, team_id, player, CURRENT_SEASON_YEAR)

    print(f"    Saved {len(squad)} players")
    return len(squad)


def fetch_all_squads():
    conn = psycopg2.connect(DB_URL)
    try:
        team_ids = get_opponent_team_ids(conn)
        print(f"Found {len(team_ids)} teams (Arsenal + opponents)")

        # Ensure Arsenal is always included
        if ARSENAL_ID not in team_ids:
            team_ids.insert(0, ARSENAL_ID)

        total = 0
        for team_id in team_ids:
            # Get team name from DB for logging
            with conn.cursor() as cur:
                cur.execute("SELECT name FROM teams WHERE id = %s", (team_id,))
                row = cur.fetchone()
            name = row[0] if row else f"Team {team_id}"

            count = fetch_and_store_squad(conn, team_id, name)
            total += count

        print(f"\nDone. Total players stored: {total}")
    finally:
        conn.close()


if __name__ == "__main__":
    fetch_all_squads()
