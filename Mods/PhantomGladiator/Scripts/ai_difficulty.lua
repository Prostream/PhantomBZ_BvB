-- Per-unit AI difficulty. The game's AI asks "is the difficulty at least X" through two blueprint
-- checks, both `GetDifficulty() >= self.Difficulty` (docs/REVERSE_ENGINEERING.md v0.32.1/v0.33.0):
--   AICondition_AboveDifficulty_C.EvaluateCondition(AIController)  shared ability-pool condition
--   BTDecorator_AboveDifficulty_C.PerformConditionCheckAI(OwnerController, ControlledPawn)
-- Both call UPBZBlueprintFunctionLibrary.GetDifficulty(ContextObject).
-- For a unit this app summoned at a chosen difficulty, the hooks answer with that unit's level:
-- the checks return `level >= Difficulty`, and GetDifficulty returns the level when its context
-- belongs to the unit. UE4SS turns a callback's non-nil return value into the function's return value;
-- nil keeps the game's answer. The player, map enemies and the world keep the game's difficulty.
-- Verified in game (v0.33.1): a value returned from the GetDifficulty *pre* callback becomes the result;
-- the post callback runs too but never sees a usable context, so it stays empty. Nothing is written.
local U=require('ue_observe')
local AI={}
local LIBRARY='/Script/ProjectPBZ.PBZBlueprintFunctionLibrary'
local DEFAULT='/Script/ProjectPBZ.Default__PBZBlueprintFunctionLibrary'
local FUNCTIONS={'GetDifficulty','GetDiffcultMode'}
local VALUES={Handicapped=0,Easy=1,Normal=2,Hard=3,Nightmare=4} -- EDifficultMode
-- Blueprint checks: the hook's single callback runs after the function; `subject` picks the argument
-- that names the AI being checked.
local CHECKS={
    {name='EvaluateCondition',path='/PBZCombatAsset/Prototypes/AI/AICondition_AboveDifficulty.AICondition_AboveDifficulty_C:EvaluateCondition',
        subject=function(controller)return controller end,call=function(node,controller)return node:EvaluateCondition(controller)end},
    {name='PerformConditionCheckAI',path='/PBZCombatAsset/Prototypes/AI/BTDecorator_AboveDifficulty.BTDecorator_AboveDifficulty_C:PerformConditionCheckAI',
        subject=function(controller,pawn)return pawn or controller end,call=function(node,controller,pawn)return node:PerformConditionCheckAI(controller,pawn)end},
}
local MAX_LINES=50
AI.values=VALUES
AI.checks=CHECKS

local function fname(object)
    local ok,name=pcall(function()return object:GetFName():ToString()end)
    return ok and type(name)=='string' and name or '?'
end
local function className(object)
    if not U.valid(object) then return 'invalid' end
    local ok,class=pcall(function()return object:GetClass()end)
    return ok and U.valid(class) and fname(class) or '?'
end
local function show(v)
    v=U.unwrap(v)
    if type(v)=='number' then return string.format('%.6g',v) end
    if v==nil or type(v)=='boolean' or type(v)=='string' then return tostring(v) end
    if U.valid(v) then return fname(v) end
    local ok,s=pcall(function()return v:ToString()end)
    return ok and type(s)=='string' and s or U.kind(v)
end

function AI.new(options)
    local log=options.log or function()end
    local clock=options.clock or os.time
    local self={state='idle',alive=true,overrides=0,verified=0,failed=0,message='还没有按所选难度召唤的单位',
        calls={},answers={}}
    local hooks,cache,logged,lines,counts,checked,installed,samples={},{},{},0,{},{},{},{}
    local summarizedAt,summarizedCount
    local function say(m)log('[AIDifficulty] '..m)end
    local function note(signature,message)
        counts[signature]=(counts[signature] or 0)+1
        if not logged[signature] and lines<MAX_LINES then logged[signature]=true;lines=lines+1;say(message)end
    end
    local function bump(t,k)t[k]=(t[k] or 0)+1 end

    -- The unit a context object belongs to, walking outers and asking controllers for their pawn.
    -- Cached per address until the next tick, so a burst of calls costs one walk.
    local function resolve(object)
        local key=U.key(object)
        if not key then return nil end
        local hit=cache[key]
        if hit then return hit end
        local level
        local current=object
        for _=1,8 do
            if not U.valid(current) then break end
            level=options.levelOfKey(U.key(current))
            if level then break end
            local okPawn,pawn=pcall(function()return current:K2_GetPawn()end)
            if okPawn and U.valid(pawn) then
                level=options.levelOfKey(U.key(pawn))
                if level then break end
            end
            local okOuter,outer=pcall(function()return current:GetOuter()end)
            if not okOuter then break end
            current=outer
        end
        hit={level=level,class=className(object)}
        cache[key]=hit
        return hit
    end

    local function difficultyCallback(name,phase)
        return function(_,contextObject)
            if not self.alive or self.state~='running' then return nil end
            bump(self.calls,name..'.'..phase)
            local hit=resolve(U.unwrap(contextObject))
            local value=hit and hit.level and VALUES[hit.level]
            if value==nil then return nil end
            self.overrides=self.overrides+1
            note(name..'|'..phase..'|'..hit.class..'|'..hit.level,'改写 '..name..'('..phase..') 上下文='..hit.class..' → '..hit.level..'('..value..')')
            return value
        end
    end

    local function checkCallback(spec)
        return function(context,...)
            if not self.alive or self.state~='running' then return nil end
            bump(self.calls,spec.name)
            local args=table.pack(...)
            local node=U.unwrap(context)
            if not logged['args|'..spec.name] then
                local kinds={}
                for i=1,args.n do kinds[#kinds+1]=i..'='..U.kind(args[i])..':'..show(args[i])end
                note('args|'..spec.name,'检查节点参数 '..spec.name..' 节点='..className(node)..' '..table.concat(kinds,' '))
            end
            local subject=spec.subject(U.unwrap(args[1]),U.unwrap(args[2]))
            local hit=resolve(subject)
            local threshold=tonumber((U.field(node,'Difficulty')))
            if not hit or not hit.level or not threshold then return nil end
            local answer=VALUES[hit.level]>=threshold
            self.overrides=self.overrides+1
            bump(self.answers,spec.name..' 门槛='..threshold..' → '..tostring(answer))
            samples[spec.name]=samples[spec.name] or {node=node,args={U.unwrap(args[1]),U.unwrap(args[2])},threshold=threshold,level=hit.level}
            note(spec.name..'|'..threshold..'|'..hit.level,'改写 '..spec.name..' 单位='..hit.class..'/'..hit.level..' 门槛='..threshold..' → '..tostring(answer))
            return answer
        end
    end

    local function register(path,label,pre,post)
        local okFind,found=pcall(StaticFindObject,path)
        if not okFind or not U.valid(found) then return false end
        local ok,preId,postId
        if post then ok,preId,postId=pcall(RegisterHook,path,pre,post) else ok,preId,postId=pcall(RegisterHook,path,pre) end
        if ok and type(preId)=='number' and type(postId)=='number' then
            hooks[#hooks+1]={path=path,pre=preId,post=postId}
            say('挂钩注册ID读回 '..label..' pre='..preId..' post='..postId)
        else say('挂钩注册失败 '..label..'：'..tostring(preId))end
        return true
    end

    local function install()
        for _,name in ipairs({'StaticFindObject','RegisterHook','UnregisterHook'})do
            if type(_G[name])~='function' then self.state='failed';self.message='缺少 '..name..'，AI难度未启用';say(self.message);return end
        end
        for _,name in ipairs(FUNCTIONS)do
            local path=LIBRARY..':'..name
            if not register(path,name,difficultyCallback(name,'pre'),function()end) then say('函数不可用 '..path)end
        end
        self.state='running'
        self.message='已挂钩，等待读回'
    end

    -- Lua calls go through the same hooks. Asking for a unit's difficulty proves the GetDifficulty
    -- override and asking with the World proves everyone else still gets the game's answer; calling a
    -- recorded check with the unit's arguments proves the check override.
    local library,world
    local function gameValue()
        local okWorld,game=pcall(function()return library:GetDifficulty(world)end)
        return okWorld and tonumber(U.unwrap(game)) or nil
    end
    local function readbackUnit(actor,level)
        local okUnit,unit=pcall(function()return library:GetDifficulty(actor)end)
        unit=okUnit and tonumber(U.unwrap(unit)) or nil
        local game=gameValue()
        local ok=unit==VALUES[level] and game~=nil
        if ok then self.verified=self.verified+1 else self.failed=self.failed+1 end
        say('读回 GetDifficulty 单位='..className(actor)..' 期望='..level..'('..tostring(VALUES[level])..') 返回='..tostring(unit)
            ..' World返回='..tostring(game)..' 结果='..tostring(ok)..' 前回调计数='..(self.calls['GetDifficulty.pre'] or 0))
    end
    local function readbackCheck(spec,sample)
        if not U.valid(sample.node) then return end
        local okCall,result=pcall(spec.call,sample.node,sample.args[1],sample.args[2])
        result=okCall and U.unwrap(result) or nil
        local expected=VALUES[sample.level]>=sample.threshold
        local game=gameValue()
        local gameAnswer=game and game>=sample.threshold
        local ok=result==expected
        if ok then self.verified=self.verified+1 else self.failed=self.failed+1 end
        say('读回 '..spec.name..' 门槛='..sample.threshold..' 单位难度='..sample.level..' 期望='..tostring(expected)..' 返回='..tostring(result)
            ..' 游戏难度下应为='..tostring(gameAnswer)..'（'..(expected~=gameAnswer and '可区分' or '与游戏答案相同，不能区分')..'）结果='..tostring(ok))
    end

    function self:summary(reason)
        local parts={}
        for k,v in pairs(self.calls)do parts[#parts+1]=k..'='..v end
        table.sort(parts)
        local answers={}
        for k,v in pairs(self.answers)do answers[#answers+1]=k..' ×'..v end
        table.sort(answers)
        say('汇总 reason='..reason..' 改写='..self.overrides..' 读回成功='..self.verified..' 失败='..self.failed..' 回调='..table.concat(parts,' '))
        if #answers>0 then say('  检查节点改写：'..table.concat(answers,'；'))end
    end

    function self:tick()
        if not self.alive then return end
        cache={}
        if options.ready and not options.ready() then return end
        local leveled={}
        for _,entry in ipairs(options.members and options.members() or {})do
            local level=options.levelOf(entry.actor)
            if level and VALUES[level] then leveled[#leveled+1]={actor=entry.actor,level=level}end
        end
        if self.state=='idle' and #leveled>0 then install() end
        if self.state~='running' then return end
        -- The blueprint checks load with the first AI that uses them.
        for _,spec in ipairs(CHECKS)do
            if not installed[spec.name] and register(spec.path,spec.name,checkCallback(spec)) then installed[spec.name]=true end
        end
        library=StaticFindObject(DEFAULT);world=options.getWorld and options.getWorld()
        if not U.valid(library) or not U.valid(world) then return end
        for _,unit in ipairs(leveled)do
            local key=U.key(unit.actor)
            if key and not checked[key] then checked[key]=true;readbackUnit(unit.actor,unit.level)end
        end
        for _,spec in ipairs(CHECKS)do
            if samples[spec.name] and not checked[spec.name] then checked[spec.name]=true;readbackCheck(spec,samples[spec.name])end
        end
        -- A running tally once a minute while it changes, so a fight is readable without a reload.
        if not summarizedAt then summarizedAt=clock() end
        if clock()-summarizedAt>=60 and summarizedCount~=self.overrides then
            summarizedAt=clock();summarizedCount=self.overrides;self:summary('每分钟')
        end
    end

    function self:silence(reason)
        if not self.alive then return end
        self.alive=false
        if self.state=='running' then self:summary(reason or 'Mod卸载')end
    end
    function self:status()
        return {state=self.state,overrides=self.overrides,verified=self.verified,failed=self.failed,message=self.message}
    end
    return self
end
return AI
