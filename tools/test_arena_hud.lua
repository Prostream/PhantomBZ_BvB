package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local HUD=require('arena_hud')
local function object(id)
    return {alive=true,IsValid=function(self)return self.alive end,GetAddress=function(self)assert(self.alive);return id end}
end
local blue,red=object(1),object(2);blue.hp=100;red.hp=80
local created,removed,updates=0,0,{}
local renderer={}
function renderer:create(unit)
    created=created+1;return {widget=object(100+created),actor=unit.actor}
end
function renderer:update(record,unit,hp,maximum,title,row)
    if record.actor~=unit.actor then return false,'fixture rebind' end
    updates[#updates+1]={hp=hp,maximum=maximum,title=title,row=row}
    return {visible=true,health=true,names=true,numbers=true}
end
function renderer:remove(record)removed=removed+1;record.widget.alive=false;return true end
function renderer:syncNative(desired,privateKeys)self.desired=desired;self.privateKeys=privateKeys end
local hud=HUD.new({renderer=renderer,isBoss=function()return true end,hp=function(a)return a.hp end,
    maxHP=function()return 100 end,getName=function(unit)return unit.team=='blue' and '甲' or '乙' end})
local members={{actor=blue,team='blue',class_path='blue'},{actor=red,team='red',class_path='red'}}
hud:sync(members)
assert(created==2 and hud:status().visible==2 and hud:status().numbers_verified==2)
assert(updates[1].title=='蓝队 · 甲' and updates[2].title=='红队 · 乙')
hud:sync(members);assert(created==2,'unchanged bars must be retained')
blue.hp=23.5;hud:sync(members);assert(updates[#updates-1].hp==23.5)
hud.records['1'].actor=red
hud:sync(members);assert(hud:status().pending==1 and removed==1,'foreign binding must retire the private record')
hud:sync(members);assert(created==3 and hud:status().visible==2,'a lost binding must rebuild without hijacking the foreign actor')
blue.hp=0;hud:sync(members);assert(hud:status().visible==1 and hud.records['1']==nil,'dead units hide immediately')
hud:clear(true);assert(hud:status().visible==0 and next(hud.records)==nil and next(renderer.desired)==nil)
local calls=0
local failed=HUD.new({isBoss=function()return true end,hp=function()return 10 end,maxHP=function()return 10 end,
    renderer={create=function()calls=calls+1;return nil,'fixture failure' end,remove=function()return true end,syncNative=function()end}})
for _=1,20 do failed:sync(members)end
assert(calls==6,'failed construction must be bounded per actor')
failed:clear();failed:sync(members);assert(calls==8,'manual cleanup resets failed registration attempts')
print('arena_hud: PASS (independent ownership, rebind recovery, real HP/max, dead hide, bounded creation, cleanup)')
