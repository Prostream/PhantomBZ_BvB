package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Activity=require('arena_activity')
local function object(id,data)
    local obj=data or {};obj.alive=true
    function obj:IsValid()return self.alive end
    function obj:GetAddress()assert(self.alive);return id end
    return obj
end
local actor=object(1,{bDisableAllOptimizationsOnBeginPlay=false})
actor.AttributeSetBase=object(5,{Health={CurrentValue=123},Shachi={CurrentValue=45}})
local outsider=object(2)
local proxy=object(3,{wave=0,calls=0})
function proxy:GetOwner()return actor end
function proxy:GetOptimizationWave()return self.wave end
function proxy:DisableAllOptimizations()self.calls=self.calls+1;self.wave=1 end
actor.OptimizationProxy=proxy
local mesh=object(4,{VisibilityBasedAnimTickOption=1,bEnableUpdateRateOptimizations=true})
function mesh:GetOwner()return actor end
function mesh:GetComponentTickInterval()return 0 end
function mesh:SetComponentTickEnabled()error('the bone experiment must not alter tick enablement')end
function mesh:SetComponentTickInterval()error('the bone experiment must not alter tick interval')end
actor.Mesh=mesh
local camera=false
local observed={}
local activity=Activity.new({isNPC=function()return true end,freeCam=function()return camera end,log=function(line)observed[#observed+1]=line end})
activity:prepare(actor);assert(actor.bDisableAllOptimizationsOnBeginPlay==true)
activity:sync({{actor=actor,class_path='owned'}})
assert(proxy.calls==1 and activity:status().full_update_count==1)
assert(mesh.VisibilityBasedAnimTickOption==0 and mesh.bEnableUpdateRateOptimizations==true)
assert(activity:status().bone_refresh_count==1)
assert(table.concat(observed,'\n'):find('HP=123 Shachi=45',1,true),'diagnostics must use actual attributes')
camera=true;activity:sync({{actor=actor,class_path='owned'}})
assert(proxy.calls==1 and activity:status().free_camera,'stable full-update actors must not be rewritten every frame')
proxy.wave=3;activity:sync({{actor=actor,class_path='owned'}})
assert(activity:status().full_update_count==0,'readback drift must not be reported as full updates')
outsider.OptimizationProxy=proxy
activity:sync({{actor=outsider,class_path='wrong_owner'}})
assert(proxy.calls==1,'a component owned by a different actor must not be modified')
-- A native write-back cannot cause an unbounded mutation/log loop.
activity=Activity.new({isNPC=function()return true end})
for _=1,3 do mesh.VisibilityBasedAnimTickOption=2;activity:sync({{actor=actor}});assert(mesh.VisibilityBasedAnimTickOption==0)end
mesh.VisibilityBasedAnimTickOption=2;activity:sync({{actor=actor}})
assert(mesh.VisibilityBasedAnimTickOption==2 and activity:status().bone_refresh_count==0)
-- Valid outer actor does not authorize writes to invalid or foreign mesh objects.
activity=Activity.new({isNPC=function()return true end})
mesh.GetOwner=function()return outsider end
activity:sync({{actor=actor}});assert(mesh.VisibilityBasedAnimTickOption==2)
mesh.GetOwner=function()error('invalid mesh accessed')end;mesh.alive=false
activity:sync({{actor=actor}});assert(activity:status().bone_refresh_count==0)
actor.AttributeSetBase.alive=false
setmetatable(actor.AttributeSetBase,{__index=function()error('invalid attribute set accessed')end})
for _=1,10 do activity:sync({{actor=actor}})end
print('arena_activity: PASS (native ownership and validity, bounded one-variable bone refresh, URO/tick unchanged, drift visible)')
