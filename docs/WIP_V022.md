# v0.22施工历史记录

**本文件下方是施工过程的旧计划，现已完成部署。当前结论以docs/HANDOFF.md顶部和SPAWN_AND_COUNTS.md为准，不再将下面的待办当作当前状态。**

最新用户要求：总量不设上限；暂不配队单列数量与单独清理；所有目录单位开放尝试召唤。此前用户还报告死亡后计数很慢，必须一起完成。自由视角不动，只有用户能操作游戏。

## 已运行状态

- v0.21-single-spawn-trials 已实机加载，00:11:22读回175条原生图鉴试召唤许可（100小怪、75BOSS）；配置动态更新，后端仍PID36996，无需服务重启。
- 用户00:14:57通过面板生成长枪暴徒（Spear_Blue），日志生成1/1、ControllerAI=true、HP400，用户确认出现且会行动。00:15:20该怪HP0。用户又生成未配队一只，00:15:39 HP0，00:15:45 F4仍valid且未进入销毁，故数量滞后有实证。
- 源码/证据备份：`D:\Claude CODE\影之刃0-backups\v021-spawn-trials`，prepared含175许可manifest；deployed-before为v0.20.2的24Lua；deployment.json为v0.21部署hash；evidence-spear有游戏日志、status、spawn-attempts。
- panel/unit_validation.json当前61090字节左右，177路径（Sword、Vessel、175试召唤），Spear追加spawn_observed=true，但仍controlled_test。API受64KiB限制。
- 面板浏览器当前绑定spawnPanel，IAB2/tab1，搜索长枪暴徒，已保存panel-enabled.png。每跨用户轮次常报browser.user unavailable，cua_repl reset后getTab('1',{browser:'2'})恢复。只操作网页筛选/刷新，不点击生成/F8/F4等游戏按钮。

## 未部署源码变更（v0.21.1草稿，需继续改为v0.22）

- arena_controller.lua新增alive_readback：按removed检查和HP>0计算存活数；死者保留owned_records供清理，返回dead_count、unreadable_count、max_units；日志存活变化。start跳过HP0但目前对所有队伍先读alive，需修正：非战斗的neutral不能阻挡开战。
- main.lua BUILD暂为v0.21.1-live-counts，maxUnits暂24（最新要求改0代表无限）；panel_runtime已输出arena_owned_records/dead_count/unreadable_count/max_units。
- spawn_policy暂给Sword/Spear 8/24，其他试召1/2；最新用户明确全部开放，因此需替换为规范类路径检查+运行时真实Actor验证，不再白名单锁定（包含以前隔离的火狗，仍可显示历史提示）。
- 新死亡计数回归先失败后通过，Spear/Sword容量草稿也通过纯Lua，但未部署。前端仍写总2，尚未改容量/neutral区/快速轮询。

## 接下来的实现

1. Arena maxUnits=0无限；next_slot不能for 1..24，改根据已管理记录寻找空位。每批仍1–8（用户只要求总量无限）。增加clearNeutral只清理自有neutral，保留蓝红与战斗状态，不调用全局restore。死亡不当作清理完成。
2. 桥接新增clear_neutral action：backend.ACTIONS、Lua panel_bridge.ACTIONS、panel_runtime.handlers；不加改键项。前端neutral独立卡片，计数/清理；蓝红标存活、死者清理提示；网页轮询1800ms→500ms。
3. 所有当前866目录候选开放尝试，状态experimental_spawn，不能伪标verified。backend需去掉NPC/单只白名单的强制禁用，但仍排除已知非单位、要求目录成员+格式+计数。非Actor在原生类验证阶段拒绝并说明。运行后端需要加载新代码：旧一次Stop-Process被自动审批拒绝，原因只给blocked by policy；没有绕过。此前靠配置/静态文件完成。这次先完成代码和验证，再尝试正常受控服务更新；若仍拒绝则解释并请用户明确允许/手动重启面板，不能伪称已上线。
4. NPC照旧走SpawnAIDefered/FinishSpawnAIDefered。非NPC角色需通用Actor延迟生成，先登记所有权再Finish，别把玩家/演出类传PBZ ActivateAI。Catalog.new增加allowActors=true可选，默认保留旧NPC测试；验证Actor继承、记录entry.isNPC。MAX_ENTRIES512也需适应866条（如4096）。
5. 通用接口已核对本地Engine.hpp：UGameplayStatics BeginDeferredActorSpawnFromClass(World,Class,Transform,collision,Owner,scale)和FinishSpawningActor(Actor,Transform,scale)。枚举Engine_enums.hpp：AlwaysSpawn=1，MultiplyWithRoot=1。Epic官方搜索结果确认二者返回AActor*（本地dump把返回类型写void）。UE4SS UWorld.SpawnActor文档确认就是这两者组合，但为保留所有权顺序，应分开调用。Default__GameplayStatics路径需正常StaticFindObject并IsValid。用actorRoutes表记录NPC/Actor，非NPC不读PBZ属性，不发ActivateAI，初始化只确认实例有效；无血量普通实体按有效实例计数，交战仍要求战斗AI+正HP。
6. 完成后检查已有游戏所有权/F8状态，请用户F4/F8关闭恢复再Reload；助手不能操作游戏。必须保存docs/HANDOFF、REVERSE_ENGINEERING、README和checkpoint（目前v0.21尚未追加到正式docs，别遗忘）。

## 当前测试与工具

- panel后端45项在v0.21许可配置通过；fixtures已固定Sword/Vessel避免生产配置扩展干扰。production policy test现在断言177条，后续全开放需更新对应契约。
- test_spawn_ui.js确认原生policy读回门禁与已实测标签；test_arena_controller新增HP0立即扣存活/保留清理/回血恢复回归通过。
- main_boot要隔离Runtime目录参数（已有backups/v021-spawn-trials/boot-test-runtime），texlua在D:\texlive\2026\bin\windows\texlua.exe。
- 现有main与v0.20.2除版本/SpawnPolicy.loadTrials/容量/状态接线外没有变化，已逐字归一化比较过相机及共享玩家查找。后续也必须保持。
- 不调用子代理、不新建goal、memory无相关命中，无需memory引用。无GitHub发布。

官方来源： https://docs.ue4ss.com/dev/lua-api/classes/uworld.html ， https://dev.epicgames.com/documentation/unreal-engine/API/Runtime/Engine/UGameplayStatics 。只能据此说明接口，不当作本游戏通用角色实测成功。
