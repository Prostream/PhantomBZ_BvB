package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Match=require('stat_match')
local Fields={'Attack','ShachiAttack','Resistance_Physical','Health_Max','Shachi_Max'}
local function harness()
    local h={files={},writes={},snapshots=0,logs={}}
    local fs={open=function(name,mode)
        if mode=='w' and h.failSave then return nil end
        if mode=='r' and not h.files[name] then return nil end
        local text=h.files[name] or ''
        return {read=function()return text end,write=function(_,s)text=s;return true end,
            close=function()if mode=='w' then h.files[name]=text end;return true end}
    end}
    function h:actor(hp,shachi,attack)
        local actor={values={},mods={}}
        for field,value in pairs({Health=hp,Health_Max=hp,Shachi=shachi,Shachi_Max=shachi,Attack=attack,ShachiAttack=15,Resistance_Physical=0.2})do
            actor.values[field]={base=value,current=value}
        end
        return actor
    end
    local adapter={}
    function adapter:read(actor,field)
        local v=actor.values[field]
        return v and {base=v.base,current=v.current} or nil,'missing '..field
    end
    function adapter:snapshot(actor)
        h.snapshots=h.snapshots+1
        local result={}
        for field,v in pairs(actor.values)do result[field]={base=v.base,current=v.current}end
        return result
    end
    function adapter:writeBase(actor,field,value)
        h.writes[#h.writes+1]={actor=actor,field=field,value=value}
        local mod=actor.mods[field] or {}
        if field=='Health' then value=math.min(value,actor.values.Health_Max.current)end
        if field=='Shachi' then value=math.min(value,actor.values.Shachi_Max.current)end
        actor.values[field]={base=value,current=mod.fixed or value*(mod.mul or 1)+(mod.add or 0)}
        if field=='Health_Max' and actor.values.Health.current>value then actor.values.Health.current=value;actor.values.Health.base=value end
        if field=='Shachi_Max' and actor.values.Shachi.current>value then actor.values.Shachi.current=value;actor.values.Shachi.base=value end
        return true
    end
    function adapter:nativeValue(actor,field)
        if h.failNative then return nil end
        return actor.values[field].current
    end
    h.options={path='memory',io=fs,adapter=adapter,fields=Fields,log=function(s)h.logs[#h.logs+1]=s end}
    h.match=Match.new(h.options);return h
end
local count=0
local function test(name,fn)fn();count=count+1;print('PASS '..name)end
test('default off, persisted switch, immutable first-spawn snapshot and full new resources',function()
    local h=harness();local a=h:actor(100,80,20);local b=h:actor(300,200,60)
    assert(h.match:onSpawn(a,'A').ok and h.snapshots==0 and #h.writes==0)
    assert(h.match:toggle().ok and h.match:onSpawn(a,'A').baseline)
    a.values.Health.current=30;a.values.Attack.current=100
    assert(h.match:onSpawn(b,'B').applied)
    assert(b.values.Health.current==100 and b.values.Shachi.current==80 and b.values.Attack.current==20)
    assert(a.values.Health.current==30 and a.values.Attack.current==100,'matching cannot mutate the baseline actor')
    local writes=#h.writes;b.values.Health.current=75
    h.match:roster({a,b});assert(#h.writes==writes and b.values.Health.current==75,'no periodic healing')
    local reloaded=Match.new(h.options);assert(reloaded:status().enabled and reloaded:status().baseline_unit=='','only switch persists')
end)
test('active multipliers are compensated without permanent override effects',function()
    local h=harness();h.match:toggle();h.match:onSpawn(h:actor(100,80,20),'A')
    local b=h:actor(100,80,10);b.mods.Attack={mul=2,add=5};b.values.Attack.current=25
    assert(h.match:onSpawn(b,'B').applied and math.abs(b.values.Attack.base-7.5)<0.0001 and b.values.Attack.current==20)
end)
test('unchanged base with a scaled current value uses a bounded calibration',function()
    local h=harness();h.match:toggle();h.match:onSpawn(h:actor(100,80,70),'A')
    local b=h:actor(100,80,70);b.mods.Attack={mul=1.2};b.values.Attack.current=84
    assert(h.match:onSpawn(b,'B').applied and math.abs(b.values.Attack.current-70)<0.001)
    local writes=0;for _,item in ipairs(h.writes)do if item.field=='Attack' then writes=writes+1 end end
    assert(writes<=3)
end)
test('clear resets the baseline; partial cleanup and switch-off do not rewrite actors',function()
    local h=harness();h.match:toggle();local a=h:actor(100,80,20);h.match:onSpawn(a,'A')
    h.match:roster({a});assert(h.match:status().baseline_unit=='A')
    h.match:roster({});assert(h.match:status().baseline_unit=='')
    local b=h:actor(200,150,45);assert(h.match:onSpawn(b,'B').baseline)
    h.match:toggle();local writes=#h.writes
    local c=h:actor(300,90,60);assert(h.match:onSpawn(c,'C').ok and #h.writes==writes and c.values.Health.current==300)
end)
test('unreachable native override fails and restores the original base',function()
    local h=harness();h.match:toggle();h.match:onSpawn(h:actor(100,80,20),'A')
    local b=h:actor(300,200,60);b.mods.Attack={fixed=90};b.values.Attack.current=90
    local result=h.match:onSpawn(b,'B')
    assert(not result.ok and result.rollback_verified and b.values.Attack.base==60 and b.values.Attack.current==90)
    assert(h.match:status().matched==0)
end)
test('failed independent readback restores maxima before restoring clamped resources',function()
    local h=harness();h.match:toggle();h.match:onSpawn(h:actor(100,80,20),'A')
    local b=h:actor(300,200,60);h.failNative=true
    local result=h.match:onSpawn(b,'B')
    assert(not result.ok and result.rollback_verified,'all modified values must roll back')
    assert(b.values.Health.current==300 and b.values.Shachi.current==200)
end)
test('failed settings readback cannot enable matching',function()
    local h=harness();h.failSave=true
    assert(not h.match:toggle().ok and not h.match:status().enabled)
end)
print('stat_match: PASS ('..count..' lifecycle, calibration and rollback regressions)')
