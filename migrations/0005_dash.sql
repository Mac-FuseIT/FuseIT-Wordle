-- Dash.IT tables
CREATE TABLE IF NOT EXISTS dash_levels (
  date TEXT PRIMARY KEY,
  level_data TEXT NOT NULL,
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS dash_scores (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL,
  date TEXT NOT NULL,
  nickname TEXT NOT NULL,
  score INTEGER NOT NULL,
  time_seconds INTEGER NOT NULL,
  coins INTEGER NOT NULL,
  completed_at TEXT NOT NULL,
  UNIQUE(user_id, date)
);
