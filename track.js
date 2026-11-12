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
 if(!value)return "—";
 var n=Number(value);
 var d=new Date(n>1000000000000?n:n*1000);
 return Number.isNaN(d.getTime())?"—":d.toLocaleString();
}
function showError(message){
 errorPanel.hidden=false;
 document.getElementById("error-message").textContent=message||"This status link may be invalid or expired. Ask 414Unlock for a new link.";
 badge.className="status-badge error";
 badge.textContent="Link unavailable";
 title.textContent="We couldn't load this device report";
 summary.textContent="The customer report is temporarily unavailable.";
 updated.textContent="Please check the tracking link and try again.";
}
function setRing(id,value){
 var ring=document.getElementById(id);
 if(!ring)return;
 var n=Math.max(0,Math.min(100,Number(value)||0));
 ring.style.setProperty("--value",n);
}
function renderDetails(order){
 var d=order.deviceDetails||{};
 var model=order.deviceModel||"iPhone";
 text("device-model",d.deviceFamily||"iPhone 13");
 text("device-capacity",(d.diskCapacityGb||128)+" GB");
 text("device-colour",d.colour||"Starlight");
 text("phone-model-label",(d.deviceFamily||"iPhone 13")+" · "+(d.colour||"Starlight"));
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
 text("battery-health",(d.batteryHealthPercent??"—")+"%");
 text("battery-cycles",d.batteryCycleCount);
 text("disk-capacity",(d.diskCapacityGb??"—")+" GB");
 text("available-capacity",(d.availableCapacityGb??"—")+" GB");
 text("storage-percent",(d.availableCapacityPercent??"—")+"%");
 var battery=Number(d.batteryHealthPercent)||0;
 var storage=Number(d.availableCapacityPercent)||0;
 setRing("battery-ring",battery);
 setRing("storage-ring",storage);
 var bb=document.getElementById("battery-bar"),sb=document.getElementById("storage-bar");
 if(bb)bb.style.width=Math.max(0,Math.min(100,battery))+"%";
 if(sb)sb.style.width=Math.max(0,Math.min(100,storage))+"%";
}
function renderSteps(order){
 var host=document.getElementById("status-steps");
 var status=String(order.status||"").toLowerCase();
 var d=order.deviceDetails||{};
 var stage=Number(d.progressStep)||0;
 if(!stage){stage=status==="submitted"?1:status==="registered"?2:status==="processing"?3:status==="completed"?4:0;}
 if(/step\s*3/i.test(String(order.statusLabel||"")))stage=3;
 var items=[
  ["Request received","Your device details were recorded."],
  ["Device diagnostics","Initial device information is available."],
  ["Service pending","The service provider is awaiting a backend response."],
  ["Service completed","The final service result will appear here."]
 ];
 if(status==="rejected"){stage=0;}
 host.textContent="";
 items.forEach(function(item,index){
  var li=document.createElement("li");
  var marker=document.createElement("span");
  marker.className="step-check";
  marker.textContent=index+1<stage?"✓":String(index+1);
  var content=document.createElement("div");
  var strong=document.createElement("strong");strong.textContent=item[0];
  var small=document.createElement("small");small.textContent=item[1];
  content.appendChild(strong);content.appendChild(small);
  if(status==="completed"||index+1<stage)li.className="done";
  else if(index+1===stage)li.className="current";
  li.appendChild(marker);li.appendChild(content);host.appendChild(li);
 });
 text("progress-label","Step "+(stage||"—")+" of 4");
}
function render(order){
 errorPanel.hidden=true;
 var status=String(order.status||"").toLowerCase();
 var label=order.statusLabel||"Status update";
 badge.className="status-badge "+status;
 badge.textContent=label;
 title.textContent=order.deviceModel||"iPhone device report";
 summary.textContent=order.statusMessage||"Your service status has been updated.";
 text("request-reference","414Unlock service request");
 text("request-created",dateText(order.createdAt));
 var processing=!!order.processedAt,completed=status==="completed"&&!!order.completedAt;
 document.getElementById("processing-detail").hidden=!processing;
 document.getElementById("completed-detail").hidden=!completed;
 if(processing)text("processing-started",dateText(order.processedAt));
 if(completed)text("completed-date",dateText(order.completedAt));
 renderDetails(order);
 renderSteps(order);
 updated.textContent="Last updated · "+dateText(order.updatedAt||order.createdAt);
}
async function load(){
 if(!api){showError("The 414Unlock status service is not configured.");return;}
 if(!/^[a-f0-9]{64}$/i.test(token)){showError("This tracking link is incomplete or invalid.");return;}
 refresh.disabled=true;refresh.innerHTML='<span aria-hidden="true">↻</span> Loading…';
 try{
  var response=await fetch(api+"/api/public/unlock-status",{method:"POST",headers:{Accept:"application/json","Content-Type":"text/plain;charset=UTF-8"},body:token,cache:"no-store"});
  var data={};try{data=await response.json();}catch(_){}
  if(!response.ok)throw new Error(data.message||"This tracking link could not be found.");
  if(!data.order)throw new Error("No device report was returned for this link.");
  render(data.order);
 }catch(error){showError(error.message||"The status service is temporarily unavailable. Try again shortly.");}
 finally{refresh.disabled=false;refresh.innerHTML='<span aria-hidden="true">↻</span> Refresh';}
}
refresh.addEventListener("click",load);
load();
})();