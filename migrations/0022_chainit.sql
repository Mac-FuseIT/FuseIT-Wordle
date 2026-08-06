CREATE TABLE IF NOT EXISTS chainit_puzzles (
  date TEXT PRIMARY KEY,
  start_word TEXT NOT NULL,
  target_word TEXT NOT NULL,
  length INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS chainit_state (
  user_id INTEGER NOT NULL,
  date TEXT NOT NULL,
  guesses TEXT NOT NULL DEFAULT '[]',
  PRIMARY KEY (user_id, date),
  FOREIGN KEY (user_id) REFERENCES users(id)
);

CREATE TABLE IF NOT EXISTS chainit_attempts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL,
  date TEXT NOT NULL,
  guesses TEXT NOT NULL,
  steps INTEGER NOT NULL,
  completed_at TEXT,
  FOREIGN KEY (user_id) REFERENCES users(id),
  UNIQUE (user_id, date)
);

CREATE INDEX IF NOT EXISTS idx_chainit_attempts_date ON chainit_attempts(date);
