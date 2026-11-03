local U=require('ue_observe')
local Hold=require('bvb_hold')
local Director=require('bvb_director')
local Engine={}
function Engine.new(o)
    local function valid(actor)
        if not U.valid(actor) then return false end
        local ok,dying=pcall(function()return actor:IsActorBeingDestroyed()end)
        return ok and not dying
    end
    local function pose(actor)
        if not valid(actor) then return nil end
        local ok,p=pcall(function()
            local loc=actor:K2_GetActorLocation()
            if not valid(actor) then return nil end
            local f=actor:GetActorForwardVector()
            local x,y=U.struct(f,'X'),U.struct(f,'Y')
            if type(x)~='number' or type(y)~='number' then return nil end
            local atan=math.atan2 or math.atan
            return {x=U.struct(loc,'X'),y=U.struct(loc,'Y'),z=U.struct(loc,'Z'),yaw=math.deg(atan(y,x))}
        end)
        return ok and p or nil
    end
    local hold=Hold.new({path=o.path,log=o.log,valid=valid,key=U.key,
        name=function(a)local name=a:GetFullName();return name:match('^%S+ (.+)$')end,
        find=function(path)local a=StaticFindObject(path);return U.valid(a) and a or nil end,
        get=function(a)return U.field(a,'CustomTimeDilation')end,
        set=function(a,n)
            if not valid(a) then return false end
            return pcall(function()a.CustomTimeDilation=n end)
        end})
    local self
    local function rules(team)
        if o.difficulty:status().game~='Hard' then return false,'请先在游戏中选择逆天者，再召唤；工具不修改存档难度' end
        if o.cycle()~=0 then return false,'需要一周目存档（周目读回须为 0）' end
        local actions={}
        if o.stats:status().mode~='game' then actions[#actions+1]=function()return o.stats:setMode('GAME')end end
        if o.levels:status().mode~='HOME' then actions[#actions+1]=function()return o.levels:configure(nil,'HOME')end end
        if next(o.levels.picks) then return false,'发现手动指定的单位等级，请先在原生等级设置中清除' end
        if o.difficulty:status().level~='HARD' then actions[#actions+1]=function()return o.difficulty:set('HARD')end end
        for _,team in ipairs({'blue','red'})do
            if o.immortal:status()[team] then actions[#actions+1]=function()return o.immortal:set(team,'OFF')end end
        end
        for _,action in ipairs(actions)do local r=action();if not r.ok then return false,r.message end end
        local spectator=o.spectator:status()
        if team=='neutral' and (spectator.enabled_requested or spectator.player_can_be_hatred_readback~=true
            or spectator.pending_relations~=0 or spectator.pending_flags~=0) then
            return false,'请退出自由镜头，并等待主角仇恨资格及关系恢复后再召唤'
        end
        if not self.playerAggro and not spectator.enabled_requested then
            local r=o.spectator:toggle();if not r.ok then return false,r.message end
        end
        return true
    end
    local function resolve(short)
        local f=io.open(o.path..'/codex.tsv','rb');if not f then return nil end
        local found
        for line in f:lines()do
            local path=line:match('^([^\t]+)\t')
            if path and path:match('%.([%w_]+)_C$')==short then
                if found and found~=path then f:close();return nil end
                found=path
            end
        end
        f:close();return found
    end
    self=Director.new({path=o.path,hold=hold,rules=rules,pose=pose,valid=valid,hp=o.hp,maxHP=o.maxHP,
        anchor=function()return pose(o.player())end,
        world=function()
            local w=o.world();if not U.valid(w) then return nil end
            return w:GetFullName()
        end,
        canSpawn=o.canSpawn,resolve=resolve,members=function()return o.arena:members()end,
        stop=function()return o.arena:stop()end,now=o.now,
        finish=function()o.arena:finishRound()end,
        spawn=function(path,team,p)
            local yaw=math.rad(p.yaw)/2
            return o.arena:spawn(path,team,1,{Translation={X=p.x,Y=p.y,Z=p.z},
                Rotation={X=0,Y=0,Z=math.sin(yaw),W=math.cos(yaw)},Scale3D={X=1,Y=1,Z=1}})
        end})
    function self:setPlayerAggro(enabled)
        local result=o.spectator:setEnabled(not enabled)
        if result.enabled_requested==(not enabled) then
            self.playerAggro=enabled
            if enabled then
                result.message=result.ok and '已请求恢复主角仇恨，资格以面板读回为准' or '正在恢复原有仇恨关系，等待面板读回'
            end
        end
        return result
    end
    return self
end
return Engine
