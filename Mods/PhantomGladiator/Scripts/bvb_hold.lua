-- Introduction hold, not a world pause. Only registered arena actors are written.
-- Persist exact object identity and original dilation BEFORE writing; recover on reload.
local Hold={}
function Hold.new(o)
    local self={records={},pending={},message=''}
    local file=o.path..'/bvb-hold.tsv'
    local function read()
        local f=io.open(file,'rb');if not f then return '' end
        local s=f:read(1048577);f:close();return s
    end
    local data=read()
    if #data>1048576 or (data~='' and not data:match('^BVBHold1\n')) then
        self.corrupt=true;self.message='定身恢复记录损坏，请重启游戏并保留日志'
    else
        for key,path,value in data:gmatch('\n([^\t\n]+)\t([^\t\n]+)\t([^\t\n]+)')do
            local n=tonumber(value)
            if n and n>=0 and n<=100 then self.pending[key]={key=key,path=path,before=n}
            else self.corrupt=true end
        end
    end
    local function persist()
        local lines={'BVBHold1'}
        for _,group in ipairs({self.pending,self.records})do
            for key,r in pairs(group)do lines[#lines+1]=key..'\t'..r.path..'\t'..string.format('%.17g',r.before) end
        end
        local s=table.concat(lines,'\n')..'\n'
        local f=io.open(file,'wb');if not f then return false end
        local ok=f:write(s);local closed=f:close()
        return ok~=nil and closed~=nil and read()==s
    end
    function self:recover()
        if self.corrupt then return false end
        if not next(self.pending) then return true end
        for key,r in pairs(self.pending)do
            local actor=o.find(r.path)
            if actor and o.valid(actor) and o.key(actor)==key then
                local current=o.get(actor)
                if current==0 then
                    local ok=o.set(actor,r.before)
                    if not ok or o.get(actor)~=r.before then self.message='定身恢复失败';return false end
                    o.log('[BVB Hold] 热重载恢复 '..r.path..' readback='..tostring(o.get(actor)))
                end
            end
            -- Missing object or different address: prior game/session object no longer exists.
            self.pending[key]=nil
        end
        return persist()
    end
    function self:apply(actor)
        if not self:recover() or not o.valid(actor) then return false end
        local key=o.key(actor);if not key then return false end
        if self.records[key] and o.get(actor)==0 then return true end
        if not self.records[key] then
            local before=o.get(actor);local path=o.name(actor)
            if type(before)~='number' or before~=before or before<=0 or before>100 or not path or path:find('[\t\r\n]') then return false end
            self.records[key]={actor=actor,path=path,before=before}
            if not persist() then self.records[key]=nil;return false end
        end
        local ok=o.set(actor,0);local after=o.get(actor)
        o.log('[BVB Hold] 定身 '..self.records[key].path..' readback='..tostring(after))
        return ok and after==0
    end
    function self:release()
        if not self:recover() then return false end
        local success=true
        for key,r in pairs(self.records)do
            if not o.valid(r.actor) or o.key(r.actor)~=key then self.records[key]=nil
            else
                local ok=o.set(r.actor,r.before);local after=o.get(r.actor)
                o.log('[BVB Hold] 解除 '..r.path..' expected='..r.before..' readback='..tostring(after))
                if ok and after==r.before then self.records[key]=nil else success=false end
            end
        end
        return persist() and success
    end
    return self
end
return Hold
