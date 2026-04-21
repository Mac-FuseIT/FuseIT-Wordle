CREATE TABLE IF NOT EXISTS users (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  email TEXT UNIQUE,
  nickname TEXT,
  password TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS daily_words (
  date TEXT PRIMARY KEY,
  word TEXT NOT NULL,
  length INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS game_state (
  user_id INTEGER NOT NULL,
  date TEXT NOT NULL,
  guesses TEXT NOT NULL DEFAULT '[]',
  PRIMARY KEY (user_id, date),
  FOREIGN KEY (user_id) REFERENCES users(id)
);

CREATE TABLE IF NOT EXISTS attempts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL,
  date TEXT NOT NULL,
  guesses TEXT,
  num_guesses INTEGER NOT NULL,
  solved INTEGER NOT NULL DEFAULT 0,
  completed_at TEXT,
  FOREIGN KEY (user_id) REFERENCES users(id),
  UNIQUE (user_id, date)
);

CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
