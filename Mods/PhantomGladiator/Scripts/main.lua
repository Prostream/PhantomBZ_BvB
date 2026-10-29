-- ============================================================
-- PhantomGladiator — 《影之刃零》斗蛐蛐 Mod (UE4SS Lua)
-- 让 NPC 互相为敌、观战、慢动作、自由镜头。
-- 状态: v0.1 脚手架 — 通用策略链已就绪，游戏特定类名见 config.lua
-- ============================================================
local Config = require("config")
local Teams = require("teams")
local Hatred = require("hatred")
local UEHelpers = require("UEHelpers")

local MOD = "[PhantomGladiator]"
local function log(msg) print(string.format("%s %s\n", MOD, tostring(msg))) end

log("loading... 按 F1 扫描 / F2 全场互殴 / F3 决斗 / F4 重置 / F5 慢动作 / F6 自由镜头")

-- ---------- 基础工具 ----------

local function GetPlayerPawn()
    local ok, pawn = pcall(function()
        local pc = UEHelpers.GetPlayerController()
        return pc and pc:IsValid() and pc.Pawn or nil
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

--- 扫描场上所有候选 NPC（排除玩家与友方关键词）
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

-- ---------- F1: 扫描并列出 NPC ----------

local function ScanNPCs()
    ExecuteInGameThread(function()
        local npcs = CollectNPCs()
        local player = GetPlayerPawn()
        local pLoc = player and GetLocation(player)
        log(string.format("扫描到 %d 个候选 NPC:", #npcs))
        for i, pawn in ipairs(npcs) do
            local dist = -1
            local loc = GetLocation(pawn)
            if loc and pLoc then dist = math.sqrt(DistSq(loc, pLoc)) / 100 end
            log(string.format("  [%d] %s  距离 %.1fm", i, pawn:GetFullName(), dist))
        end
        if #npcs == 0 then
            log("没扫到 NPC。请调整 config.EnemyClasses（用 UE4SS Live View 看真实类名）")
        end
    end)
end

-- ---------- F2: 全场互殴 ----------

local function GlobalInfight()
    ExecuteInGameThread(function()
        local npcs = CollectNPCs()
        local okCount, strategyUsed = 0, nil
        for i, pawn in ipairs(npcs) do
            local teamId = Config.TeamIdBase + (i % Config.TeamCount)
            local strategy = Teams.ApplyTeam(pawn, teamId)
            if strategy then
                okCount = okCount + 1
                strategyUsed = strategyUsed or strategy
            end
        end
        if okCount > 0 then
            log(string.format("全场互殴！%d/%d 个 NPC 已分成 %d 个阵营（策略: %s）",
                okCount, #npcs, Config.TeamCount, strategyUsed))
        else
            log("阵营写入全部失败 — 本作不走标准阵营接口。")
            log("下一步: 用 UE4SS Live View 观察敌人索敌时变化的属性，把名字填进 config.lua，")
            log("或在 Dump 里找目标选择函数，改用 hook 方案（见 README 适配指南）。")
        end
    end)
end

-- ---------- F3: 决斗模式（离玩家最近的两个 NPC 互殴） ----------

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
        local s1 = Teams.ApplyTeam(npcs[1], Config.TeamIdBase)
        local s2 = Teams.ApplyTeam(npcs[2], Config.TeamIdBase + 1)
        if s1 and s2 then
            log(string.format("决斗开始: %s  VS  %s", npcs[1]:GetFullName(), npcs[2]:GetFullName()))
        else
            log("决斗阵营写入失败（同 F2 的适配问题）")
        end
    end)
end

-- ---------- F4: 重置阵营 ----------

local function ResetTeams()
    ExecuteInGameThread(function()
        local npcs = CollectNPCs()
        local okCount = 0
        for _, pawn in ipairs(npcs) do
            if Teams.ApplyTeam(pawn, Config.DefaultTeamId) then okCount = okCount + 1 end
        end
        Hatred.Reset()
        log(string.format("已重置 %d 个 NPC 的阵营为 %d", okCount, Config.DefaultTeamId))
    end)
end

-- ---------- F5: 慢动作档位循环 ----------

local dilationIndex = 1
local function CycleSlowMo()
    ExecuteInGameThread(function()
        local ok = pcall(function()
            local ws = FindFirstOf("WorldSettings")
            if not ws or not ws:IsValid() then error("no WorldSettings") end
            dilationIndex = dilationIndex % #Config.TimeDilationSteps + 1
            ws.TimeDilation = Config.TimeDilationSteps[dilationIndex]
        end)
        if ok then
            log(string.format("时间流速: %.2fx", Config.TimeDilationSteps[dilationIndex]))
        else
            log("设置 TimeDilation 失败")
        end
    end)
end

-- ---------- F6: 自由镜头（调试相机） ----------

local function ToggleFreeCam()
    ExecuteInGameThread(function()
        local ok, err = pcall(function()
            local kismet = UEHelpers.GetKismetSystemLibrary()
            local world = UEHelpers.GetWorld()
            local pc = UEHelpers.GetPlayerController()
            kismet:ExecuteConsoleCommand(world, "ToggleDebugCamera", pc)
        end)
        if ok then
            log("切换自由镜头（若无反应说明 Shipping 版剔除了 DebugCamera，请改用 UE4SS 自带 FreeCam: 见 README）")
        else
            log("自由镜头失败: " .. tostring(err))
        end
    end)
end

-- ---------- 按键注册 ----------

RegisterKeyBind(Key.F1, ScanNPCs)
RegisterKeyBind(Key.F2, GlobalInfight)
RegisterKeyBind(Key.F3, DuelNearest)
RegisterKeyBind(Key.F4, ResetTeams)
RegisterKeyBind(Key.F5, CycleSlowMo)
RegisterKeyBind(Key.F6, ToggleFreeCam)

-- ---------- V2 仇恨矩阵（可选） ----------

if Config.EnableHatred then
    Hatred.TryInstallHook(log)
end

log("loaded ✓")
