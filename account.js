(function(){
  "use strict";
  var cfg=window.UNLOCK414_CONFIG||{}, api=(cfg.API_BASE_URL||"").replace(/\/+$/,"");
  var params=new URLSearchParams(location.search), mode=params.get("flow")==="signup"?"signup":"signin";
  var returnTarget=params.get("return")||"", returnToApp=returnTarget==="app", paymentLaunch=params.get("launch")||"", appState=params.get("state")||"";
  var form=document.getElementById("auth-form"), nameWrap=document.getElementById("name-wrap"), codeWrap=document.getElementById("email-code-wrap"), message=document.getElementById("message"), submit=document.getElementById("submit-button"), tabs=[document.getElementById("tab-signin"),document.getElementById("tab-signup")], heading=document.getElementById("heading"), intro=document.getElementById("intro"), passwordHint=document.getElementById("password-hint"), passwordInput=document.getElementById("password"), emailCode=document.getElementById("emailCode"), codeMode=false, pendingEmail="";
  function showMessage(text,type){message.textContent=text;message.className="message show "+(type||"info");}
  function setBusy(b){submit.disabled=b;submit.style.opacity=b?".65":"1";}
  function configured(){if(api&&!api.includes("YOUR_")&&!api.includes("example.workers.dev"))return true;showMessage("Secure account service is not connected yet. Configure API_BASE_URL after deploying the 414Unlock authentication API. No account has been created or signed in.", "error");return false;}
  async function request(path,options){var res=await fetch(api+path,options||{});var data={};try{data=await res.json();}catch(_){}if(!res.ok)throw new Error(data.message||data.error||("Request failed ("+res.status+")"));return data;}
  function changeMode(newMode){mode=newMode;codeMode=false;pendingEmail="";nameWrap.classList.toggle("hidden",mode!=="signup");codeWrap.classList.add("hidden");emailCode.required=false;emailCode.value="";passwordInput.classList.remove("hidden");tabs[0].classList.toggle("active",mode==="signin");tabs[1].classList.toggle("active",mode==="signup");heading.textContent=mode==="signin"?"Welcome back.":"Create your account.";intro.textContent=mode==="signin"?"Sign in to confirm your account access. When you sign in from the desktop app, you will return to 414Unlock automatically.":"Create your account and verify your email. You will then continue to the identity or professional verification steps.";submit.innerHTML=(mode==="signin"?"Sign in":"Create account")+' <span>→</span>';passwordInput.autocomplete=mode==="signin"?"current-password":"new-password";passwordHint.textContent=mode==="signin"?"Use the password you created for your account.":"Use at least 10 characters. Never reuse a password from another service.";message.className="message";var returnQuery=returnToApp?"&return=app&state="+encodeURIComponent(appState):(returnTarget==="payment"&&paymentLaunch?"&return=payment&launch="+encodeURIComponent(paymentLaunch)+(appState?"&state="+encodeURIComponent(appState):""):"");history.replaceState(null,"", "account.html?flow="+mode+returnQuery);}
  tabs[0].addEventListener("click",function(){changeMode("signin")});tabs[1].addEventListener("click",function(){changeMode("signup")});
  function finishAppLogin(code){if(!returnToApp){showMessage("You are signed in. You can close this tab and return to the 414Unlock website.", "success");submit.classList.add("hidden");return;}if(!appState){showMessage("The desktop sign-in request is missing its security state. Close this page and start sign-in again from 414Unlock.", "error");return;}var url=cfg.APP_CALLBACK+"?code="+encodeURIComponent(code)+"&state="+encodeURIComponent(appState);showMessage("Sign-in complete. Returning to 414Unlock…","success");location.href=url;}
  form.addEventListener("submit",async function(event){event.preventDefault();message.className="message";if(!configured())return;setBusy(true);
    try{
      if(mode==="signup"&&!codeMode){
        var fullName=document.getElementById("fullName").value.trim(),email=document.getElementById("email").value.trim().toLowerCase(),password=passwordInput.value;
        if(!fullName){showMessage("Enter your full name.","error");return;}if(password.length<10){showMessage("Use a password with at least 10 characters.","error");return;}
        await request("/api/auth/signup",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({fullName:fullName,email:email,password:password})});
        pendingEmail=email;codeMode=true;codeWrap.classList.remove("hidden");emailCode.required=true;passwordInput.classList.add("hidden");passwordHint.textContent="A one-time code was requested for "+email+".";submit.innerHTML="Verify email <span>→</span>";showMessage("Check your email for the verification code. Keep this page open to continue.","success");return;
      }
      if(mode==="signup"&&codeMode){
        var verified=await request("/api/auth/verify-email",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({email:pendingEmail,code:emailCode.value.trim()})});
        if(!verified.token)throw new Error("The server did not return an authenticated session.");
        sessionStorage.setItem("414unlock_token",verified.token);sessionStorage.setItem("414unlock_flow","signup");
        location.href="verify.html?source=signup"+(returnToApp?"&return=app&state="+encodeURIComponent(appState):"");return;
      }
      var emailValue=document.getElementById("email").value.trim().toLowerCase(),passwordValue=passwordInput.value;
      var data=await request("/api/auth/login",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({email:emailValue,password:passwordValue})});
      if(!data.token)throw new Error("The server did not return an authenticated session.");
      sessionStorage.setItem("414unlock_token",data.token);
      if(returnToApp){
        var appCode=await request("/api/auth/app-code",{method:"POST",headers:{"Authorization":"Bearer "+data.token,"Content-Type":"application/json"},body:"{}"});
        if(!appCode.code)throw new Error("Could not create a one-time app handoff code.");
        finishAppLogin(appCode.code);
      }else if(returnTarget==="payment"&&paymentLaunch){
        var paymentUrl="payment.html?launch="+encodeURIComponent(paymentLaunch)+(appState?"&state="+encodeURIComponent(appState):"");
        location.href=paymentUrl;return;
      }else{showMessage("You are signed in. You can close this tab and return to the 414Unlock website.","success");submit.classList.add("hidden");}
    }catch(err){showMessage(err.message||"Unable to complete the request. Please try again.","error");}
    finally{setBusy(false);}
  });
  changeMode(mode);
  if(!api||api.includes("YOUR_")||api.includes("example.workers.dev"))document.getElementById("api-notice").classList.remove("hidden");else document.getElementById("api-notice").classList.add("hidden");
})();