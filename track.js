(function(){
"use strict";
var cfg=window.UNLOCK414_CONFIG||{},api=String(cfg.API_BASE_URL||"").replace(/\/+$/,""),token=String(location.hash||"").replace(/^#/,"")||new URLSearchParams(location.search).get("token")||"";
var badge=document.getElementById("status-badge"),title=document.getElementById("status-title"),summary=document.getElementById("status-summary"),details=document.getElementById("device-details"),steps=document.getElementById("status-steps"),updated=document.getElementById("last-updated"),refresh=document.getElementById("refresh-status");
function dateText(value){if(!value)return "—";try{return new Date(Number(value)*1000).toLocaleString();}catch(_){return "—";}}
function showError(message){badge.className="badge error";badge.textContent="Link unavailable";title.textContent="We can't retrieve this unlock status";summary.textContent=message||"This status link may be invalid, expired or replaced. Ask the person who shared it for a new link.";details.hidden=true;steps.hidden=true;updated.hidden=true;}
function render(order){
var status=String(order.status||"").toLowerCase(),label=order.statusLabel||"Status update";
badge.className="badge "+status;badge.textContent=label.toUpperCase();
var messages={submitted:"Your unlock request has been received. The service provider has not started processing it yet.",registered:"Your device has been registered for service. The next update will appear here.",processing:"Your device unlock is currently being processed. Check back for the final result.",completed:"The service provider has confirmed that your device was successfully unlocked.",rejected:"The service provider marked this request as unable to complete. Contact the person who shared this link if you need more information."};
title.textContent=status==="completed"?"Your device was successfully unlocked":status==="rejected"?"This unlock could not be completed":label;
summary.textContent=messages[status]||"Your device status has been updated.";
document.getElementById("device-model").textContent=order.deviceModel||"iPhone";
document.getElementById("device-identifier").textContent=order.maskedIdentifier||"Protected";
details.hidden=false;
steps.textContent="";
var names=[["submitted","Request received"],["registered","Registered"],["processing","Unlock in progress"],["completed","Successfully unlocked"]];
if(status==="rejected"){steps.hidden=true;}else{
var current=names.findIndex(function(x){return x[0]===status;});steps.hidden=false;
names.forEach(function(item,index){var li=document.createElement("li");li.textContent=item[1];if(status==="completed"||index<current)li.className="done";else if(index===current)li.className="current";steps.appendChild(li);});
}
updated.hidden=false;updated.textContent="Last updated: "+dateText(order.updatedAt||order.createdAt)+(status==="completed"&&order.completedAt?" · Completed: "+dateText(order.completedAt):"");
}
async function load(){
if(!api){showError("The 414Unlock status service is not configured.");return;}
if(!/^[a-f0-9]{64}$/i.test(token)){showError("The customer status link is incomplete or invalid.");return;}
refresh.disabled=true;refresh.textContent="Refreshing…";
try{
var response=await fetch(api+"/api/public/unlock-status",{method:"POST",headers:{Accept:"application/json","Content-Type":"text/plain;charset=UTF-8"},body:token,cache:"no-store"});
var data={};try{data=await response.json();}catch(_){}
if(!response.ok)throw new Error(data.message||"This status link is invalid, expired or has been replaced.");
if(!data.order)throw new Error("No unlock status was returned for this link.");
render(data.order);
}catch(error){showError(error.message||"The status service is temporarily unavailable. Try again shortly.");}
finally{refresh.disabled=false;refresh.textContent="Refresh status";}
}
refresh.addEventListener("click",load);
load();
})();