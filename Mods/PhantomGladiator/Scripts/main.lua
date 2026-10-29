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

local function ApplyTeamTracked(pawn, teamId)
    local addr = pawn:GetAddress()
    if originalTeams[addr] == nil then
        local orig = Teams.ReadTeam(pawn)
        if orig ~= nil then originalTeams[addr] = orig end
    end
    return Teams.ApplyTeam(pawn, teamId)
end

-- ---------- 召唤图鉴（F1 扫描时登记；后续版本接 AssetRegistry 全量目录） ----------

local catalog = {}         -- { {name=短类名, class=UClass}, ... }
local catalogIndex = 0
local catalogSeen = {}

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
        local npcs = CollectNPCs()
        local okCount, strategyUsed = 0, nil
        for i, pawn in ipairs(npcs) do
            local teamId = Config.TeamIdBase + (i % Config.TeamCount)
            local strategy = ApplyTeamTracked(pawn, teamId)
            if strategy then
                okCount = okCount + 1
                strategyUsed = strategyUsed or strategy
            end
        end
        if okCount > 0 then
            log(string.format("全场互殴！%d/%d 个 NPC 已分成 %d 个阵营（策略: %s）",
                okCount, #npcs, Config.TeamCount, strategyUsed))
        else
            log("阵营写入全部失败（适配问题，见 README）")
        end
    end)
end

local function DuelNearest()
    ExecuteInGameThread(function()
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
        local s1 = ApplyTeamTracked(npcs[1], Config.TeamIdBase)
        local s2 = ApplyTeamTracked(npcs[2], Config.TeamIdBase + 1)
        if s1 and s2 then
            local seeded = SeedHatred(npcs[1], npcs[2])
            log(string.format("决斗开始: %s VS %s%s",
                npcs[1]:GetFullName(), npcs[2]:GetFullName(),
                seeded and "（已互种仇恨）" or "（种仇恨失败，靠感知自然索敌）"))
        else
            log("决斗阵营写入失败")
        end
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
        Hatred.Reset()
        log(string.format("已把 %d 个 NPC 恢复到原始阵营", okCount))
    end)
end

-- ---------- 玩家中立化开关 ----------

local playerNeutral = false
local playerOrigTeam = nil

local function TogglePlayerNeutral()
    ExecuteInGameThread(function()
        local pawn = GetPlayerPawn()
        if not pawn then
            log("找不到玩家 Pawn")
            return
        end
        if not playerNeutral then
            playerOrigTeam = Teams.ReadTeam(pawn)
            if Teams.ApplyTeam(pawn, Config.NeutralTeamId) then
                playerNeutral = true
                log(string.format("玩家已中立化（原阵营 %s → %d），怪物应当无视你；再按一次恢复",
                    tostring(playerOrigTeam), Config.NeutralTeamId))
            else
                log("中立化失败：玩家阵营写不进去")
            end
        else
            local target = playerOrigTeam or 0
            if Teams.ApplyTeam(pawn, target) then
                playerNeutral = false
                log(string.format("玩家阵营已恢复为 %d", target))
            else
                log("恢复失败")
            end
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
        if #catalog == 0 or catalogIndex == 0 then
            log("图鉴是空的：先按 " .. Config.Keybinds.Scan .. " 扫描一次")
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
        local actor = nil
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
        local okFin, errFin = pcall(function() gps:FinishSpawningActor(actor, t, 1) end)
        if not okFin then
            okFin, errFin = pcall(function() gps:FinishSpawningActor(actor, t) end)
        end
        if okFin then
            log(string.format("已在面前召唤: %s", entry.name))
        else
            -- 清理半成品，别留一只不会动的"雕像"在场上
            pcall(function() actor:K2_DestroyActor() end)
            log("召唤失败（半成品已清理）：FinishSpawningActor: " .. tostring(errFin))
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

-- ---------- V2 仇恨矩阵（可选） ----------

if Config.EnableHatred then
    Hatred.TryInstallHook(log)
end

log("loaded ✓ 按键: " .. table.concat(bound, " / ")
    .. " / Shift+" .. Config.Keybinds.Summon .. "=换怪")
