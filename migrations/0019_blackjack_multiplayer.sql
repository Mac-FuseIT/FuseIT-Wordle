CREATE TABLE IF NOT EXISTS blackjack_mp_games (
  id TEXT PRIMARY KEY,
  creator_id INTEGER NOT NULL,
  creator_name TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'waiting',
  player_count INTEGER NOT NULL DEFAULT 1,
  max_players INTEGER NOT NULL DEFAULT 4,
  created_at TEXT NOT NULL,
  finished_at TEXT
);

CREATE INDEX IF NOT EXISTS idx_bj_mp_status ON blackjack_mp_games(status);
