-- Arsenal FC prediction project schema
--
-- Stores the full football-data.org v4 API payload: typed columns for the useful
-- flat fields plus a `raw JSONB` column on every ingested table holding the complete
-- API object (so nothing is lost, incl. nested arrays and paid-tier fields).

CREATE TABLE IF NOT EXISTS competitions (
    id          INTEGER PRIMARY KEY,
    name        TEXT NOT NULL,
    code        TEXT NOT NULL,
    type        TEXT,
    emblem      TEXT,
    country     TEXT,
    area_id     INTEGER,
    area_name   TEXT,
    raw         JSONB,
    created_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS seasons (
    id              INTEGER PRIMARY KEY,
    competition_id  INTEGER REFERENCES competitions(id),
    start_date      DATE NOT NULL,
    end_date        DATE NOT NULL,
    current_matchday INTEGER,
    winner_id       INTEGER,
    winner          JSONB,
    stages          JSONB,
    raw             JSONB,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS teams (
    id                   INTEGER PRIMARY KEY,
    name                 TEXT NOT NULL,
    short_name           TEXT,
    tla                  TEXT,
    crest_url            TEXT,
    founded              INTEGER,
    venue                TEXT,
    area_id              INTEGER,
    area_name            TEXT,
    address              TEXT,
    website              TEXT,
    club_colors          TEXT,
    market_value         INTEGER,
    last_updated         TIMESTAMPTZ,
    running_competitions JSONB,
    coach                JSONB,
    raw                  JSONB,
    created_at           TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS matches (
    id                  INTEGER PRIMARY KEY,
    competition_id      INTEGER REFERENCES competitions(id),
    season_id           INTEGER REFERENCES seasons(id),
    matchday            INTEGER,
    utc_date            TIMESTAMPTZ NOT NULL,
    status              TEXT NOT NULL,
    home_team_id        INTEGER REFERENCES teams(id),
    away_team_id        INTEGER REFERENCES teams(id),
    home_goals          INTEGER,
    away_goals          INTEGER,
    home_goals_ht       INTEGER,
    away_goals_ht       INTEGER,
    winner              TEXT,
    area_id             INTEGER,
    area_name           TEXT,
    stage               TEXT,
    group_name          TEXT,
    last_updated        TIMESTAMPTZ,
    minute              INTEGER,
    injury_time         INTEGER,
    attendance          INTEGER,
    venue               TEXT,
    duration            TEXT,
    home_goals_et       INTEGER,
    away_goals_et       INTEGER,
    home_penalties      INTEGER,
    away_penalties      INTEGER,
    odds_home_win       NUMERIC,
    odds_draw           NUMERIC,
    odds_away_win       NUMERIC,
    referees            JSONB,
    raw                 JSONB,
    created_at          TIMESTAMPTZ DEFAULT NOW(),
    updated_at          TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_matches_home_team ON matches(home_team_id);
CREATE INDEX IF NOT EXISTS idx_matches_away_team ON matches(away_team_id);
CREATE INDEX IF NOT EXISTS idx_matches_utc_date  ON matches(utc_date);
CREATE INDEX IF NOT EXISTS idx_matches_status    ON matches(status);

CREATE TABLE IF NOT EXISTS team_standings (
    id              SERIAL PRIMARY KEY,
    competition_id  INTEGER REFERENCES competitions(id),
    season_id       INTEGER REFERENCES seasons(id),
    matchday        INTEGER,
    team_id         INTEGER REFERENCES teams(id),
    position        INTEGER,
    played_games    INTEGER,
    won             INTEGER,
    draw            INTEGER,
    lost            INTEGER,
    points          INTEGER,
    goals_for       INTEGER,
    goals_against   INTEGER,
    goal_difference INTEGER,
    fetched_at      TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (season_id, matchday, team_id)
);

CREATE TABLE IF NOT EXISTS players (
    id              INTEGER PRIMARY KEY,
    name            TEXT NOT NULL,
    first_name      TEXT,
    last_name       TEXT,
    position        TEXT,
    nationality     TEXT,
    date_of_birth   DATE,
    market_value    INTEGER,
    contract_start  TEXT,
    contract_until  TEXT,
    raw             JSONB,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

-- Links players to teams per season (players move clubs)
CREATE TABLE IF NOT EXISTS team_players (
    id              SERIAL PRIMARY KEY,
    team_id         INTEGER REFERENCES teams(id),
    player_id       INTEGER REFERENCES players(id),
    shirt_number    INTEGER,
    season_year     INTEGER,  -- e.g. 2024 for the 2024/25 season
    contract_start  TEXT,
    contract_until  TEXT,
    raw             JSONB,
    fetched_at      TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (team_id, player_id, season_year)
);

CREATE INDEX IF NOT EXISTS idx_team_players_team   ON team_players(team_id);
CREATE INDEX IF NOT EXISTS idx_team_players_player ON team_players(player_id);

-- Arsenal FC has id 57 in football-data.org
INSERT INTO teams (id, name, short_name, tla, venue)
VALUES (57, 'Arsenal FC', 'Arsenal', 'ARS', 'Emirates Stadium')
ON CONFLICT (id) DO NOTHING;

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
