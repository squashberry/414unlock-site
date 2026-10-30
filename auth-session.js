/* Shared 414Unlock browser session storage. Tokens are never placed in URLs. */
(function () {
  "use strict";
  var key = "414unlock_token", flowKey = "414unlock_flow";
  function storage(name) { try { return window[name]; } catch (_) { return null; } }
  function safeGet(store, name) { try { return store ? (store.getItem(name) || "") : ""; } catch (_) { return ""; } }
  function safeSet(store, name, value) { try { if (store) store.setItem(name, value); } catch (_) {} }
  function safeRemove(store, name) { try { if (store) store.removeItem(name); } catch (_) {} }
  function getToken() {
    var local = storage("localStorage"), tab = storage("sessionStorage");
    var value = safeGet(local, key) || safeGet(tab, key);
    if (value) { safeSet(local, key, value); safeSet(tab, key, value); }
    return value;
  }
  function setToken(value, flow) {
    if (!value) return clear();
    var local = storage("localStorage"), tab = storage("sessionStorage");
    safeSet(local, key, value); safeSet(tab, key, value);
    if (flow) { safeSet(local, flowKey, flow); safeSet(tab, flowKey, flow); }
  }
  function clear() {
    [storage("localStorage"), storage("sessionStorage")].forEach(function (store) {
      safeRemove(store, key); safeRemove(store, flowKey);
    });
  }
  window.UNLOCK414_SESSION = Object.freeze({ getToken: getToken, setToken: setToken, clear: clear });
})();
