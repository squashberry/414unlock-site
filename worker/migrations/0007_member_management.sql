PRAGMA foreign_keys = ON;

ALTER TABLE users ADD COLUMN deleted_at INTEGER;
ALTER TABLE users ADD COLUMN deleted_by TEXT;
ALTER TABLE users ADD COLUMN deleted_note TEXT NOT NULL DEFAULT '';
ALTER TABLE users ADD COLUMN auth_version INTEGER NOT NULL DEFAULT 0 CHECK (auth_version >= 0);

CREATE INDEX IF NOT EXISTS idx_users_deleted_created
  ON users(deleted_at, created_at DESC);

CREATE TABLE IF NOT EXISTS password_reset_tokens (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash TEXT NOT NULL UNIQUE,
  expires_at INTEGER NOT NULL,
  used_at INTEGER,
  used_by TEXT,
  created_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_password_reset_user_expiry
  ON password_reset_tokens(user_id, expires_at);

CREATE TABLE IF NOT EXISTS admin_bootstrap_tokens (
  id TEXT PRIMARY KEY,
  token_hash TEXT NOT NULL UNIQUE,
  expires_at INTEGER NOT NULL,
  used_at INTEGER,
  created_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_admin_bootstrap_expiry
  ON admin_bootstrap_tokens(expires_at);
