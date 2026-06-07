-- v003 — Store the full football-data.org v4 API payload + match views
--
-- Earlier versions kept only a hand-picked subset of API fields. This adds typed
-- columns for the useful flat fields plus a `raw JSONB` column on every ingested
-- table holding the complete API object (so nothing is ever lost, including nested
-- arrays like goals/lineup/bookings and paid-tier fields). Finishes with two
-- readable match views.

-- ---------------------------------------------------------------- competitions
ALTER TABLE competitions ADD COLUMN IF NOT EXISTS type      TEXT;
ALTER TABLE competitions ADD COLUMN IF NOT EXISTS emblem    TEXT;
ALTER TABLE competitions ADD COLUMN IF NOT EXISTS area_id   INTEGER;
ALTER TABLE competitions ADD COLUMN IF NOT EXISTS area_name TEXT;
ALTER TABLE competitions ADD COLUMN IF NOT EXISTS raw       JSONB;

-- --------------------------------------------------------------------- seasons
ALTER TABLE seasons ADD COLUMN IF NOT EXISTS stages JSONB;
ALTER TABLE seasons ADD COLUMN IF NOT EXISTS winner JSONB;
ALTER TABLE seasons ADD COLUMN IF NOT EXISTS raw    JSONB;

-- ----------------------------------------------------------------------- teams
ALTER TABLE teams ADD COLUMN IF NOT EXISTS area_id              INTEGER;
ALTER TABLE teams ADD COLUMN IF NOT EXISTS area_name            TEXT;
ALTER TABLE teams ADD COLUMN IF NOT EXISTS address              TEXT;
ALTER TABLE teams ADD COLUMN IF NOT EXISTS website              TEXT;
ALTER TABLE teams ADD COLUMN IF NOT EXISTS club_colors          TEXT;
ALTER TABLE teams ADD COLUMN IF NOT EXISTS market_value         INTEGER;
ALTER TABLE teams ADD COLUMN IF NOT EXISTS last_updated         TIMESTAMPTZ;
ALTER TABLE teams ADD COLUMN IF NOT EXISTS running_competitions JSONB;
ALTER TABLE teams ADD COLUMN IF NOT EXISTS coach                JSONB;
ALTER TABLE teams ADD COLUMN IF NOT EXISTS raw                  JSONB;

-- --------------------------------------------------------------------- matches
ALTER TABLE matches ADD COLUMN IF NOT EXISTS area_id        INTEGER;
ALTER TABLE matches ADD COLUMN IF NOT EXISTS area_name      TEXT;
ALTER TABLE matches ADD COLUMN IF NOT EXISTS stage          TEXT;
ALTER TABLE matches ADD COLUMN IF NOT EXISTS group_name     TEXT;
ALTER TABLE matches ADD COLUMN IF NOT EXISTS last_updated   TIMESTAMPTZ;
ALTER TABLE matches ADD COLUMN IF NOT EXISTS minute         INTEGER;
ALTER TABLE matches ADD COLUMN IF NOT EXISTS injury_time    INTEGER;
ALTER TABLE matches ADD COLUMN IF NOT EXISTS attendance     INTEGER;
ALTER TABLE matches ADD COLUMN IF NOT EXISTS venue          TEXT;
ALTER TABLE matches ADD COLUMN IF NOT EXISTS duration       TEXT;
ALTER TABLE matches ADD COLUMN IF NOT EXISTS home_goals_et  INTEGER;
ALTER TABLE matches ADD COLUMN IF NOT EXISTS away_goals_et  INTEGER;
ALTER TABLE matches ADD COLUMN IF NOT EXISTS home_penalties INTEGER;
ALTER TABLE matches ADD COLUMN IF NOT EXISTS away_penalties INTEGER;
ALTER TABLE matches ADD COLUMN IF NOT EXISTS odds_home_win  NUMERIC;
ALTER TABLE matches ADD COLUMN IF NOT EXISTS odds_draw      NUMERIC;
ALTER TABLE matches ADD COLUMN IF NOT EXISTS odds_away_win  NUMERIC;
ALTER TABLE matches ADD COLUMN IF NOT EXISTS referees       JSONB;
ALTER TABLE matches ADD COLUMN IF NOT EXISTS raw            JSONB;

-- --------------------------------------------------------------------- players
ALTER TABLE players ADD COLUMN IF NOT EXISTS first_name     TEXT;
ALTER TABLE players ADD COLUMN IF NOT EXISTS last_name      TEXT;
ALTER TABLE players ADD COLUMN IF NOT EXISTS market_value   INTEGER;
ALTER TABLE players ADD COLUMN IF NOT EXISTS contract_start TEXT;
ALTER TABLE players ADD COLUMN IF NOT EXISTS contract_until TEXT;
ALTER TABLE players ADD COLUMN IF NOT EXISTS raw            JSONB;

-- ---------------------------------------------------------------- team_players
ALTER TABLE team_players ADD COLUMN IF NOT EXISTS contract_start TEXT;
ALTER TABLE team_players ADD COLUMN IF NOT EXISTS contract_until TEXT;
ALTER TABLE team_players ADD COLUMN IF NOT EXISTS raw            JSONB;

-- =============================================================== match views

-- General, human-readable view of any match (team/competition names resolved).
CREATE OR REPLACE VIEW vw_match_details AS
SELECT
    m.id,
    m.utc_date,
    c.name                                  AS competition,
    c.code                                  AS competition_code,
    m.matchday,
    m.stage,
    m.status,
    ht.name                                 AS home_team,
    at.name                                 AS away_team,
    m.home_goals,
    m.away_goals,
    CASE
        WHEN m.home_goals IS NULL OR m.away_goals IS NULL THEN NULL
        ELSE m.home_goals || '-' || m.away_goals
    END                                     AS score,
    m.home_goals_ht,
    m.away_goals_ht,
    m.winner,
    m.venue,
    m.attendance
FROM matches m
JOIN competitions c ON c.id = m.competition_id
JOIN teams ht       ON ht.id = m.home_team_id
JOIN teams at       ON at.id = m.away_team_id;

-- Arsenal-centric view (team id 57): one tidy row per Arsenal match.
CREATE OR REPLACE VIEW vw_arsenal_matches AS
SELECT
    m.id,
    m.utc_date,
    c.name AS competition,
    m.matchday,
    CASE WHEN m.home_team_id = 57 THEN 'Home' ELSE 'Away' END AS venue_side,
    CASE WHEN m.home_team_id = 57 THEN at.name ELSE ht.name END AS opponent,
    CASE WHEN m.home_team_id = 57 THEN m.home_goals ELSE m.away_goals END AS arsenal_goals,
    CASE WHEN m.home_team_id = 57 THEN m.away_goals ELSE m.home_goals END AS opponent_goals,
    CASE
        WHEN m.winner IS NULL THEN NULL
        WHEN m.winner = 'DRAW' THEN 'Draw'
        WHEN (m.winner = 'HOME_TEAM' AND m.home_team_id = 57)
          OR (m.winner = 'AWAY_TEAM' AND m.away_team_id = 57) THEN 'Win'
        ELSE 'Loss'
    END AS result,
    CASE
        WHEN m.winner IS NULL THEN NULL
        WHEN m.winner = 'DRAW' THEN 1
        WHEN (m.winner = 'HOME_TEAM' AND m.home_team_id = 57)
          OR (m.winner = 'AWAY_TEAM' AND m.away_team_id = 57) THEN 3
        ELSE 0
    END AS points,
    m.status
FROM matches m
JOIN competitions c ON c.id = m.competition_id
JOIN teams ht       ON ht.id = m.home_team_id
JOIN teams at       ON at.id = m.away_team_id
WHERE m.home_team_id = 57 OR m.away_team_id = 57
ORDER BY m.utc_date;
