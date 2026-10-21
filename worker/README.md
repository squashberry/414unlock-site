# 414Unlock Cloudflare Worker API

This is the server-side API for the 414Unlock website. It is separate from GitHub Pages. The website must not collect real identity documents until this Worker is deployed, configured and reviewed.

## Provision resources

From this directory, install Wrangler if needed and authenticate to the intended Cloudflare account:

1. Create a D1 database named 414unlock-auth.
2. Create a private R2 bucket named 414unlock-private-documents.
3. Copy the new D1 database ID into wrangler.toml.
4. Run: wrangler d1 migrations apply 414unlock-auth --remote
5. Set secrets with wrangler secret put JWT_SECRET, RESEND_API_KEY, FROM_EMAIL, and ADMIN_EMAILS.
6. Ensure FROM_EMAIL is a sender verified with Resend. Never put these secrets into GitHub.
7. Deploy with wrangler deploy.
8. Add the resulting Worker URL to public site-config.js as API_BASE_URL.

Generate a long random JWT secret (at least 32 bytes). The public Pages site origin is https://squashberry.github.io. CORS is origin checked. If you use a different front-end URL, update the Worker configuration.

## Included API routes

Signup, email code verification, login, current account, one-time desktop handoff code creation/redemption, verification status/submission, administrator queue, private document access and approve/reject are implemented.

Documents are uploaded to private R2, are not published as public URLs, and are deleted from R2 after an administrator decision. Application metadata remains in D1 for an audit trail. Review admins are determined by the comma-separated ADMIN_EMAILS secret.

## Before production

- Configure Cloudflare rate limiting/WAF for authentication endpoints and upload limits.
- Review data-protection obligations for each country where users live; publish complete controller, processor, retention, deletion and contact details.
- Add account recovery, verification-code resend, notification emails for decisions, abuse monitoring and backup/restore procedures.
- Independently review authentication and authorization before real users submit identity documents.
- Add optional OCR/AI-assisted name comparison only as decision support. Route uncertain matches to manual review; do not let model output alone make irreversible decisions.
- Add stronger upload file-signature scanning and a documented data-retention policy.
- Never expose document keys or access tokens to browser URLs or logs.
- The desktop app must check /api/verification/status after redeeming the one-time code and enforce device-specific authorization separately.