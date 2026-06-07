-- v001 — Initial schema
-- Core tables for the Arsenal FC prediction project: competitions, seasons,
-- teams, matches and standings. Players are added in v002, the full API payload
-- columns and views in v003.

CREATE TABLE IF NOT EXISTS competitions (
    id          INTEGER PRIMARY KEY,
    name        TEXT NOT NULL,
    code        TEXT NOT NULL,
    country     TEXT,
    created_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS seasons (
    id              INTEGER PRIMARY KEY,
    competition_id  INTEGER REFERENCES competitions(id),
    start_date      DATE NOT NULL,
    end_date        DATE NOT NULL,
    current_matchday INTEGER,
    winner_id       INTEGER,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS teams (
    id          INTEGER PRIMARY KEY,
    name        TEXT NOT NULL,
    short_name  TEXT,
    tla         TEXT,
    crest_url   TEXT,
    founded     INTEGER,
    venue       TEXT,
    created_at  TIMESTAMPTZ DEFAULT NOW()
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

-- Arsenal FC has id 57 in football-data.org
INSERT INTO teams (id, name, short_name, tla, venue)
VALUES (57, 'Arsenal FC', 'Arsenal', 'ARS', 'Emirates Stadium')
ON CONFLICT (id) DO NOTHING;
