import pathlib
import sqlite3
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
MIGRATIONS = ROOT / "migrations"


class WalletMigrationTests(unittest.TestCase):
    def setUp(self):
        self.db = sqlite3.connect(":memory:")
        self.db.execute("PRAGMA foreign_keys = ON")
        for migration in ("0001_init.sql", "0002_payments.sql", "0003_wallet_orders.sql", "0004_ios_support_rules.sql", "0005_user_account_controls.sql", "0006_support_chat.sql", "0007_member_management.sql"):
            self.db.executescript((MIGRATIONS / migration).read_text(encoding="utf-8"))
        self.db.execute(
            "INSERT INTO users (id, full_name, email, password_salt, password_hash, email_verified, created_at) VALUES (?,?,?,?,?,?,?)",
            ("user-1", "Test Customer", "customer@example.test", "salt", "hash", 1, 1000),
        )
        self.db.commit()

    def tearDown(self):
        self.db.close()

    def wallet_balance(self):
        row = self.db.execute("SELECT balance FROM wallets WHERE user_id='user-1'").fetchone()
        return None if row is None else row[0]

    def seed_wallet(self, amount):
        self.db.execute(
            "INSERT INTO wallets (user_id, balance, created_at, updated_at) VALUES ('user-1', ?, 1000, 1000)",
            (amount,),
        )
        self.db.commit()

    def insert_order(self, order_id, service="unlock", amount=1400, identifier="SERIAL0001", model="iphone_6", check_id=None, fast=0):
        created = 2000 + len(order_id)
        self.db.execute(
            """INSERT INTO service_orders (
                id, user_id, service_key, model_key, device_model, identifier_kind,
                identifier_ciphertext, identifier_fingerprint, masked_identifier,
                issue_description, fast_service, amount_due, status, ownership_confirmed,
                no_signal_confirmed, check_credit_order_id, check_credit_used_at,
                provider_reference, admin_note, created_at, updated_at, processed_at,
                completed_at, reviewed_by
            ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,'submitted',1,?,?,NULL,NULL,NULL,?,?,NULL,NULL,NULL)""",
            (
                order_id, "user-1", service, model, "iPhone test model", "serial",
                "encrypted-test-value", "fingerprint-" + identifier, "•••• " + identifier[-4:],
                "Authorized service request", fast, amount, 0 if service == "imei_check" else 1,
                check_id, created, created,
            ),
        )
        self.db.commit()


    def test_new_accounts_are_active_and_admin_can_deactivate_without_deleting_data(self):
        row = self.db.execute(
            "SELECT account_active, account_status_note FROM users WHERE id='user-1'"
        ).fetchone()
        self.assertEqual(row, (1, ""))

        self.db.execute(
            "UPDATE users SET account_active=0, account_status_note='Manual admin review', "
            "account_status_updated_at=2000, account_status_updated_by='admin@example.test' WHERE id='user-1'"
        )
        self.db.commit()

        row = self.db.execute(
            "SELECT account_active, account_status_note, account_status_updated_by FROM users WHERE id='user-1'"
        ).fetchone()
        self.assertEqual(row, (0, "Manual admin review", "admin@example.test"))
        self.assertEqual(self.db.execute("SELECT COUNT(*) FROM users WHERE id='user-1'").fetchone()[0], 1)

    def test_member_management_adds_recovery_archive_and_bootstrap_controls(self):
        columns = {row[1] for row in self.db.execute("PRAGMA table_info(users)").fetchall()}
        self.assertTrue({"deleted_at", "deleted_by", "deleted_note", "auth_version"}.issubset(columns))
        self.db.execute(
            "INSERT INTO admin_bootstrap_tokens (id, token_hash, expires_at, created_at) VALUES ('bootstrap-1','hashed-token',5000,1000)"
        )
        self.assertEqual(self.db.execute("SELECT used_at FROM admin_bootstrap_tokens WHERE id='bootstrap-1'").fetchone()[0], None)
        self.db.execute("UPDATE users SET deleted_at=2000,deleted_by='admin@example.test',deleted_note='requested',account_active=0,auth_version=auth_version+1 WHERE id='user-1'")
        self.db.commit()
        self.assertEqual(self.db.execute("SELECT deleted_at,account_active,auth_version FROM users WHERE id='user-1'").fetchone(), (2000,0,1))
        self.db.execute("UPDATE users SET deleted_at=NULL,deleted_by=NULL,deleted_note='',account_active=1,auth_version=auth_version+1 WHERE id='user-1'")
        self.db.commit()
        self.assertEqual(self.db.execute("SELECT deleted_at,account_active,auth_version FROM users WHERE id='user-1'").fetchone(), (None,1,2))

    def test_password_reset_tokens_are_single_use_records(self):
        self.db.execute("INSERT INTO password_reset_tokens (id,user_id,token_hash,expires_at,created_at) VALUES ('reset-1','user-1','hashed-reset',3000,1000)")
        self.db.execute("UPDATE password_reset_tokens SET used_at=2000,used_by='request-1' WHERE id='reset-1' AND used_at IS NULL AND expires_at>2000")
        self.db.commit()
        self.assertEqual(self.db.execute("SELECT used_at,used_by FROM password_reset_tokens WHERE id='reset-1'").fetchone(), (2000,"request-1"))
        again = self.db.execute("UPDATE password_reset_tokens SET used_at=2100,used_by='request-2' WHERE id='reset-1' AND used_at IS NULL AND expires_at>2100")
        self.db.commit()
        self.assertEqual(again.rowcount, 0)

    def test_support_tickets_and_messages_are_created_and_can_be_closed(self):
        self.db.execute(
            "INSERT INTO support_tickets (id,user_id,subject,status,created_at,updated_at,last_message_at) "
            "VALUES ('ticket-1','user-1','Wallet top-up question','open',2000,2000,2000)"
        )
        self.db.execute(
            "INSERT INTO support_messages (id,ticket_id,sender_type,sender_email,body,created_at) "
            "VALUES ('message-1','ticket-1','customer','customer@example.test','My top-up is missing.',2000)"
        )
        self.db.commit()
        self.assertEqual(self.db.execute("SELECT COUNT(*) FROM support_messages WHERE ticket_id='ticket-1'").fetchone()[0],1)
        self.db.execute("UPDATE support_tickets SET status='closed' WHERE id='ticket-1'")
        self.db.commit()
        self.assertEqual(self.db.execute("SELECT status FROM support_tickets WHERE id='ticket-1'").fetchone()[0],"closed")
    def test_topup_credits_wallet_once_after_pending_payment_is_approved(self):
        self.db.execute(
            """INSERT INTO topup_requests
            (id,user_id,amount,request_reference,provider_reference,status,created_at,submitted_at)
            VALUES ('topup-1','user-1',3000,'414T-ABC123','SBP-TXN-1','awaiting_payment',1200,NULL)"""
        )
        self.db.execute(
            "UPDATE topup_requests SET status='pending', submitted_at=1300 WHERE id='topup-1'"
        )
        self.db.execute(
            "UPDATE topup_requests SET status='approved', reviewed_by='admin@example.test', reviewed_at=1400 WHERE id='topup-1' AND status='pending'"
        )
        self.db.commit()
        self.assertEqual(self.wallet_balance(), 3000)
        self.assertEqual(self.db.execute("SELECT COUNT(*) FROM wallet_transactions WHERE reference='topup:topup-1'").fetchone()[0], 1)
        self.db.execute(
            "UPDATE topup_requests SET status='approved', reviewed_by='admin@example.test', reviewed_at=1500 WHERE id='topup-1' AND status='pending'"
        )
        self.db.commit()
        self.assertEqual(self.wallet_balance(), 3000)
        self.assertEqual(self.db.execute("SELECT COUNT(*) FROM wallet_transactions WHERE reference='topup:topup-1'").fetchone()[0], 1)

    def test_service_request_is_charged_and_preprocessing_rejection_refunds_it(self):
        self.seed_wallet(2000)
        self.insert_order("order-1", amount=1400)
        self.assertEqual(self.wallet_balance(), 600)
        self.assertEqual(self.db.execute("SELECT amount FROM wallet_transactions WHERE reference='order:order-1'").fetchone()[0], -1400)
        self.db.execute(
            "UPDATE service_orders SET status='rejected', reviewed_by='admin@example.test', updated_at=2200 WHERE id='order-1'"
        )
        self.db.commit()
        self.assertEqual(self.wallet_balance(), 2000)
        self.assertEqual(self.db.execute("SELECT amount FROM wallet_transactions WHERE reference='refund:order-1'").fetchone()[0], 1400)

    def test_rejection_after_processing_does_not_refund_automatically(self):
        self.seed_wallet(2000)
        self.insert_order("order-2", amount=1400)
        self.db.execute("UPDATE service_orders SET status='registered', updated_at=2200 WHERE id='order-2'")
        self.db.execute("UPDATE service_orders SET status='processing', processed_at=2300, updated_at=2300 WHERE id='order-2'")
        self.db.execute("UPDATE service_orders SET status='rejected', reviewed_by='admin@example.test', updated_at=2400 WHERE id='order-2'")
        self.db.commit()
        self.assertEqual(self.wallet_balance(), 600)
        self.assertEqual(self.db.execute("SELECT COUNT(*) FROM wallet_transactions WHERE reference='refund:order-2'").fetchone()[0], 0)

    def test_completed_same_device_imei_check_credit_applies_only_once(self):
        self.seed_wallet(150)
        self.insert_order("check-1", service="imei_check", amount=150, identifier="SAME-SERIAL-0001")
        self.db.execute("UPDATE service_orders SET status='completed', completed_at=2100, updated_at=2100 WHERE id='check-1'")
        self.db.commit()
        self.assertEqual(self.wallet_balance(), 0)
        self.db.execute("UPDATE wallets SET balance=2000, updated_at=2200 WHERE user_id='user-1'")
        self.db.commit()
        self.insert_order("unlock-after-check", amount=1250, identifier="SAME-SERIAL-0001", check_id="check-1")
        self.assertEqual(self.wallet_balance(), 750)
        used = self.db.execute("SELECT check_credit_used_at FROM service_orders WHERE id='check-1'").fetchone()[0]
        self.assertIsNotNone(used)
        self.assertEqual(self.db.execute("SELECT amount FROM wallet_transactions WHERE reference='order:unlock-after-check'").fetchone()[0], -1250)

    def test_insufficient_wallet_balance_rejects_charge(self):
        self.seed_wallet(100)
        with self.assertRaises(sqlite3.IntegrityError):
            self.insert_order("too-expensive", amount=1400)
        self.db.rollback()
        self.assertEqual(self.wallet_balance(), 100)
        self.assertEqual(self.db.execute("SELECT COUNT(*) FROM wallet_transactions").fetchone()[0], 0)


if __name__ == "__main__":
    unittest.main()
