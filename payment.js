(function(){
"use strict";
var cfg=window.UNLOCK414_CONFIG||{},api=(cfg.API_BASE_URL||"").replace(/\/+$/,"");
var params=new URLSearchParams(location.search),launch=params.get("launch")||"",state=params.get("state")||"";
var token=sessionStorage.getItem("414unlock_token"),session=null,verified=false;
var message=document.getElementById("payment-message"),payButton=document.getElementById("pay-button"),verifyButton=document.getElementById("verify-button"),codeInput=document.getElementById("payment-code"),continueButton=document.getElementById("continue-button"),verifiedPanel=document.getElementById("verified-panel");
function setMessage(text,type){message.textContent=text;message.className="payment-message"+(type?" "+type:"");}
function setApiConfigured(){return !!api&&!api.includes("YOUR_")&&!api.includes("example.workers.dev");}
async function request(path,options){var response=await fetch(api+path,options||{}),data={};try{data=await response.json();}catch(_){}if(!response.ok)throw new Error(data.message||data.error||("Request failed ("+response.status+")"));return data;}
function authHeaders(){return {"Authorization":"Bearer "+token};}
function accountRedirect(){var next="account.html?flow=signin&return=payment&launch="+encodeURIComponent(launch);if(state)next+="&state="+encodeURIComponent(state);location.replace(next);}
function maskedLabel(kind){return kind==="imei"?"IMEI (masked)":kind==="udid"?"UDID (masked)":"Serial number (masked)";}
function renderSession(data){
 session=data;
 document.getElementById("device-model").textContent=data.deviceModel||"Recognized iPhone";
 document.getElementById("identifier-label").textContent=maskedLabel(data.identifierKind||"serial");
 document.getElementById("masked-identifier").textContent=data.maskedIdentifier||"••••••••";
 document.getElementById("payment-reference").textContent=data.paymentReference||"Unavailable";
 document.getElementById("device-status").textContent=data.status==="verified"?"PAYMENT VERIFIED":"DEVICE MATCHED";
 codeInput.disabled=data.status==="verified";verifyButton.disabled=data.status==="verified";
 if(data.status==="verified"){verified=true;verifiedPanel.classList.remove("hidden");setMessage("This payment is already verified for the linked device.","success");}
 else if(data.status==="expired"){setMessage("This payment session has expired. Return to 414Unlock and start a new payment session.","error");codeInput.disabled=true;verifyButton.disabled=true;payButton.disabled=true;}
 else {codeInput.disabled=false;verifyButton.disabled=false;setMessage("Device preview loaded. Complete payment, then enter the confirmation code SquashberryPay sends you.");}
 if(!cfg.SQUASHBERRYPAY_CHECKOUT_URL){setMessage("The device session is ready. The SquashberryPay checkout link has not been configured yet; no payment can be initiated from this button until it is added.");}
}
async function loadSession(){
 if(!launch){document.getElementById("device-status").textContent="NO ACTIVE SESSION";setMessage("Open this page from 414Unlock after your iPhone has been detected. The preview is loaded from the app-created, device-bound payment session.","error");return;}
 if(!setApiConfigured()){document.getElementById("device-status").textContent="SETUP REQUIRED";setMessage("The secure 414Unlock payment API is not connected yet. No payment code can be verified on this page.","error");return;}
 if(!token){accountRedirect();return;}
 try{
  var params2=new URLSearchParams({launch:launch});
  var data=await request("/api/payments/session?"+params2.toString(),{headers:authHeaders()});
  if(!data.sessionId)throw new Error("The server did not return a valid device-bound payment session.");
  renderSession(data);
 }catch(error){
  if(/sign in|session|authentication/i.test(error.message)){accountRedirect();return;}
  setMessage(error.message||"Could not load the device-bound payment session.","error");
  document.getElementById("device-status").textContent="SESSION UNAVAILABLE";
 }
}
payButton.addEventListener("click",function(){
 if(!session){setMessage("Load a valid device session from 414Unlock before starting payment.","error");return;}
 var checkout=String(cfg.SQUASHBERRYPAY_CHECKOUT_URL||"").trim();
 if(!checkout){setMessage("Checkout is not connected yet. Add the SquashberryPay checkout URL in site-config.js. The payment reference shown beside your device must be associated with the transaction by the checkout integration.","error");return;}
 if(checkout.indexOf("{reference}")!==-1)checkout=checkout.replace(/\{reference\}/g,encodeURIComponent(session.paymentReference));
 var target;
 try{target=new URL(checkout);if(target.protocol!=="https:")throw new Error("The checkout URL must use HTTPS.");}
 catch(_){setMessage("The configured SquashberryPay checkout URL is invalid. Please contact support.","error");return;}
 if(checkout.indexOf("{reference}")===-1){var refParam=String(cfg.SQUASHBERRYPAY_REFERENCE_PARAM||"").trim();if(refParam)target.searchParams.set(refParam,session.paymentReference);}
 window.open(target.toString(),"_blank","noopener,noreferrer");
 setMessage("SquashberryPay checkout opened. Complete the payment there, then return here and enter the confirmation code. Do not enter a code until the checkout confirms your payment.");
});
document.getElementById("copy-reference").addEventListener("click",async function(){
 if(!session||!session.paymentReference){setMessage("Payment reference is not available yet.","error");return;}
 try{await navigator.clipboard.writeText(session.paymentReference);setMessage("Payment reference copied.","success");}
 catch(_){setMessage("Your payment reference is "+session.paymentReference+". Select and copy it manually if needed.");}
});
verifyButton.addEventListener("click",async function(){
 if(!session||!launch){setMessage("No active payment session. Start again from 414Unlock.","error");return;}
 if(!setApiConfigured()){setMessage("The secure payment API is not configured; no code has been verified.","error");return;}
 var code=codeInput.value.trim();if(!code){setMessage("Enter the confirmation code SquashberryPay sent you.","error");codeInput.focus();return;}
 verifyButton.disabled=true;verifyButton.textContent="Checking code…";
 try{
  var result=await request("/api/payments/verify-code",{method:"POST",headers:Object.assign({"Content-Type":"application/json"},authHeaders()),body:JSON.stringify({launchToken:launch,confirmationCode:code})});
  if(result.status!=="verified"||result.verified!==true)throw new Error("SquashberryPay has not confirmed a paid transaction for this device. Check the code and try again.");
  verified=true;session.status="verified";verifiedPanel.classList.remove("hidden");document.getElementById("device-status").textContent="PAYMENT VERIFIED";codeInput.disabled=true;setMessage("Payment confirmed by the server and matched to this device session.","success");
 }catch(error){setMessage(error.message||"Unable to verify the payment code. Try again after confirming payment.","error");}
 finally{verifyButton.disabled=verified;verifyButton.innerHTML=verified?"Payment verified <span>✓</span>":'Verify payment <span>→</span>';}
});
continueButton.addEventListener("click",async function(){
 if(!verified||!session){setMessage("Payment must be verified by the server before continuing.","error");return;}
 if(!state){setMessage("The app security state is missing. Close this page and reopen payment from 414Unlock so the return can be validated.","error");return;}
 try{
  continueButton.disabled=true;continueButton.textContent="Preparing secure return…";
  var auth=await request("/api/auth/app-code",{method:"POST",headers:Object.assign({"Content-Type":"application/json"},authHeaders()),body:"{}"});
  if(!auth.code)throw new Error("The server did not issue a one-time return code.");
  var callback=new URL(String(cfg.APP_CALLBACK||"414unlock://auth/callback"));
  callback.searchParams.set("code",auth.code);callback.searchParams.set("state",state);callback.searchParams.set("paymentSessionId",session.sessionId);
  location.href=callback.toString();
 }catch(error){setMessage(error.message||"Could not return securely to 414Unlock. Reopen the app to refresh payment status.","error");continueButton.disabled=false;continueButton.innerHTML='Continue in app <span>↗</span>';}
});
codeInput.addEventListener("keydown",function(e){if(e.key==="Enter"&&!verifyButton.disabled){e.preventDefault();verifyButton.click();}});
loadSession();
})();