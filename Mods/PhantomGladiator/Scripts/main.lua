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
    -- 兜底：UEHelpers 拿不到时，遍历 PlayerController 找第一个有 Pawn 的
    local ok2, found = pcall(FindAllOf, "PlayerController")
    if ok2 and found then
        for _, pc in ipairs(found) do
            local okP, p = pcall(function()
                return pc:IsValid() and pc.Pawn or nil
            end)
            if okP and p and p:IsValid() then return p end
        end
    end
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
        -- 游戏可能同时存在多个世界实例（主世界/菜单/流送），对全部生效
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

-- ---------- F6: 自由镜头（调试相机） ----------

-- 退出自由镜头。Shipping 版的 DebugCameraController 没有自己的 CheatManager
-- （被编译剔除），而原生退出流程恰恰依赖它：现场构造一个再调 DisableDebugCamera，
-- 引擎就会走正规的控制权交还。实测有效 (2026-10-29)。
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

local function ToggleFreeCam()
    ExecuteInGameThread(function()
        -- 智能开关：调试相机激活中 → 退出；否则 → 进入
        local dcc = FindFirstOf("DebugCameraController")
        if dcc and dcc:IsValid() and pcall(function()
            return dcc.Player and dcc.Player:IsValid()
        end) and dcc.Player and dcc.Player:IsValid() then
            local ok, err = pcall(ExitFreeCam, dcc)
            log(ok and "自由镜头：已退出" or ("退出失败: " .. tostring(err)))
            return
        end
        local ok = pcall(function()
            local cheat = FindFirstOf("CheatManager")
            if not cheat or not cheat:IsValid() then error("no CheatManager") end
            cheat:ToggleDebugCamera()
        end)
        log(ok and "自由镜头：已进入（WASD 移动，再按 F6 退出）"
               or "自由镜头进入失败（CheatManager 不可用）")
    end)
end

-- ---------- 按键注册 ----------

-- F7: 强制退出自由镜头。只退不进：对所有 CheatManager 调 DisableDebugCamera，
-- 无论当前哪个控制器掌权都能回到玩家视角
local function ForceExitFreeCam()
    ExecuteInGameThread(function()
        local dcc = FindFirstOf("DebugCameraController")
        if not dcc or not dcc:IsValid() then
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

RegisterKeyBind(Key.F1, ScanNPCs)
RegisterKeyBind(Key.F2, GlobalInfight)
RegisterKeyBind(Key.F3, DuelNearest)
RegisterKeyBind(Key.F4, ResetTeams)
RegisterKeyBind(Key.F5, CycleSlowMo)
RegisterKeyBind(Key.F6, ToggleFreeCam)
RegisterKeyBind(Key.F7, ForceExitFreeCam)

-- ---------- V2 仇恨矩阵（可选） ----------

if Config.EnableHatred then
    Hatred.TryInstallHook(log)
end

log("loaded ✓")
