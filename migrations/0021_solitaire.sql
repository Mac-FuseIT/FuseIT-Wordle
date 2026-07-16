CREATE TABLE IF NOT EXISTS solitaire_sessions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL,
  date TEXT NOT NULL,
  session_state TEXT NOT NULL DEFAULT '{}',
  started_at TEXT,
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE(user_id, date)
);

CREATE TABLE IF NOT EXISTS solitaire_results (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL,
  date TEXT NOT NULL,
  completed INTEGER NOT NULL DEFAULT 0,
  moves INTEGER NOT NULL DEFAULT 0,
  time_seconds INTEGER NOT NULL DEFAULT 0,
  points INTEGER NOT NULL DEFAULT 0,
  completed_at TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE(user_id, date)
);

CREATE INDEX IF NOT EXISTS idx_solitaire_results_date ON solitaire_results(date);
CREATE INDEX IF NOT EXISTS idx_solitaire_results_user_date ON solitaire_results(user_id, date);
