-- ============================================================
-- PhantomGladiator — 《影之刃零》斗蛐蛐 Mod (UE4SS Lua)
-- 让 NPC 互相为敌、召唤单位、观战、慢动作、自由镜头。
-- 按键见 config.lua 的 Keybinds 表，可自行改键。
-- ============================================================
local Config = require("config")
local Teams = require("teams")
local Hatred = require("hatred")
local UEHelpers = require("UEHelpers")

local MOD = "[PhantomGladiator]"
local function log(msg) print(string.format("%s %s\n", MOD, tostring(msg))) end

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
            if pc:GetClass():GetFullName():find("DebugCameraController") then
                return false
            end
            return pc.Player ~= nil and pc.Player:IsValid()
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
    local ok, loc = pcall(function() return actor:K2_GetActorLocation() end)
    if ok and loc then return loc end
    return nil
end

local function DistSq(a, b)
    local dx, dy, dz = a.X - b.X, a.Y - b.Y, a.Z - b.Z
    return dx * dx + dy * dy + dz * dz
end

local function IsExcluded(pawn)
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

-- ---------- 阵营快照（F4 恢复原状的依据） ----------

local originalTeams = {}   -- addr -> 原始阵营 ID
local teamOf = {}          -- addr(pawn/controller) -> 我们指派的阵营
local playerNeutral = false
local playerPawnAddr = nil

local function ApplyTeamTracked(pawn, teamId)
    local addr = pawn:GetAddress()
    if originalTeams[addr] == nil then
        local orig = Teams.ReadTeam(pawn)
        if orig ~= nil then originalTeams[addr] = orig end
    end
    teamOf[addr] = teamId
    local ok, ctrl = pcall(function() return pawn.Controller end)
    if ok and ctrl ~= nil then
        pcall(function()
            if ctrl:IsValid() then teamOf[ctrl:GetAddress()] = teamId end
        end)
    end
    return Teams.ApplyTeam(pawn, teamId)
end

-- ---------- 态度 hook：最终裁决"谁恨谁" ----------
-- 本作的敌我判定走 SGameAI 的 BlueprintGetTeamAttitudeTowards（解剖发现），
-- hook 它的返回值：被我们分过队的怪按队伍敌我，玩家中立时对玩家返回中立。
-- ETeamAttitude: 0=Friendly 1=Neutral 2=Hostile

local attitudeHooksInstalled = false
local attitudeCalls = 0

local function lookupTeam(actor)
    if actor == nil then return nil end
    local okV, valid = pcall(function() return actor:IsValid() end)
    if not okV or not valid then return nil end
    local t = teamOf[actor:GetAddress()]
    if t then return t end
    local ok, p = pcall(function() return actor.Pawn end)
    if ok and p ~= nil then
        local okA, a = pcall(function()
            return p:IsValid() and teamOf[p:GetAddress()] or nil
        end)
        if okA and a then return a end
    end
    local ok2, c = pcall(function() return actor.Controller end)
    if ok2 and c ~= nil then
        local okA, a = pcall(function()
            return c:IsValid() and teamOf[c:GetAddress()] or nil
        end)
        if okA and a then return a end
    end
    return nil
end

local function isPlayerActor(actor)
    if not playerPawnAddr or actor == nil then return false end
    local ok, hit = pcall(function()
        if not actor:IsValid() then return false end
        if actor:GetAddress() == playerPawnAddr then return true end
        local p = actor.Pawn
        return p ~= nil and p:IsValid() and p:GetAddress() == playerPawnAddr
    end)
    return ok and hit
end

local function EnsureAttitudeHooks()
    if attitudeHooksInstalled then return end
    local okAny = false
    for _, path in ipairs(Config.AttitudeHookPaths) do
        local ok, err = pcall(function()
            RegisterHook(path, function() end, function(Context, Other, Ret)
                attitudeCalls = attitudeCalls + 1
                if attitudeCalls == 1 or attitudeCalls % 200 == 0 then
                    log(string.format("态度函数被调用第 %d 次", attitudeCalls))
                end
                pcall(function()
                    local selfCtrl = Context:get()
                    local other = Other:get()
                    if playerNeutral and (isPlayerActor(other) or isPlayerActor(selfCtrl)) then
                        Ret:set(1) -- Neutral
                        return
                    end
                    local tSelf = lookupTeam(selfCtrl)
                    local tOther = lookupTeam(other)
                    if tSelf and tOther then
                        Ret:set(tSelf == tOther and 0 or 2) -- Friendly / Hostile
                    end
                end)
            end)
        end)
        if ok then
            okAny = true
            log("态度 hook 挂载成功: " .. path:match("([%w_]+)$"))
        else
            log("态度 hook 失败: " .. tostring(err))
        end
    end
    attitudeHooksInstalled = okAny
end

-- ---------- 召唤图鉴（F1 扫描时登记；后续版本接 AssetRegistry 全量目录） ----------

local catalog = {}         -- { {name=短类名, class=UClass}, ... }
local catalogIndex = 0
local catalogSeen = {}
local summonCount = 0      -- 擂台模式：交替分队计数
local lastSummoned = nil   -- 上一只召唤物（与新召唤互种仇恨）

local function RegisterInCatalog(pawn)
    local ok = pcall(function()
        local cls = pawn:GetClass()
        if not cls or not cls:IsValid() then return end
        local full = cls:GetFullName()
        if catalogSeen[full] then return end
        catalogSeen[full] = true
        local short = full:match("([%w_]+)%s*$") or full
        table.insert(catalog, { name = short, class = cls })
        if catalogIndex == 0 then catalogIndex = 1 end
    end)
    return ok
end

-- ---------- 强制锁敌：走 SGameAI 自家的作战指令（2026-10-29 解剖成果） ----------
-- SGameAIComponent:ForceIntoCombat(Target) = "进入战斗，目标是他"；
-- 另把目标写进 AI 的黑板目标键（PBZ_TargetingHandler_AI 从那里读目标）做双保险。

local function GetAIComp(pawn)
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
    local ok, h = pcall(function() return pawn.BP_PBZHatredManagerComponent end)
    if ok and h ~= nil then
        local okV, v = pcall(function() return h:IsValid() end)
        if okV and v then return h end
    end
    return nil
end

local function HatredListContains(hm, actor)
    local found = false
    pcall(function()
        local hl = hm.HatredList
        local addr = actor:GetAddress()
        for i = 1, #hl do
            local okE, hit = pcall(function()
                return hl[i]:IsValid() and hl[i]:GetAddress() == addr
            end)
            if okE and hit then found = true return end
        end
    end)
    return found
end

local function AddHatred(attacker, victim)
    local hm = GetHatredComp(attacker)
    if not hm then return false, "无仇恨组件" end
    -- 0) 开门：受害者的"可被恨"开关掰成 true（门禁疑似读这个）
    pcall(function()
        local vh = GetHatredComp(victim)
        if vh then vh.CanBeHatredNow = true end
    end)
    -- 1) 正门：官方 Add（正门进去的条目不会被当非法清理）
    pcall(function() hm:AddActorToHatredList(victim, false) end)
    if HatredListContains(hm, victim) then return true, "官方Add" end
    -- 2) 后门：直接把对方写进 HatredList 数组
    pcall(function()
        local hl = hm.HatredList
        hl[#hl + 1] = victim
    end)
    if HatredListContains(hm, victim) then return true, "数组直写" end
    return false, "两条路都被拒"
end

-- ---------- 原生阵营系统 ----------
-- NPC 和玩家身上的 "Faction Component"（UFactionComponent）决定谁和谁是敌人，
-- 伤害、格挡、攻击开关等系统都引用它。SetFactionRelationOverride(对手, 关系, Both)
-- 可以针对单个对手覆盖敌我关系，Both=true 时双方同时生效。
-- ETeamAttitude: 0=Friendly 1=Neutral 2=Hostile

local ATTITUDE_NAME = { [0] = "友好", [1] = "中立", [2] = "敌对" }
local HOSTILE, NEUTRAL = 2, 1

local function GetFactionComp(pawn)
    local ok, fc = pcall(function() return pawn["Faction Component"] end)
    if ok and fc ~= nil then
        local okV, v = pcall(function() return fc:IsValid() end)
        if okV and v then return fc end
    end
    return nil
end

local function ReadRelation(a, b)
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

local factionOverrides = {}  -- 怪物之间的覆盖记录 { {a=, b=}, ... }，供重置键清除

-- 把 a 与 b 的关系覆盖为 relation（Both=true 一次设两边）。
-- 返回 是否调用成功, 覆盖前关系, 覆盖后关系
local function SetFactionRelation(a, b, relation, noTrack)
    local fc = GetFactionComp(a)
    if not fc then return false, nil, nil end
    local before = ReadRelation(a, b)
    local ok = pcall(function() fc:SetFactionRelationOverride(b, relation, true) end)
    local after = ReadRelation(a, b)
    if ok and not noTrack then table.insert(factionOverrides, { a = a, b = b }) end
    return ok, before, after
end

-- ---------- 召唤物的"登场状态"：伏击/隐藏/免伤效果 ----------
-- 召唤物实测互相攻击但无敌、带半透明特效，且官方加仇恨被拒。怀疑是游戏刷怪时
-- 挂上的伏击/隐藏类效果（HiddenTagsCanNotBeHatred = 隐藏中不可被仇恨）没被解除：
-- 正常刷怪会走 ActivateAI，我们是直接造出来的。
-- 闪避无敌帧、格挡保护属于正常战斗机制，只诊断不移除。

local GE_TO_STRIP = { "GE_IgnoreAllDamage_C", "GE_AmbushTags_C", "GE_HiddenTags_C",
    "GE_HiddenTagsCanNotBeHatred_C" }
local GE_TO_REPORT = { "GE_IgnoreAllDamage_C", "GE_AmbushTags_C", "GE_HiddenTags_C",
    "GE_HiddenTagsCanNotBeHatred_C", "GE_HiddenTags_DodgeInvunlerable_C",
    "GE_ReadyToDeflectProtect_C" }

local function GetASC(pawn)
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

local function StripSpawnStateGEs(pawn)
    local asc = GetASC(pawn)
    if not asc then return end
    for _, name in ipairs(GE_TO_STRIP) do
        local cls = FindGEClass(name)
        if cls then
            pcall(function() asc:RemoveActiveGameplayEffectBySourceEffect(cls, nil, -1) end)
        end
    end
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

-- 用游戏官方的刷怪函数生成（刷怪点用的那套），失败返回 nil 和原因
local function SpawnViaAILib(cls, t, world)
    local lib = GetAILib()
    if not lib then return nil, "找不到函数库" end
    local pawn = nil
    local ok, err = pcall(function() pawn = lib:SpawnAIDefered(cls, t, nil, world) end)
    if not ok then return nil, "SpawnAIDefered 报错: " .. tostring(err) end
    local okV = pawn ~= nil and pcall(function() return pawn:IsValid() end) and pawn:IsValid()
    if not okV then return nil, "SpawnAIDefered 未返回实例" end
    local ok2, err2 = pcall(function() lib:FinishSpawnAIDefered(pawn, t, world) end)
    if not ok2 then
        pcall(function() pawn:K2_DestroyActor() end)
        return nil, "FinishSpawnAIDefered 报错: " .. tostring(err2)
    end
    return pawn, nil
end

-- 让召唤物走完正常的登场流程：ActivateAI + 移除伏击/隐藏/免伤效果
local function FinishEntrance(pawn)
    local before = ListSuspectGEs(pawn)
    local activated = false
    local lib = GetAILib()
    if lib then
        activated = pcall(function() lib:ActivateAI(pawn, UEHelpers.GetWorld()) end)
    end
    StripSpawnStateGEs(pawn)
    local after = ListSuspectGEs(pawn)
    log(string.format("  登场处理: ActivateAI=%s | 可疑效果 前[%s] 后[%s] | %s",
        lib and tostring(activated) or "找不到函数库", before, after, DescribeCollision(pawn)))
end

local function ClearAllFactionOverrides()
    local n = 0
    for _, pair in ipairs(factionOverrides) do
        pcall(function()
            local fa, fb = GetFactionComp(pair.a), GetFactionComp(pair.b)
            if fa and pair.b:IsValid() then fa:ClearFactionRelationOverride(pair.b) end
            if fb and pair.a:IsValid() then fb:ClearFactionRelationOverride(pair.a) end
            n = n + 1
        end)
    end
    factionOverrides = {}
    return n
end

-- ---------- 战况监视 + 锁敌续命 ----------

local function GetHP(pawn)
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
            local okO, outer = pcall(function() return s:GetOuter() end)
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

local watchGen = 0  -- 新配对会使旧监视循环自然退出

-- 受击反馈：裁判扣血时让受害者播放自己的受击蒙太奇（它身上现成的资产）
local hitMontageCache = {}  -- pawnAddr -> montage or false(找过没有)

local function PlayHitReact(victim)
    pcall(function()
        local addr = victim:GetAddress()
        local cached = hitMontageCache[addr]
        if cached == false then return end
        if not cached then
            cached = false
            local ok, montages = pcall(FindAllOf, "AnimMontage")
            if ok and montages then
                -- 轻受击优先；排除倒地/死亡/击飞/重击类（不然会反复表演躺下）
                -- 受害者的种族关键词（BP_Monster_FemaleThug_Dart_C → FemaleThug），
                -- 蒙太奇必须来自它自己的动画目录，否则骨架不匹配播不出来
                local species = nil
                pcall(function()
                    species = victim:GetClass():GetFullName()
                        :match("BP_Monster_([A-Za-z]+)")
                end)
                local best, bestScore = nil, -1
                for _, m in ipairs(montages) do
                    local okN, n = pcall(function() return m:GetFullName() end)
                    if okN and n and (n:find("[Hh]it") or n:find("[Hh]urt"))
                        and (not species or n:find(species)) then
                        if not n:find("[Dd]own") and not n:find("[Dd]ie")
                            and not n:find("[Dd]ead") and not n:find("[Kk]nock")
                            and not n:find("[Ll]ie") and not n:find("[Ff]all")
                            and not n:find("[Aa]ir") and not n:find("[Hh]eavy")
                            and not n:find("[Ee]xecut") then
                            local score = 0
                            if n:find("[Ll]ight") then score = score + 2 end
                            if n:find("[Ss]mall") then score = score + 2 end
                            if n:find("[Ff]ront") then score = score + 1 end
                            if score > bestScore then
                                best, bestScore = m, score
                            end
                        end
                    end
                end
                cached = best or false
                if best then
                    pcall(function()
                        log("受击动画选用: " .. best:GetFullName())
                    end)
                else
                    log("没找到合适的轻受击蒙太奇（本区已加载的全是倒地类）")
                end
            end
            hitMontageCache[addr] = cached
        end
        if cached and cached ~= false and cached:IsValid() then
            victim:PlayAnimMontage(cached, 1.0, FName(""))
        end
    end)
end

-- 裁判判伤实验：怪物互殴的刀互相"穿模"（命中判定不认非玩家目标），
-- 所以轮流试两种判伤手段，观察哪种能移动 HP / 触发受击与死亡：
--   A: UE 通用 ApplyDamage（走引擎伤害事件）
--   B: 直接写 Health 属性（绕开一切管线）
local function JudgeDamage(victim, attacker, amount, method)
    if method == "A" then
        local gps = GetGameplayStatics()
        if not gps then return false end
        local dmgType = StaticFindObject("/Script/Engine.DamageType")
        return pcall(function()
            gps:ApplyDamage(victim, amount, attacker.Controller, attacker, dmgType)
        end)
    else
        return pcall(function()
            local ok, sets = pcall(FindAllOf, "BasicAttributeSet")
            if not ok or not sets then error("no sets") end
            local vAddr = victim:GetAddress()
            local ascAddr = nil
            pcall(function()
                local asc = victim.AbilitySystemComponent
                if asc and asc:IsValid() then ascAddr = asc:GetAddress() end
            end)
            for _, s in ipairs(sets) do
                local okO, outer = pcall(function() return s:GetOuter() end)
                if okO and outer and outer:IsValid() then
                    local oa = outer:GetAddress()
                    if oa == vAddr or oa == ascAddr then
                        s.Health.CurrentValue = s.Health.CurrentValue - amount
                        return
                    end
                end
            end
            error("attr set not found")
        end)
    end
end

local function StartDuelWatch(a, b)
    watchGen = watchGen + 1
    local myGen = watchGen
    local ticks = 0
    local lastForceTick = -10
    local forceCount = 0
    LoopAsync(2500, function()
        if myGen ~= watchGen then return true end
        ticks = ticks + 1
        local stop = ticks >= 240  -- 最长 10 分钟，或分出胜负为止
        ExecuteInGameThread(function()
            local okA = pcall(function() return a:IsValid() end) and a:IsValid()
            local okB = pcall(function() return b:IsValid() end) and b:IsValid()
            if not okA or not okB then
                log(string.format("🏆 决斗结束：%s 存活",
                    okA and "蓝方" or (okB and "红方" or "无人")))
                watchGen = watchGen + 1
                return
            end
            local hpA, hpB = GetHP(a), GetHP(b)
            local judging = Config.JudgeDamagePerTick and Config.JudgeDamagePerTick > 0
            if not judging then
                -- 不判伤：只观察原生战斗，血打空就是游戏自己判的死
                local deadA = hpA and hpA <= 0
                local deadB = hpB and hpB <= 0
                if deadA or deadB then
                    local verdict = (deadA and deadB) and "同归于尽"
                        or (deadA and "红方获胜" or "蓝方获胜")
                    log(string.format("🏆 决斗结束（原生伤害）：%s（蓝 HP=%s 红 HP=%s）",
                        verdict, tostring(hpA), tostring(hpB)))
                    watchGen = watchGen + 1
                    return
                end
            end
            -- 判伤模式：血降到阈值就执行 Kill
            local KT = Config.KillThreshold or 25
            local lowA = judging and hpA and hpA <= KT
            local lowB = judging and hpB and hpB <= KT
            if lowA or lowB then
                -- 编导式死亡：Kill() 是瞬间清场（实测无动画），所以先播
                -- 败者自己的死亡蒙太奇，演完再清场——观感=被打死倒下
                local function stageDeath(victim)
                    local played = false
                    pcall(function()
                        local species = victim:GetClass():GetFullName()
                            :match("BP_Monster_([A-Za-z]+)")
                        local ok, montages = pcall(FindAllOf, "AnimMontage")
                        if ok and montages then
                            for _, m in ipairs(montages) do
                                local okN, n = pcall(function() return m:GetFullName() end)
                                if okN and n and (not species or n:find(species))
                                    and (n:find("[Dd]ie") or n:find("[Dd]eath")
                                         or n:find("[Dd]ead")) then
                                    victim:PlayAnimMontage(m, 1.0, FName(""))
                                    played = true
                                    log("死亡演出: " .. n)
                                    break
                                end
                            end
                        end
                    end)
                    ExecuteWithDelay(played and 2800 or 200, function()
                        ExecuteInGameThread(function()
                            pcall(function()
                                if victim:IsValid() then victim:Kill(1) end
                            end)
                        end)
                    end)
                end
                if lowA then stageDeath(a) end
                if lowB then stageDeath(b) end
                local verdict = (lowA and lowB) and "同归于尽"
                    or (lowA and "红方获胜" or "蓝方获胜")
                log(string.format("🏆 决斗结束：%s（蓝 HP=%s 红 HP=%s）",
                    verdict, tostring(hpA), tostring(hpB)))
                watchGen = watchGen + 1
                return
            end
            -- 判伤：属性直写（实测唯一有效），伤害随机浮动让比赛有真胜负
            if Config.JudgeDamagePerTick and Config.JudgeDamagePerTick > 0 then
                local base = Config.JudgeDamagePerTick
                JudgeDamage(a, b, base * (0.5 + math.random()), "B")
                JudgeDamage(b, a, base * (0.5 + math.random()), "B")
                -- 受击动画低频随机播放：每次都播会把 AI 的出招不停打断，
                -- 变成全程抽搐（实测教训）。只偶尔给一侧一个踉跄
                local roll = math.random()
                if roll < 0.35 then
                    PlayHitReact(roll < 0.175 and a or b)
                end
            end
            -- 读当前 AI 状态（诊断"站桩"用）
            local function stateOf(p)
                local s = "?"
                pcall(function()
                    local sg = GetAIComp(p)
                    if sg then s = FNameToString(sg.CurrentStateTag.TagName) end
                end)
                return s
            end
            log(string.format("战况[%d]: 蓝 HP=%s(%s) | 红 HP=%s(%s) | 关系 蓝→红=%s 红→蓝=%s",
                ticks, tostring(hpA), stateOf(a), tostring(hpB), stateOf(b),
                RelationName(ReadRelation(a, b)), RelationName(ReadRelation(b, a))))
            -- Astra 方案：脱战检测式恢复——只有仇恨列表真的丢了对方才
            -- 修复 + 单次补发作战指令（≥10 秒冷却、全场最多 3 次），
            -- 其余时间完全不打扰 AI
            local hmA, hmB = GetHatredComp(a), GetHatredComp(b)
            local lostA = hmA and not HatredListContains(hmA, b)
            local lostB = hmB and not HatredListContains(hmB, a)
            if lostA or lostB then
                -- 阵营覆盖可能被游戏重置，先补阵营再补仇恨
                if ReadRelation(a, b) ~= HOSTILE then
                    SetFactionRelation(a, b, HOSTILE, true)
                end
                AddHatred(a, b)
                AddHatred(b, a)
                if (ticks - lastForceTick) >= 4 and forceCount < 3 then
                    lastForceTick = ticks
                    forceCount = forceCount + 1
                    local sgA2, sgB2 = GetAIComp(a), GetAIComp(b)
                    if lostA and sgA2 then
                        pcall(function() sgA2:ForceIntoCombat(b) end)
                    end
                    if lostB and sgB2 then
                        pcall(function() sgB2:ForceIntoCombat(a) end)
                    end
                    log(string.format("脱战恢复 #%d（蓝丢失=%s 红丢失=%s）",
                        forceCount, tostring(lostA), tostring(lostB)))
                end
            end
        end)
        return stop
    end)
end

local function ForceAttack(attacker, victim)
    -- 先走阵营正门：关系覆盖为敌对后，官方 AddActorToHatredList 的门禁应当放行
    local okF, before, after = SetFactionRelation(attacker, victim, HOSTILE)
    local okHate, how = AddHatred(attacker, victim)
    log(string.format("  阵营关系 %s→%s（覆盖%s） | 拉仇恨 %s",
        RelationName(before), RelationName(after), okF and "成功" or "失败",
        okHate and ("成功(" .. how .. ")") or ("失败: " .. tostring(how))))
    local sg = GetAIComp(attacker)
    if not sg then return okHate end
    local okForce = pcall(function() sg:ForceIntoCombat(victim) end)
    okForce = okForce or okHate
    -- 黑板目标键直写（键名从 AI 的 TargetingHandler 实例上现读）
    pcall(function()
        local bb = sg.BlackboardComponent
        if not bb or not bb:IsValid() then return end
        local okH, handlers = pcall(FindAllOf, "PBZ_TargetingHandler_AI_C")
        if not okH or not handlers then return end
        for _, h in ipairs(handlers) do
            local okM, match = pcall(function()
                return h:IsValid() and h.Blackboard ~= nil and h.Blackboard:IsValid()
                    and h.Blackboard:GetAddress() == bb:GetAddress()
            end)
            if okM and match then
                local okK, keyName = pcall(function() return h["Target Key"] end)
                if okK and keyName then
                    bb:SetValueAsObject(keyName, victim)
                end
                break
            end
        end
    end)
    return okForce
end

-- ---------- 种仇恨：互相打 1 点伤害，触发 AI 的受击感知 ----------

local function SeedHatred(a, b)
    local gps = GetGameplayStatics()
    if not gps then return false end
    local dmgType = StaticFindObject("/Script/Engine.DamageType")
    local function hit(victim, attacker)
        return pcall(function()
            local instigator = attacker.Controller
            gps:ApplyDamage(victim, Config.SeedDamage, instigator, attacker, dmgType)
        end)
    end
    local ok1 = hit(b, a)
    local ok2 = hit(a, b)
    return ok1 and ok2
end

-- ---------- 扫描 ----------

local function CollectNPCs()
    local player = GetPlayerPawn()
    local playerAddr = player and player:GetAddress() or nil
    local result, seen = {}, {}
    for _, className in ipairs(Config.EnemyClasses) do
        local ok, found = pcall(FindAllOf, className)
        if ok and found then
            for _, pawn in ipairs(found) do
                if pawn:IsValid() then
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

local function ScanNPCs()
    ExecuteInGameThread(function()
        local npcs = CollectNPCs()
        local player = GetPlayerPawn()
        local pLoc = player and GetLocation(player)
        local ctrlSeen = {}
        log(string.format("扫描到 %d 个候选 NPC:", #npcs))
        for i, pawn in ipairs(npcs) do
            RegisterInCatalog(pawn)
            local dist = -1
            local loc = GetLocation(pawn)
            if loc and pLoc then dist = math.sqrt(DistSq(loc, pLoc)) / 100 end
            log(string.format("  [%d] %s  距离 %.1fm", i, pawn:GetFullName(), dist))
        end
        log(string.format("召唤图鉴共 %d 种（Shift+%s 切换 / %s 召唤）",
            #catalog, Config.Keybinds.Summon, Config.Keybinds.Summon))
        if #npcs == 0 then
            log("没扫到 NPC。请调整 config.EnemyClasses")
        end
    end)
end

-- ---------- 全场互殴 / 决斗 / 恢复 ----------

local function GlobalInfight()
    ExecuteInGameThread(function()
        EnsureAttitudeHooks()
        local npcs = CollectNPCs()
        local okCount = 0
        local teamIdx = {}
        for i, pawn in ipairs(npcs) do
            teamIdx[i] = i % Config.TeamCount
            ApplyTeamTracked(pawn, Config.TeamIdBase + teamIdx[i])
        end
        -- 不同队的每一对都用原生阵营接口设为敌对
        local pairCount, pairsOk = 0, 0
        for i = 1, #npcs do
            for j = i + 1, #npcs do
                if teamIdx[i] ~= teamIdx[j] then
                    pairCount = pairCount + 1
                    local ok, _, after = SetFactionRelation(npcs[i], npcs[j], HOSTILE)
                    if ok and after == HOSTILE then pairsOk = pairsOk + 1 end
                end
            end
        end
        okCount = #npcs
        log(string.format("全场互殴！%d 个 NPC 分成 %d 队，敌对关系 %d/%d 对生效",
            okCount, Config.TeamCount, pairsOk, pairCount))
    end)
end

local function DuelNearest()
    ExecuteInGameThread(function()
        EnsureAttitudeHooks()
        local player = GetPlayerPawn()
        local pLoc = player and GetLocation(player)
        if not pLoc then
            log("找不到玩家位置")
            return
        end
        local npcs = CollectNPCs()
        table.sort(npcs, function(a, b)
            local la, lb = GetLocation(a), GetLocation(b)
            if not la then return false end
            if not lb then return true end
            return DistSq(la, pLoc) < DistSq(lb, pLoc)
        end)
        if #npcs < 2 then
            log("场上不足两个 NPC，无法决斗")
            return
        end
        log(string.format("  决斗双方可疑效果: [%s] vs [%s]",
            ListSuspectGEs(npcs[1]), ListSuspectGEs(npcs[2])))
        log(string.format("  决斗双方碰撞: [%s] vs [%s]",
            DescribeCollision(npcs[1]), DescribeCollision(npcs[2])))
        ApplyTeamTracked(npcs[1], Config.TeamIdBase)
        ApplyTeamTracked(npcs[2], Config.TeamIdBase + 1)
        local f1 = ForceAttack(npcs[1], npcs[2])
        local f2 = ForceAttack(npcs[2], npcs[1])
        SeedHatred(npcs[1], npcs[2])
        log(string.format("决斗开始: %s VS %s（强制锁敌 %s/%s，战况监视已启动）",
            npcs[1]:GetFullName(), npcs[2]:GetFullName(),
            f1 and "OK" or "失败", f2 and "OK" or "失败"))
        StartDuelWatch(npcs[1], npcs[2])
    end)
end

local function ResetTeams()
    ExecuteInGameThread(function()
        local npcs = CollectNPCs()
        local okCount = 0
        for _, pawn in ipairs(npcs) do
            local addr = pawn:GetAddress()
            local orig = originalTeams[addr]
            if orig ~= nil then
                if Teams.ApplyTeam(pawn, orig) then okCount = okCount + 1 end
            end
        end
        originalTeams = {}
        teamOf = {}
        Hatred.Reset()
        local cleared = ClearAllFactionOverrides()
        log(string.format("已把 %d 个 NPC 恢复到原始阵营，清除 %d 组阵营关系覆盖",
            okCount, cleared))
    end)
end

-- ---------- 玩家中立化开关 ----------

local playerOrigTeam = nil
local neutralNPCs = {}  -- 已对玩家覆盖为中立的 NPC

-- 让一只 NPC 对玩家中立：原生阵营覆盖 + 从它的仇恨列表里除名
local function NeutralizeAgainstPlayer(npc, player)
    local ok, _, after = SetFactionRelation(npc, player, NEUTRAL, true)
    pcall(function()
        local hm = GetHatredComp(npc)
        if hm then hm:RemoveActorFromHatredList(player) end
    end)
    if ok then table.insert(neutralNPCs, npc) end
    return ok and after == NEUTRAL
end

local function TogglePlayerNeutral()
    ExecuteInGameThread(function()
        local pawn = GetPlayerPawn()
        if not pawn then
            log("找不到玩家 Pawn")
            return
        end
        EnsureAttitudeHooks()
        playerPawnAddr = pawn:GetAddress()
        if not playerNeutral then
            playerOrigTeam = Teams.ReadTeam(pawn)
            Teams.ApplyTeam(pawn, Config.NeutralTeamId)
            local npcs = CollectNPCs()
            local okN = 0
            for _, npc in ipairs(npcs) do
                if NeutralizeAgainstPlayer(npc, pawn) then okN = okN + 1 end
            end
            playerNeutral = true
            log(string.format("玩家已中立化：%d/%d 个怪对你的阵营关系已覆盖为中立；再按一次恢复",
                okN, #npcs))
        else
            local cleared = 0
            for _, npc in ipairs(neutralNPCs) do
                pcall(function()
                    if npc:IsValid() then
                        local fc = GetFactionComp(npc)
                        if fc then
                            fc:ClearFactionRelationOverride(pawn)
                            cleared = cleared + 1
                        end
                    end
                end)
            end
            neutralNPCs = {}
            Teams.ApplyTeam(pawn, playerOrigTeam or 0)
            playerNeutral = false
            log(string.format("玩家中立已解除（清除 %d 只怪的中立覆盖）", cleared))
        end
    end)
end

-- ---------- 召唤 ----------

local function CycleSummonClass()
    if #catalog == 0 then
        log("图鉴是空的：先按 " .. Config.Keybinds.Scan .. " 扫描一次")
        return
    end
    catalogIndex = catalogIndex % #catalog + 1
    log(string.format("已选中 [%d/%d] %s", catalogIndex, #catalog,
        catalog[catalogIndex].name))
end

local function SummonSelected()
    ExecuteInGameThread(function()
        if #catalog == 0 then
            -- 图鉴空了（热重载会清空）就自动扫一遍
            for _, pawn in ipairs(CollectNPCs()) do RegisterInCatalog(pawn) end
            if #catalog > 0 then
                log(string.format("图鉴自动重建：%d 种", #catalog))
            end
        end
        if #catalog == 0 or catalogIndex == 0 then
            log("附近没有可登记的怪，图鉴为空")
            return
        end
        local entry = catalog[catalogIndex]
        local player = GetPlayerPawn()
        local loc = player and GetLocation(player)
        if not loc then
            log("找不到玩家位置")
            return
        end
        local okF, fwd = pcall(function() return player:GetActorForwardVector() end)
        if not okF or not fwd then fwd = { X = 1, Y = 0, Z = 0 } end
        local t = {
            Rotation = { X = 0, Y = 0, Z = 0, W = 1 },
            Translation = {
                X = loc.X + fwd.X * Config.SummonDistance,
                Y = loc.Y + fwd.Y * Config.SummonDistance,
                Z = loc.Z + Config.SummonHeightOffset,
            },
            Scale3D = { X = 1, Y = 1, Z = 1 },
        }
        local gps = GetGameplayStatics()
        local world = UEHelpers.GetWorld()
        if not gps or not world or not world:IsValid() then
            log("召唤失败：GameplayStatics/World 不可用")
            return
        end
        -- 优先走游戏官方刷怪函数；失败再退回引擎通用生成
        local actor, why = SpawnViaAILib(entry.class, t, world)
        local okFin, errFin = actor ~= nil, nil
        if actor then
            log("  召唤途径: 官方刷怪函数")
        else
            log("  召唤途径: 引擎通用生成（官方刷怪失败: " .. tostring(why) .. "）")
            -- UE5 不同小版本参数个数不同，两种签名都试
            local ok = pcall(function()
                actor = gps:BeginDeferredActorSpawnFromClass(world, entry.class, t, 1, nil, 1)
            end)
            if not ok or not actor or not actor:IsValid() then
                ok = pcall(function()
                    actor = gps:BeginDeferredActorSpawnFromClass(world, entry.class, t, 1, nil)
                end)
            end
            if not ok or not actor or not actor:IsValid() then
                log("召唤失败：BeginDeferredActorSpawnFromClass 未返回实例")
                return
            end
            -- 5.4+ 多了 TransformScaleMethod 参数，反射调用可能必填：两种签名都试
            okFin, errFin = pcall(function() gps:FinishSpawningActor(actor, t, 1) end)
            if not okFin then
                okFin, errFin = pcall(function() gps:FinishSpawningActor(actor, t) end)
            end
        end
        if okFin then
            -- 擂台模式：召唤物交替分蓝/红队，并与上一只互种仇恨，落地即开打
            EnsureAttitudeHooks()
            FinishEntrance(actor)
            if playerNeutral then NeutralizeAgainstPlayer(actor, player) end
            summonCount = summonCount + 1
            local teamId = Config.TeamIdBase + (summonCount % 2)
            ApplyTeamTracked(actor, teamId)
            local fightNote = ""
            if lastSummoned and lastSummoned:IsValid() then
                local fA = ForceAttack(actor, lastSummoned)
                local fB = ForceAttack(lastSummoned, actor)
                SeedHatred(actor, lastSummoned)
                StartDuelWatch(actor, lastSummoned)
                fightNote = (fA and fB) and "，已强制互相锁敌（战况监视启动）"
                    or "，强制锁敌部分失败（可再按决斗键补）"
            end
            lastSummoned = actor
            log(string.format("已在面前召唤: %s（%s队%s）", entry.name,
                summonCount % 2 == 0 and "红" or "蓝", fightNote))
        else
            -- 清理半成品，别留一只不会动的"雕像"在场上
            pcall(function() actor:K2_DestroyActor() end)
            log("召唤失败（半成品已清理）：FinishSpawningActor: " .. tostring(errFin))
        end
    end)
end

-- ---------- 解剖：把最近一只怪的 AI 大脑结构写到文件（Shift+扫描键） ----------
-- 注意：UE4SS 对象的空指针链式调用会原生崩溃，pcall 拦不住，
-- 所以每一步都先取引用、IsValid 之后再往下走。

local function safeValid(obj)
    local ok, v = pcall(function() return obj ~= nil and obj:IsValid() end)
    return ok and v
end

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
    local ok, err = pcall(function()
        local asc = nil
        pcall(function() asc = pawn.AbilitySystemComponent end)
        if not asc or not pcall(function() return asc:IsValid() end) or not asc:IsValid() then
            pcall(function() asc = pawn.AbilitySystem end)
        end
        if not asc or not asc:IsValid() then
            log(label .. " 没有 AbilitySystemComponent")
            return
        end
        local container = {}
        asc:GetOwnedGameplayTags(container)
        local names = {}
        local okBreak = pcall(function()
            local lib = StaticFindObject(
                "/Script/GameplayTags.Default__BlueprintGameplayTagLibrary")
            local arr = {}
            lib:BreakGameplayTagContainer(container, arr)
            for i = 1, #arr do
                pcall(function()
                    table.insert(names, FNameToString(arr[i].TagName))
                end)
            end
        end)
        if not okBreak then
            -- 退路：直接遍历容器的 GameplayTags 数组
            pcall(function()
                local tags = container.GameplayTags or container
                for i = 1, #tags do
                    pcall(function()
                        table.insert(names, FNameToString(tags[i].TagName))
                    end)
                end
            end)
        end
        log(string.format("%s 身上标签 [%d]: %s", label, #names,
            table.concat(names, ", ")))
    end)
    if not ok then
        log(string.format("%s 标签读取报错: %s", label, tostring(err)))
    end
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
                return npcs[i]:GetClass():GetFullName():match("([%w_]+)$")
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
                            log("    " .. hl[i]:GetFullName())
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
                                if a.GetFullName then return a:GetFullName() end
                                if a.get then return a:get():GetFullName() end
                                return tostring(a)
                            end)
                            log("    " .. (okE and nameE or "?"))
                        end
                    end
                end
            end)
        end
    end)
end

-- ---------- 慢动作 ----------

local dilationIndex = 1
local function CycleSlowMo()
    ExecuteInGameThread(function()
        dilationIndex = dilationIndex % #Config.TimeDilationSteps + 1
        local target = Config.TimeDilationSteps[dilationIndex]
        local count = 0
        local ok, list = pcall(FindAllOf, "WorldSettings")
        if ok and list then
            for _, ws in ipairs(list) do
                if pcall(function() ws.TimeDilation = target end) then
                    count = count + 1
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

local function ToggleFreeCam()
    ExecuteInGameThread(function()
        local dcc = FindActiveDebugCam()
        if dcc then
            local ok, err = pcall(ExitFreeCam, dcc)
            log(ok and "自由镜头：已退出" or ("退出失败: " .. tostring(err)))
            return
        end
        -- 必须用"真玩家控制器自己"的 CheatManager：FindFirstOf 会抓到
        -- 我们之前在报废调试相机上构造的孤儿实例，指令会发给死对象
        local ok, err = pcall(function()
            local pc = GetRealPlayerController()
            if not pc then error("real PlayerController not found") end
            local cm = pc.CheatManager
            if not cm or not cm:IsValid() then
                local cmClass = StaticFindObject("/Script/Engine.CheatManager")
                cm = StaticConstructObject(cmClass, pc)
                if not cm or not cm:IsValid() then
                    error("construct CheatManager failed")
                end
                pc.CheatManager = cm
            end
            cm:ToggleDebugCamera()
        end)
        log(ok and "自由镜头：已进入（再按一次退出）"
               or ("自由镜头进入失败: " .. tostring(err)))
    end)
end

local function ForceExitFreeCam()
    ExecuteInGameThread(function()
        local dcc = FindActiveDebugCam()
        if not dcc then
            log("没有激活的 DebugCameraController，无需退出")
            return
        end
        local ok, err = pcall(ExitFreeCam, dcc)
        if ok then
            log("强制退出自由镜头：控制权已交还")
        else
            log("强制退出失败: " .. tostring(err) .. "（只能重启游戏了）")
        end
    end)
end

-- ---------- 按键注册（映射见 config.lua 的 Keybinds） ----------

local actions = {
    Scan = ScanNPCs,
    Infight = GlobalInfight,
    Duel = DuelNearest,
    Reset = ResetTeams,
    SlowMo = CycleSlowMo,
    FreeCam = ToggleFreeCam,
    ForceExitCam = ForceExitFreeCam,
    PlayerNeutral = TogglePlayerNeutral,
    Summon = SummonSelected,
}

local bound = {}
for name, keyName in pairs(Config.Keybinds) do
    local key = Key[keyName]
    if key and actions[name] then
        RegisterKeyBind(key, actions[name])
        table.insert(bound, string.format("%s=%s", keyName, name))
    else
        log(string.format("按键配置无效: %s = %s", name, tostring(keyName)))
    end
end
if Key[Config.Keybinds.Summon] then
    RegisterKeyBind(Key[Config.Keybinds.Summon], { ModifierKey.SHIFT }, CycleSummonClass)
end
if Key[Config.Keybinds.Scan] then
    RegisterKeyBind(Key[Config.Keybinds.Scan], { ModifierKey.SHIFT }, DumpBrain)
end
if Key[Config.Keybinds.Infight] then
    RegisterKeyBind(Key[Config.Keybinds.Infight], { ModifierKey.SHIFT }, TargetDiag)
end

-- ---------- V2 仇恨矩阵（可选） ----------

if Config.EnableHatred then
    Hatred.TryInstallHook(log)
end

log("loaded ✓ 按键: " .. table.concat(bound, " / ")
    .. " / Shift+" .. Config.Keybinds.Summon .. "=换怪")
