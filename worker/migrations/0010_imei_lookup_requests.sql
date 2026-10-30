PRAGMA foreign_keys = ON;

-- One wallet charge per live HiCellTek lookup request. The full IMEI stays encrypted
-- in the existing service_orders fields; this table stores only the TAC and a
-- short-lived, sanitised result for safe browser retries.
CREATE TABLE IF NOT EXISTS imei_lookup_requests (
  request_id TEXT PRIMARY KEY CHECK (length(request_id) = 32),
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  service_order_id TEXT NOT NULL UNIQUE REFERENCES service_orders(id) ON DELETE CASCADE,
  identifier_fingerprint TEXT NOT NULL,
  tac TEXT NOT NULL CHECK (length(tac) = 8 AND tac NOT GLOB '*[^0-9]*'),
  status TEXT NOT NULL CHECK (status IN ('processing','completed','failed')),
  result_json TEXT,
  error_code TEXT,
  error_message TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL,
  CHECK (status != 'completed' OR result_json IS NOT NULL OR expires_at <= updated_at)
);

CREATE INDEX IF NOT EXISTS idx_imei_lookup_user_date
  ON imei_lookup_requests(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_imei_lookup_fingerprint_date
  ON imei_lookup_requests(user_id, identifier_fingerprint, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_imei_lookup_expiry
  ON imei_lookup_requests(status, expires_at);
CREATE UNIQUE INDEX IF NOT EXISTS idx_imei_lookup_one_processing_per_device
  ON imei_lookup_requests(user_id, identifier_fingerprint)
  WHERE status = 'processing';
