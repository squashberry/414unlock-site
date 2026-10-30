const encoder = new TextEncoder();
const decoder = new TextDecoder();
const PASSWORD_ITERATIONS = 310000;
const TOKEN_TTL_SECONDS = 3600;
const APP_CODE_TTL_SECONDS = 120;
const EMAIL_CODE_TTL_SECONDS = 900;
const MAX_DOCUMENT_BYTES = 7 * 1024 * 1024;
const ALLOWED_TYPES = new Set(["application/pdf", "image/png", "image/jpeg"]);

export default {
  async fetch(request, env) {
    const origin = request.headers.get("Origin") || "";
    const headers = corsHeaders(origin, env);
    if (request.method === "OPTIONS") return new Response(null, { status: 204, headers });
    try {
      if (!isOriginAllowed(origin, env)) return json({ error: "ORIGIN_NOT_ALLOWED", message: "This origin is not permitted." }, 403, headers);
      const path = new URL(request.url).pathname;
      if (request.method === "GET" && path === "/api/health") {
        let databaseReady = false;
        if (env.DB) {
          try {
            const tableCheck = await env.DB.prepare(
              "SELECT name FROM sqlite_master WHERE type='table' AND name IN ('users','verification_submissions','payment_sessions','wallets','wallet_transactions','topup_requests','service_orders','ios_support_rules','support_tickets','support_messages','password_reset_tokens','admin_bootstrap_tokens')"
            ).all();
            const names = new Set((tableCheck.results || []).map((row) => row.name));
            databaseReady = ["users","verification_submissions","payment_sessions","wallets","wallet_transactions","topup_requests","service_orders","ios_support_rules","support_tickets","support_messages","password_reset_tokens","admin_bootstrap_tokens"].every((name) => names.has(name));
          } catch (_) { databaseReady = false; }
        }
        const cloudinaryReady = cloudinaryConfigured(env);
        const authReady = typeof env.JWT_SECRET === "string" && env.JWT_SECRET.length >= 32;
        const adminReady = Boolean(env.ADMIN_EMAILS && env.ADMIN_EMAILS.trim());
        const deviceEncryptionReady = typeof env.DEVICE_DATA_ENCRYPTION_KEY === "string" && env.DEVICE_DATA_ENCRYPTION_KEY.length >= 32;
        // Login/admin auth do not depend on optional document storage or outbound email.
        const ready = databaseReady && authReady && adminReady && deviceEncryptionReady;
        return json({
          ok: ready, service: "414unlock-api", version: "member-management-v1",
          checks: {
            database: databaseReady, privateDocuments: cloudinaryReady, authentication: authReady,
            emailDelivery: Boolean(env.RESEND_API_KEY && env.FROM_EMAIL),
            adminAccess: adminReady, deviceEncryption: deviceEncryptionReady
          }
        }, ready ? 200 : 503, headers);
      }
      if (!env.DB) return json({ error: "SERVICE_NOT_CONFIGURED", message: "The account database is not configured." }, 503, headers);
      if (!env.JWT_SECRET || env.JWT_SECRET.length < 32) return json({ error: "SERVICE_NOT_CONFIGURED", message: "The account service is not fully configured." }, 503, headers);
      if (request.method === "POST" && path === "/api/admin/bootstrap") return await bootstrapFirstAdmin(request, env, headers);
      if (request.method === "POST" && path === "/api/auth/forgot-password") return await requestPasswordReset(request, env, headers);
      if (request.method === "POST" && path === "/api/auth/reset-password") return await resetPassword(request, env, headers);
      if (request.method === "POST" && path === "/api/auth/signup") return await signup(request, env, headers);
      if (request.method === "POST" && path === "/api/auth/verify-email") return await verifyEmail(request, env, headers);
      if (request.method === "POST" && path === "/api/auth/login") return await login(request, env, headers);
      if (request.method === "GET" && path === "/api/auth/me") return await getMe(request, env, headers);
      if (request.method === "POST" && path === "/api/auth/app-code") return await createAppCode(request, env, headers);
      if (request.method === "POST" && path === "/api/auth/redeem-app-code") return await redeemAppCode(request, env, headers);
      if (request.method === "GET" && path === "/api/wallet/overview") return await walletOverview(request, env, headers);
      if (request.method === "POST" && path === "/api/wallet/topups") return await createTopupRequest(request, env, headers);
      const submitTopupMatch = path.match(/^\/api\/wallet\/topups\/([a-f0-9]{32})\/submit-reference$/i);
      if (request.method === "POST" && submitTopupMatch) return await submitTopupReference(request, env, headers, submitTopupMatch[1]);
      if (request.method === "POST" && path === "/api/orders") return await createServiceOrder(request, env, headers);
      if (request.method === "GET" && path === "/api/support/tickets") return await listMySupportTickets(request, env, headers);
      if (request.method === "POST" && path === "/api/support/tickets") return await createSupportTicket(request, env, headers);
      const supportMessagesMatch = path.match(/^\/api\/support\/tickets\/([a-f0-9]{32})\/messages$/i);
      if (request.method === "GET" && supportMessagesMatch) return await getSupportTicketMessages(request, env, headers, supportMessagesMatch[1]);
      if (request.method === "POST" && supportMessagesMatch) return await postSupportTicketMessage(request, env, headers, supportMessagesMatch[1]);
      if (request.method === "GET" && path === "/api/admin/support/tickets") return await listAdminSupportTickets(request, env, headers);
      const adminSupportStatusMatch = path.match(/^\/api\/admin\/support\/tickets\/([a-f0-9]{32})\/status$/i);
      if (request.method === "POST" && adminSupportStatusMatch) return await updateAdminSupportTicketStatus(request, env, headers, adminSupportStatusMatch[1]);
      if (request.method === "GET" && path === "/api/admin/queue") return await adminQueue(request, env, headers);
      if (request.method === "GET" && path === "/api/admin/users") return await listAdminUsers(request, env, headers);
      const adminUserDetailMatch = path.match(/^\/api\/admin\/users\/([a-f0-9]{32})$/i);
      if (request.method === "GET" && adminUserDetailMatch) return await getAdminUserDetails(request, env, headers, adminUserDetailMatch[1]);
      const adminUserProfileMatch = path.match(/^\/api\/admin\/users\/([a-f0-9]{32})\/profile$/i);
      if (request.method === "POST" && adminUserProfileMatch) return await updateAdminUserProfile(request, env, headers, adminUserProfileMatch[1]);
      const adminUserDeleteMatch = path.match(/^\/api\/admin\/users\/([a-f0-9]{32})\/delete$/i);
      if (request.method === "POST" && adminUserDeleteMatch) return await deleteAdminUser(request, env, headers, adminUserDeleteMatch[1]);
      const adminUserRestoreMatch = path.match(/^\/api\/admin\/users\/([a-f0-9]{32})\/restore$/i);
      if (request.method === "POST" && adminUserRestoreMatch) return await restoreAdminUser(request, env, headers, adminUserRestoreMatch[1]);
      const adminUserPasswordResetMatch = path.match(/^\/api\/admin\/users\/([a-f0-9]{32})\/password-reset$/i);
      if (request.method === "POST" && adminUserPasswordResetMatch) return await sendAdminUserPasswordReset(request, env, headers, adminUserPasswordResetMatch[1]);
      const adminUserWalletMatch = path.match(/^\/api\/admin\/users\/([a-f0-9]{32})\/wallet-adjustment$/i);
      if (request.method === "POST" && adminUserWalletMatch) return await adjustAdminUserWallet(request, env, headers, adminUserWalletMatch[1]);
      const adminUserStatusMatch = path.match(/^\/api\/admin\/users\/([a-f0-9]{32})\/status$/i);
      if (request.method === "POST" && adminUserStatusMatch) return await updateAdminUserStatus(request, env, headers, adminUserStatusMatch[1]);
      const adminTopupMatch = path.match(/^\/api\/admin\/topups\/([a-f0-9]{32})\/review$/i);
      if (request.method === "POST" && adminTopupMatch) return await reviewTopup(request, env, headers, adminTopupMatch[1]);
      const adminOrderMatch = path.match(/^\/api\/admin\/orders\/([a-f0-9]{32})\/status$/i);
      if (request.method === "POST" && adminOrderMatch) return await updateServiceOrderStatus(request, env, headers, adminOrderMatch[1]);
      if (request.method === "POST" && path === "/api/payments/session") return await createPaymentSession(request, env, headers);
      if (request.method === "GET" && path === "/api/payments/session") return await getPaymentSession(request, env, headers, new URL(request.url));
      if (request.method === "GET" && path === "/api/payments/status") return await getPaymentStatus(request, env, headers, new URL(request.url));
      if (request.method === "GET" && path === "/api/payments/check-device") return await checkDevicePayment(request, env, headers, new URL(request.url));
      if (request.method === "GET" && path === "/api/compatibility/ios") return await checkIosCompatibility(env, headers, new URL(request.url));
      if (request.method === "GET" && path === "/api/admin/ios-support/rules") return await listIosSupportRules(request, env, headers);
      if (request.method === "POST" && path === "/api/admin/ios-support/rules") return await saveIosSupportRule(request, env, headers);
      if (request.method === "POST" && path === "/api/payments/validate-device") return await validatePaymentDevice(request, env, headers);
      if (request.method === "POST" && path === "/api/payments/verify-code") return await verifyPaymentCode(request, env, headers);
      if (request.method === "GET" && path === "/api/verification/status") return await verificationStatus(request, env, headers);
      if (request.method === "POST" && path === "/api/verification/submit") return await submitVerification(request, env, headers);
      if (request.method === "GET" && path === "/api/admin/submissions") return await listSubmissions(request, env, headers);
      const documentMatch = path.match(/^\/api\/admin\/submissions\/([a-f0-9-]+)\/document$/i);
      if (request.method === "GET" && documentMatch) return await getSubmissionDocument(request, env, headers, documentMatch[1]);
      const reviewMatch = path.match(/^\/api\/admin\/submissions\/([a-f0-9-]+)\/review$/i);
      if (request.method === "POST" && reviewMatch) return await reviewSubmission(request, env, headers, reviewMatch[1]);
      return json({ error: "NOT_FOUND", message: "Endpoint not found." }, 404, headers);
    } catch (error) {
      if (error instanceof ApiError) return json({ error: error.code, message: error.publicMessage }, error.status, headers);
      console.error("414Unlock API request failed:", safeErrorCode(error));
      return json({ error: "INTERNAL_ERROR", message: "The request could not be completed. Please try again." }, 500, headers);
    }
  }
};

function isOriginAllowed(origin, env) {
  if (!origin) return true;
  const allowed = (env.SITE_ORIGIN || "https://squashberry.github.io").split(",").map((x) => x.trim()).filter(Boolean);
  return allowed.includes(origin) || origin === "http://127.0.0.1" || origin === "http://localhost";
}
function corsHeaders(origin, env) {
  const h = {
    "Vary": "Origin",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Access-Control-Allow-Headers": "Authorization, Content-Type",
    "Access-Control-Max-Age": "86400",
    "Cache-Control": "no-store",
    "X-Content-Type-Options": "nosniff",
    "Referrer-Policy": "no-referrer"
  };
  if (isOriginAllowed(origin, env)) h["Access-Control-Allow-Origin"] = origin || (env.SITE_ORIGIN || "https://squashberry.github.io").split(",")[0].trim();
  return h;
}
function json(value, status, headers) {
  return new Response(JSON.stringify(value), { status: status || 200, headers: { ...headers, "Content-Type": "application/json; charset=utf-8" } });
}
function safeErrorCode(error) { return error && typeof error.name === "string" ? error.name : "Error"; }
class ApiError extends Error {
  constructor(status, code, message) { super(message); this.status = status; this.code = code; this.publicMessage = message; }
}
async function readJson(request) {
  const type = request.headers.get("Content-Type") || "";
  if (!type.toLowerCase().includes("application/json")) throw new ApiError(415, "JSON_REQUIRED", "Send a JSON request.");
  const length = Number(request.headers.get("Content-Length") || 0);
  if (length > 128 * 1024) throw new ApiError(413, "BODY_TOO_LARGE", "The request is too large.");
  try { return await request.json(); } catch (_) { throw new ApiError(400, "INVALID_JSON", "The request body is invalid."); }
}
function randomBytes(length) { const out = new Uint8Array(length); crypto.getRandomValues(out); return out; }
function randomHex(length) { return Array.from(randomBytes(length), (b) => b.toString(16).padStart(2, "0")).join(""); }
function base64url(bytes) {
  let binary = "";
  for (let i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i]);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}
function base64urlText(value) { return base64url(encoder.encode(value)); }
function fromBase64url(value) {
  const padded = value.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((value.length + 3) % 4);
  const binary = atob(padded), bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}
function bytesToHex(bytes) { return Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join(""); }
async function sha256Hex(value) {
  return bytesToHex(new Uint8Array(await crypto.subtle.digest("SHA-256", encoder.encode(value))));
}
async function keyedHash(value, env) {
  const key = await crypto.subtle.importKey("raw", encoder.encode(env.JWT_SECRET), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  return bytesToHex(new Uint8Array(await crypto.subtle.sign("HMAC", key, encoder.encode(value))));
}
async function hmacBytes(value, secret) {
  const key = await crypto.subtle.importKey("raw", encoder.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  return new Uint8Array(await crypto.subtle.sign("HMAC", key, encoder.encode(value)));
}
async function createPasswordHash(password, saltHex) {
  const key = await crypto.subtle.importKey("raw", encoder.encode(password), "PBKDF2", false, ["deriveBits"]);
  const salt = Uint8Array.from(saltHex.match(/.{2}/g).map((x) => parseInt(x, 16)));
  const bits = await crypto.subtle.deriveBits({ name: "PBKDF2", salt, iterations: PASSWORD_ITERATIONS, hash: "SHA-256" }, key, 256);
  return bytesToHex(new Uint8Array(bits));
}
function constantTimeEqual(a, b) {
  if (typeof a !== "string" || typeof b !== "string" || a.length !== b.length) return false;
  let result = 0;
  for (let i = 0; i < a.length; i++) result |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return result === 0;
}
async function issueToken(user, env) {
  const now = Math.floor(Date.now() / 1000);
  const head = base64urlText(JSON.stringify({ alg: "HS256", typ: "JWT" }));
  const body = base64urlText(JSON.stringify({ sub: user.id, email: user.email, ver: Number(user.auth_version || 0), iat: now, exp: now + TOKEN_TTL_SECONDS, iss: "414unlock-auth" }));
  const signingInput = head + "." + body;
  return signingInput + "." + base64url(await hmacBytes(signingInput, env.JWT_SECRET));
}
async function readToken(request, env) {
  const header = request.headers.get("Authorization") || "";
  if (!header.startsWith("Bearer ")) throw new ApiError(401, "AUTH_REQUIRED", "Sign in to continue.");
  const parts = header.slice(7).trim().split(".");
  if (parts.length !== 3) throw new ApiError(401, "INVALID_SESSION", "Your session is invalid. Sign in again.");
  const expected = base64url(await hmacBytes(parts[0] + "." + parts[1], env.JWT_SECRET));
  if (!constantTimeEqual(expected, parts[2])) throw new ApiError(401, "INVALID_SESSION", "Your session is invalid. Sign in again.");
  let claims;
  try { claims = JSON.parse(decoder.decode(fromBase64url(parts[1]))); } catch (_) { throw new ApiError(401, "INVALID_SESSION", "Your session is invalid. Sign in again."); }
  if (!claims.sub || !claims.exp || claims.iss !== "414unlock-auth" || claims.exp <= Math.floor(Date.now() / 1000)) throw new ApiError(401, "SESSION_EXPIRED", "Your session expired. Sign in again.");
  const user = await env.DB.prepare("SELECT id, full_name, email, email_verified, created_at, account_active, auth_version, deleted_at FROM users WHERE id = ?").bind(claims.sub).first();
  if (!user || !user.email_verified || user.deleted_at) throw new ApiError(401, "INVALID_SESSION", "Your session is invalid. Sign in again.");
  if (Number(user.account_active) !== 1) throw new ApiError(403, "ACCOUNT_DISABLED", "This 414Unlock account is currently deactivated. Contact support.");
  if (Number(claims.ver || 0) !== Number(user.auth_version || 0)) throw new ApiError(401, "SESSION_REVOKED", "Your account session has been reset. Sign in again.");
  return user;
}
function publicUser(user) { return { id: user.id, fullName: user.full_name, email: user.email, emailVerified: !!user.email_verified, active: Number(user.account_active) !== 0 }; }
function validEmail(email) { return typeof email === "string" && email.length <= 254 && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email); }
function htmlEscape(value) { return String(value).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c])); }
function generateCode() { return String(crypto.getRandomValues(new Uint32Array(1))[0] % 1000000).padStart(6, "0"); }
async function sendEmail(env, to, subject, html) {
  if (!env.RESEND_API_KEY || !env.FROM_EMAIL) throw new ApiError(503, "EMAIL_NOT_CONFIGURED", "Email verification is not configured yet. Contact support.");
  const response = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { "Authorization": "Bearer " + env.RESEND_API_KEY, "Content-Type": "application/json" },
    body: JSON.stringify({ from: env.FROM_EMAIL, to: [to], subject, html })
  });
  if (!response.ok) throw new ApiError(502, "EMAIL_DELIVERY_FAILED", "The verification email could not be sent. Try again later.");
}
async function makeEmailCode(env, userId, purpose) {
  const code = generateCode(), now = Math.floor(Date.now() / 1000), codeHash = await keyedHash(userId + ":" + purpose + ":" + code, env);
  await env.DB.prepare("DELETE FROM email_codes WHERE user_id = ? AND purpose = ?").bind(userId, purpose).run();
  await env.DB.prepare("INSERT INTO email_codes (id,user_id,purpose,code_hash,expires_at,attempts,created_at) VALUES (?,?,?,?,?,0,?)").bind(randomHex(16), userId, purpose, codeHash, now + EMAIL_CODE_TTL_SECONDS, now).run();
  return code;
}
async function signup(request, env, headers) {
  try {
    const body = await readJson(request);
    const fullName = typeof body.fullName === "string" ? body.fullName.trim() : "";
    const email = typeof body.email === "string" ? body.email.trim().toLowerCase() : "";
    const password = typeof body.password === "string" ? body.password : "";
    if (fullName.length < 2 || fullName.length > 120) throw new ApiError(400, "INVALID_NAME", "Enter your full name.");
    if (!validEmail(email)) throw new ApiError(400, "INVALID_EMAIL", "Enter a valid email address.");
    if (password.length < 10 || password.length > 128) throw new ApiError(400, "INVALID_PASSWORD", "Use a password between 10 and 128 characters.");
    if (isAdminEmail(email, env)) throw new ApiError(403, "ADMIN_INVITE_REQUIRED", "The administrator account must be created through the private first-time setup link.");
    if (!env.RESEND_API_KEY || !env.FROM_EMAIL) throw new ApiError(503, "EMAIL_NOT_CONFIGURED", "Email verification is not configured yet.");
    const existing = await env.DB.prepare("SELECT id FROM users WHERE email = ?").bind(email).first();
    if (existing) throw new ApiError(409, "ACCOUNT_EXISTS", "An account already exists for this email. Try signing in.");
    const id = randomHex(16), salt = randomHex(16), passwordHash = await createPasswordHash(password, salt), now = Math.floor(Date.now() / 1000);
    await env.DB.prepare("INSERT INTO users (id,full_name,email,password_salt,password_hash,email_verified,created_at) VALUES (?,?,?,?,?,0,?)").bind(id, fullName, email, salt, passwordHash, now).run();
    try {
      const code = await makeEmailCode(env, id, "verify_email");
      await sendEmail(env, email, "Verify your 414Unlock account", "<div style='font-family:Arial,sans-serif;max-width:520px;margin:auto;color:#182019'><h2>Verify your 414Unlock account</h2><p>Hello " + htmlEscape(fullName) + ",</p><p>Enter this code on the verification page. It expires in 15 minutes.</p><p style='font-size:30px;font-weight:700;letter-spacing:8px'>" + code + "</p><p>If you did not request this account, you can ignore this email.</p></div>");
    } catch (error) { await env.DB.prepare("DELETE FROM users WHERE id = ?").bind(id).run(); throw error; }
    return json({ ok: true, needsEmailVerification: true, message: "A verification code has been sent to your email." }, 201, headers);
  } catch (error) { throwOrReturn(error, headers); }
}
async function verifyEmail(request, env, headers) {
  try {
    const body = await readJson(request), email = typeof body.email === "string" ? body.email.trim().toLowerCase() : "", code = typeof body.code === "string" ? body.code.trim() : "";
    if (!validEmail(email) || !/^\d{6}$/.test(code)) throw new ApiError(400, "INVALID_CODE", "Enter the email address and six-digit code.");
    const user = await env.DB.prepare("SELECT id,full_name,email,email_verified,account_active,auth_version,deleted_at FROM users WHERE email = ?").bind(email).first();
    if (!user || user.deleted_at) throw new ApiError(400, "INVALID_CODE", "The code is invalid or expired.");
    if (Number(user.account_active) !== 1) throw new ApiError(403, "ACCOUNT_DISABLED", "This 414Unlock account is currently deactivated. Contact support.");
    if (user.email_verified) return json({ ok: true, token: await issueToken(user, env), user: publicUser(user) }, 200, headers);
    const now = Math.floor(Date.now() / 1000);
    const row = await env.DB.prepare("SELECT id,code_hash,expires_at,attempts FROM email_codes WHERE user_id = ? AND purpose = 'verify_email' ORDER BY created_at DESC LIMIT 1").bind(user.id).first();
    if (!row || row.expires_at <= now || row.attempts >= 5) throw new ApiError(400, "INVALID_CODE", "The code is invalid or expired. Request a new one.");
    const actual = await keyedHash(user.id + ":verify_email:" + code, env);
    if (!constantTimeEqual(actual, row.code_hash)) {
      await env.DB.prepare("UPDATE email_codes SET attempts = attempts + 1 WHERE id = ?").bind(row.id).run();
      throw new ApiError(400, "INVALID_CODE", "The code is invalid or expired.");
    }
    await env.DB.prepare("UPDATE users SET email_verified = 1 WHERE id = ?").bind(user.id).run();
    await env.DB.prepare("DELETE FROM email_codes WHERE user_id = ? AND purpose = 'verify_email'").bind(user.id).run();
    const verifiedUser = { ...user, email_verified: 1 };
    return json({ ok: true, token: await issueToken(verifiedUser, env), user: publicUser(verifiedUser) }, 200, headers);
  } catch (error) { throwOrReturn(error, headers); }
}
async function login(request, env, headers) {
  try {
    const body = await readJson(request), email = typeof body.email === "string" ? body.email.trim().toLowerCase() : "", password = typeof body.password === "string" ? body.password : "";
    if (!validEmail(email) || !password) throw new ApiError(400, "INVALID_CREDENTIALS", "Enter your email and password.");
    const user = await env.DB.prepare("SELECT id,full_name,email,password_salt,password_hash,email_verified,account_active,auth_version,deleted_at FROM users WHERE email = ?").bind(email).first();
    const passwordHash = await createPasswordHash(password, user ? user.password_salt : "00000000000000000000000000000000");
    if (!user || !constantTimeEqual(passwordHash, user.password_hash)) throw new ApiError(401, "INVALID_CREDENTIALS", "Email or password is incorrect.");
    if (user.deleted_at) throw new ApiError(403, "ACCOUNT_DELETED", "This account has been deleted. Contact support to request recovery.");
    if (!user.email_verified) throw new ApiError(403, "EMAIL_NOT_VERIFIED", "Verify your email before signing in.");
    if (Number(user.account_active) !== 1) throw new ApiError(403, "ACCOUNT_DISABLED", "This 414Unlock account is currently deactivated. Contact support.");
    return json({ ok: true, token: await issueToken(user, env), user: publicUser(user) }, 200, headers);
  } catch (error) { throwOrReturn(error, headers); }
}
async function getMe(request, env, headers) {
  try { const user = await readToken(request, env); return json({ ok: true, user: publicUser(user) }, 200, headers); }
  catch (error) { throwOrReturn(error, headers); }
}
async function createAppCode(request, env, headers) {
  try {
    const user = await readToken(request, env), now = Math.floor(Date.now() / 1000), code = randomHex(24), codeHash = await keyedHash("app:" + code, env);
    await env.DB.prepare("INSERT INTO app_codes (code_hash,user_id,expires_at,used_at,created_at) VALUES (?,?,?,NULL,?)").bind(codeHash, user.id, now + APP_CODE_TTL_SECONDS, now).run();
    return json({ ok: true, code, expiresIn: APP_CODE_TTL_SECONDS }, 200, headers);
  } catch (error) { throwOrReturn(error, headers); }
}
async function redeemAppCode(request, env, headers) {
  try {
    const body = await readJson(request), code = typeof body.code === "string" ? body.code.trim() : "";
    if (!/^[a-f0-9]{48}$/.test(code)) throw new ApiError(400, "INVALID_APP_CODE", "The sign-in code is invalid or expired.");
    const codeHash = await keyedHash("app:" + code, env), now = Math.floor(Date.now() / 1000);
    const used = await env.DB.prepare("UPDATE app_codes SET used_at = ? WHERE code_hash = ? AND used_at IS NULL AND expires_at > ? RETURNING user_id").bind(now, codeHash, now).first();
    if (!used) throw new ApiError(400, "INVALID_APP_CODE", "The sign-in code is invalid or expired. Start sign-in again.");
    const user = await env.DB.prepare("SELECT id,full_name,email,email_verified,account_active,auth_version,deleted_at FROM users WHERE id = ?").bind(used.user_id).first();
    if (!user || user.deleted_at || !user.email_verified) throw new ApiError(401, "AUTH_REQUIRED", "Sign in again to continue.");
    if (Number(user.account_active) !== 1) throw new ApiError(403, "ACCOUNT_DISABLED", "This 414Unlock account is currently deactivated. Contact support.");
    return json({ ok: true, token: await issueToken(user, env), user: publicUser(user) }, 200, headers);
  } catch (error) { throwOrReturn(error, headers); }
}
async function verificationStatus(request, env, headers) {
  try {
    const user = await readToken(request, env);
    const row = await env.DB.prepare("SELECT id,status,review_note,submitted_at,reviewed_at FROM verification_submissions WHERE user_id = ? ORDER BY submitted_at DESC LIMIT 1").bind(user.id).first();
    if (!row) return json({ ok: true, status: "not_submitted" }, 200, headers);
    return json({ ok: true, status: row.status, submissionId: row.id, submittedAt: row.submitted_at, reviewedAt: row.reviewed_at, note: row.review_note || "" }, 200, headers);
  } catch (error) { throwOrReturn(error, headers); }
}
function cloudinaryConfigured(env) { return Boolean(env.CLOUDINARY_CLOUD_NAME && env.CLOUDINARY_API_KEY && env.CLOUDINARY_API_SECRET); }
async function sha1Hex(value) { return bytesToHex(new Uint8Array(await crypto.subtle.digest("SHA-1", encoder.encode(value)))); }
async function cloudinaryApiSignature(params, secret) {
  const canonical = Object.keys(params).sort().map((key) => key + "=" + params[key]).join("&");
  return sha1Hex(canonical + secret);
}
function cloudinaryApiBase(env) {
  if (!cloudinaryConfigured(env)) throw new ApiError(503, "PRIVATE_STORAGE_NOT_CONFIGURED", "Private document storage is not configured yet.");
  return "https://api.cloudinary.com/v1_1/" + encodeURIComponent(env.CLOUDINARY_CLOUD_NAME);
}
async function uploadCloudinaryDocument(file, documentId, env) {
  const timestamp = Math.floor(Date.now() / 1000), publicId = "414unlock/verification/" + documentId;
  const params = { public_id: publicId, timestamp: String(timestamp), type: "authenticated" };
  const signature = await cloudinaryApiSignature(params, env.CLOUDINARY_API_SECRET), body = new FormData();
  body.append("file", file, "identity-document"); body.append("public_id", publicId);
  body.append("timestamp", String(timestamp)); body.append("type", "authenticated");
  body.append("api_key", env.CLOUDINARY_API_KEY); body.append("signature", signature);
  const response = await fetch(cloudinaryApiBase(env) + "/raw/upload", { method: "POST", body });
  let data = {}; try { data = await response.json(); } catch (_) {}
  if (!response.ok || !data.public_id || !data.version) {
    console.error("Cloudinary upload failed:", Number(response.status));
    throw new ApiError(502, "PRIVATE_STORAGE_UPLOAD_FAILED", "Your document could not be stored securely. Please try again later.");
  }
  return "cloudinary:" + data.public_id + "|" + String(data.version);
}
function parseCloudinaryDocumentKey(value) {
  if (typeof value !== "string" || !value.startsWith("cloudinary:")) return null;
  const match = value.slice("cloudinary:".length).match(/^([A-Za-z0-9/_\-.]+)\|(\d+)$/);
  return match ? { publicId: match[1], version: match[2] } : null;
}
async function cloudinaryDocumentUrl(documentKey, env) {
  const asset = parseCloudinaryDocumentKey(documentKey);
  if (!asset) throw new ApiError(404, "DOCUMENT_NOT_AVAILABLE", "This document is not available for review.");
  const deliveryPath = "v" + asset.version + "/" + asset.publicId;
  const signature = base64url(new Uint8Array(await crypto.subtle.digest("SHA-1", encoder.encode(deliveryPath + env.CLOUDINARY_API_SECRET)))).slice(0, 8);
  return "https://res.cloudinary.com/" + encodeURIComponent(env.CLOUDINARY_CLOUD_NAME) + "/raw/authenticated/s--" + signature + "--/" + deliveryPath.split("/").map(encodeURIComponent).join("/");
}
async function deleteCloudinaryDocument(documentKey, env) {
  if (!documentKey) return;
  const asset = parseCloudinaryDocumentKey(documentKey);
  if (!asset) throw new ApiError(409, "DOCUMENT_REFERENCE_INVALID", "The stored document reference is invalid; the review was not completed.");
  const timestamp = Math.floor(Date.now() / 1000);
  const params = { invalidate: "true", public_id: asset.publicId, timestamp: String(timestamp), type: "authenticated" };
  const signature = await cloudinaryApiSignature(params, env.CLOUDINARY_API_SECRET), body = new FormData();
  body.append("public_id", asset.publicId); body.append("timestamp", String(timestamp)); body.append("type", "authenticated");
  body.append("invalidate", "true"); body.append("api_key", env.CLOUDINARY_API_KEY); body.append("signature", signature);
  const response = await fetch(cloudinaryApiBase(env) + "/raw/destroy", { method: "POST", body });
  let data = {}; try { data = await response.json(); } catch (_) {}
  if (!response.ok || (data.result && !["ok", "not found"].includes(String(data.result).toLowerCase()))) {
    console.error("Cloudinary delete failed:", Number(response.status));
    throw new ApiError(502, "PRIVATE_STORAGE_DELETE_FAILED", "The stored document could not be deleted securely. The application was not changed.");
  }
}

async function submitVerification(request, env, headers) {
  let documentKey = null;
  try {
    const user = await readToken(request, env), type = request.headers.get("Content-Type") || "";
    if (!cloudinaryConfigured(env)) throw new ApiError(503, "PRIVATE_STORAGE_NOT_CONFIGURED", "Private document storage is not configured yet.");
    if (!type.toLowerCase().includes("multipart/form-data")) throw new ApiError(415, "MULTIPART_REQUIRED", "Upload the application as a multipart form.");
    const form = await request.formData(), legalName = String(form.get("legalName") || "").trim(), country = String(form.get("country") || "").trim();
    const applicantType = String(form.get("applicantType") || ""), termsAccepted = String(form.get("termsAccepted") || "") === "true";
    const termsVersion = String(form.get("termsVersion") || env.TERMS_VERSION || "unknown").slice(0, 40), file = form.get("document");
    if (legalName.length < 2 || legalName.length > 120 || country.length < 2 || country.length > 80) throw new ApiError(400, "INVALID_DETAILS", "Check your name and document country.");
    if (!["professional", "individual"].includes(applicantType)) throw new ApiError(400, "INVALID_APPLICANT_TYPE", "Choose a valid applicant type.");
    if (!termsAccepted) throw new ApiError(400, "TERMS_REQUIRED", "Accept the current terms and privacy notice.");
    if (!(file instanceof File) || file.size < 1 || file.size > MAX_DOCUMENT_BYTES || !ALLOWED_TYPES.has(file.type)) throw new ApiError(400, "INVALID_DOCUMENT", "Upload a PDF, PNG or JPG no larger than 7 MB.");
    const pending = await env.DB.prepare("SELECT id FROM verification_submissions WHERE user_id = ? AND status = 'pending' LIMIT 1").bind(user.id).first();
    if (pending) throw new ApiError(409, "APPLICATION_PENDING", "You already have an application awaiting review.");
    const id = randomHex(16), now = Math.floor(Date.now() / 1000), ext = file.type === "application/pdf" ? "pdf" : file.type === "image/png" ? "png" : "jpg";
    documentKey = await uploadCloudinaryDocument(file, id + "." + ext, env);
    const originalName = String(file.name || "document").replace(/[^a-zA-Z0-9._ -]/g, "_").slice(0, 100);
    await env.DB.prepare("INSERT INTO verification_submissions (id,user_id,legal_name,country,applicant_type,document_key,document_name,document_type,status,terms_version,terms_accepted_at,submitted_at) VALUES (?,?,?,?,?,?,?,?, 'pending',?,?,?)")
      .bind(id, user.id, legalName, country, applicantType, documentKey, originalName, file.type, termsVersion, now, now).run();
    return json({ ok: true, status: "pending", submissionId: id, message: "Your application has been submitted for review." }, 201, headers);
  } catch (error) {
    if (documentKey) { try { await deleteCloudinaryDocument(documentKey, env); } catch (_) {} }
    throwOrReturn(error, headers);
  }
}
async function requireAdmin(request, env) {
  const user = await readToken(request, env), allowed = (env.ADMIN_EMAILS || "").split(",").map((x) => x.trim().toLowerCase()).filter(Boolean);
  if (!allowed.includes(user.email.toLowerCase())) throw new ApiError(403, "ADMIN_REQUIRED", "Administrator access is required.");
  return user;
}
function isAdminEmail(email, env) {
  return (env.ADMIN_EMAILS || "").split(",").map((x) => x.trim().toLowerCase()).filter(Boolean).includes(String(email || "").toLowerCase());
}
async function listMySupportTickets(request, env, headers) {
  try {
    const user = await readToken(request, env);
    const data = await env.DB.prepare(
      `SELECT t.id,t.subject,t.status,t.created_at,t.updated_at,
        (SELECT m.body FROM support_messages m WHERE m.ticket_id=t.id ORDER BY m.created_at DESC LIMIT 1) AS latest_message,
        (SELECT m.sender_type FROM support_messages m WHERE m.ticket_id=t.id ORDER BY m.created_at DESC LIMIT 1) AS latest_sender
       FROM support_tickets t WHERE t.user_id=? ORDER BY t.updated_at DESC LIMIT 50`
    ).bind(user.id).all();
    return json({ ok:true, tickets:(data.results||[]).map((t)=>({id:t.id,subject:t.subject,status:t.status,createdAt:t.created_at,updatedAt:t.updated_at,latestMessage:t.latest_message||"",latestSender:t.latest_sender||""})) },200,headers);
  } catch(error){throwOrReturn(error,headers);}
}
async function createSupportTicket(request, env, headers) {
  try {
    const user=await readToken(request,env),body=await readJson(request);
    const subject=typeof body.subject==="string"?body.subject.trim().slice(0,120):"";
    const message=typeof body.message==="string"?body.message.trim().slice(0,4000):"";
    if(subject.length<3)throw new ApiError(400,"INVALID_SUPPORT_SUBJECT","Enter a subject with at least 3 characters.");
    if(message.length<2)throw new ApiError(400,"INVALID_SUPPORT_MESSAGE","Enter a message for support.");
    const now=Math.floor(Date.now()/1000),id=randomHex(16),messageId=randomHex(16);
    await env.DB.batch([
      env.DB.prepare("INSERT INTO support_tickets (id,user_id,subject,status,created_at,updated_at,last_message_at) VALUES (?,?,?,'open',?,?,?)").bind(id,user.id,subject,now,now,now),
      env.DB.prepare("INSERT INTO support_messages (id,ticket_id,sender_type,sender_email,body,created_at) VALUES (?,?,'customer',?,?,?)").bind(messageId,id,user.email,message,now)
    ]);
    return json({ok:true,ticket:{id,subject,status:"open",createdAt:now,updatedAt:now},message:"Your message has been sent to 414Unlock support."},201,headers);
  } catch(error){throwOrReturn(error,headers);}
}
async function getSupportTicketMessages(request, env, headers, id) {
  try {
    const user=await readToken(request,env),admin=isAdminEmail(user.email,env);
    const ticket=await env.DB.prepare("SELECT id,user_id,subject,status,created_at,updated_at FROM support_tickets WHERE id=?").bind(id).first();
    if(!ticket||(!admin&&ticket.user_id!==user.id))throw new ApiError(404,"SUPPORT_TICKET_NOT_FOUND","That support conversation could not be found.");
    const data=await env.DB.prepare("SELECT id,sender_type,sender_email,body,created_at FROM support_messages WHERE ticket_id=? ORDER BY created_at ASC LIMIT 300").bind(id).all();
    return json({ok:true,ticket:{id:ticket.id,subject:ticket.subject,status:ticket.status,createdAt:ticket.created_at,updatedAt:ticket.updated_at},messages:(data.results||[]).map((m)=>({id:m.id,senderType:m.sender_type,senderEmail:m.sender_email,body:m.body,createdAt:m.created_at}))},200,headers);
  } catch(error){throwOrReturn(error,headers);}
}
async function postSupportTicketMessage(request, env, headers, id) {
  try {
    const user=await readToken(request,env),admin=isAdminEmail(user.email,env),body=await readJson(request);
    const message=typeof body.message==="string"?body.message.trim().slice(0,4000):"";
    if(message.length<2)throw new ApiError(400,"INVALID_SUPPORT_MESSAGE","Enter a message before sending.");
    const ticket=await env.DB.prepare("SELECT id,user_id,status FROM support_tickets WHERE id=?").bind(id).first();
    if(!ticket||(!admin&&ticket.user_id!==user.id))throw new ApiError(404,"SUPPORT_TICKET_NOT_FOUND","That support conversation could not be found.");
    const now=Math.floor(Date.now()/1000),sender=admin?"admin":"customer";
    await env.DB.batch([
      env.DB.prepare("INSERT INTO support_messages (id,ticket_id,sender_type,sender_email,body,created_at) VALUES (?,?,?,?,?,?)").bind(randomHex(16),id,sender,user.email,message,now),
      env.DB.prepare("UPDATE support_tickets SET status=?,updated_at=?,last_message_at=? WHERE id=?").bind(admin?ticket.status:"open",now,now,id)
    ]);
    return json({ok:true,message:{senderType:sender,body:message,createdAt:now},messageText:"Message sent."},201,headers);
  } catch(error){throwOrReturn(error,headers);}
}
async function listAdminSupportTickets(request, env, headers) {
  try {
    await requireAdmin(request,env);
    const statusParam=new URL(request.url).searchParams.get("status")||"open";
    if(!["open","closed","all"].includes(statusParam))throw new ApiError(400,"INVALID_SUPPORT_FILTER","Choose open, closed, or all.");
    const sql=`SELECT t.id,t.user_id,t.subject,t.status,t.created_at,t.updated_at,u.full_name,u.email,
      (SELECT m.body FROM support_messages m WHERE m.ticket_id=t.id ORDER BY m.created_at DESC LIMIT 1) AS latest_message,
      (SELECT m.sender_type FROM support_messages m WHERE m.ticket_id=t.id ORDER BY m.created_at DESC LIMIT 1) AS latest_sender
      FROM support_tickets t JOIN users u ON u.id=t.user_id
      WHERE (?='all' OR t.status=?) ORDER BY CASE t.status WHEN 'open' THEN 0 ELSE 1 END,t.updated_at DESC LIMIT 100`;
    const data=await env.DB.prepare(sql).bind(statusParam,statusParam).all();
    return json({ok:true,tickets:(data.results||[]).map((t)=>({id:t.id,userId:t.user_id,fullName:t.full_name,email:t.email,subject:t.subject,status:t.status,createdAt:t.created_at,updatedAt:t.updated_at,latestMessage:t.latest_message||"",latestSender:t.latest_sender||""}))},200,headers);
  } catch(error){throwOrReturn(error,headers);}
}
async function updateAdminSupportTicketStatus(request, env, headers, id) {
  try {
    const admin=await requireAdmin(request,env),body=await readJson(request),status=String(body.status||"");
    if(!["open","closed"].includes(status))throw new ApiError(400,"INVALID_SUPPORT_STATUS","Choose open or closed.");
    const ticket=await env.DB.prepare("SELECT user_id FROM support_tickets WHERE id=?").bind(id).first();
    if(!ticket)throw new ApiError(404,"SUPPORT_TICKET_NOT_FOUND","That support conversation could not be found.");
    const now=Math.floor(Date.now()/1000);
    const result=await env.DB.prepare("UPDATE support_tickets SET status=?,updated_at=? WHERE id=?").bind(status,now,id).run();
    if(!result.meta||result.meta.changes!==1)throw new ApiError(404,"SUPPORT_TICKET_NOT_FOUND","That support conversation could not be found.");
    await env.DB.prepare("INSERT INTO admin_audit_log (id,actor_email,action,target_user_id,details,created_at) VALUES (?,?,?,?,?,?)").bind(randomHex(16),admin.email,"support_ticket_"+status,ticket.user_id,"ticket:"+id,now).run();
    return json({ok:true,status,message:"Support conversation "+status+"."},200,headers);
  } catch(error){throwOrReturn(error,headers);}
}

async function listSubmissions(request, env, headers) {
  try {
    await requireAdmin(request, env);
    const data = await env.DB.prepare("SELECT s.id,s.user_id,s.legal_name,s.country,s.applicant_type,s.document_name,s.document_type,s.status,s.submitted_at,u.email FROM verification_submissions s JOIN users u ON u.id=s.user_id WHERE s.status='pending' ORDER BY s.submitted_at ASC LIMIT 100").all();
    return json({ ok: true, submissions: (data.results || []).map((s) => ({ id: s.id, userId: s.user_id, legalName: s.legal_name, country: s.country, applicantType: s.applicant_type, documentName: s.document_name, documentType: s.document_type, status: s.status, submittedAt: s.submitted_at, email: s.email })) }, 200, headers);
  } catch (error) { throwOrReturn(error, headers); }
}
async function getSubmissionDocument(request, env, headers, id) {
  try {
    await requireAdmin(request, env);
    if (!cloudinaryConfigured(env)) throw new ApiError(503, "PRIVATE_STORAGE_NOT_CONFIGURED", "Private document storage is not configured yet.");
    const row = await env.DB.prepare("SELECT document_key,document_type,status FROM verification_submissions WHERE id = ?").bind(id).first();
    if (!row || !row.document_key || row.status !== "pending") throw new ApiError(404, "DOCUMENT_NOT_AVAILABLE", "This document is not available for review.");
    const secureUrl = await cloudinaryDocumentUrl(row.document_key, env);
    const upstream = await fetch(secureUrl, { headers: { "Accept": row.document_type } });
    if (!upstream.ok) throw new ApiError(502, "DOCUMENT_RETRIEVAL_FAILED", "The private document could not be retrieved from storage.");
    return new Response(upstream.body, { status: 200, headers: { ...headers, "Content-Type": row.document_type, "Content-Disposition": "inline; filename=\"verification-document\"", "X-Content-Type-Options": "nosniff", "Cache-Control": "private, no-store" } });
  } catch (error) { throwOrReturn(error, headers); }
}
async function reviewSubmission(request, env, headers, id) {
  try {
    const admin = await requireAdmin(request, env), body = await readJson(request);
    const decision = String(body.decision || ""), note = typeof body.note === "string" ? body.note.trim().slice(0, 500) : "";
    if (!["approve", "reject"].includes(decision)) throw new ApiError(400, "INVALID_DECISION", "Choose approve or reject.");
    const row = await env.DB.prepare("SELECT id,document_key,status FROM verification_submissions WHERE id = ?").bind(id).first();
    if (!row || row.status !== "pending") throw new ApiError(404, "APPLICATION_NOT_PENDING", "This application is no longer pending.");
    if (row.document_key && !cloudinaryConfigured(env)) throw new ApiError(503, "PRIVATE_STORAGE_NOT_CONFIGURED", "Private document storage is not configured; the application was not changed.");
    if (row.document_key) await deleteCloudinaryDocument(row.document_key, env);
    const now = Math.floor(Date.now() / 1000), status = decision === "approve" ? "approved" : "rejected";
    const result = await env.DB.prepare("UPDATE verification_submissions SET status=?,review_note=?,reviewed_at=?,reviewed_by=? WHERE id=? AND status='pending'").bind(status, note, now, admin.email, id).run();
    if (!result.meta || result.meta.changes !== 1) throw new ApiError(409, "REVIEW_CONFLICT", "Another reviewer already handled this application.");
    if (row.document_key) {
      await env.DB.prepare("UPDATE verification_submissions SET document_key=NULL WHERE id=?").bind(id).run();
    }
    return json({ ok: true, status, message: "Application " + status + ". Uploaded document deleted after review." }, 200, headers);
  } catch (error) { throwOrReturn(error, headers); }
}

const WALLET_MODEL_PRICES = Object.freeze({
  iphone_6: 1400,
  iphone_7: 1600,
  iphone_8: 1900,
  iphone_x: 2200,
  iphone_xr: 2500,
  iphone_11_12: 3000,
  iphone_13_14: 3500,
  iphone_15: 5000,
  iphone_16: 6500
});
const WALLET_MODEL_NAMES = Object.freeze({
  iphone_6: "iPhone 6 / 6 Plus / 6S / SE",
  iphone_7: "iPhone 7 / 7 Plus",
  iphone_8: "iPhone 8 / 8 Plus",
  iphone_x: "iPhone X",
  iphone_xr: "iPhone XR / XS / XS Max",
  iphone_11_12: "iPhone 11 & 12 Series",
  iphone_13_14: "iPhone 13 & 14 Series",
  iphone_15: "iPhone 15 Series",
  iphone_16: "iPhone 16 Series"
});

async function requireApprovedAccount(user, env) {
  const approved = await env.DB.prepare(
    "SELECT id FROM verification_submissions WHERE user_id=? AND status='approved' ORDER BY submitted_at DESC LIMIT 1"
  ).bind(user.id).first();
  if (!approved) throw new ApiError(403, "VERIFICATION_REQUIRED", "Complete account verification and wait for approval before using wallet top-ups or service requests.");
}

async function ensureWallet(userId, env, now) {
  await env.DB.prepare("INSERT OR IGNORE INTO wallets (user_id,balance,created_at,updated_at) VALUES (?,0,?,?)")
    .bind(userId, now, now).run();
}

function walletServiceName(serviceKey) {
  return serviceKey === "imei_check" ? "IMEI check" : "iPhone unlock service";
}

function publicWalletOrder(row) {
  return {
    id: row.id,
    serviceKey: row.service_key,
    serviceName: walletServiceName(row.service_key),
    modelKey: row.model_key,
    modelName: WALLET_MODEL_NAMES[row.model_key] || row.model_key,
    deviceModel: row.device_model,
    maskedIdentifier: row.masked_identifier,
    fastService: Boolean(row.fast_service),
    amountDue: Number(row.amount_due),
    status: row.status,
    checkCreditApplied: Boolean(row.check_credit_order_id),
    providerReference: row.provider_reference || "",
    adminNote: row.admin_note || "",
    createdAt: row.created_at,
    updatedAt: row.updated_at
  };
}

async function walletOverview(request, env, headers) {
  try {
    const user = await readToken(request, env), now = Math.floor(Date.now() / 1000);
    await ensureWallet(user.id, env, now);
    const wallet = await env.DB.prepare("SELECT balance FROM wallets WHERE user_id=?").bind(user.id).first();
    const transactions = await env.DB.prepare(
      "SELECT id,kind,amount,balance_after,reference,description,created_at FROM wallet_transactions WHERE user_id=? ORDER BY created_at DESC LIMIT 30"
    ).bind(user.id).all();
    const topups = await env.DB.prepare(
      "SELECT id,amount,request_reference,provider_reference,status,created_at,submitted_at,reviewed_at,review_note FROM topup_requests WHERE user_id=? ORDER BY created_at DESC LIMIT 20"
    ).bind(user.id).all();
    const orders = await env.DB.prepare(
      "SELECT id,service_key,model_key,device_model,masked_identifier,fast_service,amount_due,status,check_credit_order_id,provider_reference,admin_note,created_at,updated_at FROM service_orders WHERE user_id=? ORDER BY created_at DESC LIMIT 25"
    ).bind(user.id).all();
    return json({
      ok: true,
      balance: Number(wallet ? wallet.balance : 0),
      transactions: (transactions.results || []).map((r) => ({
        id: r.id, kind: r.kind, amount: Number(r.amount), balanceAfter: Number(r.balance_after),
        reference: r.reference, description: r.description, createdAt: r.created_at
      })),
      topups: (topups.results || []).map((r) => ({
        id: r.id, amount: Number(r.amount), requestReference: r.request_reference,
        providerReference: r.provider_reference || "", status: r.status, createdAt: r.created_at,
        submittedAt: r.submitted_at, reviewedAt: r.reviewed_at, reviewNote: r.review_note || ""
      })),
      orders: (orders.results || []).map(publicWalletOrder)
    }, 200, headers);
  } catch (error) { throwOrReturn(error, headers); }
}

async function createTopupRequest(request, env, headers) {
  try {
    const user = await readToken(request, env), body = await readJson(request);
    await requireApprovedAccount(user, env);
    const amount = Number(body.amount);
    if (!Number.isSafeInteger(amount) || amount < 50 || amount > 100000) {
      throw new ApiError(400, "INVALID_TOPUP_AMOUNT", "Enter a whole-Dalasi top-up from D50 to D100,000.");
    }
    const now = Math.floor(Date.now() / 1000), id = randomHex(16);
    const requestReference = "414T-" + randomHex(5).toUpperCase();
    await ensureWallet(user.id, env, now);
    await env.DB.prepare(
      "INSERT INTO topup_requests (id,user_id,amount,request_reference,provider_reference,status,created_at,submitted_at) VALUES (?,?,?,?,NULL,'awaiting_payment',?,NULL)"
    ).bind(id, user.id, amount, requestReference, now).run();
    return json({ ok: true, topup: { id, amount, requestReference, status: "awaiting_payment", createdAt: now }, message: "Top-up request created. Submit the SquashberryPay transaction reference after payment; the wallet is credited only after an administrator verifies it." }, 201, headers);
  } catch (error) { throwOrReturn(error, headers); }
}

async function submitTopupReference(request, env, headers, id) {
  try {
    const user = await readToken(request, env), body = await readJson(request);
    await requireApprovedAccount(user, env);
    const providerReference = typeof body.providerReference === "string" ? body.providerReference.trim().slice(0, 120) : "";
    if (providerReference.length < 3) throw new ApiError(400, "INVALID_PAYMENT_REFERENCE", "Enter the SquashberryPay transaction reference shown for the completed payment.");
    const now = Math.floor(Date.now() / 1000);
    let result;
    try {
      result = await env.DB.prepare(
        "UPDATE topup_requests SET provider_reference=?,status='pending',submitted_at=? WHERE id=? AND user_id=? AND status='awaiting_payment'"
      ).bind(providerReference, now, id, user.id).run();
    } catch (error) {
      if (String(error && error.message || "").toLowerCase().includes("unique")) {
        throw new ApiError(409, "PAYMENT_REFERENCE_ALREADY_USED", "That provider transaction reference has already been submitted for another request.");
      }
      throw error;
    }
    if (!result.meta || result.meta.changes !== 1) throw new ApiError(409, "TOPUP_NOT_AWAITING_REFERENCE", "This top-up request is not awaiting a payment reference. Refresh your wallet and check its current status.");
    return json({ ok: true, status: "pending", message: "Payment reference submitted for review. Wallet credit is pending until SquashberryPay confirms the transaction." }, 200, headers);
  } catch (error) { throwOrReturn(error, headers); }
}

async function deviceEncryptionKey(env, usage) {
  const secret = env.DEVICE_DATA_ENCRYPTION_KEY || "";
  if (secret.length < 32) throw new ApiError(503, "DEVICE_STORAGE_NOT_CONFIGURED", "Secure device-data storage is not configured. No device order was accepted.");
  const digest = await crypto.subtle.digest("SHA-256", encoder.encode(secret));
  return crypto.subtle.importKey("raw", digest, { name: "AES-GCM" }, false, usage || ["encrypt", "decrypt"]);
}

async function encryptDeviceIdentifier(value, env) {
  const key = await deviceEncryptionKey(env, ["encrypt"]), iv = randomBytes(12);
  const cipher = new Uint8Array(await crypto.subtle.encrypt({ name: "AES-GCM", iv }, key, encoder.encode(value)));
  const joined = new Uint8Array(iv.length + cipher.length);
  joined.set(iv, 0);
  joined.set(cipher, iv.length);
  return base64url(joined);
}

function decodeBase64Url(value) {
  const padded = String(value).replace(/-/g, "+").replace(/_/g, "/");
  const binary = atob(padded + "=".repeat((4 - padded.length % 4) % 4));
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

async function decryptDeviceIdentifier(value, env) {
  try {
    const joined = decodeBase64Url(value);
    if (joined.length < 29) throw new Error("Invalid ciphertext");
    const iv = joined.slice(0, 12), cipher = joined.slice(12);
    const key = await deviceEncryptionKey(env, ["decrypt"]);
    const plain = await crypto.subtle.decrypt({ name: "AES-GCM", iv }, key, cipher);
    return decoder.decode(plain);
  } catch (error) {
    if (error instanceof ApiError) throw error;
    throw new ApiError(503, "DEVICE_DATA_UNAVAILABLE", "Device details cannot be decrypted. Check the configured encryption secret before continuing.");
  }
}

async function createServiceOrder(request, env, headers) {
  try {
    const user = await readToken(request, env), body = await readJson(request);
    await requireApprovedAccount(user, env);
    const serviceKey = body.serviceType === "imei_check" ? "imei_check" : body.serviceType === "unlock" ? "unlock" : "";
    const modelKey = typeof body.modelKey === "string" ? body.modelKey.trim() : "";
    const deviceModel = typeof body.deviceModel === "string" ? body.deviceModel.trim().slice(0, 120) : "";
    const identifierKind = typeof body.identifierKind === "string" ? body.identifierKind.trim().toLowerCase() : "";
    const rawIdentifier = typeof body.identifier === "string" ? body.identifier.trim() : "";
    const identifier = rawIdentifier.replace(/[^a-zA-Z0-9]/g, "").toUpperCase();
    const issueDescription = typeof body.issueDescription === "string" ? body.issueDescription.trim().slice(0, 1000) : "";
    const ownershipConfirmed = body.ownershipConfirmed === true;
    const noSignalConfirmed = body.noSignalConfirmed === true;
    const fastService = serviceKey === "unlock" && body.fastService === true;

    if (!serviceKey) throw new ApiError(400, "INVALID_SERVICE", "Choose a listed iPhone service.");
    if (!Object.prototype.hasOwnProperty.call(WALLET_MODEL_PRICES, modelKey)) throw new ApiError(400, "INVALID_MODEL_PRICE", "Choose a model band from the published price list.");
    if (deviceModel.length < 2) throw new ApiError(400, "INVALID_DEVICE_MODEL", "Enter the exact device model.");
    if (!["serial", "imei"].includes(identifierKind)) throw new ApiError(400, "INVALID_IDENTIFIER_KIND", "Choose serial number or IMEI.");
    if (identifierKind === "imei" && !/^\d{14,16}$/.test(identifier)) throw new ApiError(400, "INVALID_DEVICE_IDENTIFIER", "The IMEI format is invalid.");
    if (identifierKind === "serial" && !/^[A-Z0-9]{6,64}$/.test(identifier)) throw new ApiError(400, "INVALID_DEVICE_IDENTIFIER", "The serial number format is invalid.");
    if (issueDescription.length < 3) throw new ApiError(400, "ISSUE_DESCRIPTION_REQUIRED", "Describe the device issue or service request.");
    if (!ownershipConfirmed) throw new ApiError(400, "DEVICE_AUTHORIZATION_REQUIRED", "Confirm that you own the device or are authorised by its owner.");
    if (serviceKey === "unlock" && !noSignalConfirmed) throw new ApiError(400, "SERVICE_LIMITS_NOT_CONFIRMED", "Confirm the listed Wi-Fi-only / no-signal service limitation.");
    if (serviceKey === "imei_check" && body.fastService === true) throw new ApiError(400, "FAST_SERVICE_NOT_APPLICABLE", "Fast service is an add-on for unlock services only.");

    const now = Math.floor(Date.now() / 1000);
    const basePrice = serviceKey === "imei_check" ? 150 : WALLET_MODEL_PRICES[modelKey];
    const fingerprint = await keyedHash("wallet-order:" + identifierKind + ":" + identifier, env);
    let checkCreditOrderId = null, checkCredit = 0;
    if (serviceKey === "unlock") {
      const completedCheck = await env.DB.prepare(
        "SELECT id FROM service_orders WHERE user_id=? AND service_key='imei_check' AND status='completed' AND check_credit_used_at IS NULL AND identifier_fingerprint=? AND created_at>=? ORDER BY created_at DESC LIMIT 1"
      ).bind(user.id, fingerprint, now - 604800).first();
      if (completedCheck) { checkCreditOrderId = completedCheck.id; checkCredit = 150; }
    }
    const amountDue = basePrice + (fastService ? 1000 : 0) - checkCredit;
    const ciphertext = await encryptDeviceIdentifier(identifier, env);
    const id = randomHex(16);
    const maskedIdentifier = "•••• •••• " + identifier.slice(-4);
    await ensureWallet(user.id, env, now);
    try {
      await env.DB.prepare(
        "INSERT INTO service_orders (id,user_id,service_key,model_key,device_model,identifier_kind,identifier_ciphertext,identifier_fingerprint,masked_identifier,issue_description,fast_service,amount_due,status,ownership_confirmed,no_signal_confirmed,check_credit_order_id,check_credit_used_at,provider_reference,admin_note,created_at,updated_at,processed_at,completed_at,reviewed_by) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,'submitted',1,?,?,NULL,NULL,NULL,?,?,NULL,NULL,NULL)"
      ).bind(id, user.id, serviceKey, modelKey, deviceModel, identifierKind, ciphertext, fingerprint, maskedIdentifier, issueDescription, fastService ? 1 : 0, amountDue, serviceKey === "unlock" ? 1 : 0, checkCreditOrderId, now, now).run();
    } catch (error) {
      const message = String(error && error.message || "");
      if (message.includes("INSUFFICIENT_BALANCE")) throw new ApiError(409, "INSUFFICIENT_BALANCE", "Your wallet balance is not enough for this service. Top up before submitting the request.");
      if (message.includes("CHECK_CREDIT_INVALID")) throw new ApiError(409, "CHECK_CREDIT_ALREADY_USED", "The IMEI-check credit changed before the order was created. Refresh the quote and try again.");
      if (message.includes("WALLET_MISSING")) throw new ApiError(503, "WALLET_NOT_READY", "The wallet is not ready. Refresh your dashboard and try again.");
      throw error;
    }
    const wallet = await env.DB.prepare("SELECT balance FROM wallets WHERE user_id=?").bind(user.id).first();
    const order = await env.DB.prepare(
      "SELECT id,service_key,model_key,device_model,masked_identifier,fast_service,amount_due,status,check_credit_order_id,provider_reference,admin_note,created_at,updated_at FROM service_orders WHERE id=? AND user_id=?"
    ).bind(id, user.id).first();
    return json({ ok: true, order: publicWalletOrder(order), balance: Number(wallet ? wallet.balance : 0), message: "Service request submitted. The request is queued for manual review." + (checkCredit ? " D150 IMEI-check credit was applied." : "") }, 201, headers);
  } catch (error) { throwOrReturn(error, headers); }
}

async function listAdminUsers(request, env, headers) {
  try {
    const admin=await requireAdmin(request,env),url=new URL(request.url);
    const q=String(url.searchParams.get("q")||"").trim().slice(0,80),like="%"+q+"%",status=String(url.searchParams.get("status")||"all");
    if(!["all","active","inactive","deleted"].includes(status))throw new ApiError(400,"INVALID_USER_FILTER","Choose a valid account filter.");
    const result=await env.DB.prepare(
      `SELECT u.id,u.full_name,u.email,u.email_verified,u.account_active,u.account_status_note,u.account_status_updated_at,u.created_at,u.deleted_at,u.deleted_note,
        (SELECT v.status FROM verification_submissions v WHERE v.user_id=u.id ORDER BY v.submitted_at DESC LIMIT 1) AS verification_status,
        COALESCE(w.balance,0) AS wallet_balance,
        (SELECT COUNT(*) FROM service_orders o WHERE o.user_id=u.id) AS order_count,
        (SELECT COUNT(*) FROM topup_requests t WHERE t.user_id=u.id) AS topup_count
       FROM users u LEFT JOIN wallets w ON w.user_id=u.id
       WHERE (?='' OR u.email LIKE ? OR u.full_name LIKE ?)
        AND (?='all' OR (?='deleted' AND u.deleted_at IS NOT NULL) OR (?='inactive' AND u.deleted_at IS NULL AND u.account_active=0) OR (?='active' AND u.deleted_at IS NULL AND u.account_active=1))
       ORDER BY CASE WHEN u.deleted_at IS NOT NULL THEN 2 WHEN u.account_active=0 THEN 1 ELSE 0 END,u.created_at DESC LIMIT 100`
    ).bind(q,like,like,status,status,status,status).all();
    return json({ok:true,adminEmail:admin.email,users:(result.results||[]).map(u=>({
      id:u.id,fullName:u.full_name,email:u.email,emailVerified:Boolean(u.email_verified),
      accountActive:Number(u.account_active)===1&&!u.deleted_at,deleted:Boolean(!!u.deleted_at),deletedAt:u.deleted_at,
      deletedNote:u.deleted_note||"",accountStatusNote:u.account_status_note||"",accountStatusUpdatedAt:u.account_status_updated_at,
      createdAt:u.created_at,verificationStatus:u.verification_status||"not_submitted",walletBalance:Number(u.wallet_balance||0),
      orderCount:Number(u.order_count||0),topupCount:Number(u.topup_count||0)
    }))},200,headers);
  }catch(error){throwOrReturn(error,headers);}
}
async function getAdminUserDetails(request,env,headers,id){
  try{
    await requireAdmin(request,env);
    const user=await env.DB.prepare(
      `SELECT u.id,u.full_name,u.email,u.email_verified,u.created_at,u.account_active,u.account_status_note,
        u.account_status_updated_at,u.account_status_updated_by,u.deleted_at,u.deleted_by,u.deleted_note,
        COALESCE(w.balance,0) AS wallet_balance
       FROM users u LEFT JOIN wallets w ON w.user_id=u.id WHERE u.id=?`
    ).bind(id).first();
    if(!user)throw new ApiError(404,"USER_NOT_FOUND","That member account could not be found.");
    const [verification,orders,topups,transactions,tickets]=await Promise.all([
      env.DB.prepare("SELECT id,legal_name,country,applicant_type,status,review_note,submitted_at,reviewed_at,reviewed_by FROM verification_submissions WHERE user_id=? ORDER BY submitted_at DESC LIMIT 20").bind(id).all(),
      env.DB.prepare("SELECT id,service_key,model_key,device_model,masked_identifier,amount_due,status,provider_reference,admin_note,created_at,updated_at FROM service_orders WHERE user_id=? ORDER BY created_at DESC LIMIT 30").bind(id).all(),
      env.DB.prepare("SELECT id,amount,request_reference,provider_reference,status,created_at,submitted_at,reviewed_at,review_note FROM topup_requests WHERE user_id=? ORDER BY created_at DESC LIMIT 30").bind(id).all(),
      env.DB.prepare("SELECT id,kind,amount,balance_after,reference,description,created_at,created_by FROM wallet_transactions WHERE user_id=? ORDER BY created_at DESC LIMIT 40").bind(id).all(),
      env.DB.prepare("SELECT id,subject,status,created_at,updated_at FROM support_tickets WHERE user_id=? ORDER BY updated_at DESC LIMIT 20").bind(id).all()
    ]);
    return json({ok:true,user:{
      id:user.id,fullName:user.full_name,email:user.email,emailVerified:Boolean(user.email_verified),createdAt:user.created_at,
      accountActive:Number(user.account_active)===1&&!user.deleted_at,deleted:Boolean(user.deleted_at),deletedAt:user.deleted_at,deletedBy:user.deleted_by||"",
      deletedNote:user.deleted_note||"",accountStatusNote:user.account_status_note||"",accountStatusUpdatedAt:user.account_status_updated_at,
      accountStatusUpdatedBy:user.account_status_updated_by||"",walletBalance:Number(user.wallet_balance||0)
    },history:{
      verification:(verification.results||[]).map(v=>({id:v.id,legalName:v.legal_name,country:v.country,applicantType:v.applicant_type,status:v.status,reviewNote:v.review_note||"",submittedAt:v.submitted_at,reviewedAt:v.reviewed_at,reviewedBy:v.reviewed_by||""})),
      orders:(orders.results||[]).map(o=>({id:o.id,serviceKey:o.service_key,modelKey:o.model_key,deviceModel:o.device_model,maskedIdentifier:o.masked_identifier,amountDue:Number(o.amount_due),status:o.status,providerReference:o.provider_reference||"",adminNote:o.admin_note||"",createdAt:o.created_at,updatedAt:o.updated_at})),
      topups:(topups.results||[]).map(t=>({id:t.id,amount:Number(t.amount),requestReference:t.request_reference,providerReference:t.provider_reference||"",status:t.status,createdAt:t.created_at,submittedAt:t.submitted_at,reviewedAt:t.reviewed_at,reviewNote:t.review_note||""})),
      walletTransactions:(transactions.results||[]).map(t=>({id:t.id,kind:t.kind,amount:Number(t.amount),balanceAfter:Number(t.balance_after),reference:t.reference,description:t.description,createdAt:t.created_at,createdBy:t.created_by||""})),
      supportTickets:(tickets.results||[]).map(t=>({id:t.id,subject:t.subject,status:t.status,createdAt:t.created_at,updatedAt:t.updated_at}))
    }},200,headers);
  }catch(error){throwOrReturn(error,headers);}
}
async function updateAdminUserProfile(request,env,headers,id){
  try{
    const admin=await requireAdmin(request,env),body=await readJson(request);
    const fullName=typeof body.fullName==="string"?body.fullName.trim():"",email=typeof body.email==="string"?body.email.trim().toLowerCase():"";
    if(fullName.length<2||fullName.length>120)throw new ApiError(400,"INVALID_NAME","Enter a name between 2 and 120 characters.");
    if(!validEmail(email))throw new ApiError(400,"INVALID_EMAIL","Enter a valid email address.");
    const target=await env.DB.prepare("SELECT id,email,deleted_at FROM users WHERE id=?").bind(id).first();
    if(!target)throw new ApiError(404,"USER_NOT_FOUND","That member account could not be found.");
    if(isAdminEmail(target.email,env)&&email!==target.email.toLowerCase())throw new ApiError(403,"ADMIN_ACCOUNT_PROTECTED","The configured administrator email cannot be changed from member management.");
    if(email!==target.email.toLowerCase()&&isAdminEmail(email,env))throw new ApiError(409,"EMAIL_ALREADY_IN_USE","That email is reserved for an administrator account.");
    const changedEmail=email!==target.email.toLowerCase(),now=Math.floor(Date.now()/1000);
    if(changedEmail){
      if(!env.RESEND_API_KEY||!env.FROM_EMAIL)throw new ApiError(503,"EMAIL_NOT_CONFIGURED","Email delivery must be configured before changing a member's email address.");
      const code=await makeEmailCode(env,id,"verify_email");
      try{
        await sendEmail(env,email,"Verify your new 414Unlock email address",
          "<div style='font-family:Arial,sans-serif;max-width:520px;margin:auto;color:#0d1337'><h2>Verify your 414Unlock email</h2><p>Hello "+htmlEscape(fullName)+",</p><p>Your account email was changed by an administrator. Enter this code on the sign-in verification screen.</p><p style='font-size:30px;font-weight:700;letter-spacing:8px'>"+code+"</p></div>");
      }catch(error){await env.DB.prepare("DELETE FROM email_codes WHERE user_id=? AND purpose='verify_email'").bind(id).run();throw error;}
    }
    const update=await env.DB.prepare(
      "UPDATE users SET full_name=?,email=?,email_verified=CASE WHEN lower(email)<>? THEN 0 ELSE email_verified END,auth_version=auth_version+CASE WHEN lower(email)<>? THEN 1 ELSE 0 END WHERE id=?"
    ).bind(fullName,email,email,email,id).run();
    if(!update.meta||update.meta.changes!==1)throw new ApiError(409,"PROFILE_UPDATE_CONFLICT","The member profile could not be updated.");
    if(changedEmail)await env.DB.prepare("DELETE FROM email_codes WHERE user_id=? AND purpose='verify_email' AND created_at<> (SELECT MAX(created_at) FROM email_codes WHERE user_id=? AND purpose='verify_email')").bind(id,id).run();
    await env.DB.prepare("INSERT INTO admin_audit_log (id,actor_email,action,target_user_id,details,created_at) VALUES (?,?,?,?,?,?)").bind(randomHex(16),admin.email,"user_profile_updated",id,"email_changed="+changedEmail+"; name_updated=true",now).run();
    return json({ok:true,message:changedEmail?"Profile updated. A verification code was sent to the new email address.":"Member profile updated.",emailChanged:changedEmail},200,headers);
  }catch(error){
    if(String(error&&error.message||"").toLowerCase().includes("unique"))throw new ApiError(409,"EMAIL_ALREADY_IN_USE","That email address is already used by another account.");
    throwOrReturn(error,headers);
  }
}
async function updateAdminUserStatus(request,env,headers,id){
  try{
    const admin=await requireAdmin(request,env),body=await readJson(request);
    if(typeof body.active!=="boolean")throw new ApiError(400,"INVALID_ACCOUNT_STATUS","Choose whether the account should be active or deactivated.");
    const target=await env.DB.prepare("SELECT id,email,account_active,deleted_at FROM users WHERE id=?").bind(id).first();
    if(!target)throw new ApiError(404,"USER_NOT_FOUND","That user account could not be found.");
    if(target.deleted_at)throw new ApiError(409,"ACCOUNT_DELETED","Restore this deleted account before changing its active status.");
    if(!body.active&&isAdminEmail(target.email,env))throw new ApiError(403,"ADMIN_ACCOUNT_PROTECTED","An administrator account cannot be deactivated from user management.");
    const note=typeof body.note==="string"?body.note.trim().slice(0,500):"",now=Math.floor(Date.now()/1000);
    const result=await env.DB.prepare("UPDATE users SET account_active=?,account_status_note=?,account_status_updated_at=?,account_status_updated_by=?,auth_version=auth_version+1 WHERE id=?").bind(body.active?1:0,note,now,admin.email,id).run();
    if(!result.meta||result.meta.changes!==1)throw new ApiError(409,"ACCOUNT_STATUS_CONFLICT","The account status could not be changed. Refresh and try again.");
    await env.DB.prepare("INSERT INTO admin_audit_log (id,actor_email,action,target_user_id,details,created_at) VALUES (?,?,?,?,?,?)").bind(randomHex(16),admin.email,body.active?"user_activated":"user_deactivated",id,note,now).run();
    return json({ok:true,user:{id:target.id,email:target.email,active:body.active},message:body.active?"User account activated.":"User account deactivated. All existing sessions have been revoked."},200,headers);
  }catch(error){throwOrReturn(error,headers);}
}
async function deleteAdminUser(request,env,headers,id){
  try{
    const admin=await requireAdmin(request,env),body=await readJson(request),note=typeof body.note==="string"?body.note.trim().slice(0,500):"Deleted by administrator";
    const target=await env.DB.prepare("SELECT id,email,deleted_at FROM users WHERE id=?").bind(id).first();
    if(!target)throw new ApiError(404,"USER_NOT_FOUND","That member account could not be found.");
    if(isAdminEmail(target.email,env))throw new ApiError(403,"ADMIN_ACCOUNT_PROTECTED","An administrator account cannot be deleted from member management.");
    if(target.deleted_at)throw new ApiError(409,"ACCOUNT_ALREADY_DELETED","This member account is already deleted.");
    const now=Math.floor(Date.now()/1000);
    await env.DB.batch([
      env.DB.prepare("UPDATE users SET deleted_at=?,deleted_by=?,deleted_note=?,account_active=0,auth_version=auth_version+1,account_status_note=?,account_status_updated_at=?,account_status_updated_by=? WHERE id=? AND deleted_at IS NULL").bind(now,admin.email,note,note,now,admin.email,id),
      env.DB.prepare("INSERT INTO admin_audit_log (id,actor_email,action,target_user_id,details,created_at) VALUES (?,?,?,?,?,?)").bind(randomHex(16),admin.email,"user_deleted",id,note,now)
    ]);
    return json({ok:true,message:"Member deleted from active use. Financial and service history is retained and the account can be restored."},200,headers);
  }catch(error){throwOrReturn(error,headers);}
}
async function restoreAdminUser(request,env,headers,id){
  try{
    const admin=await requireAdmin(request,env),body=await readJson(request);
    const target=await env.DB.prepare("SELECT id,email,deleted_at FROM users WHERE id=?").bind(id).first();
    if(!target)throw new ApiError(404,"USER_NOT_FOUND","That member account could not be found.");
    if(!target.deleted_at)throw new ApiError(409,"ACCOUNT_NOT_DELETED","This member account is not deleted.");
    const note=typeof body.note==="string"?body.note.trim().slice(0,500):"Restored by administrator",now=Math.floor(Date.now()/1000);
    await env.DB.batch([
      env.DB.prepare("UPDATE users SET deleted_at=NULL,deleted_by=NULL,deleted_note='',account_active=1,account_status_note=?,account_status_updated_at=?,account_status_updated_by=?,auth_version=auth_version+1 WHERE id=? AND deleted_at IS NOT NULL").bind(note,now,admin.email,id),
      env.DB.prepare("INSERT INTO admin_audit_log (id,actor_email,action,target_user_id,details,created_at) VALUES (?,?,?,?,?,?)").bind(randomHex(16),admin.email,"user_restored",id,note,now)
    ]);
    return json({ok:true,message:"Member account restored. The member can sign in again after any required email verification."},200,headers);
  }catch(error){throwOrReturn(error,headers);}
}
async function adjustAdminUserWallet(request,env,headers,id){
  try{
    const admin=await requireAdmin(request,env),body=await readJson(request),amount=Number(body.amount),reason=typeof body.reason==="string"?body.reason.trim().slice(0,250):"";
    if(!Number.isSafeInteger(amount)||amount===0||Math.abs(amount)>1000000)throw new ApiError(400,"INVALID_WALLET_ADJUSTMENT","Enter a whole-number adjustment between -1,000,000 and 1,000,000.");
    if(reason.length<3)throw new ApiError(400,"WALLET_REASON_REQUIRED","Enter a reason for the wallet adjustment.");
    const target=await env.DB.prepare("SELECT id,deleted_at FROM users WHERE id=?").bind(id).first();
    if(!target)throw new ApiError(404,"USER_NOT_FOUND","That member account could not be found.");
    if(target.deleted_at)throw new ApiError(409,"ACCOUNT_DELETED","Restore the member account before adjusting its wallet.");
    const now=Math.floor(Date.now()/1000),reference="admin-adjustment:"+randomHex(16),txId=randomHex(16),auditId=randomHex(16);
    await env.DB.prepare("INSERT OR IGNORE INTO wallets (user_id,balance,created_at,updated_at) VALUES (?,0,?,?)").bind(id,now,now).run();
    const results=await env.DB.batch([
      env.DB.prepare("UPDATE wallets SET balance=balance+?,updated_at=? WHERE user_id=? AND balance+?>=0 AND balance+?<=100000000").bind(amount,now,id,amount,amount),
      env.DB.prepare("INSERT INTO wallet_transactions (id,user_id,kind,amount,balance_after,reference,description,created_at,created_by) SELECT ?,user_id,'adjustment',?,balance,?,?,?,? FROM wallets WHERE user_id=? AND changes()=1").bind(txId,amount,reference,reason,now,admin.email,id),
      env.DB.prepare("INSERT INTO admin_audit_log (id,actor_email,action,target_user_id,details,created_at) SELECT ?,?,?,?, ?,? WHERE changes()=1").bind(auditId,admin.email,"wallet_adjustment",id,"amount="+amount+"; reason="+reason,now)
    ]);
    if(!results[0].meta||results[0].meta.changes!==1)throw new ApiError(409,"WALLET_BALANCE_LIMIT","The adjustment would make the wallet negative or exceed the permitted balance.");
    const wallet=await env.DB.prepare("SELECT balance FROM wallets WHERE user_id=?").bind(id).first();
    return json({ok:true,balance:Number(wallet.balance),message:"Wallet adjustment saved to the transaction ledger."},200,headers);
  }catch(error){throwOrReturn(error,headers);}
}
async function createPasswordReset(env,user,admin){
  if(!env.RESEND_API_KEY||!env.FROM_EMAIL)throw new ApiError(503,"EMAIL_NOT_CONFIGURED","Password recovery email is not configured yet.");
  const token=randomHex(32),tokenHash=await keyedHash("password-reset:"+token,env),now=Math.floor(Date.now()/1000);
  await env.DB.prepare("DELETE FROM password_reset_tokens WHERE user_id=?").bind(user.id).run();
  await env.DB.prepare("INSERT INTO password_reset_tokens (id,user_id,token_hash,expires_at,used_at,used_by,created_at) VALUES (?,?,?, ?,NULL,NULL,?)").bind(randomHex(16),user.id,tokenHash,now+1800,now).run();
  const origin=(env.SITE_ORIGIN||"https://squashberry.github.io").split(",")[0].trim().replace(/\/+$/,"");
  const resetUrl=origin+"/414unlock-site/forgot.html?token="+encodeURIComponent(token);
  await sendEmail(env,user.email,"Reset your 414Unlock password","<div style='font-family:Arial,sans-serif;max-width:520px;margin:auto;color:#0d1337'><h2>Reset your 414Unlock password</h2><p>Hello "+htmlEscape(user.full_name)+",</p><p>Use the secure link below to choose a new password. It expires in 30 minutes and works once.</p><p><a href='"+htmlEscape(resetUrl)+"'>Reset my password</a></p><p>If you did not request this, ignore this email.</p></div>");
  if(admin)await env.DB.prepare("INSERT INTO admin_audit_log (id,actor_email,action,target_user_id,details,created_at) VALUES (?,?,?,?,?,?)").bind(randomHex(16),admin.email,"password_reset_sent",user.id,"A password reset link was sent.",now).run();
}
async function requestPasswordReset(request,env,headers){
  try{
    const body=await readJson(request),email=typeof body.email==="string"?body.email.trim().toLowerCase():"";
    if(validEmail(email)){
      const user=await env.DB.prepare("SELECT id,email,full_name,email_verified,account_active,deleted_at FROM users WHERE email=?").bind(email).first();
      if(user&&user.email_verified&&Number(user.account_active)===1&&!user.deleted_at){
        try{await createPasswordReset(env,user,null);}catch(error){console.error("414Unlock recovery email failed:",safeErrorCode(error));}
      }
    }
    return json({ok:true,message:"If an active, verified account exists for that email, a password reset link will be sent."},200,headers);
  }catch(error){throwOrReturn(error,headers);}
}
async function resetPassword(request,env,headers){
  try{
    const body=await readJson(request),token=typeof body.token==="string"?body.token.trim():"",password=typeof body.password==="string"?body.password:"";
    if(!/^[a-f0-9]{64}$/i.test(token)||password.length<10||password.length>128)throw new ApiError(400,"INVALID_RESET_REQUEST","The reset link or new password is invalid.");
    const tokenHash=await keyedHash("password-reset:"+token,env),now=Math.floor(Date.now()/1000);
    const row=await env.DB.prepare("SELECT id,user_id FROM password_reset_tokens WHERE token_hash=? AND used_at IS NULL AND expires_at>?").bind(tokenHash,now).first();
    if(!row)throw new ApiError(400,"RESET_LINK_EXPIRED","This password reset link has expired or has already been used. Request a new one.");
    const salt=randomHex(16),passwordHash=await createPasswordHash(password,salt),useId=randomHex(16);
    const results=await env.DB.batch([
      env.DB.prepare("UPDATE password_reset_tokens SET used_at=?,used_by=? WHERE id=? AND used_at IS NULL AND expires_at>?").bind(now,useId,row.id,now),
      env.DB.prepare("UPDATE users SET password_salt=?,password_hash=?,auth_version=auth_version+1 WHERE id=? AND deleted_at IS NULL AND EXISTS(SELECT 1 FROM password_reset_tokens WHERE id=? AND used_by=?)").bind(salt,passwordHash,row.user_id,row.id,useId),
      env.DB.prepare("DELETE FROM password_reset_tokens WHERE user_id=? AND id<>?").bind(row.user_id,row.id)
    ]);
    if(!results[0].meta||results[0].meta.changes!==1||!results[1].meta||results[1].meta.changes!==1)throw new ApiError(400,"RESET_LINK_EXPIRED","This password reset link is invalid or has already been used.");
    return json({ok:true,message:"Your password has been changed. Sign in with your new password."},200,headers);
  }catch(error){throwOrReturn(error,headers);}
}
async function sendAdminUserPasswordReset(request,env,headers,id){
  try{
    const admin=await requireAdmin(request,env);
    const user=await env.DB.prepare("SELECT id,email,full_name,email_verified,account_active,deleted_at FROM users WHERE id=?").bind(id).first();
    if(!user)throw new ApiError(404,"USER_NOT_FOUND","That member account could not be found.");
    if(!user.email_verified||Number(user.account_active)!==1||user.deleted_at)throw new ApiError(409,"ACCOUNT_NOT_READY","Activate and verify this member account before sending password recovery.");
    await createPasswordReset(env,user,admin);
    return json({ok:true,message:"A password reset link has been sent to the member's registered email."},200,headers);
  }catch(error){throwOrReturn(error,headers);}
}
async function bootstrapFirstAdmin(request,env,headers){
  try{
    const body=await readJson(request),email=typeof body.email==="string"?body.email.trim().toLowerCase():"",fullName=typeof body.fullName==="string"?body.fullName.trim():"",password=typeof body.password==="string"?body.password:"",token=typeof body.token==="string"?body.token.trim():"";
    if(!validEmail(email)||!isAdminEmail(email,env))throw new ApiError(403,"ADMIN_BOOTSTRAP_EMAIL","Use the administrator email configured for this service.");
    if(fullName.length<2||fullName.length>120||password.length<12||password.length>128||!/^[a-f0-9]{64}$/i.test(token))throw new ApiError(400,"INVALID_BOOTSTRAP_DETAILS","Enter your name, the private setup token, and a password of at least 12 characters.");
    const userCount=await env.DB.prepare("SELECT COUNT(*) AS count FROM users").first();
    if(Number(userCount&&userCount.count)!==0)throw new ApiError(409,"ADMIN_ALREADY_INITIALISED","The initial administrator has already been created. Sign in instead.");
    const tokenHash=await sha256Hex("414unlock-admin-bootstrap:"+token),now=Math.floor(Date.now()/1000);
    const bootstrap=await env.DB.prepare("SELECT id FROM admin_bootstrap_tokens WHERE token_hash=? AND used_at IS NULL AND expires_at>?").bind(tokenHash,now).first();
    if(!bootstrap)throw new ApiError(403,"INVALID_BOOTSTRAP_TOKEN","The private setup link is invalid or expired. Request a new setup link.");
    const id=randomHex(16),salt=randomHex(16),passwordHash=await createPasswordHash(password,salt);
    const results=await env.DB.batch([
      env.DB.prepare("INSERT INTO users (id,full_name,email,password_salt,password_hash,email_verified,created_at,account_active) SELECT ?,?,?,?,?,1,?,1 WHERE NOT EXISTS(SELECT 1 FROM users) AND EXISTS(SELECT 1 FROM admin_bootstrap_tokens WHERE id=? AND used_at IS NULL AND expires_at>?)").bind(id,fullName,email,salt,passwordHash,now,bootstrap.id,now),
      env.DB.prepare("INSERT OR IGNORE INTO wallets (user_id,balance,created_at,updated_at) SELECT id,0,?,? FROM users WHERE id=?").bind(now,now,id),
      env.DB.prepare("UPDATE admin_bootstrap_tokens SET used_at=? WHERE id=? AND used_at IS NULL AND EXISTS(SELECT 1 FROM users WHERE id=?)").bind(now,bootstrap.id,id),
      env.DB.prepare("INSERT INTO admin_audit_log (id,actor_email,action,target_user_id,details,created_at) SELECT ?,?,?,?, ?,? WHERE EXISTS(SELECT 1 FROM users WHERE id=?)").bind(randomHex(16),email,"admin_bootstrap",id,"Initial administrator account created.",now,id)
    ]);
    if(!results[0].meta||results[0].meta.changes!==1)throw new ApiError(409,"ADMIN_ALREADY_INITIALISED","The initial administrator has already been created. Sign in instead.");
    const user=await env.DB.prepare("SELECT id,full_name,email,email_verified,account_active,auth_version FROM users WHERE id=?").bind(id).first();
    return json({ok:true,token:await issueToken(user,env),user:publicUser(user),message:"Administrator account created. Keep your password safe and delete this setup link."},201,headers);
  }catch(error){throwOrReturn(error,headers);}
}

async function adminQueue(request, env, headers) {
  try {
    const admin = await requireAdmin(request, env);
    const topups = await env.DB.prepare(
      "SELECT t.id,t.user_id,t.amount,t.request_reference,t.provider_reference,t.status,t.created_at,t.submitted_at,u.full_name,u.email FROM topup_requests t JOIN users u ON u.id=t.user_id WHERE t.status='pending' ORDER BY t.submitted_at ASC LIMIT 100"
    ).all();
    const orders = await env.DB.prepare(
      "SELECT o.*,u.full_name,u.email FROM service_orders o JOIN users u ON u.id=o.user_id WHERE o.status IN ('submitted','registered','processing') ORDER BY CASE o.status WHEN 'submitted' THEN 0 WHEN 'registered' THEN 1 ELSE 2 END,o.created_at ASC LIMIT 100"
    ).all();
    const safeOrders = [];
    for (const o of (orders.results || [])) {
      safeOrders.push({
        id: o.id, userId: o.user_id, fullName: o.full_name, email: o.email,
        serviceKey: o.service_key, serviceName: walletServiceName(o.service_key),
        modelKey: o.model_key, modelName: WALLET_MODEL_NAMES[o.model_key] || o.model_key,
        deviceModel: o.device_model, identifierKind: o.identifier_kind,
        identifier: await decryptDeviceIdentifier(o.identifier_ciphertext, env),
        maskedIdentifier: o.masked_identifier, issueDescription: o.issue_description,
        fastService: Boolean(o.fast_service), amountDue: Number(o.amount_due), status: o.status,
        ownershipConfirmed: Boolean(o.ownership_confirmed), noSignalConfirmed: Boolean(o.no_signal_confirmed),
        checkCreditApplied: Boolean(o.check_credit_order_id), providerReference: o.provider_reference || "",
        adminNote: o.admin_note || "", createdAt: o.created_at, updatedAt: o.updated_at,
        processedAt: o.processed_at, completedAt: o.completed_at
      });
    }
    return json({
      ok: true,
      adminEmail: admin.email,
      topups: (topups.results || []).map((t) => ({
        id: t.id, userId: t.user_id, fullName: t.full_name, email: t.email, amount: Number(t.amount),
        requestReference: t.request_reference, providerReference: t.provider_reference || "",
        status: t.status, createdAt: t.created_at, submittedAt: t.submitted_at
      })),
      orders: safeOrders
    }, 200, headers);
  } catch (error) { throwOrReturn(error, headers); }
}

async function reviewTopup(request, env, headers, id) {
  try {
    const admin = await requireAdmin(request, env), body = await readJson(request);
    const decision = typeof body.decision === "string" ? body.decision : "";
    const note = typeof body.note === "string" ? body.note.trim().slice(0, 500) : "";
    if (!["approve", "reject"].includes(decision)) throw new ApiError(400, "INVALID_DECISION", "Choose approve or reject.");
    const current = await env.DB.prepare("SELECT id,provider_reference,status FROM topup_requests WHERE id=?").bind(id).first();
    if (!current || current.status !== "pending") throw new ApiError(409, "TOPUP_NOT_PENDING", "This top-up is no longer waiting for review.");
    if (decision === "approve" && !current.provider_reference) throw new ApiError(400, "PAYMENT_REFERENCE_REQUIRED", "A SquashberryPay transaction reference is required before approval.");
    const now = Math.floor(Date.now() / 1000), status = decision === "approve" ? "approved" : "rejected";
    const result = await env.DB.prepare(
      "UPDATE topup_requests SET status=?,reviewed_by=?,reviewed_at=?,review_note=? WHERE id=? AND status='pending'"
    ).bind(status, admin.email, now, note, id).run();
    if (!result.meta || result.meta.changes !== 1) throw new ApiError(409, "TOPUP_REVIEW_CONFLICT", "This top-up was handled by another administrator.");
    return json({ ok: true, status, credited: decision === "approve", message: decision === "approve" ? "Payment approved and wallet credited once." : "Top-up rejected; no credit was added." }, 200, headers);
  } catch (error) {
    if (String(error && error.message || "").toLowerCase().includes("unique")) throw new ApiError(409, "PAYMENT_REFERENCE_ALREADY_USED", "That SquashberryPay transaction reference is already assigned to another top-up.");
    throwOrReturn(error, headers);
  }
}

async function updateServiceOrderStatus(request, env, headers, id) {
  try {
    const admin = await requireAdmin(request, env), body = await readJson(request);
    const nextStatus = typeof body.status === "string" ? body.status.trim() : "";
    const note = typeof body.note === "string" ? body.note.trim().slice(0, 1000) : "";
    const providerReference = typeof body.providerReference === "string" ? body.providerReference.trim().slice(0, 150) : "";
    const current = await env.DB.prepare("SELECT id,status,amount_due FROM service_orders WHERE id=?").bind(id).first();
    if (!current) throw new ApiError(404, "SERVICE_ORDER_NOT_FOUND", "The service request could not be found.");
    const transitions = {
      submitted: ["registered", "rejected"],
      registered: ["processing", "rejected"],
      processing: ["completed", "rejected"],
      completed: [],
      rejected: []
    };
    if (!(transitions[current.status] || []).includes(nextStatus)) {
      throw new ApiError(409, "INVALID_ORDER_TRANSITION", "This status change is not allowed from the current order state.");
    }
    const now = Math.floor(Date.now() / 1000);
    const result = await env.DB.prepare(
      "UPDATE service_orders SET status=?,provider_reference=CASE WHEN ?<>'' THEN ? ELSE provider_reference END,admin_note=CASE WHEN ?<>'' THEN ? ELSE admin_note END,reviewed_by=?,updated_at=?,processed_at=CASE WHEN ?='processing' THEN COALESCE(processed_at,?) ELSE processed_at END,completed_at=CASE WHEN ?='completed' THEN ? ELSE completed_at END WHERE id=? AND status=?"
    ).bind(nextStatus, providerReference, providerReference, note, note, admin.email, now, nextStatus, now, nextStatus, now, id, current.status).run();
    if (!result.meta || result.meta.changes !== 1) throw new ApiError(409, "ORDER_UPDATE_CONFLICT", "The order changed while you were updating it. Refresh the queue.");
    const refunded = nextStatus === "rejected" && ["submitted", "registered"].includes(current.status);
    return json({
      ok: true, status: nextStatus, refunded,
      message: refunded ? "Request rejected before processing. Its service charge has been returned to the customer's wallet." :
        nextStatus === "rejected" ? "Request rejected after processing had started; no automatic refund was applied." : "Service request status updated."
    }, 200, headers);
  } catch (error) { throwOrReturn(error, headers); }
}

async function createPaymentSession(request, env, headers) {
  try {
    const user = await readToken(request, env);
    const body = await readJson(request);
    const deviceModel = typeof body.deviceModel === "string" ? body.deviceModel.trim().slice(0, 120) : "";
    const identifierKind = typeof body.identifierKind === "string" ? body.identifierKind.trim().toLowerCase() : "";
    const rawIdentifier = typeof body.identifier === "string" ? body.identifier.trim() : "";
    const identifier = rawIdentifier.replace(/[^a-zA-Z0-9]/g, "").toUpperCase();
    if (deviceModel.length < 2) throw new ApiError(400, "INVALID_DEVICE_MODEL", "A recognized device model is required.");
    if (!["serial", "imei", "udid"].includes(identifierKind)) throw new ApiError(400, "INVALID_IDENTIFIER_KIND", "Supply a supported device identifier type.");
    if (identifierKind === "imei" && !/^\d{14,16}$/.test(identifier)) throw new ApiError(400, "INVALID_DEVICE_IDENTIFIER", "The detected IMEI format is invalid.");
    if (identifierKind === "serial" && !/^[A-Z0-9]{6,64}$/.test(identifier)) throw new ApiError(400, "INVALID_DEVICE_IDENTIFIER", "The detected serial number format is invalid.");
    if (identifierKind === "udid" && !/^[A-Z0-9]{20,64}$/.test(identifier)) throw new ApiError(400, "INVALID_DEVICE_IDENTIFIER", "The detected UDID format is invalid.");
    const approved = await env.DB.prepare("SELECT id FROM verification_submissions WHERE user_id = ? AND status = 'approved' ORDER BY submitted_at DESC LIMIT 1").bind(user.id).first();
    if (!approved) throw new ApiError(403, "VERIFICATION_REQUIRED", "Complete account verification before creating a payment session.");
    const now = Math.floor(Date.now() / 1000);
    const id = randomHex(16);
    const launchToken = randomHex(24);
    const launchTokenHash = await keyedHash("payment-launch:" + launchToken, env);
    const identifierFingerprint = await keyedHash("device:" + identifierKind + ":" + identifier, env);
    const paymentReference = "414U-" + randomHex(8).toUpperCase();
    const expiresAt = now + 1800;
    const maskedIdentifier = "•••• •••• " + identifier.slice(-4);
    await env.DB.prepare("INSERT INTO payment_sessions (id,user_id,launch_token_hash,device_model,identifier_kind,identifier_fingerprint,masked_identifier,payment_reference,status,created_at,expires_at) VALUES (?,?,?,?,?,?,?,?,'pending',?,?)")
      .bind(id, user.id, launchTokenHash, deviceModel, identifierKind, identifierFingerprint, maskedIdentifier, paymentReference, now, expiresAt).run();
    return json({ ok: true, sessionId: id, launchToken, paymentReference, deviceModel, identifierKind, maskedIdentifier, status: "pending", expiresAt }, 201, headers);
  } catch (error) { throwOrReturn(error, headers); }
}

async function findPaymentSessionByLaunch(request, env, launchToken) {
  const user = await readToken(request, env);
  if (typeof launchToken !== "string" || !/^[a-f0-9]{48}$/.test(launchToken)) throw new ApiError(400, "INVALID_PAYMENT_SESSION", "The payment session is invalid. Start again from 414Unlock.");
  const tokenHash = await keyedHash("payment-launch:" + launchToken, env);
  const row = await env.DB.prepare("SELECT id,user_id,launch_token_hash,device_model,identifier_kind,masked_identifier,payment_reference,status,created_at,expires_at,paid_at,provider_reference FROM payment_sessions WHERE launch_token_hash = ? AND user_id = ?").bind(tokenHash, user.id).first();
  if (!row) throw new ApiError(404, "PAYMENT_SESSION_NOT_FOUND", "This payment session does not belong to the signed-in account.");
  const now = Math.floor(Date.now() / 1000);
  if (row.expires_at <= now && row.status === "pending") {
    await env.DB.prepare("UPDATE payment_sessions SET status='expired' WHERE id=? AND status='pending'").bind(row.id).run();
    row.status = "expired";
  }
  return { user, row };
}

async function getPaymentSession(request, env, headers, url) {
  try {
    const { row } = await findPaymentSessionByLaunch(request, env, url.searchParams.get("launch"));
    return json({ ok: true, sessionId: row.id, paymentReference: row.payment_reference, deviceModel: row.device_model, identifierKind: row.identifier_kind, maskedIdentifier: row.masked_identifier, status: row.status, expiresAt: row.expires_at, paidAt: row.paid_at }, 200, headers);
  } catch (error) { throwOrReturn(error, headers); }
}

async function getPaymentStatus(request, env, headers, url) {
  try {
    const user = await readToken(request, env);
    const sessionId = url.searchParams.get("sessionId") || "";
    if (!/^[a-f0-9]{32}$/.test(sessionId)) throw new ApiError(400, "INVALID_PAYMENT_SESSION", "The payment session reference is invalid.");
    const row = await env.DB.prepare("SELECT id,user_id,device_model,identifier_kind,masked_identifier,payment_reference,status,expires_at,paid_at FROM payment_sessions WHERE id=? AND user_id=?").bind(sessionId, user.id).first();
    if (!row) throw new ApiError(404, "PAYMENT_SESSION_NOT_FOUND", "The payment session was not found for this account.");
    const now = Math.floor(Date.now() / 1000);
    if (row.expires_at <= now && row.status === "pending") {
      await env.DB.prepare("UPDATE payment_sessions SET status='expired' WHERE id=? AND status='pending'").bind(row.id).run();
      row.status = "expired";
    }
    return json({ ok: true, sessionId: row.id, status: row.status, verified: row.status === "verified", paymentReference: row.payment_reference, deviceModel: row.device_model, identifierKind: row.identifier_kind, maskedIdentifier: row.masked_identifier, expiresAt: row.expires_at, paidAt: row.paid_at }, 200, headers);
  } catch (error) { throwOrReturn(error, headers); }
}


async function validatePaymentDevice(request, env, headers) {
  try {
    const user = await readToken(request, env);
    const body = await readJson(request);
    const sessionId = typeof body.sessionId === "string" ? body.sessionId.trim() : "";
    const identifierKind = typeof body.identifierKind === "string" ? body.identifierKind.trim().toLowerCase() : "";
    const rawIdentifier = typeof body.identifier === "string" ? body.identifier.trim() : "";
    const identifier = rawIdentifier.replace(/[^a-zA-Z0-9]/g, "").toUpperCase();
    if (!/^[a-f0-9]{32}$/.test(sessionId)) throw new ApiError(400, "INVALID_PAYMENT_SESSION", "The payment session reference is invalid.");
    if (!["serial", "imei", "udid"].includes(identifierKind)) throw new ApiError(400, "INVALID_IDENTIFIER_KIND", "A supported device identifier type is required.");
    if (identifierKind === "imei" && !/^\d{14,16}$/.test(identifier)) throw new ApiError(400, "INVALID_DEVICE_IDENTIFIER", "The detected IMEI format is invalid.");
    if (identifierKind === "serial" && !/^[A-Z0-9]{6,64}$/.test(identifier)) throw new ApiError(400, "INVALID_DEVICE_IDENTIFIER", "The detected serial number format is invalid.");
    if (identifierKind === "udid" && !/^[A-Z0-9]{20,64}$/.test(identifier)) throw new ApiError(400, "INVALID_DEVICE_IDENTIFIER", "The detected UDID format is invalid.");
    const row = await env.DB.prepare("SELECT id,identifier_kind,identifier_fingerprint,device_model,status,payment_reference,masked_identifier FROM payment_sessions WHERE id=? AND user_id=?")
      .bind(sessionId, user.id).first();
    if (!row) throw new ApiError(404, "PAYMENT_SESSION_NOT_FOUND", "The payment session was not found for this account.");
    if (row.status !== "verified") throw new ApiError(409, "PAYMENT_NOT_VERIFIED", "The payment for this device session has not been verified.");
    const fingerprint = await keyedHash("device:" + identifierKind + ":" + identifier, env);
    if (identifierKind !== row.identifier_kind || !constantTimeEqual(fingerprint, row.identifier_fingerprint)) {
      throw new ApiError(403, "DEVICE_MISMATCH", "The payment is not linked to the currently connected device. Reconnect the original device or start a new session.");
    }
    return json({ ok: true, authorized: true, status: "verified", sessionId: row.id, paymentReference: row.payment_reference, deviceModel: row.device_model, identifierKind: row.identifier_kind, maskedIdentifier: row.masked_identifier }, 200, headers);
  } catch (error) { throwOrReturn(error, headers); }
}

async function verifyPaymentCode(request, env, headers) {
  try {
    const body = await readJson(request);
    const code = typeof body.confirmationCode === "string" ? body.confirmationCode.trim() : "";
    if (code.length < 3 || code.length > 100) throw new ApiError(400, "INVALID_PAYMENT_CODE", "Enter the confirmation code SquashberryPay sent you.");
    const { user, row } = await findPaymentSessionByLaunch(request, env, body.launchToken);
    if (row.status === "verified") return json({ ok: true, verified: true, status: "verified", sessionId: row.id, paymentReference: row.payment_reference }, 200, headers);
    if (row.status === "expired") throw new ApiError(410, "PAYMENT_SESSION_EXPIRED", "This payment session has expired. Start a new session from 414Unlock.");
    const urlValue = env.SQUASHBERRYPAY_VERIFY_URL || "";
    const apiKey = env.SQUASHBERRYPAY_API_KEY || "";
    if (!urlValue || !apiKey) throw new ApiError(503, "PAYMENT_PROVIDER_NOT_CONFIGURED", "SquashberryPay code verification is not connected yet. No payment has been marked as verified.");
    let verifyUrl;
    try { verifyUrl = new URL(urlValue); } catch (_) { throw new ApiError(503, "PAYMENT_PROVIDER_NOT_CONFIGURED", "The SquashberryPay verification endpoint is not configured correctly."); }
    if (verifyUrl.protocol !== "https:") throw new ApiError(503, "PAYMENT_PROVIDER_NOT_CONFIGURED", "The SquashberryPay verification endpoint must use HTTPS.");
    const now = Math.floor(Date.now() / 1000);
    const attemptWindow = await env.DB.prepare("SELECT COUNT(*) AS total FROM payment_code_attempts WHERE payment_session_id=? AND attempted_at>?").bind(row.id, now - 900).first();
    if (Number(attemptWindow && attemptWindow.total || 0) >= 8) throw new ApiError(429, "TOO_MANY_PAYMENT_ATTEMPTS", "Too many attempts. Start a new session or contact support.");
    let providerResponse;
    try {
      providerResponse = await fetch(verifyUrl.toString(), {
        method: "POST",
        headers: { "Authorization": "Bearer " + apiKey, "Content-Type": "application/json", "Accept": "application/json" },
        body: JSON.stringify({ confirmationCode: code, reference: row.payment_reference })
      });
    } catch (_) {
      throw new ApiError(502, "PAYMENT_PROVIDER_UNAVAILABLE", "SquashberryPay could not be reached. No payment was marked as verified.");
    }
    let providerData = {};
    try { providerData = await providerResponse.json(); } catch (_) {}
    if (!providerResponse.ok) {
      await env.DB.prepare("INSERT INTO payment_code_attempts (id,payment_session_id,attempted_at,succeeded) VALUES (?,?,?,0)").bind(randomHex(12), row.id, now).run();
      if (providerResponse.status === 400 || providerResponse.status === 401 || providerResponse.status === 404) throw new ApiError(400, "PAYMENT_NOT_CONFIRMED", "SquashberryPay did not confirm a paid transaction for this payment reference.");
      throw new ApiError(502, "PAYMENT_PROVIDER_UNAVAILABLE", "Payment verification is temporarily unavailable. No payment was marked as verified.");
    }
    const providerStatus = String(providerData.status || "").toLowerCase();
    const providerReference = String(providerData.transactionId || providerData.transaction_id || providerData.providerReference || "").slice(0, 160);
    if (providerData.verified !== true || providerStatus !== "paid" || providerData.reference !== row.payment_reference || !providerReference) {
      await env.DB.prepare("INSERT INTO payment_code_attempts (id,payment_session_id,attempted_at,succeeded) VALUES (?,?,?,0)").bind(randomHex(12), row.id, now).run();
      throw new ApiError(400, "PAYMENT_NOT_CONFIRMED", "SquashberryPay did not confirm a paid transaction for this exact device payment reference.");
    }
    const updated = await env.DB.prepare("UPDATE payment_sessions SET status='verified',provider_reference=?,paid_at=? WHERE id=? AND user_id=? AND status='pending' AND expires_at>?")
      .bind(providerReference, now, row.id, user.id, now).run();
    if (!updated.meta || updated.meta.changes !== 1) throw new ApiError(409, "PAYMENT_STATE_CHANGED", "The payment session changed while verifying. Refresh its status before continuing.");
    await env.DB.prepare("INSERT INTO payment_code_attempts (id,payment_session_id,attempted_at,succeeded) VALUES (?,?,?,1)").bind(randomHex(12), row.id, now).run();
    return json({ ok: true, verified: true, status: "verified", sessionId: row.id, paymentReference: row.payment_reference, verifiedAt: now }, 200, headers);
  } catch (error) { throwOrReturn(error, headers); }
}



async function checkDevicePayment(request, env, headers, url) {
  try {
    const user = await readToken(request, env);
    const identifierKind = String(url.searchParams.get("identifierKind") || "").trim().toLowerCase();
    const rawIdentifier = String(url.searchParams.get("identifier") || "").trim();
    const identifier = rawIdentifier.replace(/[^a-zA-Z0-9]/g, "").toUpperCase();
    if (!["serial", "imei", "udid"].includes(identifierKind)) {
      throw new ApiError(400, "INVALID_IDENTIFIER_KIND", "Supply a supported serial, IMEI, or UDID identifier type.");
    }
    if (identifierKind === "imei" && !/^\d{14,16}$/.test(identifier)) {
      throw new ApiError(400, "INVALID_DEVICE_IDENTIFIER", "The detected IMEI format is invalid.");
    }
    if (identifierKind === "serial" && !/^[A-Z0-9]{6,64}$/.test(identifier)) {
      throw new ApiError(400, "INVALID_DEVICE_IDENTIFIER", "The detected serial number format is invalid.");
    }
    if (identifierKind === "udid" && !/^[A-Z0-9]{20,64}$/.test(identifier)) {
      throw new ApiError(400, "INVALID_DEVICE_IDENTIFIER", "The detected UDID format is invalid.");
    }

    const fingerprint = await keyedHash("device:" + identifierKind + ":" + identifier, env);
    const binding = env.DB.prepare(
      "SELECT id,status,created_at FROM payment_sessions WHERE user_id=? AND identifier_kind=? AND identifier_fingerprint=? ORDER BY created_at DESC LIMIT 1"
    ).bind(user.id, identifierKind, fingerprint);
    const verifiedQuery = env.DB.prepare(
      "SELECT id,status,paid_at,device_model FROM payment_sessions WHERE user_id=? AND identifier_kind=? AND identifier_fingerprint=? AND status='verified' ORDER BY paid_at DESC LIMIT 1"
    ).bind(user.id, identifierKind, fingerprint);
    const [latest, verified] = await Promise.all([binding.first(), verifiedQuery.first()]);
    const paid = Boolean(verified);
    const deviceRegistered = Boolean(latest);
    return json({
      ok: true,
      paid,
      deviceRegistered,
      canRetry: paid,
      status: paid ? "verified" : (latest ? latest.status : "not_found"),
      message: paid
        ? "A verified payment exists for this device on your account. You can retry without paying again."
        : (latest
          ? "This device has a payment session, but no verified payment was found. Complete payment before retrying."
          : "No verified payment was found for this device on your account.")
    }, 200, headers);
  } catch (error) { throwOrReturn(error, headers); }
}

function normalizeIosVersion(value) {
  if (typeof value !== "string") return null;
  const input = value.trim();
  if (!/^\d{1,3}(?:\.\d{1,3}){1,3}$/.test(input)) return null;
  const parts = input.split(".").map((part) => Number(part));
  if (parts.some((part) => !Number.isInteger(part) || part < 0 || part > 999)) return null;
  return parts.map(String).join(".");
}

function iosVersionParts(value) {
  return value.split(".").map((part) => Number(part));
}

function compareIosVersions(left, right) {
  const a = iosVersionParts(left), b = iosVersionParts(right);
  const length = Math.max(a.length, b.length);
  for (let i = 0; i < length; i++) {
    const av = a[i] || 0, bv = b[i] || 0;
    if (av < bv) return -1;
    if (av > bv) return 1;
  }
  return 0;
}

function iosVersionScore(value) {
  const parts = iosVersionParts(value);
  while (parts.length < 4) parts.push(0);
  return (((parts[0] * 1000) + parts[1]) * 1000 + parts[2]) * 1000 + parts[3];
}

function publicIosSupportRule(row) {
  return {
    id: row.id,
    matchType: row.match_type,
    version: row.version || "",
    minVersion: row.min_version || "",
    maxVersion: row.max_version || "",
    enabled: Boolean(row.enabled),
    note: row.note || "",
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    updatedBy: row.updated_by || ""
  };
}

function resolveIosSupportRule(rows, version) {
  const exact = rows.filter((row) =>
    row.match_type === "exact" && compareIosVersions(row.version, version) === 0
  );
  if (exact.length) {
    exact.sort((a, b) => Number(b.updated_at || 0) - Number(a.updated_at || 0));
    return exact[0];
  }

  const ranges = rows.filter((row) =>
    row.match_type === "range" &&
    compareIosVersions(version, row.min_version) >= 0 &&
    compareIosVersions(version, row.max_version) <= 0
  );
  ranges.sort((a, b) => {
    const widthA = iosVersionScore(a.max_version) - iosVersionScore(a.min_version);
    const widthB = iosVersionScore(b.max_version) - iosVersionScore(b.min_version);
    if (widthA !== widthB) return widthA - widthB;
    if (Boolean(a.enabled) !== Boolean(b.enabled)) return Number(Boolean(a.enabled)) - Number(Boolean(b.enabled));
    return Number(b.updated_at || 0) - Number(a.updated_at || 0);
  });
  return ranges[0] || null;
}

async function checkIosCompatibility(env, headers, url) {
  try {
    const rawVersion = url.searchParams.get("iosVersion") || url.searchParams.get("version") || "";
    const version = normalizeIosVersion(rawVersion);
    if (!version) throw new ApiError(400, "INVALID_IOS_VERSION", "Supply a valid iOS version such as 18.7 or 18.7.1.");
    const result = await env.DB.prepare(
      "SELECT id,match_type,version,min_version,max_version,enabled,note,created_at,updated_at,updated_by FROM ios_support_rules ORDER BY updated_at DESC LIMIT 500"
    ).all();
    const rule = resolveIosSupportRule(result.results || [], version);
    const allowed = Boolean(rule && rule.enabled);
    return json({
      ok: true,
      iosVersion: version,
      allowed,
      supported: allowed,
      matched: Boolean(rule),
      rule: rule ? {
        id: rule.id,
        matchType: rule.match_type,
        version: rule.version || "",
        minVersion: rule.min_version || "",
        maxVersion: rule.max_version || "",
      } : null,
      code: allowed ? "IOS_VERSION_ALLOWED" : "IOS_VERSION_UNSUPPORTED",
      message: allowed ? "This iOS version is enabled by 414Unlock." : "This phone's iOS version isn't supported."
    }, 200, headers);
  } catch (error) { throwOrReturn(error, headers); }
}

async function listIosSupportRules(request, env, headers) {
  try {
    const admin = await requireAdmin(request, env);
    const result = await env.DB.prepare(
      "SELECT id,match_type,version,min_version,max_version,enabled,note,created_at,updated_at,updated_by FROM ios_support_rules ORDER BY updated_at DESC,created_at DESC LIMIT 500"
    ).all();
    return json({
      ok: true,
      adminEmail: admin.email,
      rules: (result.results || []).map(publicIosSupportRule)
    }, 200, headers);
  } catch (error) { throwOrReturn(error, headers); }
}

async function saveIosSupportRule(request, env, headers) {
  try {
    const admin = await requireAdmin(request, env);
    const body = await readJson(request);
    let id = typeof body.id === "string" ? body.id.trim().toLowerCase() : "";
    if (id && !/^[a-f0-9]{32}$/.test(id)) {
      throw new ApiError(400, "INVALID_RULE_ID", "The iOS support rule identifier is invalid.");
    }
    if (!id) id = randomHex(16);

    const matchType = typeof body.matchType === "string" ? body.matchType.trim().toLowerCase() : "";
    if (!["exact", "range"].includes(matchType)) {
      throw new ApiError(400, "INVALID_MATCH_TYPE", "Choose an exact iOS version or a version range.");
    }
    if (typeof body.enabled !== "boolean") {
      throw new ApiError(400, "INVALID_ENABLED_STATE", "Choose whether this version or range is allowed.");
    }
    const note = typeof body.note === "string" ? body.note.trim().slice(0, 250) : "";
    let version = null, minVersion = null, maxVersion = null;
    if (matchType === "exact") {
      version = normalizeIosVersion(String(body.version || ""));
      if (!version) throw new ApiError(400, "INVALID_IOS_VERSION", "Enter an exact version such as 18.7 or 18.7.1.");
    } else {
      minVersion = normalizeIosVersion(String(body.minVersion || ""));
      maxVersion = normalizeIosVersion(String(body.maxVersion || ""));
      if (!minVersion || !maxVersion) {
        throw new ApiError(400, "INVALID_IOS_RANGE", "Enter both the first and last iOS version in the range.");
      }
      if (compareIosVersions(minVersion, maxVersion) > 0) {
        throw new ApiError(400, "INVALID_IOS_RANGE", "The start version must be less than or equal to the end version.");
      }
    }

    const existing = await env.DB.prepare(
      "SELECT id FROM ios_support_rules WHERE id=?"
    ).bind(id).first();
    if (existing) {
      // Existing rules may be edited in place but not silently replaced by a different record.
    } else if (body.id) {
      throw new ApiError(404, "IOS_RULE_NOT_FOUND", "That iOS support rule no longer exists. Refresh the page and try again.");
    }

    const otherResult = await env.DB.prepare(
      "SELECT id,match_type,version,min_version,max_version FROM ios_support_rules WHERE id<>?"
    ).bind(id).all();
    for (const other of (otherResult.results || [])) {
      if (other.match_type !== matchType) continue;
      const duplicate = matchType === "exact"
        ? compareIosVersions(other.version, version) === 0
        : compareIosVersions(other.min_version, minVersion) === 0 && compareIosVersions(other.max_version, maxVersion) === 0;
      if (duplicate) {
        throw new ApiError(409, "IOS_RULE_ALREADY_EXISTS", "A rule for that exact version or range already exists. Edit its existing rule instead.");
      }
    }

    const now = Math.floor(Date.now() / 1000);
    if (existing) {
      await env.DB.prepare(
        "UPDATE ios_support_rules SET match_type=?,version=?,min_version=?,max_version=?,enabled=?,note=?,updated_at=?,updated_by=? WHERE id=?"
      ).bind(matchType, version, minVersion, maxVersion, body.enabled ? 1 : 0, note, now, admin.email, id).run();
    } else {
      await env.DB.prepare(
        "INSERT INTO ios_support_rules (id,match_type,version,min_version,max_version,enabled,note,created_at,updated_at,updated_by) VALUES (?,?,?,?,?,?,?,?,?,?)"
      ).bind(id, matchType, version, minVersion, maxVersion, body.enabled ? 1 : 0, note, now, now, admin.email).run();
    }
    const saved = await env.DB.prepare(
      "SELECT id,match_type,version,min_version,max_version,enabled,note,created_at,updated_at,updated_by FROM ios_support_rules WHERE id=?"
    ).bind(id).first();
    return json({
      ok: true,
      rule: publicIosSupportRule(saved),
      message: "iOS support rule saved. The desktop app will use the current server policy at its next check."
    }, existing ? 200 : 201, headers);
  } catch (error) { throwOrReturn(error, headers); }
}

function throwOrReturn(error, headers) {
  if (error instanceof ApiError) throw error;
  if (error instanceof Error) throw error;
  throw new ApiError(500, "INTERNAL_ERROR", "The request could not be completed.");
}

export { normalizeIosVersion, compareIosVersions, resolveIosSupportRule };
