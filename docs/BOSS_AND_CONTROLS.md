# BOSS、快捷键与 F6 对照记录

> 后续：用户确认 F2 正常、v0.24.1 F6 修正无效。v0.25已改用独立观察相机，并移除召唤前的数秒全量扫描；部署待测，详见 [FREE_CAMERA_AND_SPAWN.md](FREE_CAMERA_AND_SPAWN.md)。下文保留此前实验过程。

更新：2026-10-31。v0.24.1-team-bones 已于 04:50:51 实机加载，30 个 Lua 文件哈希一致。F2 已有真实切换回执和网页同步；F6 同场对照正在进行。不能将部署或离线通过当作 F6 已修复。

## 已确认的结果

- 用户确认普通 NPC 和两只 BOSS 能互斗。碧海残躯（蓝，初始 8000 HP）与毕远残躯（红，初始 10000 HP）的日志都有连续掉血直到 0；未用伤害 hook 逐笔归因。
- v0.23 用原生 `GA_SummonPassive_C.SpawnedSummonInstances` 和技能的 Avatar 识别召唤主从，只收 `bPawnPending=false` 的有效 NPC、同世界和唯一归属。已读回碧海的两个 Stand，以及沐小葵 P2 的 Yuu_Stand/TieGui_Stand；继承队伍、同队友好、敌队敌对，并请求攻击。该证据不等于任意召唤技能的行为全通过。
- v0.23 的 BOSS 血条失败：注册了控件，但 `Character` 未关联，姓名与 HP 不更新。v0.23.1 显式关联、调用 `Init(actor)`，以真实 `Health/Health_Max` 更新，并读回 `hpbar.CurPercent` 和姓名。用户确认“名字、血量和清理都正常”。
- 清理失败原因之一：Actor 原生已失效，UE4SS 包装器 `IsValid()` 仍真。v0.23.1 调用精确的 `KismetSystemLibrary:IsValid` UFunction，未知读回仍保留记录；原生失效才移除。旧空血条由 F4 清除，不移除其他有效 Actor 的血条。
- v0.24 卡片快捷键已实机通过，用户确认“能通过绑定的键召唤”。默认未绑定；按 Esc 取消捕获，× 解除；保留用户设置。共用当前队伍和数量，不自动开战。

## F6 尚未修好

用户在同场战斗中用 F6 进入、再次 F6 退出，反复观察到自由视角攻击频率与掉血明显下降；最新补充杀气条也掉得很慢。

原相机通过 `CheatManager.ToggleDebugCamera` / `DisableDebugCamera` 进出。v0.24 只给已登记 NPC 关闭距离优化，`GetOptimizationWave()==1` 是 NoOptimization，0 才是 Invisible。用户实测这版无改善。

04:12:37 与 04:13:19 进入 F6 时，两名参赛者均读回 wave=1、mesh_tick=0、anim_visibility=1。所以“关闭距离优化即可解决”已被当前样本否定；不要重复相同修改并宣称修好。

| 日志区间 | 观察模式 | 蓝队净失血 | 红队净失血 | 解释 |
| --- | --- | ---: | ---: | --- |
| 04:12:40–04:13:00 | F6 | 0 | 0 | 10 次连续战况采样保持 HP=8693.75/8790.0，不只是没有打印变化事件 |
| 04:13:05–04:13:15 | 普通 | 84 | 682.5 | 恢复真实掉血；不是逐招伤害系数测量 |
| 04:13:25–04:13:45 | F6 | 未记录变化 | 未记录变化 | 此区间没有连续战况采样，不把“无变化日志”独立当作零伤害证据 |
| 04:14:15–04:14:35 | 普通 | 1286.25 | 476 | 同一对参与者继续掉血 |

第一段连续 HP 证据排除了“这一段仅仅血条显示慢”。原日志没记录 Shachi，不能据此证明杀气变化量或单次伤害减小。

F6 中攻击配置仍出现实际攻击实例，`IsValidTarget(opponent)` 仍为 true。正常与 F6 均出现 IgnoredActors 含双方，不能仅凭这一字段重新启用旧碰撞通道实验。F6 的 `playerAddress=UNKNOWN`，退出后恢复实际地址；当前玩家查找要求非调试控制器持有 UPlayer，存在自由视角丢失玩家引用的线索。它是否导致原生 NPC 伤害异常尚未证实，不能与伤害根因画等号。

本轮按优先级核对三项预测：

1. 完整骨骼刷新：若碰撞所需骨骼受渲染更新限制，固定 `VisibilityBasedAnimTickOption=0` 后 F6 应恢复命中/掉血。官方枚举 1 为 AlwaysTickPose，骨骼只在渲染时刷新；0 为 AlwaysTickPoseAndRefreshBones。与本地 5.7 导出一致：[Epic 5.7 说明](https://dev.epicgames.com/documentation/en-us/unreal-engine/python-api/class/VisibilityBasedAnimTickOption?application_version=5.7)。这只是候选原因。
2. 调试相机导致玩家/AI 上下文变化：如果完整骨骼刷新仍失败，但 `mod_player=nil`、原调试控制器的 `OriginalControllerRef.Pawn` 仍有效，需要进一步隔离控制器依赖。不得直接把所有玩家查找都替换为任意 Pawn。
3. 时间/属性或受击资格变化：同场前后只读 WorldSettings 时间倍率、Actor.CustomTimeDilation、Health、Shachi、Attack、ShachiAttack、bCanBeDamaged、AI.CurrentStateTag；有差异再追对应路径，不补造伤害。

v0.24.1 只增加第 1 项属性写入，限本 Mod 管理的 NPC 和确实归属该 Actor 的 Mesh，每 Actor 最多 3 次，漂移按实际状态报告。没有修改 URO、Tick 间隔、镜头操作或伤害值。`arena_bone_refresh_count` 仅表示属性读回成功，不表示实机效果通过。新增 `[F6Readback]` 每约 5 秒或相机切换时只读采样，每 Actor 最多 120 次，仍不启用 CombatProbe hooks。

## F2 切队

v0.24.1 增加 F2：蓝 → 红 → 暂不配队 → 蓝。只切换下次召唤队伍，单位、数量以及场上已有成员均不变，不生成对象。F9 与卡片绑定键都用这份选择。

回调进入游戏线程，卸载后取消；实际 `IsKeyBindRegistered(F2)` 读回成功才报告 `key_cycle_team=F2`。`arena_team_revision` 推动网页下拉框同步，不触发一条反向选择命令。F2 从四个全局动作的改键选项移除，避免覆盖。04:51:08–04:51:18 已有 6 次真实切换回执，网页随后显示蓝队，与原生状态一致；场上仍是 0。截图保存在本轮备份的 `panel-f2.png`。

04:53:20 新生成阿花的 visibility 实际从 1 变 0；只读采样返回 HP9000、Shachi800、Attack70、ShachiAttack33、world/cinematic/actor 时间倍率均 1、AI.State.Idle。这里只证明配置和观察生效，等待 F6 中的战斗结果。

## 验证和部署

- 本轮：Arena 切队不改存量成员、下一次生成沿用队伍；runtime 18 项（含 F2 注册读回与卸载）；骨骼策略仅修改一个字段、次数上限、失效/异主对象保护；真实 main 的 NPC/通用 Actor 隔离启动；单位键持久化/冲突；JS 语法、单位键、召唤 UI、目录回归通过。
- 最后的只读诊断补充再次通过 activity 和 main NPC 启动检查。没有把 mock 说成引擎行为实测。
- 与部署前 v0.24 比较，5 个相机/玩家查找函数体逐字不变。与最早 Git HEAD 比较，两个函数此前增加过有效性保护，不能声称整个历史从未修改。
- 备份：`D:\Claude CODE\影之刃0-backups\v0241-team-bones-20261031-044938`，包含部署前 Lua、日志和 30 文件部署清单。用户单位键文件部署前后 SHA-256 相同。
- 以前的 v0.23.1 验收证据在 `影之刃0-backups\boss-summons-hud\v0231-confirmed`；v0.24 在 `影之刃0-backups\v024-keys-activity`。
- 本次没改 Python 后台，不需重启面板服务。游戏由用户点 Restart All Mods；请求前已核对 owned/三队均 0、F8 false、待恢复关系/标志均 0。

玩家杀气锁定、自动精准防御、红光自动 Shift、第一人称仍只有讨论，未实现。BOSS 投技只核对到 NonPlayerGE 和成对施技/受技能力，未改变抓取行为，不能保证跨骨架通用。
