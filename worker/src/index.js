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
function throwOrReturn(error, headers) {
  if (error instanceof ApiError) throw error;
  if (error instanceof Error) throw error;
  throw new ApiError(500, "INTERNAL_ERROR", "The request could not be completed.");
}