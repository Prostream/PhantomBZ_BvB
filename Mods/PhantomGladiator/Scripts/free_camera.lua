-- Free observation without replacing UPlayer.PlayerController or possessing a pawn.
-- All engine access runs on the game thread. A small recovery journal survives reload.
local U=require('ue_observe')
local Camera={}
local function number(v)return type(v)=='number' and v==v and math.abs(v)<1e12 end
local function vec(v)
    local ok,x,y,z=pcall(function()return v.X,v.Y,v.Z end)
    if ok and number(x) and number(y) and number(z) then return {X=x,Y=y,Z=z} end
end
local function rot(v)
    local ok,p,y,r=pcall(function()return v.Pitch,v.Yaw,v.Roll end)
    if ok and number(p) and number(y) and number(r) then return {Pitch=p,Yaw=y,Roll=r} end
end
local function call(obj,name,...)
    if not U.valid(obj) then return false,'invalid '..name end
    local args=table.pack(...)
    return pcall(function()return obj[name](obj,table.unpack(args,1,args.n))end)
end
local function identity(obj)
    local ok,name=call(obj,'GetFullName')
    local path=ok and type(name)=='string' and name:match('^%S+ (/.+)$')
    local key=U.key(obj)
    if path and key then return path,key end
end
function Camera.new(options)
    local self={alive=true,active=false,record=nil,session=nil,handle=nil,keys={},objects={}}
    local log=options.log or function()end
    local fs=options.io or io
    local filePath=options.path..'/free-camera.tsv'
    local fields={'world','world_key','controller','controller_key','pawn','pawn_key',
        'target','target_key','camera','camera_key','move_owned','look_owned','input_owned','spawn_uncertain'}
    for _,name in ipairs(options.guard and options.guard.fields or {})do fields[#fields+1]=name end
    local function save(record)
        local lines={'FreeCameraV1'}
        for _,name in ipairs(fields)do
            local value=tostring(record[name] or '')
            assert(not value:find('[\t\r\n]'),'invalid recovery value')
            lines[#lines+1]=name..'\t'..value
        end
        local text=table.concat(lines,'\n')..'\n'
        local file=assert(fs.open(filePath,'w'));assert(file:write(text));assert(file:close())
        file=assert(fs.open(filePath,'r'));local actual=file:read('*a');file:close()
        assert(actual==text,'camera recovery journal readback failed')
    end
    local function clearJournal()
        local file=assert(fs.open(filePath,'w'));assert(file:write('FreeCameraV1\n'));assert(file:close())
        local check=assert(fs.open(filePath,'r'));local actual=check:read('*a');check:close()
        assert(actual=='FreeCameraV1\n','camera journal clear not verified')
    end
    do
        local file=fs.open(filePath,'r')
        if file then
            local text=file:read('*a');file:close()
            if text:match('^FreeCameraV1\n') then
                local record={};for k,v in text:gmatch('\n([^\t\r\n]+)\t([^\r\n]*)')do record[k]=v end
                if record.controller and record.controller~='' then self.record=record end
            end
        end
    end
    local function resolve(record,field)
        local path,key=record[field],record[field..'_key']
        if not path or path=='' or not key then return nil end
        local cached=self.objects[field]
        if U.valid(cached) and U.key(cached)==key and identity(cached)==path then return cached end
        local ok,obj=pcall(StaticFindObject,path)
        if not ok or not U.valid(obj) or U.key(obj)~=key then return nil end
        local actual=identity(obj)
        return actual==path and obj or nil
    end
    local function same(a,b)return U.key(a)~=nil and U.key(a)==U.key(b)end
    local function remember(record,field,obj)
        local path,key=identity(obj);assert(path,'missing identity: '..field)
        record[field],record[field..'_key']=path,key
        self.objects[field]=obj
    end
    local function guardContext(record)
        return {record=record,pc=resolve(record,'controller'),pawn=resolve(record,'pawn'),
            camera=resolve(record,'camera'),world=resolve(record,'world'),
            remember=function(name,obj)remember(record,name,obj)end,
            resolve=function(name)return resolve(record,name)end,save=function()save(record)end}
    end
    local function key(name)
        if not self.keys[name] then self.keys[name]={KeyName=FName(name)} end
        return self.keys[name]
    end
    local function axis(pc,name)
        local ok,value=call(pc,'GetInputAnalogKeyState',key(name))
        assert(ok and number(value),'input readback unavailable: '..name)
        return value
    end
    function self:isActive()return self.active end
    function self:hasPending()return self.record~=nil end
    function self:stop(reason)
        self.active=false;self.session=nil
        if self.handle then
            local ok=pcall(CancelDelayedAction,self.handle)
            if ok then self.handle=nil end
        end
        local record=self.record
        if not record then return true end
        local pc=resolve(record,'controller')
        local camera=resolve(record,'camera')
        local pending=false
        if options.guard then
            local ok,restored=pcall(function()return options.guard:stop(guardContext(record))end)
            if not ok or restored~=true then pending=true;log('[FreeCamera] 观战保护恢复待确认：'..tostring(restored)) end
        end
        if record.spawn_uncertain=='1' then
            local currentWorld=U.key(options.getWorld())
            pending=not currentWorld or currentWorld==record.world_key
        end
        if pc then
            local ok,target=call(pc,'GetViewTarget')
            if not ok or not U.valid(target) then pending=true
            elseif same(target,camera) then
                local previous=resolve(record,'target') or U.field(pc,'Pawn')
                if U.valid(previous) then
                    local changed=call(pc,'SetViewTargetWithBlend',previous,0,0,0,false)
                    local read,actual=call(pc,'GetViewTarget')
                    local verified=changed and read and same(actual,previous)
                    log('[FreeCamera] 恢复视点 reason='..tostring(reason)..' verified='..tostring(verified))
                    if not verified then pending=true end
                else pending=true end
            end
            if record.input_owned=='1' then
                local released=not camera or call(camera,'DisableInput',pc)
                if released then
                    record.input_owned='0';save(record)
                    log('[FreeCamera] 已请求撤销自建相机输入层；随后以相机销毁读回确认清理')
                else pending=true end
            end
            for _,guard in ipairs({{'move_owned','IsMoveInputIgnored','SetIgnoreMoveInput'},
                    {'look_owned','IsLookInputIgnored','SetIgnoreLookInput'}})do
                if record[guard[1]]=='1' then
                    local read,before=call(pc,guard[2])
                    if read and type(before)=='boolean' then
                        local changed=not before or call(pc,guard[3],false)
                        if changed then
                            -- Release our stack increment once; never repeatedly reset another system's guard.
                            record[guard[1]]='0';save(record)
                            local got,after=call(pc,guard[2])
                            log('[FreeCamera] 释放本次输入限制 '..guard[1]..' readback='..tostring(got and after))
                        else pending=true end
                    else pending=true end
                end
            end
        else
            -- The exact old controller no longer exists; never modify the replacement player's flags.
            record.move_owned,record.look_owned='0','0'
        end
        if camera and not pending then
            local destroyed=call(camera,'K2_DestroyActor')
            local removed=not U.valid(camera)
            if not removed then
                local read,dying=call(camera,'IsActorBeingDestroyed');removed=read and dying==true
            end
            log('[FreeCamera] 清理自建相机 call='..tostring(destroyed)..' removed='..tostring(removed))
            if not removed then pending=true end
        end
        if pending then save(record);log('[FreeCamera] 恢复待确认；可点击退出观战或使用自定义退出键重试');return false end
        clearJournal();self.record=nil;self.objects={}
        log('[FreeCamera] 已退出；原玩家控制器未切换')
        return true
    end
    function self:recover(force)
        if self.alive and not self.active and self.record and (force or not self.recoveryTried) then
            self.recoveryTried=true
            local ok,err=pcall(function()return self:stop('恢复上次相机记录')end)
            if not ok then log('[FreeCamera] 恢复失败 '..tostring(err)) end
        end
    end
    local function transform(position,rotation)
        local p,y,r=math.rad(rotation.Pitch)*0.5,math.rad(rotation.Yaw)*0.5,math.rad(rotation.Roll)*0.5
        local sp,cp,sy,cy,sr,cr=math.sin(p),math.cos(p),math.sin(y),math.cos(y),math.sin(r),math.cos(r)
        return {Translation=position,Scale3D={X=1,Y=1,Z=1},
            Rotation={X=cr*sp*sy-sr*cp*cy,Y=-cr*sp*cy-sr*cp*sy,Z=cr*cp*sy-sr*sp*cy,W=cr*cp*cy+sr*sp*sy}}
    end
    function self:tick()
        local s=self.session
        if not self.alive or not self.active or not s then return end
        local ok,err=pcall(function()
            -- No FindAllOf / player-controller enumeration in this per-frame path.
            assert(same(U.field(s.pc,'Player'),s.player) and same(U.field(s.player,'PlayerController'),s.pc)
                and same(U.field(s.pc,'Pawn'),s.pawn),'player/controller changed')
            assert(U.inWorld(s.pawn,s.world),'world changed')
            local read,target=call(s.pc,'GetViewTarget')
            assert(read and same(target,s.camera),'camera target replaced')
            local timed,now=call(s.lib,'GetRealTimeSeconds',s.world)
            assert(timed and number(now),'clock unavailable')
            if options.guard then options.guard:tick(guardContext(self.record)) end
            local dt=math.min(0.1,math.max(0,now-s.lastTime));s.lastTime=now
            local mx,my=axis(s.pc,'MouseX'),axis(s.pc,'MouseY')
            local forward=axis(s.pc,'W')-axis(s.pc,'S')
            local right=axis(s.pc,'D')-axis(s.pc,'A')
            local up=axis(s.pc,'E')-axis(s.pc,'Q')
            local fast=math.max(axis(s.pc,'LeftShift'),axis(s.pc,'RightShift'))>0
            if mx==0 and my==0 and forward==0 and right==0 and up==0 then return end
            local sensitivity=options.mouseSensitivity or 1.0
            local rotation={Pitch=math.max(-89,math.min(89,s.rotation.Pitch+my*sensitivity)),
                Yaw=(s.rotation.Yaw+mx*sensitivity)%360,Roll=0}
            local yaw,pitch=math.rad(rotation.Yaw),math.rad(rotation.Pitch)
            local scale=(options.moveSpeed or 900)*(fast and 3 or 1)*dt/math.max(1,math.sqrt(forward*forward+right*right+up*up))
            local position={X=s.position.X+(forward*math.cos(pitch)*math.cos(yaw)-right*math.sin(yaw))*scale,
                Y=s.position.Y+(forward*math.cos(pitch)*math.sin(yaw)+right*math.cos(yaw))*scale,
                Z=s.position.Z+(forward*math.sin(pitch)+up)*scale}
            local moved,result=call(s.camera,'K2_SetActorLocationAndRotation',position,rotation,false,{},true)
            assert(moved and result~=false,'camera movement failed')
            local got,actual=call(s.camera,'K2_GetActorLocation')
            actual=got and vec(actual)
            assert(actual,'camera position readback unavailable')
            assert(math.abs(actual.X-position.X)<0.5 and math.abs(actual.Y-position.Y)<0.5 and math.abs(actual.Z-position.Z)<0.5,'camera location did not follow input')
            s.position,s.rotation=actual,rotation
            if not s.movementVerified then
                s.movementVerified=true
                log('[FreeCamera] 输入/相机位置读回：WASDQE/Mouse；position='..actual.X..','..actual.Y..','..actual.Z)
            end
        end)
        if not ok then
            log('[FreeCamera] 观察相机中止：'..tostring(err))
            local restored,why=pcall(function()return self:stop('更新异常')end)
            if not restored then log('[FreeCamera] 异常恢复失败：'..tostring(why)) end
        end
    end
    function self:enter()
        if not self.alive then return false end
        if self.active then return true end
        if self.record then self:recover(true);if self.record then return false end end
        local ok,err=pcall(function()
            local pc=options.getController();assert(U.valid(pc),'player controller unavailable')
            local pawn=U.field(pc,'Pawn');local player=U.field(pc,'Player');local world=options.getWorld()
            assert(U.valid(pawn) and U.valid(player) and U.valid(world),'player/world unavailable')
            assert(same(U.field(player,'PlayerController'),pc),'local player association unavailable')
            assert(U.inWorld(pawn,world),'player world mismatch')
            local manager=U.field(pc,'PlayerCameraManager');assert(U.valid(manager),'camera manager unavailable')
            local readLocation,location=call(manager,'GetCameraLocation');location=readLocation and vec(location)
            local readRotation,rotation=call(manager,'GetCameraRotation');rotation=readRotation and rot(rotation)
            local readTarget,target=call(pc,'GetViewTarget')
            assert(location and rotation and readTarget and U.valid(target),'current viewpoint unavailable')
            local moveRead,moveIgnored=call(pc,'IsMoveInputIgnored')
            local lookRead,lookIgnored=call(pc,'IsLookInputIgnored')
            assert(moveRead and lookRead and type(moveIgnored)=='boolean' and type(lookIgnored)=='boolean','input guard readback unavailable')
            axis(pc,'W');axis(pc,'MouseX') -- Validate FKey reflection before any state changes.
            assert(type(LoopInGameThreadWithDelay)=='function' and type(CancelDelayedAction)=='function','camera timer unavailable')
            local lib=StaticFindObject('/Script/Engine.Default__GameplayStatics')
            local cls=StaticFindObject('/Script/Engine.CameraActor')
            assert(U.valid(lib) and U.valid(cls),'native camera class/library unavailable')
            local timed,now=call(lib,'GetRealTimeSeconds',world);assert(timed and number(now),'clock unavailable')
            local record={move_owned='0',look_owned='0',input_owned='0'}
            remember(record,'world',world);remember(record,'controller',pc);remember(record,'pawn',pawn);remember(record,'target',target)
            save(record);self.record=record;self.recoveryTried=false
            local t=transform(location,rotation)
            record.spawn_uncertain='1';save(record)
            local spawned,camera=call(lib,'BeginDeferredActorSpawnFromClass',world,cls,t,1,nil,1)
            assert(spawned and U.valid(camera),'camera spawn not confirmed')
            remember(record,'camera',camera);record.spawn_uncertain='0';save(record)
            local finished=call(lib,'FinishSpawningActor',camera,t,1);assert(finished and U.valid(camera),'camera finish not confirmed')
            local component=U.field(camera,'CameraComponent');assert(U.valid(component),'camera component unavailable')
            local owned,owner=call(component,'GetOwner');assert(owned and same(owner,camera),'camera component ownership mismatch')
            local gotFOV,fov=call(manager,'GetFOVAngle')
            if gotFOV and number(fov) and fov>5 and fov<175 then
                assert(call(component,'SetFieldOfView',fov),'camera FOV not applied')
                local actual=U.field(component,'FieldOfView')
                assert(number(actual) and math.abs(actual-fov)<0.01,'camera FOV not verified')
            end
            -- An owned input component blocks underlying gameplay actions, including
            -- Jump and Dodge. Raw key state still drives this camera; the player's
            -- input components and mappings are never removed or disabled.
            assert(U.valid(camera),'camera invalid before input registration')
            camera.bBlockInput=true
            camera.InputPriority=10000
            assert(U.field(camera,'bBlockInput')==true and U.field(camera,'InputPriority')==10000,'input layer configuration not verified')
            record.input_owned='1';save(record)
            assert(call(camera,'EnableInput',pc),'observer input layer registration failed')
            local input=U.field(camera,'InputComponent')
            local readInputOwner,inputOwner=call(input,'GetOwner')
            assert(readInputOwner and same(inputOwner,camera),'observer input component ownership not verified')
            local rawW,rawMouse=axis(pc,'W'),axis(pc,'MouseX')
            log('[FreeCamera] 动作输入层登记读回：block=true priority=10000 component_owner=observer raw_W='..rawW..' raw_MouseX='..rawMouse..'；跳跃/攻击屏蔽效果待实测')
            for _,guard in ipairs({{'move_owned',moveIgnored,'SetIgnoreMoveInput','IsMoveInputIgnored'},
                    {'look_owned',lookIgnored,'SetIgnoreLookInput','IsLookInputIgnored'}})do
                if not guard[2] then
                    record[guard[1]]='1';save(record)
                    assert(call(pc,guard[3],true),'input guard failed')
                    local read,actual=call(pc,guard[4]);assert(read and actual==true,'input guard not verified')
                end
            end
            assert(call(pc,'SetViewTargetWithBlend',camera,0,0,0,false),'view target request failed')
            local read,actual=call(pc,'GetViewTarget')
            assert(read and same(actual,camera),'view target not verified')
            assert(same(U.field(pc,'Player'),player) and same(U.field(pc,'Pawn'),pawn),'original player/controller association changed')
            if options.guard then options.guard:enter(guardContext(record)) end
            self.session={pc=pc,player=player,pawn=pawn,world=world,lib=lib,camera=camera,position=location,rotation=rotation,lastTime=now}
            self.active=true
            self.handle=LoopInGameThreadWithDelay(16,function()self:tick()end)
            assert(self.handle~=nil and self.handle~=false,'camera timer registration not confirmed')
            log('[FreeCamera] 已进入；原控制器/Player/Pawn关联读回=true；view_target='..record.camera..'；面板或自定义键退出，WASD移动、Q/E升降、Shift加速、鼠标转向')
        end)
        if not ok then
            log('[FreeCamera] 进入未完成：'..tostring(err))
            local restored,why=pcall(function()return self:stop('进入失败')end)
            if not restored then log('[FreeCamera] 失败回滚待确认：'..tostring(why)) end
        end
        return ok
    end
    function self:toggle()if self.active then return self:stop('切换自由观战') else return self:enter()end end
    function self:silence()
        self.alive=false;self.active=false;self.session=nil
        if self.handle then pcall(CancelDelayedAction,self.handle);self.handle=nil end
        if self.record then log('[FreeCamera] 卸载保留恢复记录；下一次游戏线程恢复，不在卸载线程访问对象') end
    end
    return self
end
return Camera
