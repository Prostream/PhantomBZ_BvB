package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Camera=require('free_camera')
local function harness()
    local h={objects={},files={},timers={},time=1,input={},logs={},spawned=0,engineCalls=0,actions=0,inputActors={}}
    local serial=0
    local function object(path,fields)
        serial=serial+1
        local o=fields or {};o.key=serial;o.alive=true;o.path=path
        function o:IsValid()return self.alive end
        function o:GetAddress()assert(self.alive,'accessed invalid object');return self.key end
        function o:GetFullName()assert(self.alive);return 'Object '..self.path end
        h.objects[path]=o;return o
    end
    h.world=object('/Test.World')
    h.player=object('/Test.LocalPlayer')
    h.pawn=object('/Test.World:PersistentLevel.Player')
    function h.pawn:GetOuter()assert(self.alive);return h.world end
    h.pc=object('/Test.World:PersistentLevel.PC',{Pawn=h.pawn,Player=h.player,moveDepth=0,lookDepth=0,target=h.pawn})
    h.player.PlayerController=h.pc
    function h.pc:GetViewTarget()assert(self.alive);return self.target end
    function h.pc:SetViewTargetWithBlend(target,seconds,mode,exp,lock)
        assert(self.alive and target:IsValid() and seconds==0 and mode==0 and lock==false)
        if not h.rejectView then self.target=target end
    end
    function h.pc:IsMoveInputIgnored()assert(self.alive);return self.moveDepth>0 end
    function h.pc:IsLookInputIgnored()assert(self.alive);return self.lookDepth>0 end
    function h.pc:SetIgnoreMoveInput(on)assert(self.alive);self.moveDepth=math.max(0,self.moveDepth+(on and 1 or -1))end
    function h.pc:SetIgnoreLookInput(on)assert(self.alive);self.lookDepth=math.max(0,self.lookDepth+(on and 1 or -1))end
    function h.pc:GetInputAnalogKeyState(k)
        assert(self.alive and type(k)=='table' and type(k.KeyName)=='string')
        if h.badInput then return nil end
        return h.input[k.KeyName] or 0
    end
    h.manager=object('/Test.World:PersistentLevel.Manager')
    function h.manager:GetCameraLocation()return {X=100,Y=200,Z=300}end
    function h.manager:GetCameraRotation()return {Pitch=0,Yaw=0,Roll=0}end
    function h.manager:GetFOVAngle()return 80 end
    h.pc.PlayerCameraManager=h.manager
    h.lib=object('/Script/Engine.Default__GameplayStatics')
    object('/Script/Engine.CameraActor')
    function h.lib:GetRealTimeSeconds(world)assert(world==h.world and world:IsValid());return h.time end
    function h.lib:BeginDeferredActorSpawnFromClass(...)
        local world,cls,t,collision,owner,scale=...
        assert(select('#',...)==6 and world==h.world and cls==h.objects['/Script/Engine.CameraActor'])
        assert(collision==1 and owner==nil and scale==1 and t.Rotation.W==1)
        h.spawned=h.spawned+1
        if h.unknownSpawn then return nil end
        local camera=object('/Test.World:PersistentLevel.Observer'..h.spawned,{position=t.Translation,rotation={Pitch=0,Yaw=0,Roll=0}})
        function camera:K2_GetActorLocation()assert(self.alive);return self.position end
        function camera:K2_SetActorLocationAndRotation(p,r,sweep,hit,teleport)
            assert(self.alive and sweep==false and type(hit)=='table' and teleport==true)
            if h.rejectMove then return false end
            self.position,self.rotation=p,r;return true
        end
        function camera:K2_DestroyActor()assert(self.alive);self.alive=false;self.inputActive=false end
        function camera:IsActorBeingDestroyed()assert(self.alive);return false end
        function camera:EnableInput(pc)
            assert(self.alive and pc==h.pc)
            self.inputActive=true;h.inputActors[#h.inputActors+1]=self
            if h.rejectInputLayer then return end
            self.InputComponent=object(self.path..'.InputComponent')
            function self.InputComponent:GetOwner()assert(self.alive);return camera end
        end
        function camera:DisableInput(pc)assert(self.alive and pc==h.pc);self.inputActive=false end
        local component=object(camera.path..'.CameraComponent')
        function component:GetOwner()assert(self.alive);return camera end
        function component:SetFieldOfView(fov)assert(self.alive);self.FieldOfView=fov end
        camera.CameraComponent=component
        h.camera=camera;return camera
    end
    function h.lib:FinishSpawningActor(camera,t,scale)
        assert(camera==h.camera and scale==1)
        if h.rejectFinish then error('fixture finish failure')end
        return camera
    end
    local fs={open=function(path,mode)
        if mode=='r' and not h.files[path] then return nil end
        local text=h.files[path] or ''
        return {write=function(_,value)text=value;return true end,
            read=function()return text end,
            close=function()if mode=='w' then h.files[path]=text end;return true end}
    end}
    StaticFindObject=function(path)h.engineCalls=h.engineCalls+1;return h.objects[path]end
    FName=function(name)return name end
    LoopInGameThreadWithDelay=function(ms,callback)
        assert(ms==16)
        local handle=#h.timers+1;h.timers[handle]={callback=callback}
        if h.rejectTimer then return nil end
        return handle
    end
    CancelDelayedAction=function(handle)assert(h.timers[handle]);h.timers[handle].cancelled=true end
    h.options={path='memory',io=fs,log=function(s)h.logs[#h.logs+1]=s end,
        getController=function()return h.pc end,getWorld=function()return h.world end}
    function h:new()return Camera.new(self.options)end
    function h:tick()
        self.time=self.time+0.02
        for _,t in ipairs(self.timers)do if not t.cancelled then t.callback()end end
    end
    function h:pressAction()
        for _,actor in ipairs(self.inputActors)do
            if actor.alive and actor.inputActive and actor.bBlockInput and actor.InputPriority>0 then return end
        end
        self.actions=self.actions+1
    end
    h.cameraController=h:new()
    return h
end
local passed=0
local function test(name,fn)fn();passed=passed+1;print('PASS '..name)end

test('observer blocks player actions while raw movement remains available and restores on exit',function()
    local h=harness();h:pressAction();assert(h.actions==1)
    assert(h.cameraController:enter());h:pressAction()
    assert(h.actions==1,'Space/attack actions must not reach the player during observation')
    h.input.W=1;h:tick();assert(h.camera.position.X>100)
    assert(h.cameraController:stop('F6'));h:pressAction();assert(h.actions==2)
end)

test('view target changes without replacing PlayerController, Player or Pawn; exit restores',function()
    local h=harness();local c=h.cameraController
    assert(c:enter() and c:isActive())
    assert(h.pc.target==h.camera and h.pc.Player==h.player and h.pc.Pawn==h.pawn and h.player.PlayerController==h.pc)
    assert(h.pc.moveDepth==1 and h.pc.lookDepth==1)
    assert(h.camera.CameraComponent.FieldOfView==80)
    h.options.getController=function()error('no controller enumeration per frame')end
    h.options.getWorld=function()error('no world enumeration per frame')end
    h.input.W=1;h.input.MouseX=2;h:tick()
    assert(c:isActive() and h.camera.position.X>100 and h.camera.rotation.Yaw==2)
    assert(c:stop('F7') and not h.camera.alive and h.pc.target==h.pawn)
    assert(h.pc.moveDepth==0 and h.pc.lookDepth==0 and not c:hasPending())
    h.timers[1].callback();assert(not h.camera.alive,'retained callback is inert after exit')
end)
test('preexisting guards and another systems increment are preserved',function()
    local h=harness();h.pc.moveDepth=2;h.pc.lookDepth=1
    assert(h.cameraController:enter());assert(h.cameraController:stop('F7'))
    assert(h.pc.moveDepth==2 and h.pc.lookDepth==1)
    h=harness();assert(h.cameraController:enter());h.pc.moveDepth=h.pc.moveDepth+1
    assert(h.cameraController:stop('F7'));assert(h.pc.moveDepth==1)
    assert(h.cameraController:stop('F7'));assert(h.pc.moveDepth==1,'never release someone elses counter twice')
end)
test('failed view target, finish or timer registration rolls back only owned changes',function()
    for _,failure in ipairs({'rejectView','rejectFinish','rejectTimer','rejectInputLayer'})do
        local h=harness();h[failure]=true
        assert(not h.cameraController:enter(),failure)
        assert(not h.cameraController:isActive() and not h.cameraController:hasPending())
        assert(not h.camera.alive and h.pc.target==h.pawn and h.pc.moveDepth==0 and h.pc.lookDepth==0,failure)
        h:pressAction();assert(h.actions==1,'failed entry must not leave an input blocker')
        for _,timer in ipairs(h.timers)do timer.callback()end
    end
end)
test('input signature is checked before creating an actor or restricting input',function()
    local h=harness();h.badInput=true
    assert(not h.cameraController:enter() and h.spawned==0 and h.pc.moveDepth==0)
end)
test('movement failure restores view and controls instead of leaving the player stuck',function()
    local h=harness();assert(h.cameraController:enter());h.rejectMove=true;h.input.W=1;h:tick()
    assert(not h.cameraController:isActive() and not h.cameraController:hasPending())
    assert(h.pc.target==h.pawn and h.pc.moveDepth==0 and h.pc.lookDepth==0)
end)
test('hot reload cancels work without touching UObjects and the new module restores the journal',function()
    local h=harness();local first=h.cameraController;assert(first:enter())
    local calls=h.engineCalls;first:silence();assert(h.engineCalls==calls,'unload must not inspect engine objects')
    assert(h.pc.target==h.camera and h.pc.moveDepth==1)
    h.timers[1].callback();assert(h.engineCalls==calls)
    local reloaded=h:new();assert(reloaded:hasPending());reloaded:recover()
    assert(not reloaded:hasPending() and h.pc.target==h.pawn and not h.camera.alive)
    assert(h.pc.moveDepth==0 and h.pc.lookDepth==0)
    h:pressAction();assert(h.actions==1,'reload must remove the owned action blocker')
end)
test('game-selected view target is not overwritten on stop',function()
    local h=harness();assert(h.cameraController:enter())
    h.pc.target=h.manager
    assert(h.cameraController:stop('F7') and h.pc.target==h.manager)
end)
test('invalid original controller does not modify the replacement controller',function()
    local h=harness();assert(h.cameraController:enter())
    h.pc.alive=false
    h.cameraController:tick()
    assert(not h.cameraController:isActive() and not h.camera.alive)
    assert(h.pc.moveDepth==1,'invalid object must not be called')
end)
test('unconfirmed native creation cannot be retried into duplicate unknown objects',function()
    local h=harness();h.unknownSpawn=true
    assert(not h.cameraController:enter() and h.cameraController:hasPending())
    assert(not h.cameraController:enter() and h.spawned==1)
    assert(h.pc.target==h.pawn and h.pc.moveDepth==0 and h.pc.lookDepth==0)
    h.options.getWorld=function()return nil end
    assert(not h.cameraController:stop('loading') and h.cameraController:hasPending(),'unknown world must not discard an uncertain creation')
end)
test('observer lifecycle is journaled, ticked while stationary and restored before camera destruction',function()
    local h=harness();local ticks,restores=0,0
    h.options.guard={fields={'guard_fixture'},enter=function(_,c)
        assert(c.pc==h.pc and c.pawn==h.pawn and c.camera==h.camera)
        c.record.guard_fixture='owned';c.save()
    end,tick=function()ticks=ticks+1 end,stop=function(_,c)
        if c.record.guard_fixture then assert(c.camera.alive);restores=restores+1 end
        return true
    end}
    local camera=h:new();assert(camera:enter());h:tick();assert(ticks==1,'idle camera must still maintain protection')
    camera:silence();local nextCamera=h:new();nextCamera:recover()
    assert(restores==1 and not nextCamera:hasPending() and not h.camera.alive)
end)
test('observer entry failure rolls back the camera and original input association',function()
    local h=harness();local restored=false
    h.options.guard={fields={},enter=function()error('fixture protection failure')end,tick=function()end,
        stop=function()restored=true;return true end}
    local camera=h:new();assert(not camera:enter())
    assert(restored and not camera:hasPending() and h.pc.target==h.pawn and h.pc.moveDepth==0)
end)
print('free_camera: PASS ('..passed..' control, recovery and ownership regressions; no game accessed)')
