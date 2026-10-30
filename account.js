(function(){
  "use strict";
  var cfg=window.UNLOCK414_CONFIG||{},api=(cfg.API_BASE_URL||"").replace(/\/+$/,""),session=window.UNLOCK414_SESSION||null;
  var params=new URLSearchParams(location.search),mode=params.get("flow")==="signup"?"signup":"signin";
  var returnTarget=params.get("return")||"",returnToApp=returnTarget==="app",paymentLaunch=params.get("launch")||"",appState=params.get("state")||"",appCallback=params.get("callback")||"";
  var form=document.getElementById("auth-form"),nameWrap=document.getElementById("name-wrap"),message=document.getElementById("message"),submit=document.getElementById("submit-button"),tabs=[document.getElementById("tab-signin"),document.getElementById("tab-signup")],heading=document.getElementById("heading"),intro=document.getElementById("intro"),passwordHint=document.getElementById("password-hint"),passwordInput=document.getElementById("password"),authView=document.getElementById("auth-view"),browserView=document.getElementById("browser-check-view"),browserStatus=document.getElementById("browser-check-status");
  function showMessage(text,type){message.textContent=text;message.className="message show "+(type||"info");}
  function setBusy(b){submit.disabled=b;submit.style.opacity=b?".65":"1";}
  function configured(){if(api&&!api.includes("YOUR_")&&!api.includes("example.workers.dev"))return true;showMessage("Secure account services are not connected yet. Please contact support.", "error");return false;}
  async function request(path,options){var res=await fetch(api+path,options||{}),data={};try{data=await res.json();}catch(_){}if(!res.ok)throw new Error(data.message||data.error||("Request failed ("+res.status+")"));return data;}
  function browserState(text){authView.classList.add("hidden");browserView.classList.remove("hidden");browserStatus.textContent=text;document.title="Verifying browser · 414Unlock";}
  function hideBrowserState(){browserView.classList.add("hidden");authView.classList.remove("hidden");document.title=(mode==="signup"?"Create account":"Sign in")+" · 414Unlock";}
  function leadingZeroBits(bytes){var total=0;for(var i=0;i<bytes.length;i++){var value=bytes[i];if(value===0){total+=8;continue;}for(var bit=7;bit>=0;bit--){if(value&(1<<bit))return total;total++;}return total;}return total;}
  function toHex(bytes){return Array.from(bytes,function(b){return b.toString(16).padStart(2,"0");}).join("");}
  async function createBrowserProof(purpose,email){
    if(!window.crypto||!window.crypto.subtle||!window.TextEncoder)throw new Error("This browser cannot complete the secure browser check. Please use an updated browser.");
    if(navigator.webdriver===true)throw new Error("This browser session could not be verified. Open 414Unlock in a standard browser.");
    browserState("Starting a fresh Squashberry browser check…");
    var challenge=await request("/api/auth/browser-challenge",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({purpose:purpose})});
    if(!challenge.challengeId||!challenge.nonce||Number(challenge.difficulty)!==12)throw new Error("The security service returned an invalid browser challenge.");
    var nonce=challenge.nonce,counter=0,proof="",difficulty=Number(challenge.difficulty),encoder=new TextEncoder(),languages=(navigator.languages||[navigator.language||"en"]).filter(Boolean).slice(0,5);
    if(!languages.length)languages=["und"];
    browserState("Rotating one-time browser challenge…");
    while(counter<=10000000){
      var digest=await window.crypto.subtle.digest("SHA-256",encoder.encode(nonce+":"+String(counter))),bytes=new Uint8Array(digest);
      if(leadingZeroBits(bytes)>=difficulty){proof=toHex(bytes);break;}
      counter++;
      if(counter%256===0){
        browserState(counter%512===0?"Checking browser activity and session signals…":"Verifying the rotating Squashberry challenge…");
        await new Promise(function(resolve){setTimeout(resolve,0);});
      }
    }
    if(!proof)throw new Error("The browser check expired. Refresh the page and try again.");
    browserState("Browser verified. Completing secure authentication…");
    return {challengeId:challenge.challengeId,nonce:nonce,counter:counter,proof:proof,signals:{webCrypto:true,webdriver:navigator.webdriver===true,languages:languages}};
  }
  function changeMode(newMode){
    mode=newMode;nameWrap.classList.toggle("hidden",mode!=="signup");tabs[0].classList.toggle("active",mode==="signin");tabs[1].classList.toggle("active",mode==="signup");
    heading.textContent=mode==="signin"?"Welcome back.":"Create your account.";
    intro.textContent=mode==="signin"?"Sign in securely. Squashberry checks the browser session every time you authenticate.":"Create your account directly. Your browser session is checked before the account is activated.";
    submit.innerHTML=(mode==="signin"?"Sign in":"Create account")+' <span>→</span>';
    passwordInput.autocomplete=mode==="signin"?"current-password":"new-password";
    passwordHint.textContent=mode==="signin"?"Use your account password.":"Use at least 10 characters. Never reuse a password from another service.";
    message.className="message";hideBrowserState();
    var returnQuery=returnToApp?"&return=app&state="+encodeURIComponent(appState)+(appCallback?"&callback="+encodeURIComponent(appCallback):""):(returnTarget==="payment"&&paymentLaunch?"&return=payment&launch="+encodeURIComponent(paymentLaunch)+(appState?"&state="+encodeURIComponent(appState):"")+(appCallback?"&callback="+encodeURIComponent(appCallback):""):(returnTarget==="admin"||returnTarget==="review"?"&return="+returnTarget:""));
    history.replaceState(null,"","account.html?flow="+mode+returnQuery);
  }
  tabs[0].addEventListener("click",function(){changeMode("signin");});
  tabs[1].addEventListener("click",function(){changeMode("signup");});
  function finishAppLogin(code){
    if(!returnToApp){showMessage("You are signed in. You can close this tab and return to the 414Unlock website.","success");submit.classList.add("hidden");return;}
    if(!appState){showMessage("The desktop sign-in request is missing its security state. Close this page and start sign-in again from 414Unlock.","error");return;}
    var targetCb=(appCallback&&(appCallback.startsWith("414unlock://")||appCallback.startsWith("http://127.0.0.1:")||appCallback.startsWith("http://localhost:")))?appCallback:cfg.APP_CALLBACK;
    showMessage("Sign-in complete. Returning to 414Unlock…","success");location.href=targetCb+"?code="+encodeURIComponent(code)+"&state="+encodeURIComponent(appState);
  }
  async function routeAuthenticated(token,flow){
    if(session&&session.setToken)session.setToken(token,flow);else{localStorage.setItem("414unlock_token",token);sessionStorage.setItem("414unlock_token",token);localStorage.setItem("414unlock_flow",flow);sessionStorage.setItem("414unlock_flow",flow);}
    if(flow==="signup"){
      var verificationUrl="verify.html?source=signup";
      if(returnToApp)verificationUrl+="&return=app&state="+encodeURIComponent(appState)+(appCallback?"&callback="+encodeURIComponent(appCallback):"");
      else verificationUrl+="&return=dashboard";
      location.href=verificationUrl;return;
    }
    if(returnToApp){
      if(!appState){showMessage("The desktop sign-in request is missing its security state. Start sign-in again from 414Unlock.","error");return;}
      var appCode=await request("/api/auth/app-code",{method:"POST",headers:{"Authorization":"Bearer "+token,"Content-Type":"application/json"},body:"{}"});
      if(!appCode.code)throw new Error("Could not create a one-time app handoff code.");
      finishAppLogin(appCode.code);return;
    }
    if(returnTarget==="admin"){location.href="admin.html";return;}
    if(returnTarget==="review"){location.href="review.html";return;}
    if(returnTarget==="payment"&&paymentLaunch){location.href="payment.html?launch="+encodeURIComponent(paymentLaunch)+(appState?"&state="+encodeURIComponent(appState):"");return;}
    location.href="dashboard.html";
  }
  form.addEventListener("submit",async function(event){
    event.preventDefault();message.className="message";if(!configured())return;setBusy(true);
    var email=document.getElementById("email").value.trim().toLowerCase(),password=passwordInput.value;
    try{
      if(mode==="signup"){
        var fullName=document.getElementById("fullName").value.trim();
        if(fullName.length<2){showMessage("Enter your full name.","error");return;}
        if(password.length<10){showMessage("Use a password with at least 10 characters.","error");return;}
        var browserVerification=await createBrowserProof("signup",email);
        var created=await request("/api/auth/signup",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({fullName:fullName,email:email,password:password,browserVerification:browserVerification})});
        if(!created.token)throw new Error("The server did not return an authenticated session.");
        await routeAuthenticated(created.token,"signup");
      }else{
        var browserVerification=await createBrowserProof("login",email);
        var signed=await request("/api/auth/login",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({email:email,password:password,browserVerification:browserVerification})});
        if(!signed.token)throw new Error("The server did not return an authenticated session.");
        await routeAuthenticated(signed.token,"signin");
      }
    }catch(err){hideBrowserState();showMessage(err.message||"Unable to complete the request. Please try again.","error");}
    finally{setBusy(false);}
  });
  changeMode(mode);
  if(!api||api.includes("YOUR_")||api.includes("example.workers.dev"))document.getElementById("api-notice").classList.remove("hidden");else document.getElementById("api-notice").classList.add("hidden");
})();