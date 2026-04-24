CREATE TABLE IF NOT EXISTS crossword_puzzles (
  date TEXT PRIMARY KEY,
  grid TEXT NOT NULL,
  clues_across TEXT NOT NULL,
  clues_down TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS crossword_attempts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL,
  date TEXT NOT NULL,
  time_seconds INTEGER NOT NULL,
  completed_at TEXT,
  FOREIGN KEY (user_id) REFERENCES users(id),
  UNIQUE (user_id, date)
);

CREATE TABLE IF NOT EXISTS crossword_state (
  user_id INTEGER NOT NULL,
  date TEXT NOT NULL,
  grid TEXT NOT NULL DEFAULT '[]',
  elapsed INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (user_id, date),
  FOREIGN KEY (user_id) REFERENCES users(id)
);
