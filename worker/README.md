# 414Unlock Cloudflare Worker API

This is the server-side API for the 414Unlock website. It is separate from GitHub Pages. Do not collect real identity documents, device identifiers, or payment references until this Worker is deployed, configured and reviewed.

## Provision resources

1. Create a Cloudflare D1 database named `414unlock-auth`.
2. Configure Cloudinary secrets: `CLOUDINARY_CLOUD_NAME`, `CLOUDINARY_API_KEY`, and `CLOUDINARY_API_SECRET`. Identity documents are uploaded as authenticated raw assets; no public delivery URL is stored.
3. Put the real D1 database ID into `wrangler.toml`.
4. Apply migrations in order: `0001_init.sql`, `0002_payments.sql`, `0003_wallet_orders.sql`, and `0004_ios_support_rules.sql`, then `0005_user_account_controls.sql` and `0006_support_chat.sql`. Example: `wrangler d1 migrations apply 414unlock-auth --remote`.
5. Set secrets with `wrangler secret put JWT_SECRET`, `ADMIN_EMAILS`, and `DEVICE_DATA_ENCRYPTION_KEY`.
6. Use unique random values for secrets; never commit them to GitHub. Authentication does not need an email-delivery provider.
7. Deploy with `wrangler deploy`.
8. Set `API_BASE_URL` in the public `site-config.js` to the resulting Worker URL.
9. Configure `SQUASHBERRYPAY_TOPUP_URL` only after verifying the real checkout URL, amount format and reference handling. This browser value must not contain any secret.

The `DEVICE_DATA_ENCRYPTION_KEY` must be a high-entropy random secret of at least 32 characters. The Worker derives an AES-GCM key from it. Back it up securely: if it is lost, previously stored device identifiers cannot be decrypted. Do not rotate it without a planned re-encryption migration. The public Pages origin is `https://squashberry.github.io`; CORS is origin-checked.

## Wallet and top-up workflow

- `GET /api/wallet/overview` — authenticated user's balance, ledger entries, top-up requests and masked service-order history.
- `POST /api/wallet/topups` — creates a top-up request for D50–D100,000 and returns a unique `414T-` request reference. It does not credit the wallet.
- `POST /api/wallet/topups/:id/submit-reference` — authenticated user submits the SquashberryPay transaction reference. The request becomes pending for review.
- `GET /api/admin/queue` — admin-only queue for payment review and active service requests; full device identifiers are decrypted only for a configured administrator.
- `GET /api/admin/users?q=...` — admin-only user directory with account state, latest identity-review state, wallet balance, service/top-up counts, and account status. Search matches name or email.
- `POST /api/admin/users/:id/status` — admin-only account activation control. Send `{"active":false,"note":"..."}` to deactivate or `{"active":true,"note":"..."}` to reactivate. Deactivation blocks login, desktop-code redemption, and every existing API token immediately. It never deletes user data, wallet balance, or transaction history. Configured administrator accounts cannot be deactivated through this endpoint. Changes are written to `admin_audit_log` and are available in the Users tab of `admin.html`.
- `POST /api/admin/topups/:id/review` — admin approves/rejects a pending top-up. An approved status transition credits the wallet through a database trigger and creates one ledger entry. Check the actual transaction inside SquashberryPay before approving.
- `POST /api/orders` — creates a priced service request after approved account verification, authorisation acknowledgements, and a sufficient wallet balance. The price is calculated on the server, not trusted from the browser.
- `POST /api/admin/orders/:id/status` — admin moves a service request through submitted → registered → processing → completed, or rejects it. A request rejected before processing starts is refunded automatically; rejection after processing starts does not trigger an automatic refund.

The account verification workflow gates top-ups and service requests. Customers must assert that they own the device or have permission from its owner. Full serial/IMEI values are encrypted in D1 using `DEVICE_DATA_ENCRYPTION_KEY`; customer responses show only the masked suffix. Only `ADMIN_EMAILS` can use the admin queue. Do not expose raw identifiers in URLs or logs.

Model pricing on the server reflects the published 414Unlock list (whole GMD): D1,400; D1,600; D1,900; D2,200; D2,500; D3,000; D3,500; D5,000; and D6,500 by model band. IMEI checks are D150; fast service adds D1,000. An eligible completed IMEI check may be applied once against the same device's unlock request if used within seven days.

## Existing desktop payment session API

- `POST /api/payments/session` — authenticated desktop app creates a 30-minute payment session using deviceModel, identifierKind (serial/imei/udid) and identifier. The raw identifier for this payment session is not stored; the Worker computes a keyed fingerprint and stores only a masked suffix.
- `GET /api/payments/session?launch=...` — authenticated website retrieves the device preview and masked identifier.
- `POST /api/payments/verify-code` — delegates code verification to the configured server-side SquashberryPay adapter.
- `GET /api/payments/status?sessionId=...` — desktop app re-checks server-side payment state.
- `POST /api/payments/validate-device` — desktop app confirms that the paid session matches its currently detected device.
- `GET /api/payments/check-device?identifier=...&identifierKind=serial|imei|udid` — authenticated lookup for an existing verified payment session belonging to the signed-in user and the same device fingerprint. Returns `paid`, `deviceRegistered`, `canRetry`, `status`, and a user-facing `message`. It never returns the raw identifier or another customer's payment details. A verified matching session allows retry without creating another checkout; a session owned by another account does not.

## Server-controlled iOS compatibility policy

- `GET /api/compatibility/ios?iosVersion=18.7` — public, read-only compatibility decision used by the desktop app before the unlock workflow. The response includes `allowed`/`supported`, `matched`, a safe rule summary, a stable `code`, and a message. The internal administrator note is not exposed.
- `GET /api/admin/ios-support/rules` — administrator-only list of exact-version and inclusive version-range rules.
- `POST /api/admin/ios-support/rules` — administrator-only create/update endpoint. JSON fields: `id` (omit for a new rule), `matchType` (`exact` or `range`), `version` for exact rules or `minVersion`/`maxVersion` for ranges, `enabled` (boolean), and optional `note`. Disable a rule to block its version/range. Rules can be edited and toggled from the **iOS support** tab of `admin.html`.

Policy evaluation is numeric semantic version comparison, not a text prefix. Exact-version rules override ranges. When more than one range matches, the narrowest range is used; a disabled range wins a tie. Versions must be numeric dotted versions with two to four components. If no rule matches, the API returns `allowed:false` and “This phone's iOS version isn't supported.” There are deliberately no seeded allow rules: after migration, administrators must add and explicitly enable versions/ranges after confirming service compatibility. An API/network/database error must also stop the desktop workflow; the client must not fall back to a local allow list. Model/chipset eligibility remains a separate check and must not be inferred from an iOS version rule.

The public policy endpoint does not authenticate because device compatibility may be checked before the customer signs in. It exposes only the decision and non-sensitive match metadata. Rule creation and modification are protected by the existing `ADMIN_EMAILS` allowlist.

### SquashberryPay adapter contract — must be confirmed before production

No provider endpoint has been assumed to exist. The existing desktop payment-code feature deliberately rejects verification until the actual provider API is configured as secrets:

- `SQUASHBERRYPAY_VERIFY_URL` — the official server-side endpoint that validates a confirmation code.
- `SQUASHBERRYPAY_API_KEY` — server-only authentication credential.

The current adapter sends a POST over HTTPS containing `confirmationCode` and `reference`. It expects a successful JSON response with `verified: true`, `status: "paid"`, the same `reference`, and a non-empty transaction identifier. Confirm the endpoint, authentication method, request and response contract with SquashberryPay before enabling it. Never simulate payment verification locally.

The wallet top-up workflow in this revision is deliberately **manual-review**: a transaction reference submitted by the user is not proof of payment; an administrator must confirm payment in SquashberryPay. It does not assume an undocumented provider API or treat a URL redirect as payment confirmation.

## Other API routes

Direct signup, Squashberry rotating browser verification, login, current account, single-use desktop handoff codes, verification status/submission, administrator identity-review queue, private document access and approve/reject are also present.

Documents are uploaded to Cloudinary as raw assets with authenticated delivery, never published as public URLs, and are deleted after an administrator decision. Application metadata remains in D1 for an audit trail. Review admins are configured by the comma-separated `ADMIN_EMAILS` secret.

## Before production

- Provision real Cloudflare resources and run all migrations; do not leave placeholder IDs or secrets.
- In the admin **iOS support** tab, add and explicitly enable only the exact iOS versions/ranges you have verified. Test an enabled range, an explicitly disabled exact version inside that range, an unlisted version, and API failure. Confirm exact rules override ranges and the app fails closed when the policy request fails.
- Test `GET /api/payments/check-device` with a verified payment on the same account/device, a pending or expired session, a different account, and a mismatched identifier; only a verified same-account match should return `paid:true`/`canRetry:true`.
- Configure rate limiting/WAF for authentication, top-up and upload endpoints.
- Verify the SquashberryPay payment process end-to-end; manual review must not be advertised as automated.
- Review data-protection requirements; publish support contacts, controller/processor details, retention and deletion periods.
- Independently review authentication, balance ledger, payment authorization and admin access before accepting real users.
- Complete support-led account recovery procedures, notification preferences, periodic abuse review, backups and restore tests.
- Use a secure operational process for device-authorisation evidence and delete full identifiers when no longer needed.


## Production deployment through GitHub Actions

The backend source is committed, but this repository does not contain Cloudflare credentials. To deploy it without hard-coding credentials or database IDs:

1. In GitHub, open **Settings → Secrets and variables → Actions → Secrets** and add:
   - `CLOUDFLARE_API_TOKEN` — a Cloudflare API token scoped to the intended account, with Workers Scripts Edit, D1 Edit, Cloudinary credentials stored as Worker secrets, and the account permissions required to inspect the Workers.dev hostname.
   - `CLOUDFLARE_ACCOUNT_ID` — the 32-character account ID for the exact account you want to use.
   - `RESEND_API_KEY` — your Resend API key.
   - `FROM_EMAIL` — a sender identity verified with Resend.
2. Under **Settings → Secrets and variables → Actions → Variables**, add `SQUASHBERRYPAY_TOPUP_URL`. This must be the official **custom-amount** SquashberryPay checkout link you created in the SquashberryPay merchant dashboard. A fixed-price product link cannot collect arbitrary wallet top-up amounts. The checkout URL is public configuration, so do not put secrets in it.
3. Open **Actions → Deploy 414Unlock backend → Run workflow**. Enter the email address that should have administrator access. Use the Workers.dev account subdomain shown in Cloudflare; the default input is `squashberrypay`.
4. The workflow checks its required settings before infrastructure changes, reuses the named D1 database if it exists, creates it only if missing, applies all tracked migrations, deploys the Worker, preserves existing JWT and device-encryption secrets (generating them only when absent), configures Cloudinary secrets and administrator access, then checks `/api/health` including browser-security readiness. Only after a successful health check does it write the API URL into `site-config.js`.
5. Confirm the latest GitHub Pages build publishes the updated `site-config.js`, then test direct signup, browser verification, admin login, wallet top-up and service ordering with a small non-production test before accepting real payments or device details.

### Payment handling is deliberately manual

The configured SquashberryPay URL must allow the customer to pay the exact amount requested. 414Unlock does not currently send the request reference into SquashberryPay's checkout session or verify a payment automatically through a documented server-to-server SquashberryPay API. The customer therefore submits SquashberryPay's transaction reference, and an administrator must look up and confirm the actual successful payment in SquashberryPay before approving the top-up. Approval credits the matching wallet exactly once; a submitted reference alone never adds credit. Do not set the variable to a fixed-amount checkout and assume the `amount` URL parameter will change that payment.

The deployment workflow itself cannot create a SquashberryPay merchant payment link because that link belongs to your merchant account and must be configured by you in the SquashberryPay dashboard. Likewise, it cannot succeed without the Cloudflare API token and required Cloudinary, administrator and encryption secrets being added to GitHub Actions secrets first.


## Customer support centre

The public support page is `support.html`. It includes FAQs and the support email address. Signed-in customers can create tickets, read replies, and continue a private conversation. The Admin workspace includes a Support inbox tab for the configured admin emails to read, reply, and close/reopen tickets. Customers can read only their own tickets; administrators can access all tickets.

## Cloudinary secrets

Set `CLOUDINARY_CLOUD_NAME`, `CLOUDINARY_API_KEY`, and `CLOUDINARY_API_SECRET` as Cloudflare Worker secrets. Never add the API secret to `site-config.js`, HTML, or browser-side JavaScript. The Worker proxies authenticated document downloads only after checking administrator access.
