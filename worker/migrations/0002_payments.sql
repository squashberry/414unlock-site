PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS payment_sessions (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  launch_token_hash TEXT NOT NULL UNIQUE,
  device_model TEXT NOT NULL,
  identifier_kind TEXT NOT NULL CHECK (identifier_kind IN ('serial','imei','udid')),
  identifier_fingerprint TEXT NOT NULL,
  masked_identifier TEXT NOT NULL,
  payment_reference TEXT NOT NULL UNIQUE,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','verified','expired')),
  provider_reference TEXT,
  created_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL,
  paid_at INTEGER
);

CREATE INDEX IF NOT EXISTS idx_payment_sessions_user_date
ON payment_sessions(user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_payment_sessions_status_expiry
ON payment_sessions(status, expires_at);

CREATE TABLE IF NOT EXISTS payment_code_attempts (
  id TEXT PRIMARY KEY,
  payment_session_id TEXT NOT NULL REFERENCES payment_sessions(id) ON DELETE CASCADE,
  attempted_at INTEGER NOT NULL,
  succeeded INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_payment_attempts_session_time
ON payment_code_attempts(payment_session_id, attempted_at DESC);