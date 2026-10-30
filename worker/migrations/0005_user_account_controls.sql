PRAGMA foreign_keys = ON;

ALTER TABLE users ADD COLUMN account_active INTEGER NOT NULL DEFAULT 1
  CHECK (account_active IN (0,1));
ALTER TABLE users ADD COLUMN account_status_note TEXT NOT NULL DEFAULT '';
ALTER TABLE users ADD COLUMN account_status_updated_at INTEGER;
ALTER TABLE users ADD COLUMN account_status_updated_by TEXT;

CREATE INDEX IF NOT EXISTS idx_users_account_active_created
  ON users(account_active, created_at DESC);

CREATE TABLE IF NOT EXISTS admin_audit_log (
  id TEXT PRIMARY KEY,
  actor_email TEXT NOT NULL,
  action TEXT NOT NULL,
  target_user_id TEXT,
  details TEXT NOT NULL DEFAULT '',
  created_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_admin_audit_log_created
  ON admin_audit_log(created_at DESC);
