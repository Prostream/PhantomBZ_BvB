-- Spawn level: a map NPC comes out of its area's AI spawner, which sets the character's own `Level`
-- property (BP_RenewalNPC.hpp, a double next to MobGroup and Spawner) before the character starts.
-- A summoned unit skips the spawner and keeps Level 0; the player found summoned bosses taking damage
-- like mobs while the map's own NPCs were normal. v0.36.5 raised the Level *attribute* after
-- activation and nothing changed (docs/REVERSE_ENGINEERING.md), so now the property is written
-- before FinishSpawn, the way the spawner would, to the highest Level among the map's own NPCs near
-- the player. It is never lowered. After activation the unit and that map NPC are logged side by side
-- (property, GetCombatLevel, the Level attribute, health and defence attributes) to show what the
-- level changes. v0.36.7 confirmed it: a summoned 阿花 written to 18 came out with 104652 HP instead
-- of 9000, and the player found it normal. The last level found is remembered and saved, so a summon
-- where no map NPC is loaded (an empty field, right after a load) still gets the area's level.
local U=require('ue_observe')
local Stats=require('character_stats')
local Level={}
local RADIUS=20000       -- cm around the player whose map NPCs count; all loaded ones when none are that close
local CACHE=5            -- seconds the scan is reused, so a batch of summons scans the map once
local EPS=0.01
local HEADER='SpawnLevelV1\t'
-- Read side by side after activation.
local COMPARE={'Level','Health_Max','Attack','Shachi_Max','ShachiAttack','Resistance_Physical',
    'TakenReductionMultiplier_Physical','TakenVulnerabilityMultiplier_Physical','TakenAdditiveMultiplier_Physical',
    'Resistance_Poise','Resistance_DefenceShachi','TakenReductionMultiplier_DefenceShachi'}

local function num(v)return type(v)=='number' and v==v and v or nil end
local function short(actor)
    local ok,cls=pcall(function()return actor:GetClass():GetFName():ToString()end)
    return ok and type(cls)=='string' and cls:gsub('_C$','') or '?'
end
local function fmt(v)return v and string.format('%.2f',v) or 'nil' end

function Level.new(options)
    local log=options.log or function()end
    local clock=options.clock or os.clock
    local stats=options.attributes or Stats.new()
    local fs=options.io or io
    local self={raised=0,kept=0,failures=0,message=''}
    local cached
    -- The last map level found: {level=, name=}, read from and written to Runtime/spawn-level.tsv.
    local saved=options.path and options.path..'/spawn-level.tsv'
    local last
    if saved then
        local file=fs.open(saved,'r')
        if file then
            local text=file:read('*a');file:close()
            local level,name=(type(text)=='string' and text or ''):match('^SpawnLevelV1\t([%d%.]+)\t([^\t\n]*)\n$')
            level=tonumber(level)
            if level and level>0 then last={level=level,name=name} end
        end
    end
    local function remember(entry)
        if last and math.abs(last.level-entry.level)<=EPS and last.name==entry.name then return end
        last={level=entry.level,name=entry.name}
        local file=saved and fs.open(saved,'w')
        if not file then return end
        file:write(HEADER..string.format('%.2f',entry.level)..'\t'..entry.name..'\n');file:close()
    end
    local references={}    -- summoned unit key -> the map NPC its level came from, for the after-activation log
    local function say(m)log('[SpawnLevel] '..m)end
    local function property(actor)return num(U.field(actor,'Level'))end
    local function combatLevel(actor)
        if not U.valid(actor) then return nil end
        local ok,value=pcall(function()return actor:GetCombatLevel()end)
        return ok and num(U.unwrap(value)) or nil
    end
    -- The map's own NPCs with a Level property, preferring those near the player; the highest one wins.
    local function mapLevel()
        if cached and clock()-cached.at<CACHE then return cached end
        local ours=options.ours and options.ours() or {}
        local player=options.getPlayer and options.getPlayer()
        local origin=U.valid(player) and options.getLocation and options.getLocation(player) or nil
        local near,all={}, {}
        for _,pawn in ipairs(options.collect and options.collect() or {})do
            local key=U.key(pawn)
            local level=key and not ours[key] and property(pawn)
            if level then
                local entry={actor=pawn,name=short(pawn),level=level}
                all[#all+1]=entry
                local at=origin and options.getLocation(pawn)
                if at then
                    local dx,dy,dz=at.X-origin.X,at.Y-origin.Y,at.Z-origin.Z
                    if dx*dx+dy*dy+dz*dz<=RADIUS*RADIUS then near[#near+1]=entry end
                end
            end
        end
        local pool=#near>0 and near or all
        local best
        for _,entry in ipairs(pool)do if not best or entry.level>best.level then best=entry end end
        if best then remember(best) end
        local sample={}
        for i=1,math.min(10,#pool)do sample[#sample+1]=pool[i].name..'='..string.format('%.0f',pool[i].level) end
        cached={at=clock(),best=best,count=#pool,scope=#near>0 and '玩家附近' or '已加载地图',sample=table.concat(sample,',')}
        return cached
    end
    -- Before FinishSpawn.
    function self:prepare(actor,unitPath)
        local own=property(actor)
        if own==nil then
            self.kept=self.kept+1;self.message='该单位没有等级字段'
            say('跳过 unit='..tostring(unitPath)..'：没有 Level 字段')
            return {applied=false}
        end
        local area=mapLevel()
        local key=U.key(actor)
        if key and area.best then references[key]=area.best.actor end
        say(string.format('出生前 unit=%s 自身等级=%s %s地图怪=%d只 最高=%s(%s) 样本=[%s]',tostring(unitPath),fmt(own),
            area.scope,area.count,area.best and fmt(area.best.level) or 'nil',area.best and area.best.name or '-',area.sample))
        local target=area.best and area.best.level
        if not target and last then
            target=last.level
            say(string.format('附近没有地图怪，沿用上次记录的等级 %s（来自 %s）',fmt(last.level),tostring(last.name)))
        end
        if not target then self.kept=self.kept+1;self.message='附近没有地图怪可参照';return {applied=false} end
        if target<=own+EPS then
            self.kept=self.kept+1;self.message='召唤单位等级不低于地图怪，未调整'
            say('不调整：自身等级已不低于地图怪')
            return {applied=false}
        end
        local ok,err=pcall(function()actor.Level=target end)
        local after=property(actor)
        local good=ok and after and math.abs(after-target)<=EPS
        if good then self.raised=self.raised+1;self.message='已按地图怪等级生成' else self.failures=self.failures+1;self.message='等级写入未读回' end
        say(string.format('写入等级 %s→%s 调用=%s 读回=%s %s',fmt(own),fmt(target),tostring(ok),fmt(after),err and ('错误='..tostring(err)) or ''))
        return {applied=good}
    end
    local function describe(actor)
        local parts={'等级字段='..fmt(property(actor)),'战斗等级='..fmt(combatLevel(actor))}
        for _,field in ipairs(COMPARE)do
            local entry=stats:read(actor,field)
            parts[#parts+1]=field..'='..(entry and fmt(entry.current) or 'nil')
        end
        return table.concat(parts,' ')
    end
    -- After activation: the unit next to the map NPC it took its level from (or the best one found now).
    function self:verify(actor)
        if not U.valid(actor) then return end
        local key=U.key(actor)
        local reference=key and references[key]
        if key then references[key]=nil end
        say('出生后 召唤 '..short(actor)..' '..describe(actor))
        reference=U.valid(reference) and reference or (mapLevel().best or {}).actor
        if U.valid(reference) then say('出生后 对照地图怪 '..short(reference)..' '..describe(reference)) end
        return U.valid(reference) and reference or nil
    end
    function self:status()return {raised=self.raised,kept=self.kept,failures=self.failures,message=self.message}end
    return self
end
return Level
