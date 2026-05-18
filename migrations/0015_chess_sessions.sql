CREATE TABLE IF NOT EXISTS chess_sessions (
  user_id INTEGER NOT NULL,
  date TEXT NOT NULL,
  fen TEXT NOT NULL DEFAULT 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
  move_history TEXT NOT NULL DEFAULT '[]',
  move_count INTEGER NOT NULL DEFAULT 0,
  redos_used INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY(user_id, date)
);
