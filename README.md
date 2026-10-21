# 414Unlock website

Public website and verification UI for 414Unlock. This repository is public because it hosts a GitHub Pages site. **Do not commit API secrets, user data, identity documents, certificates, payment data, or access tokens.**

- Homepage: https://squashberry.github.io/414unlock-site/
- Sign in / create account: \`account.html\`
- Unlisted verification flow: \`verify.html\` (unlisted is not private; the backend must authorize every request)
- Restricted review UI: \`review.html\` (admin permission must be enforced by the API)
- Download CTA: GitHub Releases for this repository. Upload the actual signed Windows release asset before advertising the download as available.

## Important status

This repository contains the public front end and API client contract. Authentication, email delivery, document upload, approval/rejection, and app handoff will **not work until the Cloudflare Worker API is implemented/deployed and configured**. The site intentionally fails closed when \`API_BASE_URL\` is empty.

## GitHub Pages

Pages should publish the \`main\` branch root. Relative links are used for GitHub Pages project-site paths.

## Configure API

Edit \`site-config.js\` after the Worker is deployed:

\`\`\`js
window.UNLOCK414_CONFIG = Object.freeze({
  API_BASE_URL: "https://YOUR-WORKER.YOUR-SUBDOMAIN.workers.dev",
  DOWNLOAD_URL: "https://github.com/squashberry/414unlock-site/releases/latest",
  APP_CALLBACK: "414unlock://auth/callback",
  TERMS_VERSION: "2026-10-21"
});
\`\`\`

The Worker must allow the exact site origin \`https://squashberry.github.io\` and implement the API routes used in \`account.js\`, \`verify.js\`, and \`review.js\`. Do not use client-side flags to approve accounts.

## Required API contract

- \`POST /api/auth/signup\` — create account, send email verification code.
- \`POST /api/auth/verify-email\` — verify email and issue short-lived access token.
- \`POST /api/auth/login\` — authenticate email/password and issue token.
- \`GET /api/auth/me\` — return authenticated user status.
- \`POST /api/auth/app-code\` — create a random, short-lived, single-use desktop handoff code.
- \`GET /api/verification/status\` — return \`not_submitted\`, \`pending\`, \`approved\`, or \`rejected\` and an optional review note.
- \`POST /api/verification/submit\` — validate and privately store the multipart document submission.
- \`GET /api/admin/submissions\` and \`POST /api/admin/submissions/:id/review\` — administrator-only review queue and decision endpoint.

The desktop app should redeem the one-time code through a dedicated API endpoint. It must verify the state nonce generated locally before exchanging the code. After returning from payment, the desktop app must call /api/payments/status and POST the currently detected serial/IMEI/UDID to /api/payments/validate-device. Never pass a raw device identifier, access token, or document contents in a redirect URL.

## Cloudflare backend setup

The API requires a server-side service, database, and private object storage. GitHub Pages cannot securely store passwords, authenticate users, or protect identity documents on its own. Configure a Cloudflare Worker with D1 for account/verification metadata and private R2 storage for documents; use a verified email provider for email codes. Keep all secrets as Worker secrets, never in this repo. Admin access must be decided by the Worker from trusted configuration, not by a field submitted by the browser.

Before real users can submit documents, implement rate limits, password hashing, email verification, upload size/type validation, private storage, short-lived sessions, CSRF/CORS protection, audit logs that do not contain document data, retention/deletion procedures, and a manual fallback for uncertain AI document matching.

## Desktop integration

The Flutter Windows app should launch \`account.html?flow=signin&return=app&state=<random-nonce>\` in the system browser. Register the \`414unlock://auth/callback\` URI handler or use a loopback callback. The app must validate the nonce and redeem the one-time code server-side. New-account registration continues into \`verify.html\`; sign-in returns to the desktop app. Never trust a URL parameter as proof that verification, payment, or service authorization passed.
