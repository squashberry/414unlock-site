/* Public site configuration only. Never put secrets in this file. */
window.UNLOCK414_CONFIG = Object.freeze({
  API_BASE_URL: "https://414unlock-auth-api.414unlock.workers.dev",
  DOWNLOAD_URL: "https://github.com/squashberry/414unlock-site/releases/latest",
  APP_CALLBACK: "414unlock://auth/callback",
  SQUASHBERRYPAY_CHECKOUT_URL: "",
  SQUASHBERRYPAY_TOPUP_URL: "",
  SQUASHBERRYPAY_REFERENCE_PARAM: "reference",
  TERMS_VERSION: "2026-10-30",
  SUPPORT_EMAIL: "414unlock@gmail.com"
});
(function () {
  "use strict";
  function adaptNavigation() {
    var token = "";
    try { token = localStorage.getItem("414unlock_token") || sessionStorage.getItem("414unlock_token") || ""; } catch (_) {}
    if (!token) return;
    document.querySelectorAll('a.brand[href="index.html"],a[aria-label="414Unlock home"][href="index.html"],a.back[href="index.html"]').forEach(function (a) { a.href = "dashboard.html"; a.setAttribute("aria-label", "414Unlock dashboard"); });
    document.querySelectorAll('nav a[href="index.html"]').forEach(function (a) { if (/^\s*home\s*$/i.test(a.textContent)) { a.href = "dashboard.html"; a.textContent = "Dashboard"; } });
    var nav = document.querySelector(".nav");
    if (nav) {
      var signIn = nav.querySelector('a[href^="account.html?flow=signin"]');
      if (signIn) { signIn.href = "dashboard.html"; signIn.textContent = "Dashboard"; }
      var signUp = nav.querySelector('a[href^="account.html?flow=signup"]');
      if (signUp) signUp.hidden = true;
    }
  }
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", adaptNavigation);
  else adaptNavigation();
})();
