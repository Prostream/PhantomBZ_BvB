-- PhantomGladiator 配置
-- ============================================================
-- 这里集中了所有"游戏特定"的名字。发售后用 UE4SS 的 Object Dumper
-- 和 Live View 找到真实类名/属性名后，只需要改这个文件。
-- 填法见 README「发售日适配指南」。
-- ============================================================

local Config = {}

-- 敌人搜索：FindAllOf 会按这些类名找 Pawn。
-- "Character" 是引擎基类，保证能扫到所有角色（含玩家，稍后按关键词排除）。
-- TODO(解包后): 换成真实敌人基类，例如 "BP_EnemyBase_C"，可大幅减少误伤。
Config.EnemyClasses = { "Character" }

-- 类名里含有这些关键词的 Pawn 视为玩家/友方，永不参与斗蛐蛐
Config.ExcludeClassKeywords = { "Player", "Hero", "Soul", "Protagonist",
    -- 影之刃零: 主角"魂"的 Blueprint 类 (实测 2026-10-29)
    "Renewal_Hun" }

-- 阵营写入策略（按顺序尝试，成功即停）：
-- 1) 在 Pawn / Controller 上找这些属性名直接写值
Config.TeamPropertyCandidates = { "GenericTeamId", "TeamId", "TeamID", "Team", "FactionId" }
-- 2) 在 Pawn / Controller 上找这些函数名调用
Config.TeamFunctionCandidates = { "SetGenericTeamId", "SetTeamId", "SetTeam", "SetFaction" }

-- 全局互殴时把敌人分成几个阵营（2 = 捉对厮杀，更大 = 混战）
Config.TeamCount = 2
-- 写入的阵营 ID 从这个值开始（避开游戏自己常用的 0/1/255）
Config.TeamIdBase = 50
-- 重置时写回的阵营 ID。TODO(解包后): 用 Live View 看敌人原始值后修改
Config.DefaultTeamId = 1

-- 按键映射（改这里换键位；键名见 UE4SS 的 Key 枚举，如 "F1"、"NUM_ONE"、"K"）
-- Summon 键加 Shift = 切换要召唤的怪
Config.Keybinds = {
    Scan = "F1",          -- 扫描场上 NPC（同时登记进召唤图鉴）
    Infight = "F2",       -- 全场互殴
    Duel = "F3",          -- 决斗：最近两个 NPC 互杀（自动种仇恨）
    Reset = "F4",         -- 恢复所有被改过的阵营
    SlowMo = "F5",        -- 慢动作档位
    FreeCam = "F6",       -- 自由镜头开/关
    ForceExitCam = "F7",  -- 强制退出自由镜头
    PlayerNeutral = "F8", -- 玩家中立化开关（怪物无视你）
    Summon = "F9",        -- 在面前召唤选中的怪
}

-- 玩家中立化写入的阵营 ID（FGenericTeamId::NoTeam = 255）
Config.NeutralTeamId = 255

-- 召唤位置：玩家前方多少厘米、抬高多少厘米
Config.SummonDistance = 400
Config.SummonHeightOffset = 50

-- 种仇恨的点火伤害（互相打一下，触发 AI 的受击感知）
Config.SeedDamage = 1.0

-- 慢动作档位（循环切换）
Config.TimeDilationSteps = { 1.0, 0.5, 0.2, 0.05 }

-- V2 仇恨矩阵（实验性，默认关）。
-- 开启后尝试 hook 下面的伤害事件来累积仇恨值。
Config.EnableHatred = false
Config.DamageHookFunction = "/Script/Engine.Actor:ReceiveAnyDamage"
Config.HatredThreshold = 30.0   -- 仇恨超过该值视为"结仇"
Config.HatredDecayPerSecond = 1.0

return Config
