-- v002 — Add players
-- Adds the players catalogue and the team_players link table. team_players links
-- players to teams *per season* (season_year, e.g. 2024 = 2024/25) because
-- players change clubs.

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
    season_year     INTEGER,  -- e.g. 2024 for the 2024/25 season
    fetched_at      TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (team_id, player_id, season_year)
);

CREATE INDEX IF NOT EXISTS idx_team_players_team   ON team_players(team_id);
CREATE INDEX IF NOT EXISTS idx_team_players_player ON team_players(player_id);
