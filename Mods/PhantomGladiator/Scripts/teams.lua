-- 阵营写入模块：对一个 Pawn 依次尝试多种策略，返回成功的策略名或 nil
local Config = require("config")

local Teams = {}

-- FGenericTeamId 是个只有一个 uint8 字段 (Id) 的结构体；
-- 有的游戏直接暴露整数属性。两种写法都试。
local function tryWriteProperty(obj, propName, teamId)
    if not obj or not obj:IsValid() then return false end
    -- 结构体写法: obj.GenericTeamId.Id = n
    local ok = pcall(function()
        local prop = obj[propName]
        if prop ~= nil and prop.Id ~= nil then
            prop.Id = teamId
        else
            error("not a struct")
        end
    end)
    if ok then return true end
    -- 整数写法: obj.TeamId = n
    ok = pcall(function() obj[propName] = teamId end)
    return ok
end

local function tryCallFunction(obj, fnName, teamId)
    if not obj or not obj:IsValid() then return false end
    return pcall(function()
        local fn = obj[fnName]
        if fn == nil then error("no such function") end
        obj[fnName](obj, teamId)
    end)
end

local function getController(pawn)
    local ok, controller = pcall(function() return pawn.Controller end)
    if ok and controller and controller:IsValid() then return controller end
    return nil
end

--- 读出 pawn 当前的阵营 ID（用于快照/恢复），读不到返回 nil
function Teams.ReadTeam(pawn)
    local targets = { pawn }
    local controller = getController(pawn)
    if controller then table.insert(targets, controller) end
    for _, obj in ipairs(targets) do
        for _, propName in ipairs(Config.TeamPropertyCandidates) do
            local ok, value = pcall(function()
                local prop = obj[propName]
                if prop == nil then error("no prop") end
                if prop.Id ~= nil then return prop.Id end
                if type(prop) == "number" then return prop end
                error("not readable")
            end)
            if ok and value ~= nil then return value end
        end
    end
    return nil
end

--- 把 pawn（及其 AIController）写入指定阵营。
--- @return string|nil 成功时返回策略描述，便于在日志里确认哪条路通了
function Teams.ApplyTeam(pawn, teamId)
    local targets = { pawn }
    local controller = getController(pawn)
    if controller then table.insert(targets, controller) end

    for _, obj in ipairs(targets) do
        for _, propName in ipairs(Config.TeamPropertyCandidates) do
            if tryWriteProperty(obj, propName, teamId) then
                return string.format("property %s on %s", propName, obj:GetFullName())
            end
        end
    end
    for _, obj in ipairs(targets) do
        for _, fnName in ipairs(Config.TeamFunctionCandidates) do
            if tryCallFunction(obj, fnName, teamId) then
                return string.format("function %s on %s", fnName, obj:GetFullName())
            end
        end
    end
    return nil
end

return Teams
