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
      if (!env.DB || !env.DOCUMENTS) return json({ error: "SERVICE_NOT_CONFIGURED", message: "The account service is not fully configured." }, 503, headers);
      if (!env.JWT_SECRET || env.JWT_SECRET.length < 32) return json({ error: "SERVICE_NOT_CONFIGURED", message: "The account service is not fully configured." }, 503, headers);
      const path = new URL(request.url).pathname;
      if (request.method === "POST" && path === "/api/auth/signup") return await signup(request, env, headers);
      if (request.method === "POST" && path === "/api/auth/verify-email") return await verifyEmail(request, env, headers);
      if (request.method === "POST" && path === "/api/auth/login") return await login(request, env, headers);
      if (request.method === "GET" && path === "/api/auth/me") return await getMe(request, env, headers);
      if (request.method === "POST" && path === "/api/auth/app-code") return await createAppCode(request, env, headers);
      if (request.method === "POST" && path === "/api/auth/redeem-app-code") return await redeemAppCode(request, env, headers);
      if (request.method === "POST" && path === "/api/payments/session") return await createPaymentSession(request, env, headers);
      if (request.method === "GET" && path === "/api/payments/session") return await getPaymentSession(request, env, headers, new URL(request.url));
      if (request.method === "GET" && path === "/api/payments/status") return await getPaymentStatus(request, env, headers, new URL(request.url));
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
  const body = base64urlText(JSON.stringify({ sub: user.id, email: user.email, iat: now, exp: now + TOKEN_TTL_SECONDS, iss: "414unlock-auth" }));
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
  const user = await env.DB.prepare("SELECT id, full_name, email, email_verified, created_at FROM users WHERE id = ?").bind(claims.sub).first();
  if (!user || !user.email_verified) throw new ApiError(401, "INVALID_SESSION", "Your session is invalid. Sign in again.");
  return user;
}
function publicUser(user) { return { id: user.id, fullName: user.full_name, email: user.email, emailVerified: !!user.email_verified }; }
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
    const user = await env.DB.prepare("SELECT id,full_name,email,email_verified FROM users WHERE email = ?").bind(email).first();
    if (!user) throw new ApiError(400, "INVALID_CODE", "The code is invalid or expired.");
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
    const user = await env.DB.prepare("SELECT id,full_name,email,password_salt,password_hash,email_verified FROM users WHERE email = ?").bind(email).first();
    const passwordHash = await createPasswordHash(password, user ? user.password_salt : "00000000000000000000000000000000");
    if (!user || !constantTimeEqual(passwordHash, user.password_hash)) throw new ApiError(401, "INVALID_CREDENTIALS", "Email or password is incorrect.");
    if (!user.email_verified) throw new ApiError(403, "EMAIL_NOT_VERIFIED", "Verify your email before signing in.");
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
    const user = await env.DB.prepare("SELECT id,full_name,email,email_verified FROM users WHERE id = ?").bind(used.user_id).first();
    if (!user || !user.email_verified) throw new ApiError(401, "AUTH_REQUIRED", "Sign in again to continue.");
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
async function submitVerification(request, env, headers) {
  let documentKey = null;
  try {
    const user = await readToken(request, env), type = request.headers.get("Content-Type") || "";
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
    documentKey = "verification/" + user.id + "/" + id + "." + ext;
    await env.DOCUMENTS.put(documentKey, file.stream(), { httpMetadata: { contentType: file.type, cacheControl: "private, no-store" }, customMetadata: { userId: user.id, submissionId: id } });
    const originalName = String(file.name || "document").replace(/[^a-zA-Z0-9._ -]/g, "_").slice(0, 100);
    await env.DB.prepare("INSERT INTO verification_submissions (id,user_id,legal_name,country,applicant_type,document_key,document_name,document_type,status,terms_version,terms_accepted_at,submitted_at) VALUES (?,?,?,?,?,?,?,?, 'pending',?,?,?)")
      .bind(id, user.id, legalName, country, applicantType, documentKey, originalName, file.type, termsVersion, now, now).run();
    return json({ ok: true, status: "pending", submissionId: id, message: "Your application has been submitted for review." }, 201, headers);
  } catch (error) {
    if (documentKey) { try { await env.DOCUMENTS.delete(documentKey); } catch (_) {} }
    throwOrReturn(error, headers);
  }
}
async function requireAdmin(request, env) {
  const user = await readToken(request, env), allowed = (env.ADMIN_EMAILS || "").split(",").map((x) => x.trim().toLowerCase()).filter(Boolean);
  if (!allowed.includes(user.email.toLowerCase())) throw new ApiError(403, "ADMIN_REQUIRED", "Administrator access is required.");
  return user;
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
    const row = await env.DB.prepare("SELECT document_key,document_type,status FROM verification_submissions WHERE id = ?").bind(id).first();
    if (!row || !row.document_key || row.status !== "pending") throw new ApiError(404, "DOCUMENT_NOT_AVAILABLE", "This document is not available for review.");
    const object = await env.DOCUMENTS.get(row.document_key);
    if (!object) throw new ApiError(404, "DOCUMENT_NOT_AVAILABLE", "This document is no longer available.");
    return new Response(object.body, { status: 200, headers: { ...headers, "Content-Type": row.document_type, "Content-Disposition": "inline; filename=\"verification-document\"", "X-Content-Type-Options": "nosniff", "Cache-Control": "private, no-store" } });
  } catch (error) { throwOrReturn(error, headers); }
}
async function reviewSubmission(request, env, headers, id) {
  try {
    const admin = await requireAdmin(request, env), body = await readJson(request);
    const decision = String(body.decision || ""), note = typeof body.note === "string" ? body.note.trim().slice(0, 500) : "";
    if (!["approve", "reject"].includes(decision)) throw new ApiError(400, "INVALID_DECISION", "Choose approve or reject.");
    const row = await env.DB.prepare("SELECT id,document_key,status FROM verification_submissions WHERE id = ?").bind(id).first();
    if (!row || row.status !== "pending") throw new ApiError(404, "APPLICATION_NOT_PENDING", "This application is no longer pending.");
    const now = Math.floor(Date.now() / 1000), status = decision === "approve" ? "approved" : "rejected";
    const result = await env.DB.prepare("UPDATE verification_submissions SET status=?,review_note=?,reviewed_at=?,reviewed_by=? WHERE id=? AND status='pending'").bind(status, note, now, admin.email, id).run();
    if (!result.meta || result.meta.changes !== 1) throw new ApiError(409, "REVIEW_CONFLICT", "Another reviewer already handled this application.");
    if (row.document_key) {
      await env.DOCUMENTS.delete(row.document_key);
      await env.DB.prepare("UPDATE verification_submissions SET document_key=NULL WHERE id=?").bind(id).run();
    }
    return json({ ok: true, status, message: "Application " + status + ". Uploaded document deleted after review." }, 200, headers);
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

function throwOrReturn(error, headers) {
  if (error instanceof ApiError) throw error;
  if (error instanceof Error) throw error;
  throw new ApiError(500, "INTERNAL_ERROR", "The request could not be completed.");
}