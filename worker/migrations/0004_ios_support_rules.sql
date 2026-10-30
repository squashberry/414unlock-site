PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS ios_support_rules (
  id TEXT PRIMARY KEY,
  match_type TEXT NOT NULL CHECK (match_type IN ('exact','range')),
  version TEXT,
  min_version TEXT,
  max_version TEXT,
  enabled INTEGER NOT NULL DEFAULT 0 CHECK (enabled IN (0,1)),
  note TEXT NOT NULL DEFAULT '',
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  updated_by TEXT NOT NULL,
  CHECK (
    (match_type='exact' AND version IS NOT NULL AND min_version IS NULL AND max_version IS NULL)
    OR
    (match_type='range' AND version IS NULL AND min_version IS NOT NULL AND max_version IS NOT NULL)
  )
);

CREATE INDEX IF NOT EXISTS idx_ios_support_rules_enabled_updated
  ON ios_support_rules(enabled, updated_at DESC);
