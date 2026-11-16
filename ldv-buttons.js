/* LDV action buttons v3.59. Navigation, tabs, close and icon-only controls retain their own styling. */
(()=>{'use strict';
const paths={
 save:'M19 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11l5 5v11a2 2 0 0 1-2 2ZM17 21v-8H7v8M7 3v5h8',
 delete:'M3 6h18M8 6V4h8v2m3 0-1 15H6L5 6m5 4v7m4-7v7',
 edit:'M12 20h9M16.5 3.5a2.12 2.12 0 0 1 3 3L9 17l-4 1 1-4Z',
 add:'M12 5v14M5 12h14',
 upload:'M12 16V3m-5 5 5-5 5 5M4 17v3a1 1 0 0 0 1 1h14a1 1 0 0 0 1-1v-3',
 download:'M12 3v13m-5-5 5 5 5-5M4 18v2a1 1 0 0 0 1 1h14a1 1 0 0 0 1-1v-2',
 search:'M21 21l-4.3-4.3M19 11a8 8 0 1 1-16 0 8 8 0 0 1 16 0Z',
 back:'M15 18l-6-6 6-6',
 reset:'M3 12a9 9 0 1 0 3-6.7M3 3v6h6',
 check:'M20 6 9 17l-5-5',
 image:'M3 3h18v18H3zM8.5 10a1.5 1.5 0 1 0 0-3 1.5 1.5 0 0 0 0 3ZM3 17l5-5 4 4 3-3 6 6',
 generic:'M5 12h14m-6-6 6 6-6 6'
};
const admin=/admin\.html(?:$|[?#])/.test(location.pathname);
function excluded(b){
 if(b.closest('.nav,.quick-grid,.ldv-admin-tabs,[role="tablist"],.section-head,.header-home,.refresh-button,.participant-dialog-top,.profile-close,.ldv-admin-auth-links'))return true;
 if(b.matches('[role="tab"],[aria-label="Stäng"],[aria-label="Öppna Min profil"],[aria-label="Uppdatera appen"],.profile-close,.header-home,.refresh-button'))return true;
 if(b.id==='ldv-header-profile'||b.id==='ldv-logo-refresh'||b.classList.contains('nav'))return true;
 const t=(b.textContent||'').trim();
 return !t||t==='×'||t==='✕'||t.length>65;
}
function decorate(b){
 if(b.dataset.ldvActionReady||excluded(b))return;
 if(!admin&&!b.matches('.btn,[type="submit"],[type="reset"],#ldv-photo-reset,#ldv-myprofile-save-top,#ldv-myprofile-save-bottom,.danger')&&!b.closest('#min-profil,#minprofil,#ldv-myprofile-photo-dialog,.profile-actions,.avatar-editor,#ldv-myprofile-form'))return;
 const t=(b.textContent||'').trim().toLocaleLowerCase('sv');
 const danger=b.matches('.danger,[data-danger]')||/^(radera|ta bort|avlägsna)/.test(t);
 let type=danger?'delete':/spara|bekräfta/.test(t)?'save':/redigera|justera|ändra/.test(t)?'edit':/lägg till|skapa|ny deltagare/.test(t)?'add':/ladda upp|välj fil/.test(t)?'upload':/exportera|ladda ner/.test(t)?'download':/sök|jämför/.test(t)?'search':/tillbaka|avbryt/.test(t)?'back':/rensa|återställ/.test(t)?'reset':/bild|foto/.test(t)?'image':/importera|logga in|skicka/.test(t)?'check':'generic';
 const svg=document.createElementNS('http://www.w3.org/2000/svg','svg');
 svg.setAttribute('viewBox','0 0 24 24');svg.setAttribute('width','18');svg.setAttribute('height','18');svg.setAttribute('fill','none');svg.setAttribute('stroke','currentColor');svg.setAttribute('stroke-width','2');svg.setAttribute('stroke-linecap','round');svg.setAttribute('stroke-linejoin','round');svg.setAttribute('aria-hidden','true');svg.classList.add('ldv-action-icon');
 const path=document.createElementNS('http://www.w3.org/2000/svg','path');path.setAttribute('d',paths[type]);svg.append(path);
 b.classList.add('ldv-action-button');if(danger)b.classList.add('ldv-action-danger');
 if(!b.querySelector('svg,.lucide,[class*="icon"],img'))b.prepend(svg);b.dataset.ldvActionReady='1';
}
let scheduled=false;
function scan(){scheduled=false;document.querySelectorAll('button,input[type="button"],input[type="submit"],input[type="reset"]').forEach(b=>{if(b.tagName==='BUTTON')decorate(b)})}
function schedule(){if(scheduled)return;scheduled=true;requestAnimationFrame(scan)}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',()=>{scan();new MutationObserver(schedule).observe(document.body,{childList:true,subtree:true})});
else{scan();new MutationObserver(schedule).observe(document.body,{childList:true,subtree:true})}
})();
