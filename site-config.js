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

  var TOKEN_KEY = "414unlock_token";
  var FLOW_KEY = "414unlock_flow";
  var config = window.UNLOCK414_CONFIG || {};
  var api = String(config.API_BASE_URL || "");
  while (api.endsWith("/")) api = api.slice(0, -1);
  var token = readToken();

  function store(name) {
    try { return window[name]; } catch (_) { return null; }
  }
  function safeGet(target, key) {
    try { return target ? (target.getItem(key) || "") : ""; } catch (_) { return ""; }
  }
  function safeRemove(target, key) {
    try { if (target) target.removeItem(key); } catch (_) {}
  }
  function readToken() {
    try {
      if (window.UNLOCK414_SESSION && typeof window.UNLOCK414_SESSION.getToken === "function") {
        var shared = window.UNLOCK414_SESSION.getToken();
        if (shared) return shared;
      }
    } catch (_) {}
    return safeGet(store("localStorage"), TOKEN_KEY) || safeGet(store("sessionStorage"), TOKEN_KEY);
  }
  function clearSession() {
    try {
      if (window.UNLOCK414_SESSION && typeof window.UNLOCK414_SESSION.clear === "function") {
        window.UNLOCK414_SESSION.clear();
        return;
      }
    } catch (_) {}
    [store("localStorage"), store("sessionStorage")].forEach(function (target) {
      safeRemove(target, TOKEN_KEY);
      safeRemove(target, FLOW_KEY);
    });
  }
  function pageFile() {
    var path = String(window.location.pathname || "").split("/").pop().toLowerCase();
    return path || "index.html";
  }
  function isAccountPage() {
    return pageFile() === "account.html";
  }
  function addPendingStyle() {
    if (!document.documentElement) return;
    document.documentElement.classList.add("u414-auth-pending");
    var style = document.createElement("style");
    style.textContent = "html.u414-auth-pending nav[aria-label='Main navigation'],html.u414-auth-pending nav.nav{visibility:hidden}";
    (document.head || document.documentElement).appendChild(style);
  }
  function isHomeLink(anchor) {
    var href = String(anchor.getAttribute("href") || "").split("?")[0].split("#")[0].toLowerCase();
    return href === "index.html" || href.endsWith("/index.html");
  }
  function isAccountAction(anchor) {
    var href = String(anchor.getAttribute("href") || "").toLowerCase();
    var label = String(anchor.textContent || "").trim().toLowerCase();
    var labels = ["dashboard", "my wallet", "sign in", "create account", "sign out", "sign out / switch account"];
    return href.indexOf("account.html") >= 0 || href === "dashboard.html" || labels.indexOf(label) >= 0;
  }
  function makeLink(text, href, className) {
    var anchor = document.createElement("a");
    anchor.textContent = text;
    anchor.href = href;
    if (className) anchor.className = className;
    return anchor;
  }
  function bindSignOut(anchor) {
    anchor.id = "logout-link";
    anchor.href = "account.html?flow=signin";
    anchor.setAttribute("data-auth-action", "signout");
    anchor.setAttribute("aria-label", "Sign out of 414Unlock");
    anchor.addEventListener("click", function (event) {
      event.preventDefault();
      clearSession();
      window.location.assign("account.html?flow=signin");
    });
  }
  function normalizeMainNavigation(signedIn) {
    var navs = document.querySelectorAll('nav[aria-label="Main navigation"],nav.nav');
    Array.prototype.forEach.call(navs, function (nav) {
      var anchors = Array.prototype.filter.call(nav.children, function (child) {
        return child && child.tagName && child.tagName.toLowerCase() === "a";
      });
      var home = null;
      anchors.forEach(function (anchor) {
        if (isHomeLink(anchor) && !home) home = anchor;
        if (isAccountAction(anchor)) anchor.remove();
      });

      if (signedIn) {
        if (home) {
          home.href = "dashboard.html";
          home.textContent = "Dashboard";
          home.setAttribute("aria-label", "Open your 414Unlock dashboard");
          home.classList.add("auth-dashboard-link");
        } else {
          nav.appendChild(makeLink("Dashboard", "dashboard.html", "auth-dashboard-link"));
        }
        var signOut = makeLink("Sign out", "account.html?flow=signin", "btn btn-o auth-nav-button");
        bindSignOut(signOut);
        nav.appendChild(signOut);
      } else {
        if (home) {
          home.href = "index.html";
          home.textContent = "Home";
          home.removeAttribute("aria-label");
          home.classList.remove("auth-dashboard-link");
        }
        nav.appendChild(makeLink("Sign in", "account.html?flow=signin", "auth-nav-signin"));
        nav.appendChild(makeLink("Create account", "account.html?flow=signup", "btn btn-w auth-nav-button"));
      }
    });
  }
  function normalizeAdminNavigation() {
    var nav = document.querySelector('nav[aria-label="Admin navigation"]');
    if (!nav) return;
    var signOut = nav.querySelector("#logout-link") ||
      Array.prototype.find.call(nav.querySelectorAll("a"), function (anchor) {
        return String(anchor.textContent || "").toLowerCase().indexOf("sign out") >= 0;
      });
    if (signOut && !signOut.getAttribute("data-auth-action")) bindSignOut(signOut);
  }
  function normalizeOtherAccountLinks(signedIn) {
    var anchors = document.querySelectorAll("a[href]");
    Array.prototype.forEach.call(anchors, function (anchor) {
      if (anchor.closest("nav[aria-label='Main navigation'],nav.nav,nav[aria-label='Admin navigation']")) return;
      var href = String(anchor.getAttribute("href") || "");
      var label = String(anchor.textContent || "").trim().toLowerCase();
      var isSignIn = href.toLowerCase().indexOf("account.html?flow=signin") >= 0;
      var isSignUp = href.toLowerCase().indexOf("account.html?flow=signup") >= 0;
      var isDashboard = href.split("?")[0].split("#")[0].toLowerCase().endsWith("dashboard.html");

      if (signedIn && (isSignIn || isSignUp)) {
        if (href.toLowerCase().indexOf("return=support") >= 0 || label === "sign in to chat") {
          anchor.href = "#new-ticket-form";
          if (!anchor.querySelector("*")) anchor.textContent = "Open support chat";
        } else {
          anchor.href = "dashboard.html";
          if (!anchor.querySelector("*") && ["sign in", "create account", "account", "my wallet", "dashboard", "open my account", "back to sign in"].indexOf(label) >= 0) {
            anchor.textContent = "Dashboard";
          }
        }
      } else if (!signedIn && isDashboard) {
        anchor.href = "account.html?flow=signin";
        if (!anchor.querySelector("*") && ["dashboard", "my wallet"].indexOf(label) >= 0) anchor.textContent = "Sign in";
      }

      if (anchor.closest("footer")) {
        if (signedIn && (isSignIn || isSignUp)) {
          anchor.href = "dashboard.html";
          if (!anchor.querySelector("*")) anchor.textContent = "Dashboard";
        } else if (!signedIn && isDashboard) {
          anchor.href = "account.html?flow=signin";
          if (!anchor.querySelector("*")) anchor.textContent = "Account";
        }
      }
    });
  }
  function renderNavigation(signedIn) {
    normalizeMainNavigation(signedIn);
    normalizeAdminNavigation();
    normalizeOtherAccountLinks(signedIn);
    document.documentElement.classList.remove("u414-auth-pending");
  }
  function accountDestination() {
    var params = new URLSearchParams(window.location.search || "");
    return params.get("return") === "support" ? "support.html" : "dashboard.html";
  }
  function validateSession() {
    if (!token || !api) return Promise.resolve({ signedIn: false });
    return fetch(api + "/api/auth/me", {
      method: "GET",
      headers: { Authorization: "Bearer " + token, Accept: "application/json" },
      cache: "no-store"
    }).then(function (response) {
      return response.json().catch(function () { return {}; }).then(function (data) {
        if (response.ok && data && data.user) return { signedIn: true, user: data.user };
        if (response.status === 401 || response.status === 403) {
          clearSession();
          token = "";
          return { signedIn: false };
        }
        return { signedIn: true, unverified: true };
      });
    }).catch(function () {
      return { signedIn: true, unverified: true };
    });
  }
  function initialize() {
    var fallbackSignedIn = Boolean(token);
    renderNavigation(fallbackSignedIn);
    validateSession().then(function (auth) {
      if (auth.signedIn !== fallbackSignedIn) renderNavigation(auth.signedIn);
      if (isAccountPage() && auth.signedIn) window.location.replace(accountDestination());
    });
  }

  addPendingStyle();
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", initialize, { once: true });
  } else {
    initialize();
  }
  window.addEventListener("pageshow", function () {
    var freshToken = readToken();
    if (freshToken !== token) {
      token = freshToken;
      renderNavigation(Boolean(token));
      validateSession().then(function (auth) { renderNavigation(auth.signedIn); });
    }
  });
})();