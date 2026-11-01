package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Level=require('spawn_level')
local address=0
-- A character with the BP_RenewalNPC Level property (nil level: a class without it).
local function object(name,level,at,attrs)
    address=address+1;local a=address
    return {IsValid=function()return true end,GetAddress=function()return a end,Level=level,at=at,attrs=attrs or {},
        GetCombatLevel=function(self)return self.Level end,
        GetClass=function()return {GetFName=function()return {ToString=function()return name..'_C' end}end}end}
end
local function harness(npcs,files)
    local h={lines={},scans=0,clock=0,files=files or {}}
    h.io={open=function(path,mode)
        if mode=='r' and h.files[path]==nil then return nil end
        local text=h.files[path] or ''
        return {read=function()return text end,write=function(_,s)text=s;return true end,
            close=function()if mode=='w' then h.files[path]=text end;return true end}
    end}
    h.stats={read=function(_,actor,field)
        local v=actor.attrs[field];return v and {base=v,current=v} or nil
    end}
    h.player=object('BP_RenewalPlayer',nil,{X=0,Y=0,Z=0})
    h.npcs=npcs
    h.ours={}
    h.level=Level.new({log=function(s)h.lines[#h.lines+1]=s end,attributes=h.stats,clock=function()return h.clock end,
        path='R',io=h.io,
        getPlayer=function()return h.player end,getLocation=function(a)return a.at end,
        collect=function()h.scans=h.scans+1;return h.npcs end,ours=function()return h.ours end})
    function h.all()return table.concat(h.lines,'\n')end
    return h
end

-- Before FinishSpawn: written up to the highest Level among nearby map NPCs; ours and far ones don't count.
do
    local summoned=object('BP_Monster_MoTian',0,{X=0,Y=0,Z=0},{Health_Max=12000})
    local other=object('BP_Monster_MoTian',30,{X=100,Y=0,Z=0})
    local mob=object('Mob_B',15,{X=5000,Y=0,Z=0},{Level=15,Health_Max=3000})
    local h=harness({object('Mob_A',12,{X=1000,Y=0,Z=0}),mob,object('Far_Boss',40,{X=900000,Y=0,Z=0}),other})
    h.ours[tostring(other.GetAddress())]=true
    local r=h.level:prepare(summoned,'MoTian')
    assert(r.applied and summoned.Level==15,h.all())
    assert(h.all():find('玩家附近地图怪=2只 最高=15.00(Mob_B)',1,true),h.all())
    assert(h.all():find('写入等级 0.00→15.00 调用=true 读回=15.00',1,true),h.all())
    -- After activation the unit is logged next to the map NPC its level came from.
    summoned.attrs={Level=15,Health_Max=30000}
    h.level:verify(summoned)
    assert(h.all():find('出生后 召唤 BP_Monster_MoTian 等级字段=15.00 战斗等级=15.00 Level=15.00 Health_Max=30000.00',1,true),h.all())
    assert(h.all():find('出生后 对照地图怪 Mob_B 等级字段=15.00',1,true),h.all())
    -- A second summon in the same batch reuses the scan.
    local second=object('BP_Monster_MoTian',0,{X=0,Y=0,Z=0})
    h.level:prepare(second,'MoTian')
    assert(second.Level==15 and h.scans==1 and h.level:status().raised==2)
end

-- Never lowered; no Level property or nothing to compare with leaves the unit as it is.
do
    local h=harness({object('Mob',20,{X=10,Y=0,Z=0})})
    local strong=object('Boss',50,{X=0,Y=0,Z=0})
    assert(not h.level:prepare(strong,'Boss').applied and strong.Level==50 and h.all():find('不调整',1,true))
    local plain=object('Actor',nil,{X=0,Y=0,Z=0})
    assert(not h.level:prepare(plain,'Actor').applied and plain.Level==nil)
    local lonely=harness({})
    local unit=object('Unit',0,{X=0,Y=0,Z=0})
    assert(not lonely.level:prepare(unit,'Unit').applied and unit.Level==0)
    assert(lonely.level:status().message=='附近没有地图怪可参照')
    local far=harness({object('Far',25,{X=900000,Y=0,Z=0})})
    local unit2=object('Unit',0,{X=0,Y=0,Z=0})
    far.level:prepare(unit2,'Unit')
    assert(unit2.Level==25 and far.all():find('已加载地图地图怪=1只',1,true),far.all())
end

-- A write the actor refuses is a failure, not a raise.
do
    local h=harness({object('Mob',20,{X=10,Y=0,Z=0})})
    local stuck=setmetatable({},{__index=object('Unit',0,{X=0,Y=0,Z=0}),__newindex=function()end})
    assert(not h.level:prepare(stuck,'Unit').applied)
    assert(h.level:status().failures==1 and h.level:status().raised==0)
end

-- The last level found is remembered and saved: a summon with no map NPC loaded uses it, also after a reload.
do
    local h=harness({object('Mob_A',18,{X=10,Y=0,Z=0})})
    local first=object('Unit',0,{X=0,Y=0,Z=0})
    h.level:prepare(first,'Unit')
    assert(first.Level==18 and h.files['R/spawn-level.tsv']=='SpawnLevelV1\t18.00\tMob_A\n',h.files['R/spawn-level.tsv'])
    h.npcs={};h.clock=10
    local second=object('Unit',0,{X=0,Y=0,Z=0})
    assert(h.level:prepare(second,'Unit').applied and second.Level==18)
    assert(h.all():find('附近没有地图怪，沿用上次记录的等级 18.00（来自 Mob_A）',1,true),h.all())
    local reloaded=harness({},h.files)
    local third=object('Unit',0,{X=0,Y=0,Z=0})
    assert(reloaded.level:prepare(third,'Unit').applied and third.Level==18,reloaded.all())
    -- A new area found later replaces it.
    local moved=harness({object('Mob_C',6,{X=10,Y=0,Z=0})},h.files)
    local fourth=object('Unit',0,{X=0,Y=0,Z=0})
    moved.level:prepare(fourth,'Unit')
    assert(fourth.Level==6 and h.files['R/spawn-level.tsv']=='SpawnLevelV1\t6.00\tMob_C\n')
    -- A damaged file is ignored.
    local broken=harness({},{['R/spawn-level.tsv']='junk'})
    local fifth=object('Unit',0,{X=0,Y=0,Z=0})
    assert(not broken.level:prepare(fifth,'Unit').applied and fifth.Level==0)
end
print('spawn_level ok')
