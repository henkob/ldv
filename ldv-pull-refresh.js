/* LDV v3.70 – dra nedåt för att uppdatera (mobil/PWA). */
(()=>{'use strict';
 if(!('ontouchstart' in window)&&navigator.maxTouchPoints===0)return;
 const threshold=82,maxPull=128;
 let startY=0,startX=0,pull=0,tracking=false,triggered=false;
 const indicator=document.createElement('div');
 indicator.id='ldv-pull-refresh';
 indicator.setAttribute('role','status');
 indicator.setAttribute('aria-live','polite');
 indicator.innerHTML='<span class="ldv-pull-spinner" aria-hidden="true">↻</span><span class="ldv-pull-text">Dra ned för att uppdatera</span>';
 const css=document.createElement('style');
 css.textContent=`
 #ldv-pull-refresh{position:fixed;z-index:10000;top:calc(env(safe-area-inset-top) + 10px);left:50%;transform:translate(-50%,-130px);opacity:0;pointer-events:none;display:flex;align-items:center;gap:9px;padding:11px 16px;border-radius:999px;background:#111a67;color:white;font:700 14px Arial,sans-serif;box-shadow:0 8px 24px #06134155;transition:transform .15s,opacity .15s;white-space:nowrap}
 #ldv-pull-refresh .ldv-pull-spinner{font-size:23px;line-height:1}
 #ldv-pull-refresh.ldv-visible{opacity:1}
 #ldv-pull-refresh.ldv-loading{transform:translate(-50%,0)!important}
 #ldv-pull-refresh.ldv-loading .ldv-pull-spinner{animation:ldv-pull-spin .7s linear infinite}
 @keyframes ldv-pull-spin{to{transform:rotate(360deg)}}
 `;
 document.head.append(css);document.body.append(indicator);
 const text=indicator.querySelector('.ldv-pull-text');
 const top=()=>Math.max(document.scrollingElement?.scrollTop||0,window.scrollY||0)<=1;
 const blocked=target=>!!target?.closest?.('dialog[open],.modal.open,[role="dialog"],input,textarea,select,[contenteditable="true"]');
 const reset=()=>{tracking=false;pull=0;indicator.classList.remove('ldv-visible');indicator.style.transform='translate(-50%,-130px)'};
 document.addEventListener('touchstart',e=>{
  if(triggered||e.touches.length!==1||!top()||blocked(e.target)){tracking=false;return}
  const t=e.touches[0];startY=t.clientY;startX=t.clientX;pull=0;tracking=true;
 },{passive:true});
 document.addEventListener('touchmove',e=>{
  if(!tracking||triggered||e.touches.length!==1)return;
  const t=e.touches[0],dy=t.clientY-startY,dx=t.clientX-startX;
  if(!top()||dy<0||Math.abs(dx)>Math.abs(dy)*1.1){reset();return}
  if(dy<12)return;
  pull=Math.min(maxPull,dy*.55);
  indicator.classList.add('ldv-visible');
  indicator.style.transform='translate(-50%,'+(pull-130)+'px)';
  text.textContent=pull>=threshold?'Släpp för att uppdatera':'Dra ned för att uppdatera';
 },{passive:true});
 document.addEventListener('touchend',()=>{
  if(!tracking)return;
  if(pull<threshold){reset();return}
  tracking=false;triggered=true;
  indicator.classList.add('ldv-loading','ldv-visible');
  indicator.style.transform='translate(-50%,0)';
  text.textContent='Uppdaterar …';
  const url=new URL(location.href);
  url.searchParams.set('v',String(Date.now()));
  location.replace(url.href);
 },{passive:true});
 document.addEventListener('touchcancel',reset,{passive:true});
})();
