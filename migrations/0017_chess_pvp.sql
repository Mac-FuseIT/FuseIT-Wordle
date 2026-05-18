CREATE TABLE IF NOT EXISTS chess_pvp_challenges (
  id TEXT PRIMARY KEY,
  challenger_id INTEGER NOT NULL,
  challenger_name TEXT NOT NULL,
  opponent_id INTEGER NOT NULL,
  opponent_name TEXT NOT NULL,
  color_choice TEXT NOT NULL DEFAULT 'random',
  time_control TEXT NOT NULL DEFAULT 'unlimited',
  status TEXT NOT NULL DEFAULT 'pending',
  session_id TEXT,
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS chess_pvp_results (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  winner_id INTEGER NOT NULL,
  loser_id INTEGER NOT NULL,
  winner_name TEXT NOT NULL,
  loser_name TEXT NOT NULL,
  moves INTEGER NOT NULL,
  time_control TEXT NOT NULL,
  played_at TEXT NOT NULL
);
