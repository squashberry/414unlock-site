(function(){
  "use strict";
  if(window.__414UnlockCountryGuard)return;
  window.__414UnlockCountryGuard=true;
  var cfg=window.UNLOCK414_CONFIG||{},api=String(cfg.API_BASE_URL||"").replace(/\/+$/,"");
  var root=document.documentElement;
  root.style.visibility="visible";
  function blocked(){
    if(!document.body){document.addEventListener("DOMContentLoaded",blocked,{once:true});return;}
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
  function maintenance(data){
    if(!document.body){document.addEventListener("DOMContentLoaded",function(){maintenance(data);},{once:true});return;}
    document.body.textContent="";
    document.body.style.cssText="margin:0;min-height:100vh;display:grid;place-items:center;padding:28px;box-sizing:border-box;background:#fff;color:#111827;font:16px/1.6 system-ui,-apple-system,'Segoe UI',sans-serif";
    var card=document.createElement("main"),eyebrow=document.createElement("p"),title=document.createElement("h1"),message=document.createElement("p"),timer=document.createElement("div"),contact=document.createElement("a");
    card.style.cssText="width:min(580px,100%);text-align:center";eyebrow.textContent="414 UNLOCK · TEMPORARILY UNAVAILABLE";eyebrow.style.cssText="font-size:12px;letter-spacing:.14em;font-weight:700;color:#667085";
    title.textContent="We'll be back soon";title.style.cssText="font-size:clamp(32px,7vw,52px);line-height:1.05;margin:12px 0";
    message.textContent=data.serviceMessage||"We're carrying out scheduled maintenance. Please check back shortly.";message.style.cssText="color:#4b5563;margin:0";
    timer.style.cssText="font-size:clamp(24px,5vw,36px);font-weight:800;letter-spacing:.04em;margin:26px 0;color:#0d1337";
    contact.href="mailto:414unlock@gmail.com";contact.textContent="Contact support";contact.style.cssText="display:inline-block;margin-top:12px;color:#0b1f8f;font-weight:700";
    card.append(eyebrow,title,message,timer,contact);document.body.appendChild(card);
    var target=Number(data.returnAt||0)*1000;
    function tick(){if(!target){timer.textContent="Return time to be announced";return;}var left=Math.max(0,target-Date.now());if(!left){timer.textContent="We're preparing to return";return;}var d=Math.floor(left/86400000),h=Math.floor(left%86400000/3600000),m=Math.floor(left%3600000/60000),sec=Math.floor(left%60000/1000);timer.textContent=(d?d+"d ":"")+String(h).padStart(2,"0")+":"+String(m).padStart(2,"0")+":"+String(sec).padStart(2,"0");}
    tick();setInterval(tick,1000);
  }
  if(!api)return;
  var controller=new AbortController(),timeout=setTimeout(function(){controller.abort();},8000);
  fetch(api+"/api/access/check",{method:"GET",cache:"no-store",credentials:"omit",headers:{"Accept":"application/json"},signal:controller.signal})
    .then(function(response){
      if(response.status===403)return response.json().then(function(data){if(data&&data.error==="COUNTRY_NOT_SUPPORTED"){blocked();return null;}throw new Error("Access check denied");});
      if(!response.ok)throw new Error("Access check unavailable");
      return response.json();
    })
    .then(function(data){if(data===null)return;if(!data||data.supported!==true)return;if(data.serviceMode&&!/admin(?:-setup)?\.html$/i.test(location.pathname))maintenance(data);})
    .catch(function(){/* A temporary API outage must not falsely label a visitor as unsupported. Auth and API actions remain server-gated. */})
    .finally(function(){clearTimeout(timeout);});
})();