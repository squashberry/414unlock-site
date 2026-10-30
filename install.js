(function(){
"use strict";
var button=document.getElementById("install-action"),note=document.getElementById("install-instructions"),promptEvent=null,installed=false;
var ua=navigator.userAgent||"",ios=/iPhone|iPad|iPod/i.test(ua)||(/Macintosh/i.test(ua)&&navigator.maxTouchPoints>1),android=/Android/i.test(ua),mobile=ios||android||(/Mobile/i.test(ua)&&navigator.maxTouchPoints>0),standalone=window.matchMedia("(display-mode: standalone)").matches||navigator.standalone===true;
function openApp(){location.href="./mobile.html";}
function register(){if("serviceWorker" in navigator)navigator.serviceWorker.register("./pwa-sw.js",{scope:"./"}).catch(function(){});}
register();
if(!mobile){
 note.textContent="You need a mobile device to install this app. Open this page on an iPhone or Android phone.";
 button.textContent="Mobile device required";button.disabled=true;
 return;
}
if(standalone){
 note.textContent="414Unlock Mobile is already installed on this device.";
 button.textContent="Open 414Unlock Mobile";button.addEventListener("click",openApp);return;
}
if(ios){
 note.textContent="On iPhone or iPad, tap the Share button in Safari, choose “Add to Home Screen”, then tap Add. This is the iOS installation step.";
 button.textContent="App is ready — Add to Home Screen";
 button.addEventListener("click",function(){note.textContent="Open Safari’s Share menu, select “Add to Home Screen”, and confirm Add. After installing, open 414Unlock from your Home Screen.";button.textContent="I’ve added it — Open App";button.onclick=openApp;});
 return;
}
window.addEventListener("beforeinstallprompt",function(event){event.preventDefault();promptEvent=event;button.disabled=false;note.textContent="This phone can install 414Unlock. Tap the button below and confirm the browser’s install prompt.";});
window.addEventListener("appinstalled",function(){installed=true;promptEvent=null;note.textContent="414Unlock has been added to your Home Screen.";button.textContent="Open 414Unlock Mobile";button.onclick=openApp;});
button.addEventListener("click",async function(){
 if(installed||standalone){openApp();return;}
 if(promptEvent){
  var event=promptEvent;promptEvent=null;try{await event.prompt();var result=await event.userChoice;if(result&&result.outcome==="accepted"){note.textContent="App installation accepted. Open 414Unlock from your Home Screen.";button.textContent="Open 414Unlock Mobile";button.onclick=openApp;}else{note.textContent="Installation was cancelled. You can try again using your browser’s Install app option.";}}catch(_){note.textContent="Use your browser menu and choose Install app or Add to Home Screen.";}return;
 }
 note.textContent="Open your browser menu (⋮) and choose “Install app” or “Add to Home screen”. If the option is missing, open this page in Chrome.";
});
})();