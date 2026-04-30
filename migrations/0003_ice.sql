-- Ice.IT sessions and matches
CREATE TABLE IF NOT EXISTS ice_sessions (
  session_id TEXT PRIMARY KEY,
  creator_id INTEGER,
  settings TEXT,
  status TEXT,
  created_at TEXT,
  started_at TEXT,
  finished_at TEXT
);

CREATE TABLE IF NOT EXISTS ice_matches (
  match_id INTEGER PRIMARY KEY AUTOINCREMENT,
  session_id TEXT,
  winner_team INTEGER,
  final_score TEXT,
  duration_seconds INTEGER,
  created_at TEXT
);
