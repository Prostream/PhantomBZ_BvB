-- Pure match state; engine calls injected by main.lua. No damage/health writes.
local Director={}
local PRESET={
    {'blue','BP_Monster_GuiChai_Red'}, {'blue','BP_Monster_GuiChai_Yellow_MoDao'},
    {'blue','BP_Monster_GuiChai_Yellow_ShuangGou'}, {'blue','BP_Monster_GuiChai_Cyan_ShuangYue'},
    {'red','BP_Monster_BiYuan'}, {'red','BP_Monster_CanQu_BiHai'},
    {'red','BP_Monster_WuLengShuang'}, {'red','BP_Monster_YuBi'},
}
local function finite(x)return type(x)=='number' and x==x and math.abs(x)<1e9 end
local function result(ok,message)return {ok=ok,message=message,spawned_count=0} end
local function copy(p)return {x=p.x,y=p.y,z=p.z,yaw=p.yaw} end
local function pose(p)return type(p)=='table' and finite(p.x) and finite(p.y) and finite(p.z) and finite(p.yaw) end
local function rotate(x,y,a)a=math.rad(a);return x*math.cos(a)-y*math.sin(a),x*math.sin(a)+y*math.cos(a) end
function Director.new(o)
    local self={state='intro',roster={},message='召唤后定身，保存站位后开战',saved=nil,expected=nil,invalid=false}
    local settings=o.path..'/bvb-lineup.tsv'
    local function read()
        local f=io.open(settings,'rb');if not f then return nil end
        local s=f:read(1048577);f:close();return s
    end
    local function decode(s)
        if not s or #s>1048576 then return nil end
        local lines={};for l in s:gmatch('[^\r\n]+')do lines[#lines+1]=l end
        local world,x,y,z,yaw
        if lines[1] then world,x,y,z,yaw=lines[1]:match('^BVBLineup1\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)$') end
        local plan={world=world,anchor={x=tonumber(x),y=tonumber(y),z=tonumber(z),yaw=tonumber(yaw)},rows={}}
        if not world or not pose(plan.anchor) then return nil end
        for i=2,#lines do
            local team,path,a,b,c,d=lines[i]:match('^(%a+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)$')
            local p={x=tonumber(a),y=tonumber(b),z=tonumber(c),yaw=tonumber(d)}
            if (team~='blue' and team~='red') or not path or not path:match('^/[%w_/]+%.[%w_]+_C$') or not pose(p) then return nil end
            plan.rows[#plan.rows+1]={team=team,path=path,pose=p}
        end
        if #plan.rows<1 or #plan.rows>100 then return nil end
        return plan
    end
    self.saved=decode(read())
    local function write(plan)
        local a=plan.anchor
        local lines={table.concat({'BVBLineup1',plan.world,string.format('%.17g',a.x),string.format('%.17g',a.y),string.format('%.17g',a.z),string.format('%.17g',a.yaw)},'\t')}
        for _,r in ipairs(plan.rows)do local p=r.pose
            lines[#lines+1]=table.concat({r.team,r.path,string.format('%.17g',p.x),string.format('%.17g',p.y),string.format('%.17g',p.z),string.format('%.17g',p.yaw)},'\t')
        end
        local s=table.concat(lines,'\n')..'\n';local f=io.open(settings,'wb')
        if not f then return false end
        local ok=f:write(s);local closed=f:close()
        if ok and closed and read()==s then self.saved=plan;return true end
        return false
    end
    function self:beforeSpawn(path,team)
        if team~='blue' and team~='red' then return false,'摄影棚只接受蓝红参赛者' end
        if self.state=='running' or self.state=='ended' or self.state=='error' then return false,'请先重置或清场，再调整阵容' end
        local ok,why=o.rules();if not ok then return false,why end
        if not o.hold:recover() then return false,'定身恢复未确认' end
        return true
    end
    function self:spawned(actor,path,team)
        local p=o.pose(actor);local maximum=o.maxHP(actor);local hp=o.hp(actor)
        if not pose(p) or not finite(maximum) or maximum<=0 or not finite(hp) then
            self.state='error';self.message='出生位置或生命不可读，请清场';return false
        end
        self.roster[#self.roster+1]={actor=actor,path=path,team=team,pose=copy(p),maximum=maximum,hp=hp,dead=false}
        if not o.hold:apply(actor) then self.state='error';self.message='定身写入未确认，请清场';return false end
        return true
    end
    function self:save()
        if self.state~='intro' or #self.roster==0 then return result(false,'仅能在完整介绍状态保存阵容') end
        local anchor,world=o.anchor(),o.world()
        if not pose(anchor) or not world or world:find('[\t\r\n]') then return result(false,'地图或玩家位置不可读') end
        local plan={world=world,anchor=copy(anchor),rows={}}
        for _,r in ipairs(self.roster)do
            local p=o.pose(r.actor)
            if not o.valid(r.actor) or not pose(p) or not finite(o.hp(r.actor)) or o.hp(r.actor)<=0 then return result(false,'参赛者无效，不能保存不完整阵容') end
            plan.rows[#plan.rows+1]={team=r.team,path=r.path,pose=copy(p)}
        end
        if not write(plan) then return result(false,'阵容文件保存或读回失败') end
        return result(true,'阵容与当前站位已保存（'..#plan.rows..'名）')
    end
    function self:beforeStart()
        if self.state~='intro' or self.invalid then return false,'仅能从完整介绍状态开战；异常请重置' end
        local ok,why=o.rules();if not ok then return false,why end
        local saved=self:save();if not saved.ok then return false,saved.message end
        if not o.hold:release() then self.state='error';return false,'解除定身未全部读回，未开战' end
        self.state='running';self.winner=nil;self.started=o.now();self.ended=nil
        return true
    end
    function self:clear()
        if not o.hold:release() then return result(false,'解除定身失败，未继续清理') end
        local r=o.stop()
        if not r.ok then self.state='error';self.message=r.message;return r end
        self.roster={};self.state='intro';self.invalid=false;self.winner=nil;self.started=nil;self.ended=nil
        self.message='已清场；可加载预设或重新布置'
        return r
    end
    function self:restore(here)
        -- Validate everything possible BEFORE destroying the current match.
        local plan=decode(read());if not plan then return result(false,'没有有效保存阵容；未清场') end
        local ok,why=o.rules();if not ok then return result(false,why) end
        local anchor,world=o.anchor(),o.world()
        if not pose(anchor) or not world then return result(false,'当前位置不可读') end
        if not here and (world~=plan.world or (anchor.x-plan.anchor.x)^2+(anchor.y-plan.anchor.y)^2>10000^2) then
            return result(false,'地图或位置已变化，请用“在当前位置布置”')
        end
        for _,r in ipairs(plan.rows)do if not o.canSpawn(r.path) then return result(false,'保存阵容中存在不可生成单位，未清场') end end
        local stopped=self:clear();if not stopped.ok then return stopped end
        for _,r in ipairs(plan.rows)do
            local p=copy(r.pose)
            if here then
                local x,y=rotate(p.x-plan.anchor.x,p.y-plan.anchor.y,anchor.yaw-plan.anchor.yaw)
                p={x=anchor.x+x,y=anchor.y+y,z=anchor.z+p.z-plan.anchor.z,yaw=p.yaw+anchor.yaw-plan.anchor.yaw}
            end
            local spawned=o.spawn(r.path,r.team,p)
            if not spawned.ok or spawned.spawned_count~=1 then
                self.state='error';self.message='重置未完成，请清场检查：'..tostring(spawned.message)
                return result(false,self.message)
            end
        end
        local saved=self:save();if not saved.ok then self.state='error';return saved end
        self.message='比赛已重置，参赛者定身等待介绍和开战'
        return result(true,self.message)
    end
    function self:applyRequest(revision)
        if self.state=='running' then return result(false,'交战中不能应用新阵容，请先清场') end
        if type(revision)~='string' or not revision:match('^%d+$') then return result(false,'阵容请求编号无效') end
        local f=io.open(o.path..'/bvb-request.tsv','rb')
        if not f then return result(false,'阵容请求文件不存在，未清场') end
        local data=f:read(65537);f:close()
        if #data>65536 or data:sub(-1)~='\n' then return result(false,'阵容请求不完整，未清场') end
        local lines={};for line in data:gmatch('([^\n]*)\n')do lines[#lines+1]=line end
        if lines[1]~='BVBDraft1\t'..revision then return result(false,'阵容请求已变化，未清场') end
        local rows={};local counts={blue=0,red=0}
        for i=2,#lines do
            local team,path=lines[i]:match('^(%a+)\t(/[%w_/]+%.[%w_]+_C)$')
            if not counts[team] or not path or #path>512 or not o.canSpawn(path) then return result(false,'阵容包含无效或不支持的单位，未清场') end
            counts[team]=counts[team]+1;rows[#rows+1]={team=team,path=path}
        end
        if #rows>100 or counts.blue==0 or counts.red==0 then return result(false,'阵容需两队各至少一人，总数不超过100，未清场') end
        local ok,why=o.rules();if not ok then return result(false,why) end
        local anchor,world=o.anchor(),o.world()
        if not pose(anchor) or not world then return result(false,'当前位置不可读，未清场') end
        local cleared=self:clear();if not cleared.ok then return cleared end
        local slots={blue=0,red=0}
        for _,row in ipairs(rows)do
            local slot=slots[row.team];slots[row.team]=slot+1
            local side=row.team=='blue' and -1 or 1
            -- Up to four abreast, then rows behind; teams face each other.
            local width=math.min(4,counts[row.team])
            local x,y=rotate(800+(slot%4-(width-1)/2)*350,side*(650+math.floor(slot/4)*400),anchor.yaw)
            local spawned=o.spawn(row.path,row.team,{x=anchor.x+x,y=anchor.y+y,z=anchor.z+30,yaw=anchor.yaw-side*90})
            if not spawned.ok or spawned.spawned_count~=1 then
                self.state='error';self.message='应用阵容未完成，请清场检查：'..tostring(spawned.message)
                return result(false,self.message)
            end
        end
        local saved=self:save();if not saved.ok then self.state='error';return saved end
        self.message='新阵容已布置并保存，定身等待开战（蓝 '..counts.blue..' / 红 '..counts.red..'）'
        return result(true,self.message)
    end
    function self:preset()
        if #o.members()>0 then return result(false,'请先清场，再加载首场 4 对 4') end
        local paths={}
        for _,r in ipairs(PRESET)do
            local path=o.resolve(r[2]);if not path then return result(false,'目录尚未找到 '..r[2]..'，请先刷新游戏图鉴') end
            paths[#paths+1]={team=r[1],path=path}
        end
        local anchor=o.anchor();if not pose(anchor) then return result(false,'玩家位置不可读') end
        for i,r in ipairs(paths)do
            local row=(i-1)%4;local side=r.team=='blue' and -1 or 1
            local x,y=rotate(800+(row-1.5)*350,side*650,anchor.yaw)
            local p={x=anchor.x+x,y=anchor.y+y,z=anchor.z+30,yaw=anchor.yaw-side*90}
            local s=o.spawn(r.path,r.team,p)
            if not s.ok or s.spawned_count~=1 then self.state='error';return result(false,'预设未完成：'..tostring(s.message)) end
        end
        return self:save()
    end
    function self:tick()
        if not o.hold:recover() then self.invalid=true;return end
        if self.state=='intro' then
            for _,u in ipairs(o.members())do
                if u.summoner and (u.team=='blue' or u.team=='red') and not o.hold:apply(u.actor) then self.invalid=true end
            end
        end
        local totals={blue={hp=0,max=0,alive=0,unknown=0,count=0},red={hp=0,max=0,alive=0,unknown=0,count=0}}
        for _,r in ipairs(self.roster)do
            local t=totals[r.team];t.count=t.count+1;t.max=t.max+r.maximum
            local hp=o.valid(r.actor) and o.hp(r.actor) or nil
            if finite(hp) then r.hp=math.max(0,hp);r.dead=hp<=0
            elseif not r.dead then t.unknown=t.unknown+1 end
            t.hp=t.hp+math.min(r.maximum,math.max(0,r.hp))
            if not r.dead then t.alive=t.alive+1 end
        end
        self.totals=totals
        if self.state=='running' and totals.blue.count>0 and totals.red.count>0 and totals.blue.unknown+totals.red.unknown==0 then
            if totals.blue.alive==0 or totals.red.alive==0 then
                self.state='ended';self.ended=o.now()
                self.winner=totals.blue.alive==0 and (totals.red.alive==0 and 'draw' or 'red') or 'blue'
                o.finish()
                for _,u in ipairs(o.members())do if o.valid(u.actor) and finite(o.hp(u.actor)) and o.hp(u.actor)>0 then o.hold:apply(u.actor) end end
                self.message='本体全灭判定：'..self.winner..'；召唤物不独立续赛'
            end
        end
    end
    function self:status()
        local s={bvb_editor_version=1,bvb_state=self.state,bvb_message=self.message,bvb_saved=self.saved~=nil,bvb_winner=self.winner or '',
            bvb_seconds=self.started and math.max(0,(self.ended or o.now())-self.started) or 0,bvb_invalid=self.invalid}
        for _,team in ipairs({'blue','red'})do local t=(self.totals or {})[team] or {hp=0,max=0,alive=0,unknown=0,count=0}
            for k,v in pairs(t)do s['bvb_'..team..'_'..k]=v end
        end
        return s
    end
    return self
end
return Director
