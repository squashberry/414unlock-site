# 414Unlock Cloudflare Worker API

This is the server-side API for the 414Unlock website. It is separate from GitHub Pages. The website must not collect real identity documents or accept payment codes until this Worker is deployed, configured and reviewed.

## Provision resources

1. Create a Cloudflare D1 database named 414unlock-auth.
2. Create a private R2 bucket named 414unlock-private-documents.
3. Put the new D1 database ID into wrangler.toml.
4. Apply migrations in order, including 0002_payments.sql, for example: wrangler d1 migrations apply 414unlock-auth --remote.
5. Set secrets with wrangler secret put JWT_SECRET, RESEND_API_KEY, FROM_EMAIL, and ADMIN_EMAILS.
6. Ensure FROM_EMAIL is a sender verified with Resend. Never put these secrets into GitHub.
7. Deploy with wrangler deploy.
8. Set API_BASE_URL in the public site-config.js to the resulting Worker URL.

Generate a long random JWT secret. The public Pages site origin is https://squashberry.github.io. CORS is origin checked. If you use a different front-end URL, update the Worker configuration.

## Payment session API

- POST /api/payments/session — authenticated desktop app creates a 30-minute payment session using deviceModel, identifierKind (serial/imei/udid) and identifier. The account must have approved account verification. The server returns an opaque sessionId, launchToken and unique paymentReference. The raw device identifier is not stored; the Worker computes a keyed fingerprint and stores only a masked suffix.
- GET /api/payments/session?launch=... — authenticated website retrieves the session's device preview and masked identifier.
- POST /api/payments/verify-code — authenticated website submits launchToken and confirmationCode. The Worker delegates verification to a configured server-side SquashberryPay adapter. It verifies the returned status and payment reference match, then marks that exact session as verified.
- GET /api/payments/status?sessionId=... — desktop app re-checks the server-side payment state after returning from the browser.

### SquashberryPay adapter contract — must be confirmed before production

No provider endpoint has been assumed to exist. The Worker deliberately rejects code verification with a configuration error until these are configured as secrets:

- SQUASHBERRYPAY_VERIFY_URL — the actual official SquashberryPay server-side endpoint that can validate a confirmation code.
- SQUASHBERRYPAY_API_KEY — server-only authentication credential for that endpoint.

The current adapter sends a POST over HTTPS containing:
{
  "confirmationCode": "user-entered code",
  "reference": "414Unlock payment reference"
}

It expects a successful JSON response containing:
{
  "verified": true,
  "status": "paid",
  "reference": "the same 414Unlock payment reference",
  "transactionId": "provider transaction identifier"
}

The exact endpoint, authentication method, request fields, and response format must be adjusted to match the real SquashberryPay API before enabling this feature. A code typed by a user, a screenshot, a frontend message, or a successful HTTP response alone must never mark payment as verified. The provider must confirm that the payment is successful and linked to the exact payment reference/session. If SquashberryPay only sends email codes but exposes no server-side verification endpoint or signed webhook, design a trusted backend redemption flow with SquashberryPay instead; do not simulate verification locally.

Configure the checkout URL in site-config.js only after confirming how the checkout receives a unique payment reference. If SquashberryPay supports a reference query parameter, configure SQUASHBERRYPAY_REFERENCE_PARAM accordingly. Otherwise, integrate through its supported metadata or checkout-session API so payments cannot be mismatched across devices.

## Other API routes

Signup, email code verification, login, current account, single-use desktop handoff codes, verification status/submission, administrator queue, private document access and approve/reject are also present.

Documents are uploaded to private R2, are not published as public URLs, and are deleted from R2 after an administrator decision. Application metadata remains in D1 for an audit trail. Review admins are determined by the comma-separated ADMIN_EMAILS secret.

## Before production

- Configure Cloudflare rate limiting/WAF for authentication and upload endpoints.
- Review data-protection obligations in all countries served; publish complete data-controller, processor, retention, deletion and support-contact details.
- Add account recovery, verification-code resend, decision notification emails, abuse monitoring and backup/restore procedures.
- Independently review the authentication and payment authorization implementation before real users submit documents or codes.
- Add file-signature scanning, secure document retention/deletion controls, and a manual fallback for uncertain AI/OCR matching.
- Never expose document keys, full serial numbers/IMEIs, or access tokens to browser URLs or logs.
- After the desktop app redeems a browser handoff code, it must call /api/payments/status for the original session ID and confirm verified status and its locally stored device/session state before continuing.
