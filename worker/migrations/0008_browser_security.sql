PRAGMA foreign_keys = ON;

-- Email-code verification and email-based password reset are no longer used.
DELETE FROM email_codes;
DROP TABLE IF EXISTS email_codes;
DROP TABLE IF EXISTS password_reset_tokens;

CREATE TABLE IF NOT EXISTS auth_browser_challenges (
  id TEXT PRIMARY KEY,
  purpose TEXT NOT NULL CHECK (purpose IN ('signup','login','admin_bootstrap')),
  nonce_hash TEXT NOT NULL,
  ip_hash TEXT NOT NULL,
  user_agent_hash TEXT NOT NULL,
  expires_at INTEGER NOT NULL,
  attempts INTEGER NOT NULL DEFAULT 0 CHECK (attempts >= 0),
  used_at INTEGER,
  created_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_browser_challenges_ip_created
  ON auth_browser_challenges(ip_hash, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_browser_challenges_expiry
  ON auth_browser_challenges(expires_at);

CREATE TABLE IF NOT EXISTS auth_security_events (
  id TEXT PRIMARY KEY,
  action TEXT NOT NULL,
  outcome TEXT NOT NULL CHECK (outcome IN ('allowed','blocked')),
  reason TEXT NOT NULL DEFAULT '',
  ip_hash TEXT NOT NULL,
  email_hash TEXT NOT NULL DEFAULT '',
  country TEXT NOT NULL DEFAULT '',
  asn TEXT NOT NULL DEFAULT '',
  user_agent_hash TEXT NOT NULL,
  created_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_auth_security_events_ip_created
  ON auth_security_events(ip_hash, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_auth_security_events_email_created
  ON auth_security_events(email_hash, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_auth_security_events_created
  ON auth_security_events(created_at DESC);
