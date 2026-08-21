-- Add mode column to chess_games and chess_sessions to support amateur/expert dual daily games.
-- SQLite doesn't support dropping constraints, so we recreate the tables.

-- 1. Recreate chess_games with mode column
CREATE TABLE chess_games_new (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL,
  date TEXT NOT NULL,
  bot_level INTEGER NOT NULL,
  won INTEGER NOT NULL DEFAULT 0,
  moves INTEGER,
  redos_used INTEGER NOT NULL DEFAULT 0,
  completed_at TEXT,
  mode TEXT NOT NULL DEFAULT 'expert',
  UNIQUE(user_id, date, mode)
);

INSERT INTO chess_games_new (id, user_id, date, bot_level, won, moves, redos_used, completed_at, mode)
SELECT id, user_id, date, bot_level, won, moves, redos_used, completed_at, 'expert'
FROM chess_games;

DROP TABLE chess_games;
ALTER TABLE chess_games_new RENAME TO chess_games;

-- 2. Recreate chess_sessions with mode column
CREATE TABLE chess_sessions_new (
  user_id INTEGER NOT NULL,
  date TEXT NOT NULL,
  fen TEXT NOT NULL DEFAULT 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
  move_history TEXT NOT NULL DEFAULT '[]',
  move_count INTEGER NOT NULL DEFAULT 0,
  redos_used INTEGER NOT NULL DEFAULT 0,
  mode TEXT NOT NULL DEFAULT 'expert',
  PRIMARY KEY(user_id, date, mode)
);

INSERT INTO chess_sessions_new (user_id, date, fen, move_history, move_count, redos_used, mode)
SELECT user_id, date, fen, move_history, move_count, redos_used, 'expert'
FROM chess_sessions;

DROP TABLE chess_sessions;
ALTER TABLE chess_sessions_new RENAME TO chess_sessions;
