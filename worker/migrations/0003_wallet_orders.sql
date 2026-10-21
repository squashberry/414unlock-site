PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS wallets (
  user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  balance INTEGER NOT NULL DEFAULT 0 CHECK (balance >= 0),
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS wallet_transactions (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  kind TEXT NOT NULL CHECK (kind IN ('topup','purchase','refund','adjustment')),
  amount INTEGER NOT NULL,
  balance_after INTEGER NOT NULL CHECK (balance_after >= 0),
  reference TEXT NOT NULL UNIQUE,
  description TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  created_by TEXT
);
CREATE INDEX IF NOT EXISTS idx_wallet_transactions_user_date
  ON wallet_transactions(user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS topup_requests (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  amount INTEGER NOT NULL CHECK (amount BETWEEN 50 AND 100000),
  request_reference TEXT NOT NULL UNIQUE,
  provider_reference TEXT UNIQUE,
  status TEXT NOT NULL DEFAULT 'awaiting_payment'
    CHECK (status IN ('awaiting_payment','pending','approved','rejected')),
  created_at INTEGER NOT NULL,
  submitted_at INTEGER,
  reviewed_at INTEGER,
  reviewed_by TEXT,
  review_note TEXT
);
CREATE INDEX IF NOT EXISTS idx_topups_user_date ON topup_requests(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_topups_status_date ON topup_requests(status, created_at ASC);

CREATE TABLE IF NOT EXISTS service_orders (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  service_key TEXT NOT NULL CHECK (service_key IN ('unlock','imei_check')),
  model_key TEXT NOT NULL CHECK (model_key IN ('iphone_6','iphone_7','iphone_8','iphone_x','iphone_xr','iphone_11_12','iphone_13_14','iphone_15','iphone_16')),
  device_model TEXT NOT NULL,
  identifier_kind TEXT NOT NULL CHECK (identifier_kind IN ('serial','imei')),
  identifier_ciphertext TEXT NOT NULL,
  identifier_fingerprint TEXT NOT NULL,
  masked_identifier TEXT NOT NULL,
  issue_description TEXT NOT NULL,
  fast_service INTEGER NOT NULL DEFAULT 0 CHECK (fast_service IN (0,1)),
  amount_due INTEGER NOT NULL CHECK (amount_due >= 0),
  status TEXT NOT NULL DEFAULT 'submitted'
    CHECK (status IN ('submitted','registered','processing','completed','rejected')),
  ownership_confirmed INTEGER NOT NULL CHECK (ownership_confirmed = 1),
  no_signal_confirmed INTEGER NOT NULL DEFAULT 0 CHECK (no_signal_confirmed IN (0,1)),
  check_credit_order_id TEXT REFERENCES service_orders(id),
  check_credit_used_at INTEGER,
  provider_reference TEXT,
  admin_note TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  processed_at INTEGER,
  completed_at INTEGER,
  reviewed_by TEXT,
  CHECK (check_credit_order_id IS NULL OR service_key = 'unlock'),
  CHECK (service_key != 'unlock' OR no_signal_confirmed = 1),
  CHECK (service_key != 'imei_check' OR fast_service = 0)
);
CREATE INDEX IF NOT EXISTS idx_orders_user_date ON service_orders(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_orders_status_date ON service_orders(status, created_at ASC);
CREATE INDEX IF NOT EXISTS idx_orders_device_fingerprint ON service_orders(user_id, identifier_fingerprint, service_key, created_at DESC);

-- Funding is created only by an administrator changing a payment request from pending to approved.
CREATE TRIGGER IF NOT EXISTS wallet_credit_approved_topup
AFTER UPDATE OF status ON topup_requests
WHEN OLD.status = 'pending' AND NEW.status = 'approved'
BEGIN
  INSERT OR IGNORE INTO wallets (user_id, balance, created_at, updated_at)
  VALUES (NEW.user_id, 0, COALESCE(NEW.reviewed_at, NEW.created_at), COALESCE(NEW.reviewed_at, NEW.created_at));
  UPDATE wallets
    SET balance = balance + NEW.amount, updated_at = COALESCE(NEW.reviewed_at, NEW.created_at)
    WHERE user_id = NEW.user_id;
  INSERT INTO wallet_transactions (id, user_id, kind, amount, balance_after, reference, description, created_at, created_by)
  VALUES (
    lower(hex(randomblob(16))), NEW.user_id, 'topup', NEW.amount,
    (SELECT balance FROM wallets WHERE user_id = NEW.user_id),
    'topup:' || NEW.id,
    'SquashberryPay top-up · ' || NEW.request_reference,
    COALESCE(NEW.reviewed_at, NEW.created_at), NEW.reviewed_by
  );
END;

-- Orders are charged inside the same database transaction as order creation.
-- Identifiers are encrypted by the Worker before they are written to D1.
CREATE TRIGGER IF NOT EXISTS wallet_charge_service_order
BEFORE INSERT ON service_orders
BEGIN
  SELECT CASE
    WHEN (SELECT balance FROM wallets WHERE user_id = NEW.user_id) IS NULL
      THEN RAISE(ABORT, 'WALLET_MISSING')
    WHEN (SELECT balance FROM wallets WHERE user_id = NEW.user_id) < NEW.amount_due
      THEN RAISE(ABORT, 'INSUFFICIENT_BALANCE')
  END;

  SELECT CASE
    WHEN NEW.check_credit_order_id IS NOT NULL
     AND NOT EXISTS (
       SELECT 1 FROM service_orders c
       WHERE c.id = NEW.check_credit_order_id
         AND c.user_id = NEW.user_id
         AND c.service_key = 'imei_check'
         AND c.status = 'completed'
         AND c.check_credit_used_at IS NULL
         AND c.identifier_fingerprint = NEW.identifier_fingerprint
         AND c.created_at >= NEW.created_at - 604800
     )
      THEN RAISE(ABORT, 'CHECK_CREDIT_INVALID')
  END;

  UPDATE wallets
    SET balance = balance - NEW.amount_due, updated_at = NEW.created_at
    WHERE user_id = NEW.user_id AND balance >= NEW.amount_due;

  SELECT CASE WHEN changes() = 0 THEN RAISE(ABORT, 'INSUFFICIENT_BALANCE') END;

  UPDATE service_orders
    SET check_credit_used_at = NEW.created_at
    WHERE id = NEW.check_credit_order_id AND check_credit_used_at IS NULL;

  SELECT CASE
    WHEN NEW.check_credit_order_id IS NOT NULL AND changes() = 0
      THEN RAISE(ABORT, 'CHECK_CREDIT_INVALID')
  END;

  INSERT INTO wallet_transactions (id, user_id, kind, amount, balance_after, reference, description, created_at, created_by)
  VALUES (
    lower(hex(randomblob(16))), NEW.user_id, 'purchase', -NEW.amount_due,
    (SELECT balance FROM wallets WHERE user_id = NEW.user_id),
    'order:' || NEW.id,
    CASE WHEN NEW.service_key = 'imei_check' THEN 'IMEI check'
      ELSE 'iPhone unlock service · ' || NEW.model_key END,
    NEW.created_at, NULL
  );
END;

-- Rejections before processing starts return the service charge automatically.
CREATE TRIGGER IF NOT EXISTS wallet_refund_unstarted_rejected_order
AFTER UPDATE OF status ON service_orders
WHEN OLD.status IN ('submitted','registered') AND NEW.status = 'rejected'
BEGIN
  UPDATE wallets
    SET balance = balance + OLD.amount_due, updated_at = NEW.updated_at
    WHERE user_id = OLD.user_id;
  INSERT INTO wallet_transactions (id, user_id, kind, amount, balance_after, reference, description, created_at, created_by)
  VALUES (
    lower(hex(randomblob(16))), OLD.user_id, 'refund', OLD.amount_due,
    (SELECT balance FROM wallets WHERE user_id = OLD.user_id),
    'refund:' || OLD.id,
    'Refund · service rejected before processing',
    NEW.updated_at, NEW.reviewed_by
  );
END;