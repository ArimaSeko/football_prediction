"""Fetch Arsenal FC match data from football-data.org and store in PostgreSQL."""

import os
import time
import psycopg2
from psycopg2.extras import Json
import requests
from datetime import datetime
from dotenv import load_dotenv

load_dotenv()

API_KEY = os.environ["FOOTBALL_DATA_API_KEY"]
DB_URL = os.environ.get("DATABASE_URL", "postgresql://football:football_pass@localhost:5432/football_prediction")

BASE_URL = "https://api.football-data.org/v4"
ARSENAL_ID = 57
# Premier League competition id on football-data.org
PL_ID = 2021

HEADERS = {"X-Auth-Token": API_KEY}


def get(path: str) -> dict:
    resp = requests.get(f"{BASE_URL}{path}", headers=HEADERS, timeout=10)
    resp.raise_for_status()
    # Free tier: 10 req/min
    time.sleep(6)
    return resp.json()


def upsert_team(cur, team: dict):
    cur.execute(
        """
        INSERT INTO teams (id, name, short_name, tla, crest_url, founded, venue, raw)
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
        ON CONFLICT (id) DO UPDATE SET
            name = EXCLUDED.name,
            short_name = EXCLUDED.short_name,
            tla = EXCLUDED.tla,
            crest_url = EXCLUDED.crest_url,
            founded = EXCLUDED.founded,
            venue = EXCLUDED.venue,
            raw = EXCLUDED.raw
        """,
        (
            team["id"],
            team["name"],
            team.get("shortName"),
            team.get("tla"),
            team.get("crest"),
            team.get("founded"),
            team.get("venue"),
            Json(team),
        ),
    )


def upsert_match(cur, match: dict, competition_id: int, season_id: int):
    score = match.get("score", {})
    ft = score.get("fullTime", {})
    ht = score.get("halfTime", {})
    et = score.get("extraTime", {})
    pen = score.get("penalties", {})
    area = match.get("area", {})
    odds = match.get("odds", {})

    cur.execute(
        """
        INSERT INTO matches (
            id, competition_id, season_id, matchday, utc_date, status,
            home_team_id, away_team_id,
            home_goals, away_goals, home_goals_ht, away_goals_ht, winner,
            area_id, area_name, stage, group_name, last_updated,
            minute, injury_time, attendance, venue, duration,
            home_goals_et, away_goals_et, home_penalties, away_penalties,
            odds_home_win, odds_draw, odds_away_win, referees, raw, updated_at
        )
        VALUES (
            %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s,
            %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s,
            %s, %s, %s, %s, %s, NOW()
        )
        ON CONFLICT (id) DO UPDATE SET
            status = EXCLUDED.status,
            home_goals = EXCLUDED.home_goals,
            away_goals = EXCLUDED.away_goals,
            home_goals_ht = EXCLUDED.home_goals_ht,
            away_goals_ht = EXCLUDED.away_goals_ht,
            winner = EXCLUDED.winner,
            area_id = EXCLUDED.area_id,
            area_name = EXCLUDED.area_name,
            stage = EXCLUDED.stage,
            group_name = EXCLUDED.group_name,
            last_updated = EXCLUDED.last_updated,
            minute = EXCLUDED.minute,
            injury_time = EXCLUDED.injury_time,
            attendance = EXCLUDED.attendance,
            venue = EXCLUDED.venue,
            duration = EXCLUDED.duration,
            home_goals_et = EXCLUDED.home_goals_et,
            away_goals_et = EXCLUDED.away_goals_et,
            home_penalties = EXCLUDED.home_penalties,
            away_penalties = EXCLUDED.away_penalties,
            odds_home_win = EXCLUDED.odds_home_win,
            odds_draw = EXCLUDED.odds_draw,
            odds_away_win = EXCLUDED.odds_away_win,
            referees = EXCLUDED.referees,
            raw = EXCLUDED.raw,
            updated_at = NOW()
        """,
        (
            match["id"],
            competition_id,
            season_id,
            match.get("matchday"),
            match["utcDate"],
            match["status"],
            match["homeTeam"]["id"],
            match["awayTeam"]["id"],
            ft.get("home"),
            ft.get("away"),
            ht.get("home"),
            ht.get("away"),
            score.get("winner"),
            area.get("id"),
            area.get("name"),
            match.get("stage"),
            match.get("group"),
            match.get("lastUpdated"),
            match.get("minute"),
            match.get("injuryTime"),
            match.get("attendance"),
            match.get("venue"),
            score.get("duration"),
            et.get("home"),
            et.get("away"),
            pen.get("home"),
            pen.get("away"),
            odds.get("homeWin"),
            odds.get("draw"),
            odds.get("awayWin"),
            Json(match.get("referees")) if match.get("referees") is not None else None,
            Json(match),
        ),
    )


def fetch_arsenal_matches():
    print("Fetching Arsenal matches from football-data.org...")
    data = get(f"/teams/{ARSENAL_ID}/matches?status=FINISHED&limit=100")
    matches = data.get("matches", [])
    print(f"  Got {len(matches)} finished matches")

    conn = psycopg2.connect(DB_URL)
    try:
        with conn:
            cur = conn.cursor()

            for match in matches:
                comp = match["competition"]
                season = match["season"]

                area = comp.get("area", {})

                # Upsert competition
                cur.execute(
                    """
                    INSERT INTO competitions (id, name, code, type, emblem, area_id, area_name, raw)
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
                    ON CONFLICT (id) DO UPDATE SET
                        name = EXCLUDED.name,
                        code = EXCLUDED.code,
                        type = EXCLUDED.type,
                        emblem = EXCLUDED.emblem,
                        area_id = EXCLUDED.area_id,
                        area_name = EXCLUDED.area_name,
                        raw = EXCLUDED.raw
                    """,
                    (
                        comp["id"],
                        comp["name"],
                        comp.get("code", ""),
                        comp.get("type"),
                        comp.get("emblem"),
                        area.get("id"),
                        area.get("name"),
                        Json(comp),
                    ),
                )

                # Upsert season
                cur.execute(
                    """
                    INSERT INTO seasons (
                        id, competition_id, start_date, end_date,
                        current_matchday, winner, stages, raw
                    )
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
                    ON CONFLICT (id) DO UPDATE SET
                        current_matchday = EXCLUDED.current_matchday,
                        winner = EXCLUDED.winner,
                        stages = EXCLUDED.stages,
                        raw = EXCLUDED.raw
                    """,
                    (
                        season["id"],
                        comp["id"],
                        season["startDate"],
                        season["endDate"],
                        season.get("currentMatchday"),
                        Json(season.get("winner")) if season.get("winner") is not None else None,
                        Json(season.get("stages")) if season.get("stages") is not None else None,
                        Json(season),
                    ),
                )

                # Upsert both teams
                for team_key in ("homeTeam", "awayTeam"):
                    t = match[team_key]
                    cur.execute(
                        """
                        INSERT INTO teams (id, name, short_name, tla, crest_url, raw)
                        VALUES (%s, %s, %s, %s, %s, %s)
                        ON CONFLICT (id) DO UPDATE SET
                            name = EXCLUDED.name,
                            short_name = EXCLUDED.short_name,
                            tla = EXCLUDED.tla,
                            crest_url = EXCLUDED.crest_url,
                            raw = COALESCE(teams.raw, EXCLUDED.raw)
                        """,
                        (t["id"], t["name"], t.get("shortName"), t.get("tla"), t.get("crest"), Json(t)),
                    )

                upsert_match(cur, match, comp["id"], season["id"])

        print(f"  Saved {len(matches)} matches to database.")
    finally:
        conn.close()


if __name__ == "__main__":
    fetch_arsenal_matches()
