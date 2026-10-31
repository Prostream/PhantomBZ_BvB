-- One-time spawn stat matching. Never follows source damage or heals on a tick.
local Attributes=require('character_stats')
local Match={}
local resources={Health='Health_Max',Shachi='Shachi_Max'}
local positive={Health=true,Shachi=true,Health_Max=true,Shachi_Max=true,Attack=true,ShachiAttack=true}
local strictlyPositive={Health=true,Shachi=true,Health_Max=true,Shachi_Max=true,Attack=true}
function Match.new(options)
    local adapter=options.adapter or Attributes.new()
    local fields=options.fields or Attributes.fields
    local log=options.log or function()end
    local fs=options.io or io
    local settings=options.path..'/stat-match-settings.tsv'
    local self={enabled=false,baseline=nil,matched=0,failures=0,owned=0,message='数值统一已关闭'}
    local f=fs.open(settings,'r')
    if f then
        local text=f:read('*a');f:close()
        self.enabled=text=='StatMatchV1\t1\n'
        if self.enabled then self.message='已开启，等待第一只可用战斗单位作为基准' end
    end
    local function reset(reason)
        self.baseline=nil;self.matched=0;self.failures=0
        self.message=self.enabled and ('等待首只可用战斗单位作为基准；'..reason) or '已关闭，仅影响之后的召唤'
        log('[StatMatch] 基准重置：'..reason)
    end
    function self:toggle()
        local enabled=not self.enabled;local text='StatMatchV1\t'..(enabled and '1' or '0')..'\n'
        local file=fs.open(settings,'w')
        if not file then return {ok=false,message='数值统一开关保存失败',spawned_count=0} end
        local wrote=file:write(text);local closed=file:close()
        file=fs.open(settings,'r');local actual=file and file:read('*a');if file then file:close()end
        if not wrote or not closed or actual~=text then return {ok=false,message='开关保存未读回，未切换',spawned_count=0} end
        self.enabled=enabled;reset(enabled and '开关已开启' or '开关已关闭；场上单位保持当前数值')
        log('[StatMatch] 开关读回 enabled='..tostring(self.enabled))
        return {ok=true,message=self.message,spawned_count=0}
    end
    function self:roster(units)
        self.owned=#units
        if self.owned==0 and self.baseline then reset('本Mod单位已全部清空') end
    end
    local function writeAndRead(actor,field,base)
        if not Attributes.finite(base) or (positive[field] and base<0) or (strictlyPositive[field] and base<=0) then return nil,'无法在有效基础值范围内对齐 '..field end
        local ok,why=adapter:writeBase(actor,field,base)
        if not ok then return nil,why end
        return adapter:read(actor,field)
    end
    local function matchValue(actor,field,wanted)
        local before,why=adapter:read(actor,field);if not before then return false,why end
        if Attributes.close(before.current,wanted) then return true end
        local after;after,why=writeAndRead(actor,field,wanted)
        if not after then return false,why end
        if Attributes.close(after.current,wanted) then return true end
        -- Native ongoing modifiers can scale the base. Calibrate at most twice,
        -- with positive probes; never install a permanent override/health lock.
        local delta=after.base-before.base
        if math.abs(delta)<1e-6 then
            before=after
            after,why=writeAndRead(actor,field,after.base+math.max(0.01,math.abs(after.base)*0.01))
            if not after then return false,why end
            delta=after.base-before.base
        end
        local slope=math.abs(delta)>1e-6 and (after.current-before.current)/delta or 0
        if not Attributes.finite(slope) or slope<=1e-6 then return false,'原生覆盖/限值使属性无法对齐: '..field end
        local base=after.base+(wanted-after.current)/slope
        local final;final,why=writeAndRead(actor,field,base)
        if not final or not Attributes.close(final.current,wanted) then return false,why or ('最终属性未对齐: '..field) end
        return true
    end
    local function rollback(actor,original,touched)
        local ok=true
        local function restore(field)
            local before=adapter:read(actor,field)
            if before and Attributes.close(before.base,original[field].base) and Attributes.close(before.current,original[field].current) then return end
            local called=adapter:writeBase(actor,field,original[field].base)
            if not called then ok=false end
        end
        for i=#touched,1,-1 do
            local field=touched[i]
            if not resources[field] then restore(field) end
        end
        -- Restore the bounds first, otherwise the old health/shachi may be clamped
        -- against the temporary smaller maximum and never return to its snapshot.
        for _,field in ipairs({'Health','Shachi'})do restore(field) end
        for _,field in ipairs(touched)do
            local actual=adapter:read(actor,field)
            if not actual or not Attributes.close(actual.base,original[field].base) or not Attributes.close(actual.current,original[field].current) then ok=false end
        end
        return ok
    end
    function self:onSpawn(actor,unitPath)
        if not self.enabled then return {ok=true,message='数值统一关闭'} end
        local original,why=adapter:snapshot(actor)
        if not original then
            self.message='未统一：'..tostring(why)
            log('[StatMatch] '..self.message..' unit='..tostring(unitPath))
            return {ok=false,message=self.message,rollback_verified=true}
        end
        if not self.baseline then
            local snapshot={}
            for _,field in ipairs(fields)do snapshot[field]=original[field].current end
            self.baseline={unit=unitPath,values=snapshot}
            self.message='已读取首只单位的出生属性，后续召唤按此对齐'
            log('[StatMatch] 基准已捕获 unit='..tostring(unitPath)..' HPmax='..snapshot.Health_Max..' ShachiMax='..snapshot.Shachi_Max
                ..' Attack='..snapshot.Attack..' ShachiAttack='..snapshot.ShachiAttack..' fields='..#fields)
            return {ok=true,baseline=true,message=self.message}
        end
        local targets={};for _,field in ipairs(fields)do targets[field]=self.baseline.values[field]end
        for resource,maxField in pairs(resources)do targets[resource]=targets[maxField] end
        local ordered={};for _,field in ipairs(fields)do ordered[#ordered+1]=field end
        ordered[#ordered+1]='Health';ordered[#ordered+1]='Shachi'
        local touched={};local failure
        for _,field in ipairs(ordered)do
            touched[#touched+1]=field
            local ok,reason=matchValue(actor,field,targets[field])
            if not ok then failure=reason;break end
        end
        if not failure then
            for _,field in ipairs(ordered)do
                local actual=adapter:read(actor,field)
                if not actual or not Attributes.close(actual.current,targets[field]) then failure='批次读回不一致: '..field;break end
            end
        end
        if not failure then
            for _,field in ipairs({'Health_Max','Shachi_Max','Attack','ShachiAttack'})do
                local actual=adapter:nativeValue(actor,field)
                if not Attributes.close(actual,targets[field]) then failure='原生函数独立读回不一致: '..field;break end
            end
        end
        if failure then
            -- Resource values may also change when a maximum is adjusted.
            for _,field in ipairs({'Health','Shachi'})do
                local found=false;for _,name in ipairs(touched)do if name==field then found=true end end
                if not found then touched[#touched+1]=field end
            end
            local restored=rollback(actor,original,touched)
            self.failures=self.failures+1;self.message='数值统一失败：'..tostring(failure)..'；回滚读回='..tostring(restored)
            log('[StatMatch] '..self.message..' unit='..tostring(unitPath))
            return {ok=false,message=self.message,rollback_verified=restored}
        end
        self.matched=self.matched+1
        self.message='后续单位出生属性已读回一致；已有单位不会跟随基准的残血变化'
        log('[StatMatch] 应用并读回 unit='..tostring(unitPath)..' baseline='..self.baseline.unit..' verified='..#ordered..'/'..#ordered
            ..' HP='..targets.Health..' Shachi='..targets.Shachi..' Attack='..targets.Attack..' ShachiAttack='..targets.ShachiAttack)
        return {ok=true,applied=true,message=self.message}
    end
    function self:status()
        local values=self.baseline and self.baseline.values or {}
        return {enabled=self.enabled,baseline_unit=self.baseline and self.baseline.unit or '',matched=self.matched,failures=self.failures,message=self.message,
            health=values.Health_Max,shachi=values.Shachi_Max,attack=values.Attack,shachi_attack=values.ShachiAttack,field_count=#fields}
    end
    return self
end
return Match
