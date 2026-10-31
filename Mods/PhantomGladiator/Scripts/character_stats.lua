-- Native attribute adapter. No raw memory writes and no shared data-table edits.
-- CharacterBasics.hpp, ProjectPBZ.hpp and SGameAttributes.hpp are the local schemas.
local U=require('ue_observe')
local Stats={}
Stats.fields={'Attack','ShachiAttack'}
local families={'Physical','PhysicalSharp','PhysicalBlunt','Elemental','Fire','Toxin','Ice','Aqua',
    'Lightning','Blood','Chaos','ImpactShachi','ReflectShachi'}
local prefixes={'Amplification_','DealtVulnerabilityMultiplier_','DealtReductionMultiplier_',
    'Resistance_','TakenAdditiveMultiplier_','TakenVulnerabilityMultiplier_','TakenReductionMultiplier_'}
for _,family in ipairs(families)do for _,prefix in ipairs(prefixes)do Stats.fields[#Stats.fields+1]=prefix..family end end
for _,field in ipairs({'Resistance_Poise','TakenAdditiveMultiplier_Poise','TakenVulnerabilityMultiplier_Poise','TakenReductionMultiplier_Poise',
        'Resistance_BreakDamageAdditionalMultiplier','TakenAdditiveMultiplier_BreakDamage','TakenVulnerabilityMultiplier_BreakDamage','TakenReductionMultiplier_BreakDamage',
        'Resistance_DefenceShachi','TakenAdditiveMultiplier_DefenceShachi','TakenVulnerabilityMultiplier_DefenceShachi','TakenReductionMultiplier_DefenceShachi',
        'Health_Max','Shachi_Max'})do
    Stats.fields[#Stats.fields+1]=field
end
local function finite(n)return type(n)=='number' and n==n and math.abs(n)<=1e9 end
local function text(value)
    if type(value)=='string' then return value end
    local ok,s=pcall(function()return value:ToString()end)
    return ok and type(s)=='string' and s or nil
end
Stats.finite=finite
function Stats.close(a,b)return finite(a) and finite(b) and math.abs(a-b)<=math.max(1e-6,math.abs(b)*2e-5)end
local function attributeSet(actor)
    if not U.valid(actor) then return nil,'单位已失效' end
    local set=U.field(actor,'AttributeSetBase')
    if not U.valid(set) then return nil,'没有可读取的战斗属性' end
    local key=U.key(actor);local outer=set
    if not key then return nil,'单位标识不可读' end
    for _=1,8 do
        if not U.valid(outer) then break end
        if U.key(outer)==key then return set end
        local ok,parent=pcall(function()return outer:GetOuter()end)
        if not ok then break end
        outer=parent
    end
    return nil,'属性集不属于这个单位，未修改'
end
function Stats.new()
    local self={effects={}}
    -- Health_Min is available only to the observer guard, not the stat-matching list.
    local allowed={Health=true,Shachi=true,Health_Min=true};for _,field in ipairs(Stats.fields)do allowed[field]=true end
    function self:read(actor,field)
        local set,why=attributeSet(actor);if not set then return nil,why end
        local data,ok=U.field(set,field)
        local base=U.struct(data,'BaseValue');local current=U.struct(data,'CurrentValue')
        if not ok or not finite(base) or not finite(current) then return nil,'属性不可读: '..field end
        return {base=base,current=current}
    end
    function self:snapshot(actor)
        local result={}
        for _,field in ipairs(Stats.fields)do
            local entry,why=self:read(actor,field);if not entry then return nil,why end
            result[field]=entry
        end
        for _,field in ipairs({'Health','Shachi'})do
            local entry,why=self:read(actor,field);if not entry then return nil,why end
            result[field]=entry
        end
        if result.Health_Max.current<=0 or result.Shachi_Max.current<=0 or result.Attack.current<=0 then
            return nil,'生命/杀气上限或攻击不是有效的正数，不能作为数值对齐对象'
        end
        return result
    end
    local function descriptor(actor,field)
        local set,why=attributeSet(actor);if not set then return nil,nil,why end
        if not allowed[field] then return nil,nil,'属性不在已核对的修改范围' end
        local utils=StaticFindObject('/Script/SGameAttributes.Default__AttributeUtils')
        local abilities=StaticFindObject('/Script/GameplayAbilities.Default__AbilitySystemBlueprintLibrary')
        local check=StaticFindObject('/Script/GameplayAbilities.AbilitySystemBlueprintLibrary:IsValid')
        if not U.valid(utils) or not U.valid(abilities) or not U.valid(check) then return nil,nil,'原生属性函数库不可用' end
        -- Combat field paths and observer Health_Min were verified in asset-index.tsv.
        -- Preserve the in-place native descriptor instead of reconstructing its
        -- field path from the Lua table returned by MakeAttribute.
        local effect=self.effects[field]
        local assetName='GE_MA_'..field..'_1_Override'
        local effectPath='/PBZCombatAsset/Config/AttributesModifyEffect/'..assetName..'.'..assetName
        if not U.valid(effect) then
            effect=StaticFindObject(effectPath)
            if not U.valid(effect) then local loaded,value=pcall(LoadAsset,effectPath);if loaded then effect=value end end
            if not U.valid(effect) then return nil,nil,'原生属性效果未加载: '..field end
            local named,full=pcall(function()return effect:GetFullName()end)
            if not named or type(full)~='string' or full:match('^%S+ (/.+)$')~=effectPath then return nil,nil,'原生属性效果路径不匹配' end
            self.effects[field]=effect
        end
        local modifiers=U.array(U.field(effect,'Modifiers'))
        if not modifiers or #modifiers~=1 then return nil,nil,'原生属性效果的修饰项不唯一: '..field end
        local attr=U.struct(modifiers[1],'Attribute')
        -- Use the exact UFunction: library:IsValid(attr) would hit the Lua UObject
        -- validity method instead of checking the FGameplayAttribute itself.
        local validCall,validAttribute=pcall(function()return check(abilities,attr)end)
        local actual=text(U.struct(attr,'AttributeName'))
        if not validCall or validAttribute~=true then
            return nil,nil,'属性描述无效: '..field..' kind='..U.kind(attr)..' cached_name='..tostring(actual)
        end
        local named,debugName=pcall(function()return abilities:GetDebugStringFromGameplayAttribute(attr)end)
        debugName=named and text(debugName) or nil
        if not debugName or (debugName~=field and debugName:match('([^.:/ ]+)$')~=field) then
            return nil,nil,'属性名称未确认: '..field..' native='..tostring(debugName)..' cached='..tostring(actual)
        end
        local read,current=pcall(function()return utils:GetCharacterAttributeValue(actor,attr)end)
        local reflected=U.struct(U.field(set,field),'CurrentValue')
        if not read or not Stats.close(current,reflected) then return nil,nil,'属性原生读取与实例字段不一致: '..field end
        return attr,utils
    end
    function self:writeBase(actor,field,value)
        if not finite(value) then return false,'非有限属性值' end
        local attr,utils,why=descriptor(actor,field);if not attr then return false,why end
        if not U.valid(actor) or not U.valid(utils) then return false,'写入前对象失效' end
        -- EGameplayModOp.Override == 3 in this game's dumped enum.
        local ok,err=pcall(function()utils:ModifyCharacterAttributeValue(actor,attr,3,value)end)
        return ok,not ok and tostring(err) or nil
    end
    function self:nativeValue(actor,field)
        local attr,utils,why=descriptor(actor,field);if not attr then return nil,why end
        if not U.valid(actor) or not U.valid(utils) then return nil,'读回前对象失效' end
        local ok,value=pcall(function()return utils:GetCharacterAttributeValue(actor,attr)end)
        if not ok or not finite(value) then return nil,'原生属性读回失败: '..field end
        return value
    end
    return self
end
return Stats
