'use strict';
const $=id=>document.getElementById(id);
const overlay=new URLSearchParams(location.search).get('overlay')==='1';
if(overlay)document.body.classList.add('overlay');
let token='',online=false,busy=false,units=[],status=null,pending=null,catalogTime=0;
const names={intro:'介绍 / 定身',running:'交战中',ended:'比赛结束',error:'需要处理'};
const winners={blue:'蓝队胜',red:'红队胜',draw:'同时全灭'};
const number=n=>Number(n||0).toLocaleString('zh-CN',{maximumFractionDigits:0});
function message(text,error=false){$('message').textContent=text;$('message').classList.toggle('error',error);}
function aggroControls(){
  const v=status?.game?.values||{};
  const supported=['true','false'].includes(v.bvb_player_aggro);
  const requested=v.bvb_player_aggro==='true';
  const ready=requested&&v.spectator_enabled==='false'&&v.spectator_flag_readback==='true'&&
    v.spectator_pending_flags==='0'&&v.spectator_pending_relations==='0';
  const camera=v.arena_free_camera==='true';
  $('player-aggro').textContent=requested?'恢复拍摄无仇恨':'开启主角仇恨';
  $('player-aggro').disabled=!online||busy||!supported||(camera&&!requested);
  $('player-opponent').disabled=!online||busy||camera||!ready||v.bvb_state!=='intro'||!$('unit').value;
  $('aggro-status').textContent=!online?'等待读档':!supported?'请加载新版 Mod':camera?'自由镜头保护中':requested?
    (ready?'主角可被锁定':'等候主角仇恨资格和关系恢复'):'拍摄模式';
}
function controls(){aggroControls();document.querySelectorAll('[data-action],#spawn-button').forEach(b=>b.disabled=!online||busy);window.bvbEditor?.status(online,busy,status?.game?.values||{});}
function render(s){
  status=s;token=s.csrf_token||token;online=Boolean(s.game&&s.game.online&&s.game.values&&s.game.values.game_ready==='true'&&String(s.game.values.build||'').startsWith('PhantomBZ_BvB'));
  const v=s.game?.values||{};
  $('connection').textContent=online?'游戏已连接 · '+(v.build||''):'等待游戏 / 读取存档';
  $('phase').textContent=online?(winners[v.bvb_winner]||names[v.bvb_state]||'等待摄影棚'):'等待读档';
  const seconds=Math.floor(Number(v.bvb_seconds||0));$('timer').textContent=String(Math.floor(seconds/60)).padStart(2,'0')+':'+String(seconds%60).padStart(2,'0');
  for(const team of ['blue','red']){
    const hp=Number(v[`bvb_${team}_hp`]||0),max=Number(v[`bvb_${team}_max`]||0),unknown=Number(v[`bvb_${team}_unknown`]||0);
    $(team+'-value').textContent=!online||unknown?'读数待确认':`${number(hp)} / ${number(max)}`;
    $(team+'-bar').value=online&&!unknown&&max>0?Math.max(0,Math.min(1,hp/max)):0;
    $(team+'-detail').textContent=online?`本体存活 ${v[`bvb_${team}_alive`]||0} / ${v[`bvb_${team}_count`]||0}${unknown?' · 状态未知 '+unknown:''}`:'等待重新连接';
  }
  const commands=[...(s.queue||[])].reverse();
  if(!pending){const inflight=commands.find(c=>['queued','pending'].includes(c.status));if(inflight){pending=inflight.id;busy=true;}}
  $('history').replaceChildren(...commands.slice(0,8).map(c=>{const li=document.createElement('li');li.textContent=`#${c.id} ${c.action} · ${c.status||c.state} · ${c.message||''}`;return li;}));
  if(pending){const c=commands.find(x=>x.id===pending);if(c&&['succeeded','failed','uncertain','expired','cancelled'].includes(c.status||c.state)){
    message(c.message||c.status,(c.status||c.state)!=='succeeded');pending=null;busy=false;
  }}
  controls();
}
function filter(){const query=$('search').value.trim().toLowerCase(),selected=$('unit').value;
  const list=units.filter(u=>!u.excluded&&`${u.display_name||u.name||''} ${u.id}`.toLowerCase().includes(query));
  $('unit').replaceChildren(...list.map(u=>{const opt=document.createElement('option');opt.value=u.id;opt.textContent=u.display_name||u.name||u.id;return opt;}));
  if(list.some(u=>u.id===selected))$('unit').value=selected;
  if(!list.length){const opt=document.createElement('option');opt.value='';opt.textContent=units.length?'没有匹配的单位':'等待游戏图鉴';$('unit').append(opt);}
  window.bvbEditor?.selection();
}
async function send(action,extra={}){
  if(busy||!online)return;busy=true;controls();message('正在提交，等待游戏回执…');
  try{const r=await fetch('/api/command',{method:'POST',headers:{'Content-Type':'application/json','X-CSRF-Token':token},body:JSON.stringify({action,...extra})});const data=await r.json();if(!r.ok)throw Error(data.error||'提交失败');pending=data.id;message(`操作 #${pending} 已排队；尚未确认完成。`);}
  catch(e){message(e.message,true);busy=false;controls();}
}
document.querySelectorAll('[data-action]').forEach(b=>b.addEventListener('click',()=>send(b.dataset.action)));
$('search').addEventListener('input',filter);
$('spawn-button').addEventListener('click',()=>{const id=$('unit').value;if(id)send('spawn',{unit_id:id,team:$('team').value,count:Number($('count').value)});});
$('player-aggro').addEventListener('click',()=>{
  const requested=status?.game?.values?.bvb_player_aggro==='true';
  send(requested?'bvb_aggro_off':'bvb_aggro_on');
});
$('player-opponent').addEventListener('click',()=>{
  if($('unit').value&&$('spawn-form').reportValidity())
    send('spawn',{unit_id:$('unit').value,team:'neutral',count:Number($('count').value)});
});
window.bvbEditor?.connect(send);
async function poll(){
  try{const r=await fetch('/api/status',{cache:'no-store'});if(!r.ok)throw Error('状态读取失败');render(await r.json());
    if(!overlay&&Date.now()-catalogTime>10000){catalogTime=Date.now();const c=await fetch('/api/catalog',{cache:'no-store'});if(c.ok){const catalog=await c.json();units=catalog.units||[];filter();window.bvbEditor?.catalog(units,catalog);}}
  }catch(e){online=false;controls();$('connection').textContent='面板连接中断';$('phase').textContent='连接中断';for(const t of ['blue','red']){$(t+'-value').textContent='读数待确认';$(t+'-bar').value=0;}message('连接中断；未确认操作不会自动重发。'+e.message,true);}
  setTimeout(poll,500);
}
poll();
