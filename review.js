(function(){
var cfg=window.UNLOCK414_CONFIG||{},api=(cfg.API_BASE_URL||"").replace(/\/+$/,""),token=sessionStorage.getItem("414unlock_token"),list=document.getElementById("list"),message=document.getElementById("message");
function show(t,type){message.textContent=t;message.className="message show "+(type||"info");}
async function req(path,opts){var r=await fetch(api+path,opts||{}),d={};try{d=await r.json();}catch(_){}if(!r.ok)throw new Error(d.message||d.error||("Request failed ("+r.status+")"));return d;}
async function load(){
 if(!api||api.includes("YOUR_")||!token){show("The review API is not configured or you are not signed in.","error");return;}
 try{
  var d=await req("/api/admin/submissions",{headers:{"Authorization":"Bearer "+token}}),items=d.submissions||[];
  if(!items.length){list.textContent="No pending applications.";return;}
  items.forEach(function(x){
   var card=document.createElement("article");card.className="review-item";
   var h=document.createElement("h3");h.textContent=x.legalName+" · "+x.applicantType;
   var p=document.createElement("p");p.textContent="Application "+x.id+" · "+x.email+" · Submitted "+x.submittedAt;
   var note=document.createElement("input");note.placeholder="Optional reviewer note";note.maxLength=500;note.className="field";note.style.width="100%";note.style.minHeight="40px";
   var actions=document.createElement("div");actions.className="review-actions";
   var view=document.createElement("button");view.textContent="View private document";
   view.addEventListener("click",async function(){
    var tab=window.open("about:blank","_blank");
    if(!tab){show("Allow pop-ups for this page to view the document.","error");return;}
    tab.document.write("<title>Loading private document</title><p style='font-family:sans-serif;padding:24px'>Loading secured document…</p>");
    try{var response=await fetch(api+"/api/admin/submissions/"+encodeURIComponent(x.id)+"/document",{headers:{"Authorization":"Bearer "+token}});
     if(!response.ok)throw new Error("Could not open document ("+response.status+").");
     var blob=await response.blob(),objectUrl=URL.createObjectURL(blob);tab.location=objectUrl;setTimeout(function(){URL.revokeObjectURL(objectUrl);},60000);
    }catch(err){tab.close();show(err.message||"Unable to open document.","error");}
   });actions.appendChild(view);
   ["approve","reject"].forEach(function(action){
    var b=document.createElement("button");b.textContent=action==="approve"?"Approve":"Reject";if(action==="approve")b.className="approve";
    b.addEventListener("click",async function(){b.disabled=true;try{await req("/api/admin/submissions/"+encodeURIComponent(x.id)+"/review",{method:"POST",headers:{"Authorization":"Bearer "+token,"Content-Type":"application/json"},body:JSON.stringify({decision:action,note:note.value.trim()})});card.remove();show("Application "+action+"d. Document storage was cleared after review.","success");}catch(e){show(e.message,"error");b.disabled=false;}});
    actions.appendChild(b);
   });
   card.appendChild(h);card.appendChild(p);card.appendChild(note);card.appendChild(actions);list.appendChild(card);
  });
 }catch(e){show(e.message||"Unable to load review queue.","error");}
}
load();
})();