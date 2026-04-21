-- Add email, nickname, password to users
ALTER TABLE users ADD COLUMN email TEXT;
ALTER TABLE users ADD COLUMN nickname TEXT;
ALTER TABLE users ADD COLUMN password TEXT;

CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
