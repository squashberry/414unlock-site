(function(){
"use strict";
var cfg=window.UNLOCK414_CONFIG||{};
var api=String(cfg.API_BASE_URL||"").replace(/\/+$/,"");
var token=String(location.hash||"").replace(/^#/,"")||new URLSearchParams(location.search).get("token")||"";
var badge=document.getElementById("status-badge");
var title=document.getElementById("status-title");
var summary=document.getElementById("status-summary");
var updated=document.getElementById("last-updated");
var refresh=document.getElementById("refresh-status");
var errorPanel=document.getElementById("error-panel");

function text(id,value){var node=document.getElementById(id);if(node)node.textContent=value===null||value===undefined||value===""?"—":String(value);}
function dateText(value){
 if(value===null||value===undefined||value==="")return "—";
 var n=Number(value);
 var d=Number.isFinite(n)&&String(value).trim()!==""?new Date(n>1000000000000?n:n*1000):new Date(value);
 if(Number.isNaN(d.getTime()))return "—";
 return new Intl.DateTimeFormat("en-GB",{
  timeZone:"Africa/Banjul",day:"2-digit",month:"short",year:"numeric",
  hour:"2-digit",minute:"2-digit",second:"2-digit",hour12:true
 }).format(d);
}
function showError(message){
 errorPanel.hidden=false;
 document.getElementById("update-banner").dataset.state="error";
 document.getElementById("error-message").textContent=message||"This status link may be invalid or expired. Ask 414Unlock for a new link.";
 badge.className="status-badge error";
 badge.textContent="Link unavailable";
 title.textContent="We couldn't load this device report";
 var paymentCycle=summary.querySelector(".cycle-payment"),bypassCycle=summary.querySelector(".cycle-bypass");
 if(paymentCycle)paymentCycle.textContent=message||"Status unavailable";
 if(bypassCycle)bypassCycle.hidden=true;
 summary.setAttribute("aria-label",message||"Status unavailable");
 updated.textContent="Please check the tracking link and try again.";
}
function pct(v){return v===null||v===undefined||v===""?"—":v+"%";}
function gb(v){return v===null||v===undefined||v===""?"—":v+" GB";}
function mark(id,tone){var n=document.getElementById(id);if(!n)return;n.classList.remove("value-good","value-warn","value-bad");if(tone)n.classList.add("value-"+tone);}
function setRing(id,value,kind){
 var ring=document.getElementById(id);
 if(!ring)return;
 var has=!(value===null||value===undefined||value==="");
 var n=Math.max(0,Math.min(100,Number(value)||0));
 ring.style.setProperty("--value",has?n:0);
 ring.classList.remove("good","warn","bad");
 if(!has)return;
 var good=kind==="battery"?80:25,warn=kind==="battery"?60:10;
 ring.classList.add(n>=good?"good":n>=warn?"warn":"bad");
}
function renderDetails(order){
 var d=order.deviceDetails||{};
 var model=order.deviceModel||"iPhone";
 text("device-model",d.deviceFamily||model);
 text("device-capacity",gb(d.diskCapacityGb));
 text("device-colour",d.colour);
 text("phone-model-label",[d.deviceFamily||model,d.colour].filter(Boolean).join(" · "));
 text("device-activation-state",d.deviceActivationDisplay||"Device status available");
 text("device-subtitle",[d.diskCapacityGb?d.diskCapacityGb+" GB":null,d.iosVersion||null,d.colour||null].filter(Boolean).join(" · "));
 text("ios-version",d.iosVersion);
 text("serial-number",d.serialNumber);
 text("imei-one",d.imei1);
 text("imei-two",d.imei2);
 text("model-identifier",d.modelIdentifier);
 text("model-number",d.modelNumber);
 text("model-name",d.modelName);
 text("sales-region",d.salesRegion);
 text("activation-status",d.activationStatus);
 text("jailbreak-status",d.jailbreakStatus);
 text("id-lock-status",d.idLockStatus);
 text("icloud-status",d.icloudStatus);
 text("manufacture-date",d.manufactureDate);
 text("warranty-status",d.warrantyStatus);
 text("crash-logs",d.crashLogs);
 text("charging-status",d.chargingStatus);
 text("device-state",d.deviceActivationDisplay||"—");
 text("battery-health",pct(d.batteryHealthPercent));
 text("battery-cycles",d.batteryCycleCount);
 text("disk-capacity",gb(d.diskCapacityGb));
 text("available-capacity",gb(d.availableCapacityGb));
 text("storage-percent",pct(d.availableCapacityPercent));
 setRing("battery-ring",d.batteryHealthPercent,"battery");
 setRing("storage-ring",d.availableCapacityPercent,"storage");
 var act=String(d.activationStatus||"").toLowerCase(),jb=String(d.jailbreakStatus||"").toLowerCase();
 mark("activation-status",/^(yes|activated|true)/.test(act)?"good":/^(no|not|false|unactivated)/.test(act)?"warn":"");
 mark("jailbreak-status",/^(no|false|not)/.test(jb)?"good":/^(yes|true|detected)/.test(jb)?"bad":"");
 [["id-lock-status",d.idLockStatus],["icloud-status",d.icloudStatus]].forEach(function(p){
  var v=String(p[1]||"");
  mark(p[0],/\b(off|disabled|clean|clear)\b/i.test(v)?"good":/\b(on|enabled|locked|lost)\b/i.test(v)?"warn":"");
 });
}
function renderSteps(order){
 var host=document.getElementById("status-steps");
 var status=String(order.status||"").toLowerCase();
 var d=order.deviceDetails||{};
 var label=String(order.statusLabel||"");
 var stage=Number(d.progressStep)||0;
 if(/requesting server response for bypass/i.test(label))stage=5;
 if(!stage){stage=status==="submitted"?1:status==="registered"?2:status==="processing"?5:status==="completed"?5:0;}
 if(status==="rejected")stage=0;
 var items=[
  ["Device connected","Your iPhone was detected and its device details were collected."],
  ["Backend approved","The backend approved the device for the requested service."],
  ["Backend requested payment","The service was approved and payment was requested."],
  ["Payment successful","Your payment was received successfully."],
  ["Requesting server response for bypass","414Unlock is waiting for the service backend to respond."]
 ];
 host.textContent="";
 items.forEach(function(item,index){
  var li=document.createElement("li");
  var marker=document.createElement("span");
  marker.className="step-check";
  marker.textContent=index+1<stage||status==="completed"?"✓":String(index+1);
  var content=document.createElement("div");
  var strong=document.createElement("strong");strong.textContent=item[0];
  var small=document.createElement("small");small.textContent=item[1];
  content.appendChild(strong);content.appendChild(small);
  if(index+1<stage||status==="completed")li.className="done";
  else if(index+1===stage)li.className="current";
  li.appendChild(marker);li.appendChild(content);host.appendChild(li);
 });
 text("progress-label",stage===5&&status!=="completed"?"Step 5 of 5 · Awaiting backend":"Step "+(stage||"—")+" of 5");
}
function render(order){
 errorPanel.hidden=true;
 var status=String(order.status||"").toLowerCase();
 var label=order.statusLabel||"Status update";
 var awaitingBypass=/requesting server response for bypass/i.test(label);
 badge.className="status-badge "+(awaitingBypass?"awaiting-response":status);
 badge.textContent=label;
 document.getElementById("update-banner").dataset.state=awaitingBypass?"awaiting-response":(status||"pending");
 title.textContent=order.deviceModel||"iPhone device report";
 var paymentCycle=summary.querySelector(".cycle-payment"),bypassCycle=summary.querySelector(".cycle-bypass");
 if(paymentCycle)paymentCycle.textContent="PAYMENT SUCCESSFUL";
 if(bypassCycle){bypassCycle.textContent="REQUESTING SERVER RESPONSE FOR BYPASS";bypassCycle.hidden=!awaitingBypass;}
 summary.setAttribute("aria-label",awaitingBypass?"Payment successful. Requesting server response for bypass.":(order.statusMessage||"Your service status has been updated."));
 text("request-reference","414Unlock service request");
 text("request-created",dateText(order.createdAt));
 var processing=!!order.processedAt,completed=status==="completed"&&!!order.completedAt;
 document.getElementById("processing-detail").hidden=!processing;
 document.getElementById("completed-detail").hidden=!completed;
 if(processing)text("processing-started",dateText(order.processedAt));
 if(completed)text("completed-date",dateText(order.completedAt));
 renderDetails(order);
 renderSteps(order);
 updated.textContent="Last updated · "+dateText(order.updatedAt??order.updated_at??order.lastUpdated??order.createdAt);
}
async function load(){
 if(!api){showError("The 414Unlock status service is not configured.");return;}
 if(!/^[a-f0-9]{64}$/i.test(token)){showError("This tracking link is incomplete or invalid.");return;}
 refresh.disabled=true;refresh.innerHTML='<span class="btn-icon" aria-hidden="true">↻</span><span class="btn-label">Loading…</span>';
 try{
  var response=await fetch(api+"/api/public/unlock-status",{method:"POST",headers:{Accept:"application/json","Content-Type":"text/plain;charset=UTF-8","Cache-Control":"no-cache"},body:token,cache:"no-store"});
  var data={};try{data=await response.json();}catch(_){}
  if(!response.ok)throw new Error(data.message||"This tracking link could not be found.");
  if(!data.order)throw new Error("No device report was returned for this link.");
  render(data.order);
 }catch(error){showError(error.message||"The status service is temporarily unavailable. Try again shortly.");}
 finally{document.body.classList.remove("is-loading");refresh.disabled=false;refresh.innerHTML='<span class="btn-icon" aria-hidden="true">↻</span><span class="btn-label">Refresh</span>';}
}
refresh.addEventListener("click",load);
load();
})();