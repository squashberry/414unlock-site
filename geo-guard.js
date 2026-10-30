(function(){
  "use strict";
  if(window.__414UnlockCountryGuard)return;
  window.__414UnlockCountryGuard=true;
  var cfg=window.UNLOCK414_CONFIG||{},api=String(cfg.API_BASE_URL||"").replace(/\/+$/,"");
  var root=document.documentElement;
  root.style.visibility="hidden";
  function blocked(){
    if(document.body){
      document.body.textContent="";
      document.body.style.cssText="margin:0;min-height:100vh;display:grid;place-items:center;padding:28px;box-sizing:border-box;background:#fff;color:#111827;font:16px/1.6 system-ui,-apple-system,'Segoe UI',sans-serif";
      var card=document.createElement("main"),title=document.createElement("h1"),message=document.createElement("p"),contact=document.createElement("a");
      card.style.cssText="width:min(520px,100%);text-align:center";
      title.textContent="Access unavailable";
      title.style.cssText="font-size:clamp(28px,5vw,40px);line-height:1.1;margin:0 0 16px";
      message.textContent="Sorry, this country isn't supported. Contact us at 414unlock@gmail.com if you have any questions or requests.";
      message.style.cssText="color:#4b5563;margin:0";
      contact.href="mailto:414unlock@gmail.com";
      contact.textContent="414unlock@gmail.com";
      contact.style.cssText="display:inline-block;margin-top:18px;color:#0b1f8f;font-weight:700;text-decoration:underline;text-underline-offset:4px";
      card.append(title,message,contact);document.body.appendChild(card);
    }
    root.style.visibility="visible";
  }
  if(!api){blocked();return;}
  fetch(api+"/api/access/check",{method:"GET",cache:"no-store",credentials:"omit",headers:{"Accept":"application/json"}})
    .then(function(response){if(!response.ok)throw new Error("Access denied");return response.json();})
    .then(function(data){if(!data||data.supported!==true)throw new Error("Access denied");root.style.visibility="visible";})
    .catch(blocked);
})();