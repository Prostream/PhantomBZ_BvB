(function(){
  'use strict';
  const el=id=>document.getElementById(id),model=window.BVBRoster,key='PhantomBZ_BvB.lineup.v1';
  let rows=[],units=[],game={},online=false,busy=false,send=null,savedLocal=false,edited=false;
  function note(text,error=false){el('draft-note').textContent=text;el('draft-note').classList.toggle('error',error);}
  try{const stored=localStorage.getItem(key);if(stored){rows=model.validate(JSON.parse(stored));savedLocal=true;}}
  catch(e){note('本机草稿无法读取：'+e.message,true);}
  function remember(){
    edited=true;
    try{localStorage.setItem(key,JSON.stringify(rows));note('草稿已保存到本机；尚未应用到游戏。');}
    catch(e){note('草稿暂存在当前页面；浏览器未允许保存，刷新可能丢失。',true);}
    render();
  }
  function unitName(id){const u=units.find(x=>x.id===id);return u?.display_name||u?.name||id.split('.').pop().replace(/_C$/,'');}
  function available(id){return units.some(u=>u.id===id&&u.spawnable!==false);}
  function render(){
    for(const team of ['blue','red']){
      const members=rows.map((r,index)=>({...r,index})).filter(r=>r.team===team);
      el('draft-'+team+'-count').textContent=members.length+' 人';
      const children=members.map((r,slot)=>{
        const li=document.createElement('li'),name=document.createElement('strong'),buttons=document.createElement('div');
        name.textContent=(slot+1)+'. '+unitName(r.unit_id);name.title=r.unit_id;
        if(!available(r.unit_id)){const hint=document.createElement('small');hint.textContent='目录待确认 / 暂不可召唤';name.append(hint);}
        buttons.className='roster-buttons';
        for(const [action,label] of [['up','↑'],['down','↓'],['replace','替换'],['swap',team==='blue'?'→ 红队':'→ 蓝队'],['duplicate','复制'],['remove','删除']]){
          const b=document.createElement('button');b.type='button';b.textContent=label;
          b.setAttribute('aria-label',`${unitName(r.unit_id)} ${label}`);
          b.disabled=busy||(action==='up'&&slot===0)||(action==='down'&&slot===members.length-1)||(action==='replace'&&!available(el('unit').value));
          b.addEventListener('click',()=>{try{rows=model.edit(rows,action,r.index,el('unit').value);remember();}catch(e){note(e.message,true);}});
          buttons.append(b);
        }
        li.append(name,buttons);return li;
      });
      if(!children.length){const p=document.createElement('li');p.className='empty-lineup';p.textContent='还没有成员，从上方选择角色加入';children.push(p);}
      el('draft-'+team).replaceChildren(...children);
    }
    controls();
  }
  function controls(){
    el('add-lineup').disabled=busy||!available(el('unit').value);
    for(const id of ['draft-swap','draft-clear','draft-import','draft-preset'])el(id).disabled=busy;
    const both=rows.some(r=>r.team==='blue')&&rows.some(r=>r.team==='red');
    el('apply-lineup').disabled=!online||busy||game.bvb_editor_version!=='1'||game.bvb_state==='running'||!both||rows.some(r=>!available(r.unit_id));
    el('apply-lineup').title=game.bvb_editor_version!=='1'?'需要更新 Mod 并重新启动游戏':game.bvb_state==='running'?'请先结束或清场，再应用阵容':!both?'两队各至少一名参赛者':'';
  }
  async function importSaved(automatic=false){
    try{
      const r=await fetch('/api/bvb-lineup',{cache:'no-store'});if(!r.ok)throw Error('无法读取保存阵容');const data=await r.json();
      if(automatic&&(edited||savedLocal))return;
      if(!data.available){if(!automatic)note('游戏还没有已保存的阵容。');return;}
      rows=model.validate(data.rows);remember();note('已将游戏保存名单读入草稿；未改动场上角色。');
    }catch(e){if(!automatic)note(e.message,true);}
  }
  el('spawn-form').addEventListener('submit',e=>{
    e.preventDefault();if(busy)return;
    const id=el('unit').value,count=Number(el('count').value),team=el('team').value;
    try{
      if(!available(id))throw Error('请先选择可用单位');
      if(!Number.isInteger(count)||count<1||count>16)throw Error('一次添加数量为 1 至 16');
      rows=model.validate([...rows,...Array.from({length:count},()=>({team,unit_id:id}))]);remember();
    }catch(e){note(e.message,true);}
  });
  el('unit').addEventListener('change',render);
  el('draft-clear').addEventListener('click',()=>{rows=[];remember();});
  el('draft-swap').addEventListener('click',()=>{rows=rows.map(r=>({...r,team:r.team==='blue'?'red':'blue'}));remember();});
  el('draft-import').addEventListener('click',()=>importSaved());
  el('draft-preset').addEventListener('click',()=>{try{rows=model.fromPreset(units);remember();}catch(e){note(e.message,true);}});
  el('apply-lineup').addEventListener('click',()=>{if(!el('apply-lineup').disabled&&send)send('bvb_apply',{rows:model.validate(rows)});});
  let lastControlState='';
  window.bvbEditor={
    connect(fn){send=fn;},
    catalog(list,meta){units=list;el('catalog-note').textContent=list.length?`${list.length} 个单位 · ${meta.source==='game_codex'?'来自游戏已导出图鉴':'来自游戏目录'} · 可搜索后加入名单`:'尚无游戏图鉴。进入地图后刷新游戏图鉴，再等待列表出现。';render();},
    selection(){render();},
    status(isOnline,isBusy,values){online=isOnline;busy=isBusy;game=values;const state=[online,busy,game.bvb_editor_version,game.bvb_state].join('|');if(state!==lastControlState){lastControlState=state;render();}else controls();}
  };
  render();if(!savedLocal)importSaved(true);
})();
