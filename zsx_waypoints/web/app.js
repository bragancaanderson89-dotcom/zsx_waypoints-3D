(() => {
  'use strict';
  const $=id=>document.getElementById(id), panel=$('panel'), marker=$('destination');
  const inGame=typeof GetParentResourceName==='function';
  const resource=inGame?GetParentResourceName():'zsx_waypoints';
  let defaults={road:true,destination:true,color:'#278bff',spacing:8,opacity:.65,lift:.12,scale:1};
  let settings={...defaults}, hsv={h:212,s:.847,v:1}, timer=0, pending=null, busy=null, closing=false;
  const clamp=(n,lo,hi)=>Math.min(hi,Math.max(lo,n));
  async function post(action,data={}) {
    if(!inGame)return {ok:true};
    const response=await fetch(`https://${resource}/${action}`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(data)});
    if(!response.ok)throw new Error('NUI');
    return response.json();
  }
  function flush(){
    if(busy)return busy;
    busy=(async()=>{
      try{while(pending){const data=pending;pending=null;await post('settings',data)}$('status').textContent=''}
      catch{ $('status').textContent='Não foi possível salvar. Tente ajustar novamente.' }
    })().finally(()=>{busy=null});
    return busy;
  }
  function save(){pending={...settings};clearTimeout(timer);timer=setTimeout(flush,70)}
  function hexToHsv(hex){
    const rgb=[1,3,5].map(i=>parseInt(hex.slice(i,i+2),16)/255),[r,g,b]=rgb;
    const max=Math.max(...rgb),min=Math.min(...rgb),d=max-min;
    let h=0;if(d)h=max===r?((g-b)/d)%6:max===g?(b-r)/d+2:(r-g)/d+4;
    return {h:(h*60+360)%360,s:max?d/max:0,v:max};
  }
  function hsvToHex({h,s,v}){
    const f=n=>{const k=(n+h/60)%6;return v-v*s*Math.max(0,Math.min(k,4-k,1))};
    return '#'+[f(5),f(3),f(1)].map(n=>Math.round(n*255).toString(16).padStart(2,'0')).join('');
  }
  function paintColor(){
    document.documentElement.style.setProperty('--route',settings.color);
    document.documentElement.style.setProperty('--hue',`hsl(${hsv.h},100%,50%)`);
    $('color-cursor').style.left=`${hsv.s*100}%`;$('color-cursor').style.top=`${(1-hsv.v)*100}%`;
    $('saturation').setAttribute('aria-valuenow',Math.round(hsv.s*100));
    $('saturation').setAttribute('aria-valuetext',`Saturação ${Math.round(hsv.s*100)}%, brilho ${Math.round(hsv.v*100)}%`);
    $('hex').value=settings.color.toUpperCase();$('hue').value=hsv.h;
  }
  function paint(){
    $('road').checked=settings.road;$('destination-enabled').checked=settings.destination;
    for(const key of ['spacing','opacity','lift','scale']){
      const node=$(key);node.value=settings[key];node.style.setProperty('--fill',`${(settings[key]-Number(node.min))/(Number(node.max)-Number(node.min))*100}%`);
    }
    $('spacing-value').value=`${settings.spacing.toFixed(1)} m`;
    $('opacity-value').value=`${Math.round(settings.opacity*100)}%`;
    $('lift-value').value=`${settings.lift.toFixed(2)} m`;
    $('scale-value').value=`${settings.scale.toFixed(2)}×`;
    paintColor();
  }
  for(const key of ['spacing','opacity','lift','scale'])$(key).addEventListener('input',e=>{settings[key]=Number(e.target.value);paint();save()});
  $('road').addEventListener('change',e=>{settings.road=e.target.checked;save()});
  $('destination-enabled').addEventListener('change',e=>{settings.destination=e.target.checked;save()});
  $('hue').addEventListener('input',e=>{hsv.h=Number(e.target.value);settings.color=hsvToHex(hsv);paintColor();save()});
  $('hex').addEventListener('change',e=>{
    if(/^#[0-9a-f]{6}$/i.test(e.target.value)){settings.color=e.target.value;hsv=hexToHsv(settings.color);save()}paintColor();
  });
  const sat=$('saturation');
  function pointer(e){const r=sat.getBoundingClientRect();hsv.s=clamp((e.clientX-r.left)/r.width,0,1);hsv.v=1-clamp((e.clientY-r.top)/r.height,0,1);settings.color=hsvToHex(hsv);paintColor();save()}
  sat.addEventListener('pointerdown',e=>{sat.setPointerCapture(e.pointerId);pointer(e)});
  sat.addEventListener('pointermove',e=>{if(sat.hasPointerCapture(e.pointerId))pointer(e)});
  sat.addEventListener('pointerup',e=>{if(sat.hasPointerCapture(e.pointerId))sat.releasePointerCapture(e.pointerId)});
  sat.addEventListener('keydown',e=>{
    if(!['ArrowLeft','ArrowRight','ArrowUp','ArrowDown'].includes(e.key))return;e.preventDefault();
    hsv.s=clamp(hsv.s+(e.key==='ArrowRight'?.02:e.key==='ArrowLeft'?-.02:0),0,1);
    hsv.v=clamp(hsv.v+(e.key==='ArrowUp'?.02:e.key==='ArrowDown'?-.02:0),0,1);
    settings.color=hsvToHex(hsv);paintColor();save();
  });
  async function close(){
    if(closing)return;closing=true;
    clearTimeout(timer);await flush();
    try{await post('close');panel.hidden=true}catch{$('status').textContent='Tente fechar novamente.'}finally{closing=false}
  }
  $('close').addEventListener('click',close);
  document.addEventListener('keydown',e=>{if(e.key==='Escape'&&!panel.hidden){e.preventDefault();close()}});
  $('reset').addEventListener('click',()=>{settings={...defaults};hsv=hexToHsv(settings.color);paint();save()});
  let markerFrame=0, markerData=null;
  function drawMarker(){
    markerFrame=0;
    const data=markerData;
    if(!data || marker.hidden)return;
    marker.style.left='0';marker.style.top='0';
    marker.style.transform=`translate3d(${data.x*window.innerWidth}px,${data.y*window.innerHeight}px,0) translate(-50%,-100%)`;
    marker.style.setProperty('--stem',`${Math.max(0,(Number(data.bottom)-data.y)*window.innerHeight)}px`);
  }
  window.addEventListener('message' ,({data})=>{
    if(!data||typeof data!=='object')return;
    if(data.action==='open'){
      settings={...defaults,...data.settings};defaults={...defaults,...data.defaults};hsv=hexToHsv(settings.color);paint();panel.hidden=false;$('close').focus();
    }else if(data.action==='close'){panel.hidden=true}
    else if(data.action==='marker'){
      marker.hidden=data.visible!==true;
      if(marker.hidden)return;
      if(!Number.isFinite(data.x)||!Number.isFinite(data.y)||!Number.isFinite(data.distance)){marker.hidden=true;return}
      markerData=data;
      if(!markerFrame)markerFrame=requestAnimationFrame(drawMarker);
      $('distance').textContent=data.distance>=1000?(data.distance/1000).toFixed(1):String(Math.round(data.distance));
      $('unit').textContent=data.distance>=1000?'KM':'M';$('destination-label').textContent=data.label||'DESTINO';
    }
  });
  // Browser preview is opt-in and never displayed by the FiveM NUI page.
  if(!inGame&&new URLSearchParams(location.search).has('preview')){paint();panel.hidden=false}
  post('ready').catch(()=>{});
})();
