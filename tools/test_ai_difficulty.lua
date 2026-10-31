package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local AI=dofile('Mods/PhantomGladiator/Scripts/ai_difficulty.lua')
-- Fixture objects refuse writes: the override may only answer through hook return values.
local address=0
local function object(fields,name,outer,class)
    address=address+1;local a=address
    fields.IsValid=function()return true end
    fields.GetAddress=function()return a end
    fields.GetOuter=function()return outer end
    fields.GetFName=function()return {ToString=function()return name end}end
    fields.GetClass=function()return class end
    return setmetatable(fields,{__newindex=function(_,k)error('override wrote '..tostring(k))end})
end
local function class(name)return object({},name)end
local world=object({},'World',nil,class('World'))
local pawn=object({},'MoTian',world,class('BP_Monster_MoTian_C'))
local mob=object({},'MapMob',world,class('BP_Monster_MoTian_C'))
local controller=object({K2_GetPawn=function()return pawn end},'Controller',world,class('BP_PBZAIController_C'))
local mobController=object({K2_GetPawn=function()return mob end},'MobController',world,class('BP_PBZAIController_C'))

-- Simulated UE4SS: /Script/ hooks get pre and post callbacks, blueprint hooks one callback after the
-- function; a non-nil return replaces the result (the later one wins).
local hooks,registered={},0
RegisterHook=function(path,first,second)registered=registered+1;hooks[path]={first=first,second=second};return registered*2,registered*2+1 end
UnregisterHook=function()end
local function wrap(v)return {type=function()return 'RemoteUnrealParam' end,get=function()return v end}end
local GAME=1 -- Easy
local function getDifficulty(context)
    local hook=hooks['/Script/ProjectPBZ.PBZBlueprintFunctionLibrary:GetDifficulty']
    local result=GAME
    if hook then
        local pre=hook.first(nil,wrap(context));if pre~=nil then result=pre end
        local post=hook.second(nil,wrap(context));if post~=nil then result=post end
    end
    return result
end
local CONDITION='/PBZCombatAsset/Prototypes/AI/AICondition_AboveDifficulty.AICondition_AboveDifficulty_C:EvaluateCondition'
local DECORATOR='/PBZCombatAsset/Prototypes/AI/BTDecorator_AboveDifficulty.BTDecorator_AboveDifficulty_C:PerformConditionCheckAI'
local function blueprint(path,node,...)
    local result=getDifficulty(node)>=node.Difficulty
    local hook=hooks[path]
    if hook then local r=hook.first(wrap(node),...);if r~=nil then result=r end end
    return result
end
local pool=object({},'AbilityPool_Normal',nil,class('Pool'))
local condition=object({Difficulty=3,EvaluateCondition=function(self,c)return blueprint(CONDITION,self,wrap(c))end},'Condition',pool,class('AICondition_AboveDifficulty_C'))
local btComponent=object({},'BTComponent',controller,class('BTComp'))
local decorator=object({Difficulty=3,PerformConditionCheckAI=function(self,c,p)return blueprint(DECORATOR,self,wrap(c),wrap(p))end},'Decorator',btComponent,class('BTDecorator_AboveDifficulty_C'))
local library=object({GetDifficulty=function(_,c)return getDifficulty(c)end},'Default__PBZBlueprintFunctionLibrary')
local loaded={}
StaticFindObject=function(path)
    if path=='/Script/ProjectPBZ.Default__PBZBlueprintFunctionLibrary' then return library end
    if path:find('PBZBlueprintFunctionLibrary:',1,true) then return object({},'fn') end
    return loaded[path]
end

local lines,levels,members={}, {}, {}
local ai=AI.new({log=function(s)lines[#lines+1]=s end,ready=function()return true end,getWorld=function()return world end,
    members=function()return members end,levelOf=function(actor)return levels[actor:GetAddress()]end,
    levelOfKey=function(key)return levels[tonumber(key)]end,clock=function()return 0 end})
local function all()return table.concat(lines,'\n')end

members={{actor=pawn},{actor=mob}};ai:tick()
assert(registered==0 and getDifficulty(pawn)==1,'units that follow the game install nothing')

levels[pawn:GetAddress()]='Nightmare';ai:tick()
assert(registered==2,'GetDifficulty and GetDiffcultMode are hooked before and after')
assert(all():find('读回 GetDifficulty 单位=BP_Monster_MoTian_C 期望=Nightmare(4) 返回=4 World返回=1 结果=true 前回调计数=2',1,true),
    'Lua readback proves the override, leaves the world alone and says which callbacks ran')
assert(getDifficulty(controller)==4 and getDifficulty(mob)==1 and getDifficulty(world)==1)

-- The blueprint checks hook once their class is loaded; the game says Easy (1) < 3.
loaded[CONDITION]=object({},'fn');loaded[DECORATOR]=object({},'fn');ai:tick()
assert(registered==4,'both blueprint checks are hooked once loaded')
assert(condition:EvaluateCondition(controller)==true,'the shared ability-pool check answers for the unit it evaluates')
assert(condition:EvaluateCondition(mobController)==false,'a map enemy using the same pool keeps the game answer')
assert(decorator:PerformConditionCheckAI(controller,pawn)==true)
assert(all():find('检查节点参数 EvaluateCondition 节点=AICondition_AboveDifficulty_C 1=RemoteUnrealParam:Controller',1,true))
assert(all():find('改写 EvaluateCondition 单位=BP_PBZAIController_C/Nightmare 门槛=3 → true',1,true))
ai:tick()
assert(all():find('读回 EvaluateCondition 门槛=3 单位难度=Nightmare 期望=true 返回=true 游戏难度下应为=false（可区分）结果=true',1,true))
assert(all():find('读回 PerformConditionCheckAI 门槛=3',1,true))

levels[pawn:GetAddress()]=nil;ai:tick()
assert(getDifficulty(pawn)==1 and condition:EvaluateCondition(controller)==false,'a unit that left the arena gets the game answer after the next tick')
ai:silence('test');assert(all():find('汇总 reason=test',1,true) and all():find('检查节点改写：',1,true))
assert(getDifficulty(controller)==1)
print('ai_difficulty: PASS (no hook without a chosen level, pre/post GetDifficulty readback, shared and behaviour-tree checks answer per unit, map and world untouched, silence)')
