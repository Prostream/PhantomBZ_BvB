-- 本地面板与快捷键共用同一组动作。所有游戏回调均在游戏线程执行。
local Bridge = require("panel_bridge")
local KeyRouter=require('key_router')
local FunctionKeys=require('function_keybinds')
local Runtime = {}
Runtime.__index = Runtime
local ACTIONS = FunctionKeys.actions

local function read(path)
    local file=io.open(path,'r');if not file then return nil end
    local text=file:read('*a');file:close();return text
end

function Runtime.new(options)
    local self=setmetatable({options=options,alive=true,pumpReady=false},Runtime)
    self.log=options.log or function() end
    self.router=options.router or KeyRouter.new({log=self.log})
    self.functionKeys=FunctionKeys.new({path=options.path,router=self.router,log=self.log,
        unitOwner=function(vk)
            local unit=options.unitKeys and options.unitKeys:owner(vk)
            return unit and ((unit:match('%.([^%.]+)$') or unit):gsub('_C$',''))
        end,dispatch=function(action)self:dispatch(action,{})end})
    self.router.dispatch=function(vk,mask)
        if not self.alive then return end
        if not self.functionKeys:press(vk,mask) and options.unitKeys then options.unitKeys:dispatch(vk,mask)end
    end
    local function readyError()
        if not options.session then return "未配置游戏会话校验" end
        local status=options.session:status()
        if status.game_ready~=true then return status.game_ready_reason or "游戏尚未就绪" end
    end
    self.handlers={
        spawn=function(command)
            local why=readyError(); if why then return {ok=false,message=why,spawned_count=0} end
            return options.arena:spawn(command.unit_id,command.team,command.count)
        end,
        select_unit=function(command) return options.arena:select(command.unit_id,command.team,command.count) end,
        cycle_team=function() return options.arena:cycleTeam() end,
        toggle_camera=function()
            if not options.camera then return {ok=false,message='自由观战模块未加载',spawned_count=0}end
            local status=options.camera:status()
            if status.active or status.pending then return options.camera:exit()end
            local why=readyError();if why then return {ok=false,message=why,spawned_count=0}end
            return options.camera:toggle()
        end,
        exit_camera=function()
            if not options.camera then return {ok=false,message='自由观战模块未加载',spawned_count=0}end
            return options.camera:exit()
        end,
        toggle_stat_match=function()
            if not options.statMatch then return {ok=false,message='数值统一模块未加载',spawned_count=0} end
            return options.statMatch:toggle()
        end,
        -- The difficulty token travels in the key_spawn column (FOLLOW, EASY, NORMAL, HARD, NIGHTMARE).
        set_spawn_difficulty=function(command)
            if not options.spawnDifficulty then return {ok=false,message='召唤难度模块未加载',spawned_count=0} end
            return options.spawnDifficulty:set(command.key_spawn)
        end,
        start=function()
            local why=readyError(); if why then return {ok=false,message=why,spawned_count=0} end
            return options.arena:start()
        end,
        stop=function()
            if options.support then options.support:discover() end
            return options.arena:stop()
        end,
        clear_neutral=function()
            if options.support then options.support:discover() end
            return options.arena:clearNeutral()
        end,
        dismiss_companions=function()
            if options.support then options.support:discover() end
            return options.arena:clearCompanions()
        end,
        toggle_spectator=function()
            local why=readyError(); if why then return {ok=false,message=why,spawned_count=0} end
            if not options.spectator then return {ok=false,message="无仇恨模块未加载",spawned_count=0} end
            local result=options.spectator:toggle()
            return {ok=result.ok==true,message=result.message or "观战模式已请求切换",spawned_count=0}
        end,
        refresh_catalog=function()
            if options.references then options.references:silence('重新核对目录');self.referencesStarted=false end
            if options.spawnCatalog and not readyError() then options.spawnCatalog:export() end
            if options.tableCatalog and not readyError() then options.tableCatalog:export() end
            if options.codex and not readyError() then
                local codex=options.codex:export()
                self.log("原生图鉴读取="..tostring(codex.ok).."；"..tostring(codex.message))
            end
            if options.exporter:status().active then
                return {ok=true,message="正在读取单位目录，请等待进度更新",spawned_count=0}
            end
            local ok,status=options.exporter:start()
            return {ok=ok,message=ok and "已开始读取游戏资源目录" or tostring(status.message or status.error or status.reason or "目录扫描未启动"),spawned_count=0}
        end,
        configure_keys=function(command)
            local proposal={}
            for _,name in ipairs(ACTIONS)do
                proposal[name]=command['key_'..name] or self.functionKeys.entries[name]
            end
            return self:configure(proposal)
        end,
        configure_unit_key=function(command)
            if not options.unitKeys then return {ok=false,message='单位快捷键模块未加载',spawned_count=0} end
            local key=command.key_spawn=='UNBOUND' and 0 or tonumber((command.key_spawn or ''):match('^VK_(%d+)$'))
            local mask=tonumber((command.key_start or ''):match('^MOD_(%d+)$'))
            -- FIXED in the key_stop column: the row's team and count belong to this unit's key.
            if command.key_stop=='FIXED' then return options.unitKeys:configure(command.unit_id,key,mask,command.team,command.count) end
            return options.unitKeys:configure(command.unit_id,key,mask)
        end,
    }
    self.bridge=Bridge.new({path=options.path,log=self.log,handlers=self.handlers,
        session=function() return options.session and options.session:status() or {} end,status=function()
        local arena=options.arena:status()
        local catalog=options.exporter:status()
        local spectator=options.spectator and options.spectator:status() or {}
        local out={build=options.build,blue_count=arena.blue_count,red_count=arena.red_count,
            neutral_count=arena.neutral_count,total=arena.total,current_unit=arena.current_unit,
            current_team=arena.current_team,current_count=arena.current_count,
            arena_state=arena.state,arena_message=arena.message,
            catalog_state=catalog.active and "scanning" or (catalog.complete and "complete" or catalog.reason),
            catalog_message=string.format("%s / %s 路径 · %s 个候选 · %s",tostring(catalog.paths_done),tostring(catalog.paths_total),tostring(catalog.candidates),tostring(catalog.reason)),catalog_paths_done=catalog.paths_done,
            catalog_paths_total=catalog.paths_total,catalog_truncated=catalog.truncated,
            catalog_started_at=catalog.started_at,
            catalog_coverage=catalog.coverage,catalog_candidates=catalog.candidates}
        local session=options.session and options.session:status() or {}
        local policy=options.spawnPolicy and options.spawnPolicy.status() or {}
        out.spawn_trial_policy=policy.version or ''
        out.spawn_trial_count=policy.count or 0
        out.spawn_mode=policy.mode or 'validated'
        out.arena_owned_records=arena.owned_records
        out.arena_dead_count=arena.dead_count
        out.arena_unreadable_count=arena.unreadable_count
        out.arena_max_units=arena.max_units
        out.neutral_owned_records=arena.neutral_owned
        out.companion_count=arena.companion_count or 0
        out.companion_owned_records=arena.companion_owned or 0
        local companion=options.companions and options.companions:status() or {}
        out.companion_supported=not not options.companions
        out.companion_follow=companion.follow or 0
        out.companion_friendly=companion.friendly or 0
        out.companion_failures=companion.failures or 0
        out.companion_message=companion.message or ''
        out.arena_team_revision=arena.team_revision or 0
        out.arena_summon_count=arena.summon_count or 0
        local support=options.support and options.support:status() or {}
        out.boss_hud_registered=support.registered or 0
        out.boss_hud_visible=support.visible or 0
        out.boss_hud_pending=support.pending or 0
        out.boss_hud_health_verified=support.health_verified or 0
        out.boss_hud_names_verified=support.names_verified or 0
        out.boss_hud_numbers_verified=support.numbers_verified or 0
        out.arena_full_update_count=support.full_update_count or 0
        out.arena_bone_refresh_count=support.bone_refresh_count or 0
        out.npc_grab_events=support.grab_events or 0
        out.npc_grab_pairs=support.grab_pairs or 0
        out.npc_grab_restore_pending=support.grab_restore_pending==true
        out.arena_free_camera=support.free_camera==true
        out.observer_health_verified=support.observer_health_verified==true
        out.observer_message=support.observer_message or ''
        local matching=options.statMatch and options.statMatch:status() or {}
        out.stat_match_supported=not not options.statMatch
        out.stat_match_enabled=matching.enabled
        out.stat_match_baseline_unit=matching.baseline_unit or ''
        out.stat_match_health=matching.health
        out.stat_match_shachi=matching.shachi
        out.stat_match_attack=matching.attack
        out.stat_match_shachi_attack=matching.shachi_attack
        out.stat_match_count=matching.matched or 0
        out.stat_match_failures=matching.failures or 0
        out.stat_match_message=matching.message or ''
        out.stat_match_fields=matching.field_count or 0
        local difficulty=options.spawnDifficulty and options.spawnDifficulty:status() or {}
        out.spawn_difficulty_supported=not not options.spawnDifficulty
        out.spawn_difficulty=difficulty.level or ''
        out.spawn_difficulty_game=difficulty.game or ''
        out.spawn_difficulty_applied=difficulty.applied or 0
        out.spawn_difficulty_skipped=difficulty.skipped or 0
        out.spawn_difficulty_failures=difficulty.failures or 0
        out.spawn_difficulty_message=difficulty.message or ''
        -- ai_difficulty.lua: whether the summoned units' AI checks answered their own level on readback.
        local ai=options.aiDifficulty and options.aiDifficulty:status() or {}
        out.spawn_difficulty_ai=ai.state or ''
        out.spawn_difficulty_ai_verified=ai.verified or 0
        out.spawn_difficulty_ai_failed=ai.failed or 0
        local unitKeys=options.unitKeys and options.unitKeys:status() or {}
        out.unit_keys_epoch=unitKeys.epoch or ''
        out.unit_keys_revision=unitKeys.revision or 0
        out.unit_keys_event=unitKeys.event or 0
        out.unit_keys_last_unit=unitKeys.unit or ''
        out.unit_keys_message=unitKeys.message or ''
        out.game_session=session.game_session
        out.game_ready=session.game_ready
        out.game_ready_reason=session.game_ready_reason
        out.spectator_enabled=spectator.enabled_requested
        out.spectator_flag_readback=spectator.player_can_be_hatred_readback
        out.spectator_pending_relations=spectator.pending_relations
        out.spectator_pending_flags=spectator.pending_flags
        out.spectator_message=spectator.message
        out.spectator_read_failures=spectator.readFailures
        local functions=self.functionKeys:status()
        out.function_keys_schema=2;out.function_keys_epoch=functions.epoch;out.function_keys_revision=functions.revision
        for _,action in ipairs(ACTIONS) do out['key_'..action]=self.functionKeys:token(action)end
        return out
    end})
    return self
end
function Runtime:unitKeyReserved(vk)
    local _,label=self.functionKeys:owner(vk);return label
end
function Runtime:unitKeyShared(vk)
    return self.router.installed[vk..':0']~=nil
end
function Runtime:configure(proposal)
    local result=self.functionKeys:configure(proposal)
    if result.ok and self.options.unitKeys then self.options.unitKeys:refresh()end
    return result
end
function Runtime:dispatch(action,command)
    if not self.alive then return end
    local handler=self.handlers[action]
    if not handler then return end
    local ok,result=xpcall(function() return handler(command or {}) end,debug.traceback)
    if not ok then self.log(action.." Lua失败: "..tostring(result)); return end
    self.log(action.." 结果="..tostring(result and result.ok).."；"..tostring(result and result.message))
    return result
end
function Runtime:start()
    if self.started then return self.pumpReady end
    self.started=true
    self.functionKeys:start()
    if self.options.unitKeys then self.options.unitKeys:start() end
    if type(LoopInGameThreadWithDelay)~="function" or type(CancelDelayedAction)~="function" then
        self.log("面板轮询未启动：缺少LoopInGameThreadWithDelay或CancelDelayedAction；未回退异步排队循环")
        return false
    end
    -- 宿主持有一个稳定的周期回调引用；每轮不再注册新的游戏线程闭包。
    local function pumpBody()
        if not self.codexChecked and self.options.codex and self.options.session
            and self.options.session:status().game_ready==true then
            self.codexChecked=true
            local result=self.options.codex:export()
            self.log("原生中文图鉴首次读取="..tostring(result.ok).."；"..tostring(result.message))
        end
        if not self.spawnCatalogChecked and self.options.spawnCatalog and self.options.session
            and self.options.session:status().game_ready==true then
            self.spawnCatalogChecked=true
            local result=self.options.spawnCatalog:export()
            self.log('已加载地图刷怪配置读取='..tostring(result.ok)..'；不是全部World分区覆盖')
        end
        if not self.tableCatalogChecked and self.options.tableCatalog and self.options.session
            and self.options.session:status().game_ready==true then
            self.tableCatalogChecked=true;self.options.tableCatalog:export()
        end
        if not self.initialScanChecked and (not self.options.fullInventory or (self.options.session and self.options.session:status().game_ready==true)) then
            self.initialScanChecked=true
            local inventoryStatus=self.options.fullInventory and read(self.options.path..'/asset-index-status.tsv') or nil
            local needed=self.options.fullInventory and (not inventoryStatus or not inventoryStatus:find('\ncomplete\ttrue\n',1,true))
                or (not self.options.fullInventory and not read(self.options.path..'/catalog.tsv'))
            if self.options.autoScan and needed then
                local started,state=self.options.exporter:start()
                self.log("首次目录自动读取="..tostring(started).."；读回状态="..tostring(state.reason))
            end
        end
        self.options.exporter:tick()
        if self.options.references then
            local inventory=self.options.exporter:status()
            if not self.referencesStarted and not inventory.active and inventory.paths_total>0
                and inventory.paths_done==inventory.paths_total and self.options.exporter.referencePackages then
                self.referencesStarted=true;self.options.references:start(self.options.exporter:referencePackages())
            end
            self.options.references:tick()
        end
        if self.options.spectator then self.options.spectator:tick() end
        self.healthTicks=(self.healthTicks or 0)+1
        if self.healthTicks%4==0 and self.options.arena.sampleHealth then self.options.arena:sampleHealth() end
        if self.healthTicks%2==0 and self.options.support then self.options.support:tick() end
        self.bridge:tick()
    end
    -- A whole pump slower than 15 ms is logged (at most 60 times per Lua lifetime) to find stutter.
    local slowPumps=0
    self.pumpCallback=function()
        if not self.alive or not self.pumpReady then return end
        local started=os.clock()
        local ok,err=xpcall(pumpBody,debug.traceback)
        local spent=(os.clock()-started)*1000
        if spent>=15 and slowPumps<60 then
            slowPumps=slowPumps+1
            self.log(string.format('[Perf] 面板轮询耗时 %.1fms',spent))
        end
        if not ok and self.lastError~=tostring(err) then
            self.lastError=tostring(err); self.log("面板轮询失败: "..tostring(err))
        end
        -- 此API忽略回调返回值；停止必须明确CancelDelayedAction(handle)。
    end
    local ok,handle=pcall(LoopInGameThreadWithDelay,250,self.pumpCallback)
    if not ok or handle==nil or handle==false then
        self.log("面板轮询注册未确认："..tostring(handle).."；未回退异步排队循环")
        return false
    end
    self.pumpHandle=handle
    self.pumpReady=true
    self.log("面板周期任务已注册；handle读回="..tostring(handle).."；实际心跳待tick验证；目录: "..self.options.path)
    return true
end
function Runtime:silence()
    self.alive=false
    self.functionKeys:silence();self.router:silence()
    if self.options.unitKeys then self.options.unitKeys:silence() end
    self.pumpReady=false
    if self.pumpHandle~=nil then
        local handle=self.pumpHandle
        local ok,result=pcall(CancelDelayedAction,handle)
        self.log("面板宿主任务取消调用="..tostring(ok).."；handle="..tostring(handle).."；返回="..tostring(result).."；未执行游戏对象恢复")
        if ok and result~=false then self.pumpHandle=nil end
    end
    self.options.exporter:silence("Mod卸载")
    if self.options.references then self.options.references:silence('Mod卸载') end
    if self.options.spectator then self.options.spectator:silence("Mod卸载") end
end
return Runtime
