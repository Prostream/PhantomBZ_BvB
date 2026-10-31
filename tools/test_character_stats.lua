package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Stats=require('character_stats')
local function object(id,data)
    local o=data or {};o.alive=true
    function o:IsValid()return self.alive end
    function o:GetAddress()assert(self.alive);return id end
    return o
end
local actor=object(1);local foreign=object(2)
local cls=object(3)
local attributes=object(4)
function attributes:GetOuter()assert(self.alive);return actor end
function attributes:GetClass()assert(self.alive);return cls end
actor.AttributeSetBase=attributes
for _,field in ipairs(Stats.fields)do attributes[field]={BaseValue=1,CurrentValue=1}end
attributes.Health={BaseValue=100,CurrentValue=100};attributes.Health_Max={BaseValue=100,CurrentValue=100}
attributes.Shachi={BaseValue=80,CurrentValue=80};attributes.Shachi_Max={BaseValue=80,CurrentValue=80}
attributes.Health_Min={BaseValue=0,CurrentValue=0}
local calls=0
local effects={};local effectFields={}
for _,field in ipairs(Stats.fields)do effectFields[#effectFields+1]=field end
effectFields[#effectFields+1]='Health_Min'
for index,field in ipairs(effectFields)do
    local name='GE_MA_'..field..'_1_Override'
    local path='/PBZCombatAsset/Config/AttributesModifyEffect/'..name..'.'..name
    local attr={AttributeName={ToString=function()return field end},AttributeOwner=cls,realName=field,native=true}
    local effect=object(100+index,{Modifiers={{Attribute=attr}}})
    function effect:GetFullName()return 'GameplayEffect '..path end
    effects[path]=effect
end
local native=object(6)
function native:ModifyCharacterAttributeValue(target,attribute,op,value)
    assert(target==actor and actor.alive and attributes.alive and op==3)
    calls=calls+1;local data=attributes[attribute.realName];data.BaseValue=value;data.CurrentValue=value
end
function native:GetCharacterAttributeValue(target,attribute)assert(target==actor);return attributes[attribute.realName].CurrentValue end
local abilities=object(7)
function abilities:GetDebugStringFromGameplayAttribute(attribute)return 'BasicAttributeSet.'..attribute.realName end
local check=object(8)
setmetatable(check,{__call=function(_,context,attr)assert(context==abilities);return attr.realName~=nil and attr.native==true end})
StaticFindObject=function(path)
    if effects[path] then return effects[path] end
    if path=='/Script/SGameAttributes.Default__AttributeUtils' then return native end
    if path=='/Script/GameplayAbilities.Default__AbilitySystemBlueprintLibrary' then return abilities end
    if path=='/Script/GameplayAbilities.AbilitySystemBlueprintLibrary:IsValid' then return check end
end
local adapter=Stats.new();assert(adapter:snapshot(actor))
assert(adapter:writeBase(actor,'Attack',70) and adapter:nativeValue(actor,'Attack')==70 and calls==1)
assert(adapter:writeBase(actor,'Health_Min',100) and adapter:nativeValue(actor,'Health_Min')==100 and attributes.Health_Min.BaseValue==100)
for _,field in ipairs(Stats.fields)do assert(field~='Health_Min','matching NPCs must never copy the observer health floor')end
function attributes:GetOuter()return foreign end
assert(not adapter:snapshot(actor) and not adapter:writeBase(actor,'Attack',12) and calls==2,'foreign-owned attribute sets are read-only to this adapter')
attributes.alive=false
function attributes:GetOuter()error('invalid object dereference')end
assert(not adapter:writeBase(actor,'Attack',12) and calls==2)
print('character_stats: PASS (instance ownership, descriptor readback, native Override=3, invalid-object gate)')
