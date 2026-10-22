/* 414Unlock splash: shows once per browser session, skipped for reduced-motion users. */
(function () {
  "use strict";
  try {
    if (sessionStorage.getItem("414_splash") || matchMedia("(prefers-reduced-motion:reduce)").matches) return;
    sessionStorage.setItem("414_splash", "1");
  } catch (e) {}

  var css =
    "html.sp-lock{overflow:hidden}" +
    "#sp{position:fixed;inset:0;z-index:99999;background:#0b1f8f;color:#fff;display:grid;place-items:center;overflow:hidden;cursor:pointer;" +
    "font-family:'Bricolage Grotesque','Segoe UI',system-ui,sans-serif;transition:transform .95s cubic-bezier(.77,0,.18,1)}" +
    "#sp.out{transform:translateY(-101%)}" +
    "#sp .fs{position:absolute;left:0;right:0;height:10px;background:linear-gradient(#cf1b2e 0 3px,#fff 3px 4px,#0b1f8f 4px 6px,#fff 6px 7px,#17703a 7px)}" +
    "#sp .t{top:0}#sp .b{bottom:0}" +
    "#sp .r{position:absolute;left:50%;top:50%;width:22vmin;height:22vmin;margin:-11vmin 0 0 -11vmin;border:2px solid #ffffff33;border-radius:50%;opacity:0;animation:sp-ring 3.4s ease-out infinite}" +
    "#sp .r:nth-of-type(2){animation-delay:.9s}#sp .r:nth-of-type(3){animation-delay:1.8s}" +
    "@keyframes sp-ring{from{transform:scale(.3);opacity:.9}to{transform:scale(7.5);opacity:0}}" +
    "#sp .w{position:relative;display:flex;align-items:baseline;font-weight:800;line-height:1;letter-spacing:-.04em;" +
    "font-size:min(46vw,460px);animation:sp-shrink 1.05s cubic-bezier(.7,0,.2,1) 1.25s both}" +
    "@keyframes sp-shrink{to{font-size:min(13.5vw,150px)}}" +
    "#sp .n{display:flex}" +
    "#sp .u{display:grid;grid-template-columns:0fr;animation:sp-open .95s cubic-bezier(.2,.8,.2,1) 1.55s forwards}" +
    "#sp .u>span{display:flex;min-width:0;overflow:hidden;padding:.14em .22em .14em .14em;margin:-.14em 0;color:transparent;-webkit-text-stroke:.028em #fff}" +
    "@keyframes sp-open{to{grid-template-columns:1fr}}" +
    "#sp b{display:inline-block;font-weight:inherit;animation:sp-up .9s cubic-bezier(.2,.9,.2,1) both;animation-delay:calc(var(--d)*1s)}" +
    "#sp b i{display:inline-block;font-style:normal;animation:sp-wave 1.9s ease-in-out infinite;animation-delay:calc(var(--k)*-.17s)}" +
    "@keyframes sp-up{from{opacity:0;transform:translateY(.55em) rotate(7deg);filter:blur(14px)}}" +
    "@keyframes sp-wave{0%,100%{transform:translateY(.05em) rotate(-2deg)}50%{transform:translateY(-.06em) rotate(2deg)}}" +
    "#sp .h{position:absolute;bottom:34px;left:0;right:0;text-align:center;font:500 13px 'Instrument Sans',system-ui,sans-serif;letter-spacing:.04em;color:#aab6f0;opacity:0;animation:sp-hint .6s ease 1.2s forwards}" +
    "@keyframes sp-hint{to{opacity:1}}";

  function letters(text, base, step, kStart) {
    return text.split("").map(function (ch, i) {
      return '<b style="--d:' + (base + i * step).toFixed(2) + ";--k:" + (kStart + i) + '"><i>' + ch + "</i></b>";
    }).join("");
  }

  var root = document.documentElement;
  var style = document.createElement("style");
  style.textContent = css;
  var el = document.createElement("div");
  el.id = "sp";
  el.setAttribute("aria-hidden", "true");
  el.innerHTML =
    '<div class="fs t"></div><div class="fs b"></div><i class="r"></i><i class="r"></i><i class="r"></i>' +
    '<div class="w"><span class="n">' + letters("414", 0.05, 0.11, 0) + "</span>" +
    '<span class="u"><span>' + letters("UNLOCK", 1.9, 0.08, 3) + "</span></span></div>" +
    '<div class="h">Tap to skip</div>';
  root.appendChild(style);
  root.appendChild(el);
  root.classList.add("sp-lock");

  var done = false;
  function leave() {
    if (done) return;
    done = true;
    el.classList.add("out");
    setTimeout(function () {
      if (el.parentNode) el.parentNode.removeChild(el);
      if (style.parentNode) style.parentNode.removeChild(style);
      root.classList.remove("sp-lock");
    }, 1000);
  }
  el.addEventListener("click", leave);
  setTimeout(leave, 4400);
})();
