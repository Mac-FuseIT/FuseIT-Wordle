CREATE TABLE IF NOT EXISTS spanit_puzzles (
  date TEXT PRIMARY KEY,
  grid TEXT NOT NULL,
  theme TEXT NOT NULL DEFAULT '',
  spangram TEXT NOT NULL DEFAULT '',
  theme_words TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS spanit_state (
  user_id INTEGER NOT NULL,
  date TEXT NOT NULL,
  found_words TEXT NOT NULL DEFAULT '[]',
  hint_charges INTEGER NOT NULL DEFAULT 0,
  hints_used INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (user_id, date)
);

CREATE TABLE IF NOT EXISTS spanit_attempts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL,
  date TEXT NOT NULL,
  hints_used INTEGER NOT NULL DEFAULT 0,
  completed INTEGER NOT NULL DEFAULT 0,
  completed_at TEXT,
  UNIQUE(user_id, date)
);
