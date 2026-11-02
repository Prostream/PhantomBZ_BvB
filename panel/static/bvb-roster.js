/* Pure draft operations shared by the browser and offline tests. */
(function(root){
  'use strict';
  const preset=[['blue','BP_Monster_GuiChai_Red'],['blue','BP_Monster_GuiChai_Yellow_MoDao'],['blue','BP_Monster_GuiChai_Yellow_ShuangGou'],['blue','BP_Monster_GuiChai_Cyan_ShuangYue'],['red','BP_Monster_BiYuan'],['red','BP_Monster_CanQu_BiHai'],['red','BP_Monster_WuLengShuang'],['red','BP_Monster_YuBi']];
  const path=/^\/[A-Za-z0-9_/]+\.[A-Za-z0-9_]+_C$/;
  function validate(rows){
    if(!Array.isArray(rows)||rows.length>100||rows.some(r=>!r||!['blue','red'].includes(r.team)||typeof r.unit_id!=='string'||r.unit_id.length>512||!path.test(r.unit_id)))throw Error('阵容草稿格式无效');
    return rows.map(r=>({team:r.team,unit_id:r.unit_id}));
  }
  function edit(rows,action,index,unit){
    const next=validate(rows),r=next[index];
    if(!r)throw Error('名单条目不存在');
    if(action==='remove')next.splice(index,1);
    else if(action==='swap')r.team=r.team==='blue'?'red':'blue';
    else if(action==='replace'){r.unit_id=unit;}
    else if(action==='duplicate')next.splice(index+1,0,{...r});
    else if(action==='up'||action==='down'){
      const indices=next.map((v,i)=>v.team===r.team?i:-1).filter(i=>i>=0);
      const other=indices[indices.indexOf(index)+(action==='up'?-1:1)];
      if(other!==undefined)[next[index],next[other]]=[next[other],next[index]];
    }else throw Error('未知名单操作');
    return validate(next);
  }
  function fromPreset(units){return preset.map(([team,id])=>{
    const matches=units.filter(u=>u.id.endsWith('.'+id+'_C'));
    if(matches.length!==1)throw Error('图鉴尚未找到唯一角色：'+id);
    return {team,unit_id:matches[0].id};
  });}
  const api={validate,edit,fromPreset};
  if(typeof module==='object'&&module.exports)module.exports=api;else root.BVBRoster=api;
})(typeof window==='undefined'?globalThis:window);
