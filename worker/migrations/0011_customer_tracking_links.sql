PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS customer_tracking_links (
  id TEXT PRIMARY KEY CHECK (length(id) = 32),
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  tracking_token TEXT NOT NULL UNIQUE CHECK (length(tracking_token) = 64),
  device_model TEXT NOT NULL,
  identifier_kind TEXT NOT NULL CHECK (identifier_kind IN ('serial','imei')),
  masked_identifier TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'submitted' CHECK (status IN ('submitted','registered','processing','completed','rejected')),
  status_label TEXT NOT NULL,
  status_message TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  processed_at INTEGER,
  completed_at INTEGER
);

CREATE INDEX IF NOT EXISTS idx_customer_tracking_owner_created
  ON customer_tracking_links(user_id, created_at DESC);
