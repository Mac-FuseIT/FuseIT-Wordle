CREATE TABLE IF NOT EXISTS pong_sessions (
  session_id TEXT PRIMARY KEY,
  creator_name TEXT NOT NULL,
  created_at TEXT NOT NULL
);
