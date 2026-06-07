-- Migration: add players and team_players tables

CREATE TABLE IF NOT EXISTS players (
    id              INTEGER PRIMARY KEY,
    name            TEXT NOT NULL,
    position        TEXT,
    nationality     TEXT,
    date_of_birth   DATE,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS team_players (
    id              SERIAL PRIMARY KEY,
    team_id         INTEGER REFERENCES teams(id),
    player_id       INTEGER REFERENCES players(id),
    shirt_number    INTEGER,
    season_year     INTEGER,
    fetched_at      TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (team_id, player_id, season_year)
);

CREATE INDEX IF NOT EXISTS idx_team_players_team   ON team_players(team_id);
CREATE INDEX IF NOT EXISTS idx_team_players_player ON team_players(player_id);
