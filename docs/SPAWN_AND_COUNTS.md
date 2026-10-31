# v0.22：全部目录、无限总量、未配队管理

用户最终要求：总量不设上限；暂不配队独立显示数量并单独清理；所有目录单位开放召唤。已按此实现。每批仍1–8只，总量和单一类别总数不再由Mod限制。

## 部署与实测

- 24个Lua与游戏目录逐文件SHA-256相同；00:46:24日志加载`v0.22-open-catalog`，状态`spawn_mode=all_catalog`、`arena_max_units=0`。
- 面板新进程PID39592，实际API866条全部允许尝试、每次最大8、目录错误0。保留章节、地图、小怪/BOSS卡片布局。
- v0.21首次长枪暴徒：00:14:58读回UClass/NPC继承/精确路径、生成1/1、ControllerAI=true、HP400；用户确认出现并行动。随后HP归零，用户称亲自击杀；尚未验收该类的NPC互斗。
- v0.22命令id72一次生成3只未配队长枪暴徒，生成3/3、初始化3。00:49:48、00:50:00、00:50:08分别读回HP0和alive=false，用户确认死亡计数和清理正常。
- 命令id73的`clear_neutral`收到成功ACK；执行时实体已自然清空，日志确认0、待确认0。这验证新命令贯通，但不是实际销毁非空neutral组的证据。最后状态蓝红/未配队0、owned0、死亡待清理0、F8关闭。

## 死亡计数与未配队清理

旧计数只看UObject有效性，死亡后尸体继续有效，因此等待销毁才扣人数。新`alive_readback`在有效性及销毁状态检查后读取HP：正值计入存活、零/负值退出、读取失败单列未知。回血/换阶段后重新计入。死亡记录仍保留供清理，不把存活0冒充所有权0。

非战斗Actor没有PBZ血量，按有效实例计数，不猜血量或反复全局扫描属性集。游戏桥250ms更新，网页轮询从1800ms改500ms；这些是周期设置，不是任意负载下的延迟保证。

右侧新增未配队存活数、登记数与“仅清理未配队单位”。`clear_neutral`贯通后端、文件桥、Lua处理器、Arena；仅处理本Mod持有的neutral记录，不调用全局战斗restore、不停止蓝红会话、不销毁原生NPC。销毁后仍读回IsValid/IsActorBeingDestroyed；未确认条目保留。F4继续清理本Mod全部召唤实体。

## 全部开放与原生边界

`panel/unit_validation.json`显式设置`allow_all_catalog=true`。后端为当前目录成员返回`experimental_spawn`和最大8；不伪标已验证。仍校验目录成员、字段格式、游戏会话与数量。已知非单位资源不加入单位目录；已显示的模板/特殊/用途候选可以尝试，具体失败原因直接返回。

Lua取消白名单拒绝，只接受合法具体生成类路径。加载后必须是有效UClass、路径吻合、继承Actor；非Actor不能生成为场景实体。NPC沿用SpawnAIDefered→所有权登记→FinishSpawnAIDefered→原生ActivateAI。非NPC使用GameplayStatics.BeginDeferredActorSpawnFromClass→登记→FinishSpawningActor，不调用PBZ战斗AI。无战斗AI和正HP的实体不能被当作战斗NPC下达攻击。

通用接口先查本地Engine.hpp/Engine_enums.hpp，再核对[UE4SS UWorld](https://docs.ue4ss.com/dev/lua-api/classes/uworld.html)和[Epic GameplayStatics](https://dev.epicgames.com/documentation/unreal-engine/API/Runtime/Engine/UGameplayStatics)。通用Actor调用链仅完成隔离mock检查，真实非NPC样本仍待验证。生成结果未知仍停止该批，不自动重放。

火焰犬也按最新“全部开放”的指令允许尝试；这不代表过去崩溃关联已经排除。机灵鬼仍保留特殊机制分类，开放请求不会改变它天生穿透/无敌的机制。

## 检查与证据

后端46项、目录16项、文件桥19项、运行时16项、Arena、spawn_policy、spawn_outcomes、真实main的NPC/Actor两条隔离加载路径、前端许可和分类回归通过。新增回归覆盖HP0立即扣数/保留清理/回血恢复、32只越过旧24总量、未配队清理保留32只蓝队且不调用全局restore。离线32只不是实机压力测试。

相机和玩家查找5个函数与上一检查点逐段相同，CombatProbe保持关闭。证据在`D:\Claude CODE\影之刃0-backups\v021-spawn-trials`和`v022-open-catalog`。

服务重启动作被自动审批拒绝；用户明确授权后仍被拒绝，只有blocked by policy文本。没有换工具绕过，最终用户亲自运行身份核对脚本完成更新。`panel/Restart-Panel.ps1`只处理命令行匹配本项目backend.py、且没有在途命令的端口进程，不操作游戏进程。
