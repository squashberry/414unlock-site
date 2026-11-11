# 414Unlock website

Public website and verification UI for 414Unlock. This repository is public because it contains the static frontend deployed on Cloudflare Pages. **Do not commit API secrets, user data, identity documents, certificates, payment data, or access tokens.**

- Homepage: https://414unlock.pages.dev/
- Sign in / create account: \`account.html\`
- Unlisted verification flow: \`verify.html\` (unlisted is not private; the backend must authorize every request)
- Restricted review UI: \`review.html\` (admin permission must be enforced by the API)
- Download CTA: GitHub Releases for this repository. Upload the actual signed Windows release asset before advertising the download as available.

## Important status

This repository contains the public front end and API client contract. Authentication, document upload, approval/rejection, and app handoff require the configured Cloudflare Worker API. The site intentionally fails closed when \`API_BASE_URL\` is empty.

## Cloudflare Pages

The Cloudflare Pages project `414unlock` publishes the `main` branch root at `https://414unlock.pages.dev`. GitHub is the source repository; it is not the production web host.

## Configure API

Edit \`site-config.js\` after the Worker is deployed:

\`\`\`js
window.UNLOCK414_CONFIG = Object.freeze({
  API_BASE_URL: "https://YOUR-WORKER.YOUR-SUBDOMAIN.workers.dev",
  DOWNLOAD_URL: "https://github.com/squashberry/414unlock-site/releases/latest/download/414Unlock_Setup.exe",
  APP_CALLBACK: "414unlock://auth/callback",
  TERMS_VERSION: "2026-10-30",
  SUPPORT_EMAIL: "414unlock@gmail.com"
});
\`\`\`

The Worker must allow the exact production site origin `https://414unlock.pages.dev` and implement the API routes used in `account.js`, `verify.js`, and `review.js`. Do not use client-side flags to approve accounts.

## Required API contract

- `GET /api/access/check` — server-side access check used by the public-page guard.
- `POST /api/auth/browser-challenge` — issue a rotating, single-use Squashberry browser challenge.
- `POST /api/auth/signup` — create an account and authenticated session after browser proof is accepted.
- `POST /api/auth/login` — authenticate email/password and issue a session after a fresh browser proof.
- `GET /api/auth/me` — return authenticated user status.
- `POST /api/auth/app-code` — create a random, short-lived, single-use desktop handoff code.
- `GET /api/admin/security/events` — administrator-only recent browser and authentication activity.
- `GET /api/verification/status` and `POST /api/verification/submit` — review and privately store identity/professional verification documents.
- `GET /api/admin/submissions` and `POST /api/admin/submissions/:id/review` — administrator-only review queue and decision endpoint.

## Desktop integration

The Flutter Windows app should launch \`account.html?flow=signin&return=app&state=<random-nonce>\` in the system browser. Register the \`414unlock://auth/callback\` URI handler or use a loopback callback. The app must validate the nonce and redeem the one-time code server-side. New-account registration continues into \`verify.html\`; sign-in returns to the desktop app. Never trust a URL parameter as proof that verification, payment, or service authorization passed.


## Unlock service progress links

Approved Software / repair professionals can generate a customer progress link from their own unlock orders in the mobile app dashboard (`mobile.html`) or web dashboard (`dashboard.html`). Customers open the public tracking page (`track.html`) without signing in. The random link token is kept in the URL fragment, stored as a hash in D1, expires after 90 days, and is revoked when a replacement is generated. Customer status responses expose only a masked device identifier and service progress.
