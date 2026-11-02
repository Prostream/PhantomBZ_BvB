-- Reuse upstream private widget renderer; display totals without writing actor health.
local U=require('ue_observe')
local Renderer=require('arena_hud_widget')
local HUD={}
function HUD.new(o)
    local self={records={},tries={}}
    local renderer=Renderer.new(o)
    function self:sync(director)
        local displayed,private={},{}
        for _,r in ipairs(director.roster)do local key=U.key(r.actor);if key then displayed[key]=true end end
        for _,team in ipairs({'blue','red'})do
            local t=director.totals and director.totals[team]
            local representative
            for _,r in ipairs(director.roster)do
                if r.team==team and U.valid(r.actor) and (not representative or r.hp>representative.hp) then representative=r end
            end
            local record=self.records[team]
            if record and (not representative or record.actor~=representative.actor) then
                if renderer:remove(record) then self.records[team]=nil;record=nil;self.tries[team]=0 end
            end
            if representative and t and t.max>0 then
                local unit={actor=representative.actor,team=team,class_path=representative.path}
                if not record and (self.tries[team] or 0)<3 then
                    self.tries[team]=(self.tries[team] or 0)+1
                    record=renderer:create(unit)
                    if record then record.actor=unit.actor;self.records[team]=record end
                end
                if record then
                    local label=team=='blue' and '蓝队' or '红队'
                    label=label..' · 总生命 · '..t.alive..'/'..t.count
                    if t.unknown>0 then label=label..'（读数待确认）' end
                    renderer:update(record,unit,t.hp,t.max,label,1)
                    local key=U.key(record.widget);if key then private[key]=true end
                end
            end
        end
        renderer:syncNative(displayed,private,false)
    end
    function self:clear()
        for team,r in pairs(self.records)do if renderer:remove(r) then self.records[team]=nil;self.tries[team]=nil end end
        renderer:syncNative({},{},false)
    end
    return self
end
return HUD
