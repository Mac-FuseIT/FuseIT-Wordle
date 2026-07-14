CREATE TABLE IF NOT EXISTS roulette_results (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL,
  date TEXT NOT NULL,
  spins_played INTEGER NOT NULL DEFAULT 0,
  total_wagered INTEGER NOT NULL DEFAULT 0,
  total_won INTEGER NOT NULL DEFAULT 0,
  net_profit INTEGER NOT NULL DEFAULT 0,
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE(user_id, date)
);

CREATE INDEX IF NOT EXISTS idx_roulette_results_date ON roulette_results(date);
CREATE INDEX IF NOT EXISTS idx_roulette_results_user_date ON roulette_results(user_id, date);
