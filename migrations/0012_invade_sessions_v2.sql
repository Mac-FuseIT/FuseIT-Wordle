DROP TABLE IF EXISTS invade_sessions;
CREATE TABLE invade_sessions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL,
  session_token TEXT NOT NULL UNIQUE,
  started_at TEXT NOT NULL,
  last_updated_at TEXT NOT NULL,
  validated_score INTEGER NOT NULL DEFAULT 0,
  validated_level INTEGER NOT NULL DEFAULT 1
);
