# 414Unlock website

Public website and verification UI for 414Unlock. This repository is public because it hosts a GitHub Pages site. **Do not commit API secrets, user data, identity documents, certificates, payment data, or access tokens.**

- Homepage: https://squashberry.github.io/414unlock-site/
- Sign in / create account: \`account.html\`
- Unlisted verification flow: \`verify.html\` (unlisted is not private; the backend must authorize every request)
- Restricted review UI: \`review.html\` (admin permission must be enforced by the API)
- Download CTA: GitHub Releases for this repository. Upload the actual signed Windows release asset before advertising the download as available.

## Important status

This repository contains the public front end and API client contract. Authentication, document upload, approval/rejection, and app handoff require the configured Cloudflare Worker API. The site intentionally fails closed when \`API_BASE_URL\` is empty.

## GitHub Pages

Pages should publish the \`main\` branch root. Relative links are used for GitHub Pages project-site paths.

## Configure API

Edit \`site-config.js\` after the Worker is deployed:

\`\`\`js
window.UNLOCK414_CONFIG = Object.freeze({
  API_BASE_URL: "https://YOUR-WORKER.YOUR-SUBDOMAIN.workers.dev",
  DOWNLOAD_URL: "https://github.com/squashberry/414unlock-site/releases/latest",
  APP_CALLBACK: "414unlock://auth/callback",
  TERMS_VERSION: "2026-10-30",
  SUPPORT_EMAIL: "414unlock@gmail.com"
});
\`\`\`

The Worker must allow the exact site origin \`https://squashberry.github.io\` and implement the API routes used in \`account.js\`, \`verify.js\`, and \`review.js\`. Do not use client-side flags to approve accounts.

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
