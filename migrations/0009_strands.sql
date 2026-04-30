CREATE TABLE IF NOT EXISTS strand_puzzles (
  date TEXT PRIMARY KEY,
  grid TEXT NOT NULL,
  theme TEXT NOT NULL,
  spangram TEXT NOT NULL,
  theme_words TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS strand_attempts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL,
  date TEXT NOT NULL,
  hints_used INTEGER NOT NULL DEFAULT 0,
  completed INTEGER NOT NULL DEFAULT 0,
  completed_at TEXT,
  FOREIGN KEY (user_id) REFERENCES users(id),
  UNIQUE (user_id, date)
);

CREATE TABLE IF NOT EXISTS strand_state (
  user_id INTEGER NOT NULL,
  date TEXT NOT NULL,
  found_words TEXT NOT NULL DEFAULT '[]',
  hint_charges INTEGER NOT NULL DEFAULT 0,
  hints_used INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (user_id, date),
  FOREIGN KEY (user_id) REFERENCES users(id)
);
