-- ============================================================
-- PhantomGladiator — 《影之刃零》斗蛐蛐 Mod (UE4SS Lua)
-- 让 NPC 互相为敌、召唤单位、观战、慢动作、自由镜头。
-- 功能快捷键在面板配置；首次使用全部未绑定。
-- ============================================================
local Config = require("config")
local UEHelpers = require("UEHelpers")
local Session = require("battle_session")
local CombatProbe = require("combat_probe")
local AttackProfile = require("attack_profile")
local Catalog = require("npc_catalog")
local AssetExporter = require("asset_inventory")
local ArenaController = require("arena_controller")
local PanelRuntime = require("panel_runtime")
local SpectatorMode = require("spectator_mode")
local SpawnPolicy = require("spawn_policy")
local RuntimeSession = require("runtime_session")
local SpawnAudit = require("spawn_audit")
local CodexExporter = require("codex_catalog_export")
local SpawnGuard = require("spawn_guard")
local SpawnInspector = require("spawn_inspector")
local WorldMapCatalog = require("world_map_catalog")
local SpawnCatalog = require("spawn_catalog_export")
local ReferenceAudit = require("asset_reference_audit")
local TableCatalog = require("table_catalog_export")
local SummonLinks = require('arena_summon_links')
local BossHUD = require('arena_hud')
local EngineObjectState = require('engine_object_state')
local UEObserve = require('ue_observe')
local UnitKeys = require('unit_keybinds')
local ArenaActivity = require('arena_activity')
local FreeCamera = require('free_camera')
local GrabStudy = require('grab_study')
local ArenaGrabs = require('arena_grabs')
local StatMatch = require('stat_match')
local ObserverGuard = require('observer_guard')
local SpectatorTargets = require('spectator_targets')
local KeyRouter = require('key_router')

local MOD = "[PhantomGladiator]"
local runLogPath=Config.RuntimePath..'/run-'..os.date('%Y%m%d-%H%M%S')..'.log'
local runLogBytes,runLogWarning=0,false
local function log(msg)
    local line=string.format('%s %s\n',MOD,tostring(msg))
    print(line)
    -- UE4SS.log is overwritten on game restart. Preserve bounded per-load UTF-8
    -- evidence outside the source tree, without touching game save data.
    local durable=os.date('%Y-%m-%d %H:%M:%S')..' '..line
    if runLogBytes+#durable>8*1024*1024 then return end
    local ok,saved=pcall(function()
        local file=io.open(runLogPath,'ab')
        if not file then return false end
        local wrote=file:write(durable)
        local flushed=file:flush()
        local closed=file:close()
        return wrote~=nil and flushed~=nil and closed~=nil
    end)
    if ok and saved then runLogBytes=runLogBytes+#durable
    elseif not runLogWarning then runLogWarning=true;print(MOD..' 独立运行日志写入未确认；UE4SS日志仍保留\n') end
end
local BUILD = "v0.30-custom-keys"
SpawnPolicy.loadTrials(Config.RuntimePath..'/spawn-trials.tsv',log)
SpawnPolicy.enableAllCatalog()
log('[SpawnPolicy] 用户开启全部目录尝试召唤；总量不设上限；运行时检查Actor继承和对象有效性')
local function safeValid(obj)
    if obj == nil then return false end
    local ok, value = pcall(function() return obj:IsValid() end)
    return ok and value == true
end
local engineObjectState=EngineObjectState.new({log=log})
local function engineValid(obj)
    return safeValid(obj) and engineObjectState:check(obj)~=false
end
UEObserve.setEngineValidator(function(obj) return engineObjectState:check(obj) end)
local function checked(obj)
    if not safeValid(obj) then error("object invalid; access refused") end
    return obj
end
local function objectName(obj)
    if not safeValid(obj) then return "UNKNOWN(invalid)" end
    local ok, value = pcall(function() return obj:GetFullName() end)
    return ok and tostring(value) or "UNKNOWN(name)"
end
local function actorIsDestroying(actor)
    checked(actor)
    return actor:IsActorBeingDestroyed()
end
local battle = Session.new(log)
local probeFinished
local probe = CombatProbe.new({log=log, valid=safeValid, config=Config.Probe,
    onStop=function(state) if probeFinished then probeFinished(state) end end})
local probeSampleGen = 0
local attackProfile = AttackProfile.new({log=log,valid=safeValid})
local arenaActors = {}
local arenaOwned = {}
local spawnRoutes={}
local arena
local panelRuntime
local spectator
local bossHUD
local arenaActivity
local arenaGrabs
local statMatch
local BeginArenaObservation
local spawnAudit=SpawnAudit.new(Config.RuntimePath.."/spawn-attempts.tsv",log)
local spawnGuard=SpawnGuard.new()
local spawnInspector=SpawnInspector.new({log=log,canSpawn=SpawnPolicy.check})


local function FNameToString(v)
    local ok, s = pcall(function() return v:ToString() end)
    if ok and s then return s end
    return tostring(v)
end

-- ---------- 基础工具 ----------

-- 真正的玩家控制器：持有 UPlayer、且不是调试相机
local function GetRealPlayerController()
    local ok, list = pcall(FindAllOf, "PlayerController")
    if not ok or not list then return nil end
    for _, pc in ipairs(list) do
        local okP, good = pcall(function()
            if not pc:IsValid() then return false end
            local cls = pc:GetClass()
            if not safeValid(cls) or objectName(cls):find("DebugCameraController") then return false end
            local player = pc.Player
            return safeValid(player)
        end)
        if okP and good then return pc end
    end
    return nil
end

local function GetPlayerPawn()
    local pc = GetRealPlayerController()
    if pc then
        local ok, p = pcall(function() return pc.Pawn end)
        if ok and p and p:IsValid() then return p end
    end
    local ok, pawn = pcall(function()
        local upc = UEHelpers.GetPlayerController()
        return upc and upc:IsValid() and upc.Pawn or nil
    end)
    if ok and pawn and pawn:IsValid() then return pawn end
    return nil
end

local function GetLocation(actor)
    if not safeValid(actor) then return nil end
    local ok, loc = pcall(function() return actor:K2_GetActorLocation() end)
    if ok and loc then return loc end
    return nil
end

local function DistSq(a, b)
    local dx, dy, dz = a.X - b.X, a.Y - b.Y, a.Z - b.Z
    return dx * dx + dy * dy + dz * dz
end

local function IsExcluded(pawn)
    if not safeValid(pawn) then return true end
    local ok, name = pcall(function() return pawn:GetFullName() end)
    if not ok or not name then return true end
    for _, kw in ipairs(Config.ExcludeClassKeywords) do
        if name:find(kw) then return true end
    end
    return false
end

local function GetGameplayStatics()
    local gps = StaticFindObject("/Script/Engine.Default__GameplayStatics")
    if gps and gps:IsValid() then return gps end
    return nil
end

local playerNeutral = false
local dilationIndex = 1

-- 旧态度返回值修改已移除。脚本态度函数由 CombatProbe 正确注册只读回调。

-- 单位类型目录与活怪列表分开；已知路径及选择跨热重载保存。
local npcCatalog=Catalog.new({log=log,valid=safeValid,getPlayer=GetPlayerPawn,
    path=Config.CatalogPath,knownPaths=Config.KnownMonsterClasses,canSpawn=SpawnPolicy.check,allowActors=true,
    audit=function(stage,unit,detail) return spawnAudit:record(stage,unit,detail) end})
local exporter=AssetExporter.new({log=log,path=Config.RuntimePath,
    config=Config.AssetCatalog})
local worldMaps=WorldMapCatalog.new({log=log,getWorld=UEHelpers.GetWorld})
local codexExporter=CodexExporter.new({log=log,path=Config.RuntimePath.."/codex.tsv",getWorld=UEHelpers.GetWorld,
    locationsPath=Config.RuntimePath..'/codex-locations.tsv',
    maps=worldMaps})

-- ---------- 强制锁敌：走 SGameAI 自家的作战指令（2026-10-29 解剖成果） ----------
-- SGameAIComponent:ForceIntoCombat(Target) = "进入战斗，目标是他"；
-- 另把目标写进 AI 的黑板目标键（PBZ_TargetingHandler_AI 从那里读目标）做双保险。

local function GetAIComp(pawn)
    if not safeValid(pawn) then return nil end
    local ok, sg = pcall(function()
        local ctrl = pawn.Controller
        if not ctrl or not ctrl:IsValid() then return nil end
        local c = ctrl.SGameAIComponent
        return (c ~= nil and c:IsValid()) and c or nil
    end)
    if ok then return sg end
    return nil
end

-- 本作的原生仇恨组件（挂在每个 NPC/玩家身上，感知与索敌都以它为准）
local function GetHatredComp(pawn)
    if not safeValid(pawn) then return nil end
    local ok, h = pcall(function() return pawn.BP_PBZHatredManagerComponent end)
    if ok and h ~= nil then
        local okV, v = pcall(function() return h:IsValid() end)
        if okV and v then return h end
    end
    return nil
end

local function HatredListContains(hm, actor)
    if not safeValid(hm) or not safeValid(actor) then return nil end
    local found, unreadable = false, false
    local ok = pcall(function()
        local hl = hm.HatredList
        local addr = actor:GetAddress()
        for i = 1, #hl do
            local okE, hit = pcall(function()
                local entry = hl[i]
                return safeValid(entry) and entry:GetAddress() == addr
            end)
            if not okE then unreadable = true end
            if okE and hit then found = true; return end
        end
    end)
    if found then return true end
    if not ok or unreadable then return nil end
    return false
end

local function AddHatred(attacker, victim)
    local hm = GetHatredComp(attacker)
    if not hm or not safeValid(victim) then return false, "对象无效" end
    local before = HatredListContains(hm, victim)
    if before == nil then return false, "成员读取失败" end
    if before then return true, "原本存在" end
    battle:remember("hatred:" .. hm:GetAddress() .. ":" .. victim:GetAddress(), function()
        if (arenaOwned[attacker] or arenaOwned[victim])
            and (not engineValid(hm) or not engineValid(victim)) then
            return true,"参赛对象有效性读回=false，目标已不存在；丢弃过期成员记录"
        end
        checked(hm); checked(victim)
        hm:RemoveActorFromHatredList(victim)
        local has = HatredListContains(hm, victim)
        return has == false, "成员读回=" .. tostring(has)
    end)
    local ok, err = pcall(function() hm:AddActorToHatredList(victim, false) end)
    local has = HatredListContains(hm, victim)
    -- 仅对本Mod创建的两名参赛者保留历史已观察到出招的数组配对路径。
    local ownA,ownB=false,false
    for _,actor in ipairs(arenaActors) do
        if safeValid(actor) then
            ownA=ownA or actor:GetAddress()==attacker:GetAddress()
            ownB=ownB or actor:GetAddress()==victim:GetAddress()
        end
    end
    if not has and ownA and ownB then
        local wrote=pcall(function()
            checked(hm); checked(victim)
            local list=hm.HatredList
            list[#list+1]=victim
        end)
        has=HatredListContains(hm,victim)
        log("参赛者配对数组写入=" .. tostring(wrote) .. "；成员读回=" .. tostring(has))
        return wrote and has==true,"参赛者数组配对（官方门禁尚未修复）"
    end
    log("官方Add调用=" .. tostring(ok) .. "；成员读回=" .. tostring(has))
    return ok and has == true, ok and (has and "官方Add读回存在" or "官方Add未接纳") or tostring(err)
end


-- ---------- 原生阵营系统 ----------
-- NPC 和玩家身上的 "Faction Component"（UFactionComponent）决定谁和谁是敌人，
-- 伤害、格挡、攻击开关等系统都引用它。SetFactionRelationOverride(对手, 关系, Both)
-- 可以针对单个对手覆盖敌我关系，Both=true 时双方同时生效。
-- ETeamAttitude: 0=Friendly 1=Neutral 2=Hostile

local ATTITUDE_NAME = { [0] = "友好", [1] = "中立", [2] = "敌对" }
local HOSTILE, NEUTRAL = 2, 1

local function GetFactionComp(pawn)
    if not safeValid(pawn) then return nil end
    local ok, fc = pcall(function() return pawn["Faction Component"] end)
    if ok and fc ~= nil then
        local okV, v = pcall(function() return fc:IsValid() end)
        if okV and v then return fc end
    end
    return nil
end

local function ReadRelation(a, b)
    if not safeValid(b) then return nil end
    local fc = GetFactionComp(a)
    if not fc then return nil end
    local ok, r = pcall(function() return fc:GetFactionRelation(b) end)
    if ok and type(r) == "number" then return r end
    return nil
end

local function RelationName(r)
    if r == nil then return "?" end
    return ATTITUDE_NAME[r] or tostring(r)
end

local function ReadFactionTag(pawn)
    local fc = GetFactionComp(pawn)
    if not fc then return "无阵营组件" end
    local ok, tag = pcall(function() return fc:GetCurrnetFaction() end)
    if not ok or tag == nil then return "?" end
    local okN, n = pcall(function() return FNameToString(tag.TagName) end)
    return okN and n or "?"
end

local function SetFactionRelation(a, b, relation)
    local fa, fb = GetFactionComp(a), GetFactionComp(b)
    if not fa or not fb then return false,nil,nil end
    local beforeA,beforeB = ReadRelation(a,b),ReadRelation(b,a)
    if beforeA == nil or beforeB == nil then return false,beforeA,nil end
    local function rememberOne(source,target,fc,original)
        local owned=arenaOwned[source] or arenaOwned[target]
        battle:remember("relation:" .. source:GetAddress() .. ":" .. target:GetAddress(), function()
            if owned and (not engineValid(source) or not engineValid(target) or not engineValid(fc)) then
                return true,"参赛对象有效性读回=false，目标已不存在；丢弃过期关系记录"
            end
            checked(source); checked(target); checked(fc)
            -- 停止擂台时仍开启的全局观战模式继续生效，不撤销它的单向中立关系。
            if spectator and spectator:status().enabled_requested then
                local player=GetPlayerPawn()
                if safeValid(player) and target:GetAddress()==player:GetAddress()
                    and source:GetAddress()~=player:GetAddress() then
                    fc:SetFactionRelationOverride(target,NEUTRAL,false)
                    local neutral=ReadRelation(source,target)
                    return neutral==NEUTRAL,"观战模式仍开启，保留单向中立；读回="..tostring(neutral)
                end
            end
            fc:ClearFactionRelationOverride(target)
            local actual=ReadRelation(source,target)
            return actual==original,"清除本轮覆盖；原关系=" .. tostring(original)
                .. "；读回=" .. tostring(actual) .. "；原覆盖结构未知"
        end)
    end
    rememberOne(a,b,fa,beforeA); rememberOne(b,a,fb,beforeB)
    local ok=pcall(function() fa:SetFactionRelationOverride(b,relation,true) end)
    local afterA,afterB=ReadRelation(a,b),ReadRelation(b,a)
    log(string.format("关系写入=%s；A %s→%s；B %s→%s",tostring(relation),tostring(beforeA),tostring(afterA),tostring(beforeB),tostring(afterB)))
    return ok and afterA==relation and afterB==relation,beforeA,afterA
end


-- ---------- 召唤物的"登场状态"：伏击/隐藏/免伤效果 ----------
-- 召唤物实测互相攻击但无敌、带半透明特效，且官方加仇恨被拒。怀疑是游戏刷怪时
-- 挂上的伏击/隐藏类效果（HiddenTagsCanNotBeHatred = 隐藏中不可被仇恨）没被解除：
-- 正常刷怪会走 ActivateAI，我们是直接造出来的。
-- 闪避无敌帧、格挡保护属于正常战斗机制，只诊断不移除。

local GE_TO_REPORT = { "GE_IgnoreAllDamage_C", "GE_AmbushTags_C", "GE_HiddenTags_C",
    "GE_HiddenTagsCanNotBeHatred_C", "GE_HiddenTags_DodgeInvunlerable_C",
    "GE_ReadyToDeflectProtect_C" }

local function GetASC(pawn)
    if not safeValid(pawn) then return nil end
    local ok, asc = pcall(function() return pawn.AbilitySystemComponent end)
    if ok and asc ~= nil then
        local okV, v = pcall(function() return asc:IsValid() end)
        if okV and v then return asc end
    end
    return nil
end

local geClassCache = {}
local function FindGEClass(name)
    if geClassCache[name] then return geClassCache[name] end
    local ok, cls = pcall(FindObject, "BlueprintGeneratedClass", name)
    if ok and cls ~= nil then
        local okV, v = pcall(function() return cls:IsValid() end)
        if okV and v then
            geClassCache[name] = cls
            return cls
        end
    end
    return nil
end

local function ListSuspectGEs(pawn)
    local asc = GetASC(pawn)
    if not asc then return "无ASC" end
    local found, resolved, queried = {}, 0, 0
    for _, name in ipairs(GE_TO_REPORT) do
        local cls = FindGEClass(name)
        if cls then
            resolved = resolved + 1
            local ok, n = pcall(function() return asc:GetGameplayEffectCount(cls, nil, true) end)
            if ok and type(n) == "number" then
                queried = queried + 1
                if n > 0 then
                    table.insert(found, string.format("%s×%d", name:gsub("_C$", ""), n))
                end
            end
        end
    end
    local body = #found > 0 and table.concat(found, ", ") or "无"
    return string.format("%s｜类找到%d/%d 查询成功%d", body, resolved, #GE_TO_REPORT, queried)
end

local aiLib = nil
local function GetAILib()
    if aiLib then
        local okV, v = pcall(function() return aiLib:IsValid() end)
        if okV and v then return aiLib end
    end
    for _, path in ipairs({
        "/SGameAI/BP_SGameAIFunctionLibrary.Default__BP_SGameAIFunctionLibrary_C",
        "/SGameAI/Utils/BP_SGameAIFunctionLibrary.Default__BP_SGameAIFunctionLibrary_C",
    }) do
        local ok, obj = pcall(StaticFindObject, path)
        if ok and obj ~= nil and pcall(function() return obj:IsValid() end) and obj:IsValid() then
            aiLib = obj
            return obj
        end
    end
    local ok, obj = pcall(FindObject, "BP_SGameAIFunctionLibrary_C",
        "Default__BP_SGameAIFunctionLibrary_C")
    if ok and obj ~= nil and pcall(function() return obj:IsValid() end) and obj:IsValid() then
        aiLib = obj
        return obj
    end
    return nil
end

-- 碰撞诊断：胶囊体和模型的碰撞是否开启、用的什么碰撞配置
-- ECollisionEnabled: 0=关 1=仅查询 2=仅物理 3=查询+物理
local function DescribeCollision(pawn)
    if not safeValid(pawn) then return "UNKNOWN(invalid pawn)" end
    local function comp(c)
        if c == nil then return "无" end
        local okV, v = pcall(function() return c:IsValid() end)
        if not okV or not v then return "无" end
        local en, prof = "?", "?"
        pcall(function() en = tostring(c:GetCollisionEnabled()) end)
        pcall(function() prof = FNameToString(c:GetCollisionProfileName()) end)
        return en .. "/" .. prof
    end
    local cap, mesh = nil, nil
    pcall(function() cap = pawn.CapsuleComponent end)
    pcall(function() mesh = pawn.Mesh end)
    return string.format("胶囊=%s 模型=%s", comp(cap), comp(mesh))
end

-- 延迟生成只负责拿到Actor；控制器登记所有权后才会调用FinishSpawn。
local function SpawnViaAILib(cls, t, world)
    if not safeValid(cls) or not safeValid(world) then return nil,"Class/World无效","not_started" end
    local className=objectName(cls)
    local classPath=className:match(" (/.+)$")
    local allowed,why=SpawnPolicy.check(classPath)
    if not allowed then return nil,why,"not_started" end
    local entry=npcCatalog:selected()
    if not entry or entry.path~=classPath or type(entry.isNPC)~='boolean' then return nil,'实体类型未读回','not_started' end
    local npc=entry.isNPC
    local lib=npc and GetAILib() or StaticFindObject('/Script/Engine.Default__GameplayStatics')
    if not safeValid(lib) then return nil,'找不到函数库','not_started' end
    if not spawnAudit:record("spawn_deferred_begin",classPath,objectName(world)) then return nil,"阶段日志写入失败；未生成","not_started" end
    if not safeValid(cls) or not safeValid(lib) or not safeValid(world) then return nil,"生成前对象失效","not_started" end
    local pawn = nil
    local ok, err = pcall(function()
        if npc then pawn=lib:SpawnAIDefered(cls,t,nil,world)
        else pawn=lib:BeginDeferredActorSpawnFromClass(world,cls,t,1,nil,1) end
    end)
    spawnAudit:record("spawn_deferred_return",classPath,"call="..tostring(ok).." valid="..tostring(safeValid(pawn)))
    if not ok then return nil, "延迟生成接口报错，创建结果未知: " .. tostring(err),"uncertain" end
    local okV = safeValid(pawn)
    if not okV then return nil, "延迟生成接口未返回有效实例；创建结果未知","uncertain" end
    spawnRoutes[pawn]=npc and 'npc' or 'actor'
    log('生成路径读回='..spawnRoutes[pawn]..'；actor='..objectName(pawn))
    return pawn,nil,"created"
end

local function FinishSpawnViaAILib(pawn,t,world)
    if not safeValid(pawn) or not safeValid(world) then return false,"Actor/World无效，保留清理记录" end
    local route=spawnRoutes[pawn]
    if route~='npc' and route~='actor' then return false,'生成路径未登记，保留清理记录' end
    if route=='npc' and arenaActivity then arenaActivity:prepare(pawn) end
    local lib=route=='npc' and GetAILib() or StaticFindObject('/Script/Engine.Default__GameplayStatics')
    if not safeValid(lib) then return false,"FinishSpawn函数库不可用，保留清理记录" end
    if not spawnAudit:record("finish_spawn_begin",objectName(pawn),"所有权已登记；"..objectName(world)) then
        return false,"FinishSpawn阶段日志写入失败；未继续初始化"
    end
    if not safeValid(pawn) or not safeValid(lib) or not safeValid(world) then return false,"FinishSpawn前对象失效" end
    local ok2, err2 = pcall(function()
        if route=='npc' then lib:FinishSpawnAIDefered(pawn,t,world)
        else lib:FinishSpawningActor(pawn,t,1) end
    end)
    local audited=spawnAudit:record("finish_spawn_return",objectName(pawn),"call="..tostring(ok2).." valid="..tostring(safeValid(pawn)))
    if not ok2 or not audited then return false,"FinishSpawn未确认: "..tostring(err2).."；保留对象供F4清理" end
    return safeValid(pawn),nil
end

-- 请求原生登场并读回可见状态；不移除游戏效果。
local function FinishEntrance(pawn)
    local before = ListSuspectGEs(pawn)
    local activated = false
    local lib = GetAILib()
    local world = UEHelpers.GetWorld()
    if lib and safeValid(pawn) and safeValid(world) then
        if not spawnAudit:record("activate_begin",objectName(pawn),objectName(world)) then return false end
        activated = pcall(function() lib:ActivateAI(pawn, world) end)
        spawnAudit:record("activate_return",objectName(pawn),"call="..tostring(activated).." valid="..tostring(safeValid(pawn)))
    end
    -- 先观察原生登场状态，不再自动移除效果。
    local after = ListSuspectGEs(pawn)
    log(string.format("  登场处理: ActivateAI调用=%s（行为未验收） | 可疑效果 前[%s] 后[%s] | %s",
        lib and tostring(activated) or "找不到函数库", before, after, DescribeCollision(pawn)))
    return activated
end

-- ---------- 战况只读采样 ----------

local function GetHP(pawn)
    if not safeValid(pawn) then return nil end
    -- APBZCharacter.AttributeSetBase 已由本地头文件确认；优先直接读，避免每秒全局扫描。
    local okDirect, direct = pcall(function()
        local attributes = pawn.AttributeSetBase
        if not safeValid(attributes) then return nil end
        return attributes.Health.CurrentValue
    end)
    if okDirect and type(direct) == "number" then return direct end
    local hp = nil
    pcall(function()
        local ok, sets = pcall(FindAllOf, "BasicAttributeSet")
        if not ok or not sets then return end
        local pawnAddr = pawn:GetAddress()
        local ascAddr = nil
        pcall(function()
            local asc = pawn.AbilitySystemComponent
            if asc and asc:IsValid() then ascAddr = asc:GetAddress() end
        end)
        for _, s in ipairs(sets) do
            local okO, outer = pcall(function()
                if not safeValid(s) then return nil end
                return s:GetOuter()
            end)
            if okO and outer and outer:IsValid() then
                local oa = outer:GetAddress()
                if oa == pawnAddr or oa == ascAddr then
                    hp = s.Health.CurrentValue
                    return
                end
            end
        end
    end)
    return hp
end

local function StartDuelWatch(a,b)
    local token=battle:begin("两只NPC对照")
    attackProfile=AttackProfile.new({log=log,valid=safeValid})
    local ticks,handle=0,nil
    local function cancel()
        if handle then pcall(CancelDelayedAction,handle); handle=nil end
    end
    local function sample()
        if not battle:isCurrent(token) then cancel(); return end
        if not safeValid(a) or not safeValid(b) then
            log("对象失效，停止采样；无法据此判定死亡/胜负")
            battle:cancel("对象失效"); cancel(); return
        end
        ticks=ticks+1
        attackProfile:sample({a,b},"duel_sample_"..ticks,GetPlayerPawn())
        if ticks==1 or ticks==20 or ticks==80 then
            local ok,err=pcall(function()
                spawnInspector:combat(a,b,'tick'..ticks)
                spawnInspector:combat(b,a,'tick'..ticks)
            end)
            if not ok then log('[SpawnInspect] 战斗状态读取失败: '..tostring(err)) end
        end
        if ticks%8~=0 then return end
        local hpA,hpB=GetHP(a),GetHP(b)
        log(string.format("战况[%d] HP=%s/%s 关系=%s/%s；只读",ticks,tostring(hpA),tostring(hpB),RelationName(ReadRelation(a,b)),RelationName(ReadRelation(b,a))))
        if ticks>=240 or (hpA and hpA<=0) or (hpB and hpB<=0) then
            battle:cancel("采样结束；F4恢复当前账本"); cancel()
        end
    end
    handle=LoopInGameThreadWithDelay(250,sample)
end

local function ForceAttack(attacker, victim)
    if not safeValid(attacker) or not safeValid(victim) then return false end
    local okF = SetFactionRelation(attacker, victim, HOSTILE)
    local okH, how = AddHatred(attacker, victim)
    local sg = GetAIComp(attacker)
    local okForce = false
    if sg then okForce = pcall(function() sg:ForceIntoCombat(victim) end) end
    -- 只写实际绑定该控制器的黑板键，并保留原目标供F4恢复。
    if sg then pcall(function()
        local bb=sg.BlackboardComponent
        if not safeValid(bb) then return end
        local okHandlers,handlers=pcall(FindAllOf,"PBZ_TargetingHandler_AI_C")
        if not okHandlers or not handlers then return end
        for _,handler in ipairs(handlers) do
            if safeValid(handler) then
                local bound=handler.Blackboard
                if safeValid(bound) and bound:GetAddress()==bb:GetAddress() then
                    local key=handler["Target Key"]
                    local original=bb:GetValueAsObject(key)
                    local originalValid=safeValid(original)
                    local owned=arenaOwned[attacker]
                    battle:remember("blackboard:" .. bb:GetAddress() .. ":" .. FNameToString(key),function()
                        if owned and not engineValid(bb) then
                            return true,"参赛黑板有效性读回=false，目标已不存在；丢弃过期记录"
                        end
                        checked(bb)
                        if originalValid then checked(original); bb:SetValueAsObject(key,original)
                        else bb:ClearValue(key) end
                        local actual=bb:GetValueAsObject(key)
                        local restored=originalValid and safeValid(actual) and actual:GetAddress()==original:GetAddress()
                            or (not originalValid and not safeValid(actual))
                        return restored,"目标读回=" .. objectName(actual)
                    end)
                    checked(victim)
                    bb:SetValueAsObject(key,victim)
                    log("参赛目标写入=" .. objectName(victim) .. "；黑板读回=" .. objectName(bb:GetValueAsObject(key)))
                    break
                end
            end
        end
    end) end
    local state = "UNKNOWN"
    if sg then pcall(function() state = FNameToString(sg.CurrentStateTag.TagName) end) end
    log("作战请求=" .. tostring(okForce) .. "；状态读回=" .. state
        .. "；仇恨=" .. tostring(okH) .. "/" .. tostring(how) .. "；实际出招待观察")
    return okF and okH and okForce
end

-- 不再调用通用ApplyDamage种仇恨；本版不执行假伤害或假死亡。

-- ---------- 扫描 ----------

local function CollectNPCs()
    local player = GetPlayerPawn()
    local playerAddr = player and player:GetAddress() or nil
    local result, seen = {}, {}
    for _, className in ipairs(Config.EnemyClasses) do
        local ok, found = pcall(FindAllOf, className)
        if ok and found then
            for _, pawn in ipairs(found) do
                if safeValid(pawn) then
                    local addr = pawn:GetAddress()
                    if addr ~= playerAddr and not seen[addr] and not IsExcluded(pawn) then
                        seen[addr] = true
                        table.insert(result, pawn)
                    end
                end
            end
        end
    end
    return result
end

-- ---------- 解剖：把最近一只怪的 AI 大脑结构写到文件（Shift+扫描键） ----------
-- 注意：UE4SS 对象的空指针链式调用会原生崩溃，pcall 拦不住，
-- 所以每一步都先取引用、IsValid 之后再往下走。

local function DumpBrain()
    ExecuteInGameThread(function()
        local player = GetPlayerPawn()
        local pLoc = player and GetLocation(player)
        local npcs = CollectNPCs()
        if pLoc then
            table.sort(npcs, function(a, b)
                local la, lb = GetLocation(a), GetLocation(b)
                if not la then return false end
                if not lb then return true end
                return DistSq(la, pLoc) < DistSq(lb, pLoc)
            end)
        end
        local target = nil
        for _, pawn in ipairs(npcs) do
            local ok, ctrl = pcall(function() return pawn.Controller end)
            if ok and safeValid(ctrl) then
                target = { pawn = pawn, ctrl = ctrl }
                break
            end
        end
        if not target then
            log("解剖失败：附近没有带可用控制器的怪")
            return
        end

        local lines = {}
        local function emit(s) table.insert(lines, s) end
        emit("== 解剖对象: " .. target.pawn:GetFullName())

        -- 把一个对象的类链（属性+函数）全部倒出来
        local function dumpClassChain(obj, label)
            emit("")
            emit("######## " .. label)
            if not safeValid(obj) then emit("UNKNOWN(invalid)"); return end
            local okCls, cls = pcall(function() return obj:GetClass() end)
            while okCls and safeValid(cls) do
                local okN, clsName = pcall(function() return cls:GetFullName() end)
                emit("")
                emit("==== " .. (okN and clsName or "?"))
                pcall(function()
                    cls:ForEachProperty(function(prop)
                        pcall(function() emit("  prop " .. prop:GetFullName()) end)
                    end)
                end)
                pcall(function()
                    cls:ForEachFunction(function(fn)
                        pcall(function() emit("  func " .. fn:GetFullName()) end)
                    end)
                end)
                local nxt = nil
                pcall(function() nxt = cls:GetSuperStruct() end)
                cls = nxt
                okCls = safeValid(cls)
            end
        end

        -- 1) 控制器 + 它的 SGameAI 组件 + 感知组件 + 怪物本体
        dumpClassChain(target.ctrl, "AIController")
        local okSG, sg = pcall(function() return target.ctrl.SGameAIComponent end)
        if okSG and safeValid(sg) then
            dumpClassChain(sg, "SGameAIComponent")
        end
        local okPC, perc = pcall(function() return target.ctrl.PerceptionComponent end)
        if okPC and safeValid(perc) then
            dumpClassChain(perc, "PerceptionComponent")
        end
        dumpClassChain(target.pawn, "Pawn 本体")

        -- 2) AI 黑板的键（"打谁"大概率藏在这里）
        local okBB, bb = pcall(function() return target.ctrl.Blackboard end)
        if okBB and safeValid(bb) then
            emit("")
            emit("==== Blackboard keys")
            local okData, data = pcall(function() return bb.DefaultBlackboardAsset end)
            if okData and safeValid(data) then
                pcall(function()
                    local keys = data.Keys
                    for i = 1, #keys do
                        pcall(function()
                            local entry = keys[i]
                            emit(string.format("  key [%d] %s", i,
                                tostring(entry.EntryName)))
                        end)
                    end
                end)
            else
                emit("  (DefaultBlackboardAsset 不可用)")
            end
        else
            emit("")
            emit("==== 无 Blackboard 组件")
        end

        local f, usedPath = nil, nil
        for _, path in ipairs({
            "ue4ss\\Mods\\PhantomGladiator\\brain_dump.txt",
            "ue4ss/Mods/PhantomGladiator/brain_dump.txt",
            "brain_dump.txt",
        }) do
            f = io.open(path, "w")
            if f then usedPath = path break end
        end
        if f then
            f:write(table.concat(lines, "\n"))
            f:close()
            log(string.format("解剖完成：%d 行已写入 %s（游戏 exe 目录下）", #lines, usedPath))
        else
            log("解剖完成但写文件失败，改打到日志（共 " .. #lines .. " 行）")
            for _, s in ipairs(lines) do print(s .. "\n") end
        end
    end)
end

-- ---------- 目标系统诊断（Shift+互殴键）：读出双方的目标类型标签 ----------

local function ReadTargetTypes(pawn, label)
    if not safeValid(pawn) then log(label .. " 目标类型=UNKNOWN(invalid)"); return end
    local ok, err = pcall(function()
        local out = {}
        pawn:GetTargetTypes(out)
        local names = {}
        for i = 1, #out do
            local tag = out[i]
            local okN, n = pcall(function() return FNameToString(tag.TagName) end)
            table.insert(names, okN and n or "?")
        end
        log(string.format("%s 可打类型 [%d 个]: %s", label, #out,
            table.concat(names, ", ")))
    end)
    if not ok then
        log(string.format("%s 读取目标类型失败: %s", label, tostring(err)))
    end
end

local function ReadActorTags(pawn, label)
    -- 已知本构建没有 GetOwnedGameplayTags 反射入口，不重复失败调用。
    log(label .. " 身份标签=UNKNOWN（GetOwnedGameplayTags非反射函数；不据此推断无标签）")
end

local function TargetDiag()
    ExecuteInGameThread(function()
        local player = GetPlayerPawn()
        if player then
            ReadTargetTypes(player, "玩家")
            ReadActorTags(player, "玩家")
        end
        local npcs = CollectNPCs()
        if player then
            log("玩家 阵营: " .. ReadFactionTag(player))
        end
        -- 附近每只 NPC 的阵营标签和它对玩家的关系（在原生 NPC 互打的场景按这个键，
        -- 能直接看到双方用的阵营）
        for i = 1, math.min(#npcs, 8) do
            local rel = player and RelationName(ReadRelation(npcs[i], player)) or "?"
            local okN, n = pcall(function()
                return objectName(npcs[i]):match("([%w_]+)$")
            end)
            log(string.format("  NPC[%d] %s 阵营=%s 对玩家=%s 可疑效果=[%s] %s", i,
                okN and n or "?", ReadFactionTag(npcs[i]), rel, ListSuspectGEs(npcs[i]),
                DescribeCollision(npcs[i])))
        end
        if #npcs >= 2 then
            log(string.format("  NPC[1]→NPC[2] 关系=%s",
                RelationName(ReadRelation(npcs[1], npcs[2]))))
        end
        if #npcs > 0 then
            ReadTargetTypes(npcs[1], "怪物")
            ReadActorTags(npcs[1], "怪物")
            -- 怪物的 TargetingComponent 挂了哪些 handler
            pcall(function()
                local tc = npcs[1]["Targeting Component"]
                if tc and tc:IsValid() then
                    local hs = tc.TargetingHandlers
                    for i = 1, #hs do
                        pcall(function()
                            local entry = hs[i]
                            log(string.format("  handler[%d] tag=%s", i,
                                FNameToString(entry.Tag.TagName)))
                        end)
                    end
                end
            end)
            -- 它的原生仇恨列表里现在有谁
            pcall(function()
                local hm = GetHatredComp(npcs[1])
                if hm then
                    local hl = hm.HatredList
                    log(string.format("  仇恨列表 %d 个:", #hl))
                    for i = 1, math.min(#hl, 5) do
                        pcall(function()
                            log("    " .. objectName(hl[i]))
                        end)
                    end
                else
                    log("  （没有仇恨组件）")
                end
            end)
            -- 它的感知里现在装着谁
            pcall(function()
                local ctrl = npcs[1].Controller
                if ctrl and ctrl:IsValid() then
                    local perc = ctrl.PerceptionComponent
                    if perc and perc:IsValid() then
                        local seen = {}
                        perc:GetPerceivedHostileActors(seen)
                        log(string.format("  感知到的敌对者 %d 个:", #seen))
                        for i = 1, math.min(#seen, 5) do
                            local okE, nameE = pcall(function()
                                local a = seen[i]
                                if safeValid(a) then return objectName(a) end
                                local okGet,resolved=pcall(function() return a:get() end)
                                return okGet and objectName(resolved) or "UNKNOWN"
                            end)
                            log("    " .. (okE and nameE or "?"))
                        end
                    end
                end
            end)
        end
    end)
end

-- ---------- 碰撞通道对照（Shift+决斗键）：玩家 vs 最近的怪 ----------
-- 每个碰撞组件输出：对象类型、碰撞开关、对 32 个通道的反应（0 忽略 1 重叠 2 阻挡）。
-- 怪物攻击检测线如果只扫"玩家受击框"那类通道，而怪物身上没有对应反应的组件，
-- 怪打怪就会打空——对照这张表能直接看出来。

local function DumpCollisionMatrix()
    ExecuteInGameThread(function()
        local primClass = StaticFindObject("/Script/Engine.PrimitiveComponent")
        if not primClass or not primClass:IsValid() then
            log("碰撞对照失败：找不到 PrimitiveComponent 类")
            return
        end
        local lines = {}
        local function emit(s) table.insert(lines, s) end
        -- K2_GetComponentsByClass 在本作返回空数组（实测），改为遍历几类碰撞相关组件，
        -- 按拥有者筛选；武器等挂件是独立 Actor，拥有者链再往上查一层
        local allComps = {}
        for _, cn in ipairs({ "ShapeComponent", "SkeletalMeshComponent", "StaticMeshComponent" }) do
            local ok, list = pcall(FindAllOf, cn)
            if ok and list then
                for _, c in ipairs(list) do table.insert(allComps, c) end
            end
        end
        local function ownedBy(c, actorAddr)
            local ok, hit = pcall(function()
                if not safeValid(c) then return false end
                local o = c:GetOwner()
                if not safeValid(o) then return false end
                if o:GetAddress() == actorAddr then return true end
                local o2 = o:GetOwner()
                return o2 ~= nil and o2:IsValid() and o2:GetAddress() == actorAddr
            end)
            return ok and hit
        end
        local function dumpActor(actor, label)
            if not safeValid(actor) then return end
            emit("######## " .. label .. " " .. actor:GetFullName())
            local actorAddr = actor:GetAddress()
            local comps = {}
            for _, c in ipairs(allComps) do
                if ownedBy(c, actorAddr) then table.insert(comps, c) end
            end
            emit(string.format("  （找到 %d 个碰撞相关组件，全局扫描 %d 个）", #comps, #allComps))
            for i = 1, #comps do
                pcall(function()
                    local c = comps[i]
                    if not c:IsValid() then return end
                    local name = c:GetFullName():match("([%w_]+)$") or "?"
                    pcall(function()
                        local o = c:GetOwner()
                        if not safeValid(o) then return end
                        if o:GetAddress() ~= actor:GetAddress() then
                            name = (o:GetFullName():match("([%w_]+)$") or "?") .. "." .. name
                        end
                    end)
                    local objType, enabled, prof = "?", "?", "?"
                    pcall(function() objType = tostring(c:GetCollisionObjectType()) end)
                    pcall(function() enabled = tostring(c:GetCollisionEnabled()) end)
                    pcall(function() prof = FNameToString(c:GetCollisionProfileName()) end)
                    local resp = {}
                    for ch = 0, 31 do
                        local r = "?"
                        pcall(function() r = tostring(c:GetCollisionResponseToChannel(ch)) end)
                        table.insert(resp, r)
                    end
                    emit(string.format("  %-40s 类型=%s 开关=%s 配置=%s", name, objType, enabled, prof))
                    emit("    通道0-31: " .. table.concat(resp, ""))
                end)
            end
        end
        local player = GetPlayerPawn()
        if player then dumpActor(player, "玩家") end
        local pLoc = player and GetLocation(player)
        local npcs = CollectNPCs()
        if pLoc then
            table.sort(npcs, function(a, b)
                local la, lb = GetLocation(a), GetLocation(b)
                if not la then return false end
                if not lb then return true end
                return DistSq(la, pLoc) < DistSq(lb, pLoc)
            end)
        end
        if npcs[1] then dumpActor(npcs[1], "怪物") end
        local f = io.open("collision_matrix.txt", "w")
        if f then
            f:write(table.concat(lines, "\n"))
            f:close()
            log(string.format("碰撞对照完成：%d 行已写入 collision_matrix.txt", #lines))
        else
            log("碰撞对照写文件失败")
        end
    end)
end

-- ---------- 慢动作 ----------

local function CycleSlowMo()
    ExecuteInGameThread(function()
        dilationIndex = dilationIndex % #Config.TimeDilationSteps + 1
        local target = Config.TimeDilationSteps[dilationIndex]
        local count = 0
        local ok, list = pcall(FindAllOf, "WorldSettings")
        if ok and list then
            for _, ws in ipairs(list) do
                if safeValid(ws) then
                    local okChange=battle:change("time:" .. ws:GetAddress(),
                        function() checked(ws); return ws.TimeDilation end,
                        function(value) checked(ws); ws.TimeDilation=value end,target,
                        function(a,b) return type(a)=="number" and math.abs(a-b)<0.0001 end)
                    if okChange then count=count+1 end
                end
            end
        end
        if count > 0 then
            log(string.format("时间流速: %.2fx（%d 个世界）", target, count))
        else
            log("设置 TimeDilation 失败")
        end
    end)
end

-- ---------- 自由镜头 ----------

-- Shipping 版的 DebugCameraController 没有自己的 CheatManager（被编译剔除），
-- 而原生退出流程恰恰依赖它：现场构造一个再调 DisableDebugCamera。实测有效。
local function ExitFreeCam(dcc)
    checked(dcc)
    local cm = dcc.CheatManager
    if not cm or not cm:IsValid() then
        local cmClass = StaticFindObject("/Script/Engine.CheatManager")
        if not cmClass or not cmClass:IsValid() then
            error("CheatManager class not found")
        end
        cm = StaticConstructObject(cmClass, dcc)
        if not cm or not cm:IsValid() then
            error("construct CheatManager failed")
        end
        dcc.CheatManager = cm
    end
    cm:DisableDebugCamera()
end

-- 找"当前真正掌权"的调试相机：每次进出都会生成新实例，旧的会残留，
-- 只有持有 UPlayer 的那个才是激活中的
local function FindActiveDebugCam()
    local ok, list = pcall(FindAllOf, "DebugCameraController")
    if not ok or not list then return nil end
    for _, dcc in ipairs(list) do
        local okP, active = pcall(function()
            return dcc:IsValid() and dcc.Player and dcc.Player:IsValid()
        end)
        if okP and active then return dcc end
    end
    return nil
end

local observerGuard=ObserverGuard.new({log=log,getSpectator=function()return spectator end})
local freeCamera=FreeCamera.new({path=Config.RuntimePath,log=log,getController=GetRealPlayerController,guard=observerGuard,
    getWorld=UEHelpers.GetWorld,moveSpeed=Config.FreeCamera.MoveSpeed,mouseSensitivity=Config.FreeCamera.MouseSensitivity})

local function ToggleFreeCam()
    local dcc=FindActiveDebugCam()
    if dcc then local ok,why=pcall(ExitFreeCam,dcc);return {ok=ok,message=ok and '已退出原生调试镜头' or tostring(why),spawned_count=0}end
    local ok,result=pcall(function()return freeCamera:toggle()end)
    local confirmed=ok and result==true
    local protection=observerGuard:status()
    return {ok=confirmed,message=confirmed and (freeCamera:isActive() and (protection.health_verified and '自由观战已开启：无仇恨、隐身、无敌锁血；声音跟随镜头' or '自由观战已开启；锁血状态待确认，请查看面板保护状态') or '已退出自由观战并恢复')
        or ('相机操作未确认，可点击退出观战重试：'..tostring(result)),spawned_count=0}
end

local function ForceExitFreeCam()
    local ok,restored=pcall(function()return freeCamera:stop('面板/自定义退出键')end)
    local dcc=FindActiveDebugCam();local legacyOK=true
    if dcc then legacyOK=pcall(ExitFreeCam,dcc)end
    return {ok=ok and restored==true and legacyOK,message=ok and restored==true and legacyOK and '已退出自由观战并恢复原状态' or '退出恢复待确认，可再次点击退出观战',spawned_count=0}
end

-- ---------- 只读攻击追踪 ----------
local function LogProbeScene(label)
    local player=GetPlayerPawn()
    log("[Scene] " .. label .. " 玩家=" .. objectName(player) .. " HP=" .. tostring(GetHP(player)))
    local origin=player and GetLocation(player)
    local npcs=CollectNPCs()
    if origin then
        table.sort(npcs,function(a,b)
            local la,lb=GetLocation(a),GetLocation(b)
            return (la and DistSq(la,origin) or math.huge)<(lb and DistSq(lb,origin) or math.huge)
        end)
    end
    local subjects = {}
    if safeValid(player) then subjects[#subjects+1]=player end
    for i=1,math.min(#npcs,4) do
        local npc=npcs[i]
        subjects[#subjects+1]=npc
        log("[Scene] NPC=" .. objectName(npc) .. " HP=" .. tostring(GetHP(npc))
            .. " 阵营=" .. ReadFactionTag(npc) .. " 对玩家=" .. RelationName(ReadRelation(npc,player)))
    end
    return subjects
end
local healthSubjects = {}
probeFinished = function(state)
    probeSampleGen=probeSampleGen+1
    for _,entry in ipairs(healthSubjects) do
        local hp=GetHP(entry.actor)
        log("[HPWatch] 结束 " .. objectName(entry.actor) .. " start=" .. tostring(entry.initial)
            .. " final=" .. tostring(hp) .. " reason=" .. tostring(state.reason))
    end
    healthSubjects={}
end
local function StartHealthWatch(subjects,token)
    healthSubjects={}
    for _,actor in ipairs(subjects) do
        local hp=GetHP(actor)
        healthSubjects[#healthSubjects+1]={actor=actor,initial=hp,last=hp}
    end
    local ticks,lines,handle=0,0,nil
    local function cancel()
        if handle then pcall(CancelDelayedAction,handle); handle=nil end
    end
    local function sample()
        if token~=probeSampleGen or not probe:status().active then cancel(); return end
        ticks=ticks+1
        for _,entry in ipairs(healthSubjects) do
            local hp=GetHP(entry.actor)
            if hp~=entry.last and lines<40 then
                log("[HPWatch] sample="..ticks.." "..objectName(entry.actor)
                    .." HP="..tostring(entry.last).."→"..tostring(hp).."（只读，不据此判断伤害来源）")
                lines=lines+1
            end
            entry.last=hp
        end
        if ticks>=60 then cancel() end
    end
    handle=LoopInGameThreadWithDelay(1000,sample)
end
BeginArenaObservation=function(a,b)
    probe:stop("开始参赛者对照")
    local subjects={a,b}
    local player=GetPlayerPawn()
    if safeValid(player) then subjects[#subjects+1]=player end
    probeSampleGen=probeSampleGen+1
    if probe:start("arena_duel",subjects) then StartHealthWatch(subjects,probeSampleGen) end
end
local function ToggleProbe()
    ExecuteInGameThread(function()
        local state=probe:status()
        probeSampleGen=probeSampleGen+1
        if state.active or state.stopPending then
            probe:stop("F11手动结束"); LogProbeScene("结束"); return
        end
        local subjects=LogProbeScene("开始；只读阳性对照")
        local ok=probe:start("native_baseline",subjects)
        if not ok then return end
        local token=probeSampleGen
        StartHealthWatch(subjects,token)
        ExecuteInGameThreadWithDelay(60050,function()
            if token~=probeSampleGen then return end
            LogProbeScene("60秒窗口结束")
        end)
    end)
end
-- ---------- 单位控制器：按钮与快捷键共用，只有本Mod的参赛者受管理 ----------
local runtimeSession=RuntimeSession.new({valid=safeValid,getWorld=UEHelpers.GetWorld,
    getPlayer=GetPlayerPawn,isDestroying=actorIsDestroying,hp=GetHP})
local spectatorTargets=SpectatorTargets.new({log=log})
local spectatorExcluded={}
spectator=SpectatorMode.new({log=log,valid=engineValid,getPlayer=GetPlayerPawn,path=Config.RuntimePath,
    isActorDestroying=actorIsDestroying,
    isObserverActive=function()return freeCamera:isActive()end,
    releasePlayerTarget=function(npc,player)return spectatorTargets:release(npc,player)end,
    getNPCs=function()
        spectatorTargets:refresh()
        local out={}
        local world=UEHelpers.GetWorld()
        for _,npc in ipairs(CollectNPCs()) do
            if UEObserve.inWorld(npc,world) then
                local ok,destroying=pcall(function() checked(npc); return npc:IsActorBeingDestroyed() end)
                if not (ok and destroying==true) then out[#out+1]=npc end
            else
                local key=UEObserve.key(npc)
                if key and not spectatorExcluded[key] then
                    spectatorExcluded[key]=true;log('[Spectator] 跳过非当前世界对象：'..objectName(npc))
                end
            end
        end
        return out
    end})
arena=ArenaController.new({catalog=npcCatalog,log=log,valid=engineValid,name=objectName,
    actorKey=function(actor) checked(actor);return actor:GetAddress() end,
    hp=function(actor) if spawnRoutes[actor]=='actor' then return nil end;return GetHP(actor) end,
    hasCombatHealth=function(actor) return spawnRoutes[actor]~='actor' end,
    canSpawn=SpawnPolicy.check,maxUnits=0,
    spawnLimits=SpawnPolicy.limits,canBattle=SpawnPolicy.canBattle,
    spawnGuard=spawnGuard,
    combatReady=function(actor) return safeValid(actor) and spawnRoutes[actor]~='actor' and GetAIComp(actor)~=nil end,
    getPlayer=GetPlayerPawn,getWorld=UEHelpers.GetWorld,getLocation=GetLocation,
    getForward=function(actor) checked(actor); return actor:GetActorForwardVector() end,
    spawnClass=SpawnViaAILib,
    finishSpawn=FinishSpawnViaAILib,
    activate=function(actor,unitPath)
        if spawnRoutes[actor]=='actor' then return safeValid(actor),'通用Actor初始化完成；未调用PBZ战斗AI，不保证具有血量或战斗能力' end
        spectator:applyTo(actor)
        local activationRequested=FinishEntrance(actor)
        if spectator:status().enabled_requested then spectatorTargets:refresh(true) end
        spectator:applyTo(actor)
        local ai=GetAIComp(actor)
        local hp=GetHP(actor)
        log("召唤激活读回 ControllerAI="..tostring(ai~=nil).." HP="..tostring(hp))
        if activationRequested==true and ai~=nil and type(hp)=='number' and hp>0 then
            local result=statMatch:onSpawn(actor,unitPath)
            if not result.ok then
                if result.rollback_verified then return true,'初始化通过；数值统一失败已回滚',result.message..'；单位保留原生数值，可正常交战' end
                return false,'单位已生成；'..result.message..'；保留对象供清理'
            end
        end
        if activationRequested and safeValid(actor) then
            local inspected,inspectError=pcall(function() return spawnInspector:inspect(actor,UEHelpers.GetWorld()) end)
            if not inspected then log('[SpawnInspect] 只读检查失败: '..tostring(inspectError)) end
        end
        return activationRequested==true and ai~=nil and type(hp)=="number" and hp>0,"仅确认初始化调用、AI组件和正HP；行为待验收"
    end,
    setRelation=SetFactionRelation,forceAttack=ForceAttack,
    prepareBattle=function(members)return arenaGrabs:sync(members,Config.EnableNPCGrabs,true) end,
    destroy=function(actor) checked(actor); actor:K2_DestroyActor() end,
    isDestroying=actorIsDestroying,
    restore=function()
        probeSampleGen=probeSampleGen+1
        probe:stop("停止参赛者")
        if bossHUD then bossHUD:clear(true) end
        local grabRestored=not arenaGrabs or arenaGrabs:restore()
        local battleRestored=battle:reset("停止参赛者")
        return grabRestored and battleRestored
    end,
    onUnitsChanged=function(units)
        if statMatch then statMatch:roster(units) end
        arenaActors={}
        local routes={}
        for _,entry in ipairs(units) do
            arenaActors[#arenaActors+1]=entry.actor
            arenaOwned[entry.actor]=true
            routes[entry.actor]=spawnRoutes[entry.actor]
        end
        spawnRoutes=routes
        if #arenaActors==0 and battle:pendingCount()==0 then arenaOwned={} end
    end,
    onBattleStarted=function(a,b)
        StartDuelWatch(a,b)
        BeginArenaObservation(a,b)
    end})

local summonLinks=SummonLinks.new({getWorld=UEHelpers.GetWorld,getNPCs=CollectNPCs,log=log})
arenaActivity=ArenaActivity.new({log=log,isNPC=function(actor)return spawnRoutes[actor]~='actor' end,
    freeCam=function()return freeCamera:isActive() or safeValid(FindActiveDebugCam()) end,
    context=function()
        local debugCamera=FindActiveDebugCam()
        local original=UEObserve.field(debugCamera,'OriginalControllerRef')
        local originalPawn=UEObserve.field(original,'Pawn')
        local world=UEHelpers.GetWorld()
        local level=UEObserve.field(world,'PersistentLevel')
        local settings=UEObserve.field(level,'WorldSettings')
        return 'mod_player='..tostring(UEObserve.key(GetPlayerPawn()))
            ..' debug_original_pawn='..tostring(UEObserve.key(originalPawn))
            ..' world_time='..tostring(UEObserve.field(settings,'TimeDilation'))
            ..' cinematic_time='..tostring(UEObserve.field(settings,'CinematicTimeDilation'))
    end})
bossHUD=BossHUD.new({getController=GetRealPlayerController,getWorld=UEHelpers.GetWorld,hp=GetHP,
    maxHP=function(actor)
        if not engineValid(actor) then return nil end
        local attributes=actor.AttributeSetBase
        if not engineValid(attributes) then return nil end
        return attributes.Health_Max.CurrentValue
    end,
    codexPath=Config.RuntimePath..'/codex.tsv',log=log})
local arenaSupport={}
statMatch=StatMatch.new({path=Config.RuntimePath,log=log})
local grabStudy=Config.EnableGrabStudy and GrabStudy.new({path=Config.RuntimePath,log=log,ready=function()return runtimeSession:status().game_ready==true end}) or nil
arenaGrabs=ArenaGrabs.new({path=Config.RuntimePath,log=log,hp=GetHP,ready=function()return runtimeSession:status().game_ready==true end})
function arenaSupport:discover()
    for _,link in ipairs(summonLinks:scan(arena:members())) do
        local result=arena:adoptSummon(link.actor,link.parent,link.class_path,link.evidence)
        if not result.ok then log('[SummonLinks] 接管未确认：'..tostring(result.message)) end
    end
end
function arenaSupport:tick()
    freeCamera:recover()
    if grabStudy then grabStudy:tick() end
    self:discover()
    arenaActivity:sync(arena:members())
    arenaGrabs:sync(arena:members(),Config.EnableNPCGrabs and arena:status().battle_active)
    arena:tickReinforcements()
    local state=arena:status().state
    if state=='cleanup_pending' or state=='restore_pending' or state=='spawn_uncertain' then bossHUD:clear()
    else bossHUD:sync(arena:members()) end
end
function arenaSupport:status()
    local result=bossHUD:status();local activity=arenaActivity:status()
    result.full_update_count=activity.full_update_count;result.bone_refresh_count=activity.bone_refresh_count;result.free_camera=activity.free_camera
    local grabs=arenaGrabs:status()
    result.grab_events=grabs.events;result.grab_pairs=grabs.observed_pairs;result.grab_restore_pending=grabs.restore_pending
    local observer=observerGuard:status()
    result.observer_health_verified=observer.health_verified;result.observer_message=observer.message
    return result
end

local keyRouter=KeyRouter.new({log=log})
local unitKeys=UnitKeys.new({path=Config.RuntimePath,log=log,router=keyRouter,
    reserved=function(vk)return panelRuntime and panelRuntime:unitKeyReserved(vk) end,
    shared=function(vk)return panelRuntime and panelRuntime:unitKeyShared(vk) end,
    ready=function()local status=runtimeSession:status();return status.game_ready,status.game_ready_reason end,
    spawn=function(path)
        local current=arena:status()
        return arena:spawn(path,current.current_team,current.current_count)
    end})

-- Developer probes are opt-in, never hidden default key reservations.
if Config.EnableDeveloperKeybinds then
RegisterKeyBind(Key.F1,{ModifierKey.SHIFT},DumpBrain)
RegisterKeyBind(Key.F2,{ModifierKey.SHIFT},TargetDiag)
RegisterKeyBind(Key.F3,{ModifierKey.SHIFT},DumpCollisionMatrix)
RegisterKeyBind(Key.F9,{ModifierKey.SHIFT},function()
    ExecuteInGameThread(function()
        for _,path in ipairs(SpawnPolicy.knownPaths()) do
            local result=arena:select(path,"blue",1)
            log("验证目录切换="..tostring(result.ok).."；"..tostring(result.message))
            break
        end
    end)
end)
end
panelRuntime=PanelRuntime.new({arena=arena,exporter=exporter,path=Config.RuntimePath,
    build=BUILD,log=log,autoScan=true,fullInventory=true,spectator=spectator,statMatch=statMatch,session=runtimeSession,codex=codexExporter,spawnPolicy=SpawnPolicy,support=arenaSupport,unitKeys=unitKeys,
    router=keyRouter,camera={status=function()return {active=freeCamera:isActive(),pending=freeCamera:hasPending()}end,
        toggle=ToggleFreeCam,exit=ForceExitFreeCam},
    spawnCatalog=SpawnCatalog.new({log=log,path=Config.RuntimePath,getWorld=UEHelpers.GetWorld}),
    tableCatalog=TableCatalog.new({log=log,path=Config.RuntimePath,maps=worldMaps}),
    references=ReferenceAudit.new({log=log,path=Config.RuntimePath})})
panelRuntime:start()

if ModRef then
    ModRef.OnUnload=function()
        freeCamera:silence()
        panelRuntime:silence()
        probeSampleGen=probeSampleGen+1
        probe:silence("Mod卸载")
        battle:cancel("Mod卸载")
        if battle:pendingCount()>0 or #arenaActors>0 then
            log("卸载时仍有参赛者或恢复记录；重载不会替代停止清理")
        end
        local spectatorState=spectator:status()
        if spectatorState.pending_relations>0 or spectatorState.pending_flags>0 then
            log("无仇恨快照尚未恢复；热重载前必须先关闭无仇恨并等待恢复读回")
        end
    end
end
log("loaded ✓ "..BUILD.."；全部功能键默认未绑定，可在面板自定义；自由观战包含无仇恨、隐身、无敌锁血及镜头收音。")
