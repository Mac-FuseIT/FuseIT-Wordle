CREATE TABLE IF NOT EXISTS invade_scores (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL,
  nickname TEXT NOT NULL,
  score INTEGER NOT NULL,
  level_reached INTEGER NOT NULL,
  achieved_at TEXT NOT NULL,
  UNIQUE(user_id)
);
