-- Centralized, administrator-managed public-site controls.
CREATE TABLE IF NOT EXISTS site_controls (
  control_key TEXT PRIMARY KEY,
  control_value TEXT NOT NULL,
  updated_by TEXT NOT NULL,
  updated_at INTEGER NOT NULL
);
