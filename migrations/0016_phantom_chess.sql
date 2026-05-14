CREATE TABLE IF NOT EXISTS phantom_chess_games (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL,
  date TEXT NOT NULL,
  bot_level INTEGER NOT NULL,
  won INTEGER NOT NULL DEFAULT 0,
  moves INTEGER,
  redos_used INTEGER NOT NULL DEFAULT 0,
  completed_at TEXT,
  UNIQUE(user_id, date)
);

CREATE TABLE IF NOT EXISTS phantom_chess_sessions (
  user_id INTEGER NOT NULL,
  date TEXT NOT NULL,
  fen TEXT NOT NULL DEFAULT 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
  move_history TEXT NOT NULL DEFAULT '[]',
  move_count INTEGER NOT NULL DEFAULT 0,
  redos_used INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY(user_id, date)
);
