# 当前任务：NPC 红光投技

> **已完成本轮验收：v0.26.2-native-grabs。** 用户重新测试后明确确认可行、双方完整配套动作、结束后继续打。魔渊5项/阿花1项资源清空与恢复均有原生读回，花千笑/乱狮3项当前启用。整理后的交接见 [NPC_GRABS.md](NPC_GRABS.md)。当前仍有蓝红各1且F8开启，勿擅自清场或重载。下文保留成功与失败过程，不要把旧“未实现/待测试”当作当前结论。

2026-10-31 用户已明确授权实现。目标是**BOSS现有红光技能真实命中NPC后，触发施技/受技的完整成对动画、伤害与结束恢复**。普通红光伤害型不需要改成抓取；手动新加一招或单独播动画不算完成。被抓NPC应暂停自己的行动，结束恢复AI，玩家仍可观战。

## 已完成的附带界面修改

- 用户确认GuaiMian叫“怪面”；`panel/catalog_labels.py`已改成怪面类。运行中旧Python服务不重启，前端loadCatalogue兼容转换旧标签，卡片/详情/搜索已显示怪面类。
- 用户要求重复绑定显示占用者：前端刷新绑定信息后检查主键，显示单位中文名与实际组合键；功能键显示具体功能。已在浏览器把暴徒尝试绑定4，得到“4的主键已被鬼差队长：火流星占用”，没有提交覆盖绑定。截图`影之刃0-backups/term-key-conflict-20261031.png`，已向用户展示。
- Lua unit_keybinds也改为在拒绝信息给出占用类名，随下一次Mod重载生效。JS和隔离Lua回归通过。不要为这些界面改动再重启Python后台。

## 当前游戏基础

此前v0.25.1已由用户验收F6、召唤速度、观察时动作输入阻挡与退出恢复，保持这些能力。CombatProbe hooks继续关闭。没有创建子代理/goal，未提交/推送。

## 投技已核对的数据

- 完整注册表`Runtime/asset-index.tsv`有147个直接派生自GA_ExecutionAbilityBase_Grab或GA_ExecutedAbilityBase_Grab的能力类；不是147个可用NPC配对。
- 原生普通持刀暴徒有明确ToNpc成对资源，父类分别为施技/受技Grab基类：
  - `/PBZCombatAsset/ActorData/Mobs/003_MaleThug/Ability/Weapon_Sword/Abilities/LevelShow/GA_MaleThug_Sword_Gex_ToNpc_01.GA_MaleThug_Sword_Gex_ToNpc_01_C`
  - 同目录`GA_MaleThug_Sword_Ged_ToNpc_01.GA_MaleThug_Sword_Ged_ToNpc_01_C`
  这些仅用于验证原生配对流程，不能替代最终BOSS现有红光命中触发。
- 抓取事件类：`/SGameExecution/Bullet/Events/BP_BulletEvent_Grab.BP_BulletEvent_Grab_C`，函数`:Trigger(SourceBullet interface, FBulletEventData)`；EventData.EventActor是命中对象。字段包括Only Grab Ability Target、WaitEventToSuccess、Deactivate Bullet、Jump Point、Success Timeline、Executed Ability、Target Required/Ignored Tags、NonPlayerGE。
- NonPlayerGE很可能涉及NPC普通伤害分支，但**尚未证实具体分支**；不要盲目清空共享资产字段或直接宣称它就是开关。
- `SGameExecution.hpp`: UExecutionComponent.PlayExactExecution(FExecutionAnimData,AActor*,float)，FExecutionAnimData含ExecutionAbility/ExecutedAbility/SourceObject。CurrentExecutionInfo有弱引用Executor/Target、StartTime、IsTarget、双方SpecHandle。
- BP_RenewalNPC具有`Execution Component`（UPBZExecutionComponent）和GetExecutionComponent接口。AActor.GetComponentByClass也可查，必须核对Owner。
- Grab施技基类有GrabSuccess和PlayGrabTimeline；施技/受技基类的K2_OnEndAbility负责碰撞、无敌等恢复。GameplayAbilities.hpp确认K2_EndAbility/K2_CancelAbility/GetAvatarActorFromActorInfo。
- ULegoAbilityBlueprintGeneratedClass.AbilityTimelines为TArray<ULGATimeline*>；后者有SequenceLength、bAutoPlay、bLooping、bStopAbility等。不要猜空FLGAActionEvent的未导出字段。

## 进行中的只读核对

`v0.26-grab-study`已部署32Lua并由用户重载，05:41:57读取完成177行，Runtime/grab-study.tsv。每个就绪tick只读一个已核对资源类，记录CDO字段/时间线、特定UFunction地址与flags，最后最多24个已加载Grab事件实例配置；未触发能力、未生成Actor、未改NonPlayerGE、未安装hooks。

## 已证实的原生分支（下一步直接实现，不要重复只读实验）

- 新工具`tools/read_grab_bytecode.py`只用OpenProcess(VM_READ|QUERY_LIMITED_INFORMATION)，验证进程完整路径与新报告FunctionFlags，按已核对的UStruct.Script=0xb0读取四个特定函数Script；双读一致，不写内存。当前游戏PID9756，启动器PID32536不是目标。
- 证据目录`D:\Claude CODE\影之刃0-backups\v026-grab-study-20261031-054138\bytecode`。原生Trigger3495字节，SHA256=`9ea917ab707025d36f3f7c33b0286151b3958b42b6fe74f0894d76f1d7066e23`。不要提交这些游戏字节码。
- 入口offset34的EX_JumpIfNot：NonPlayerGE类无效则跳100（完整抓取流程）。类有效时计算EventData.EventActor是否玩家；offset86的EX_JumpIfNot：非玩家则跳342。342–543获取命中者/来源ASC、以NonPlayerGE应用GE，随后PopExecutionFlow到外层结束。原生玩家/NonPlayerGE为空的路径先检查Target Required/Ignored Tags再进入配对流程。EExprToken=0x07/0x4C/0x4D/0x4F/0x68已核对Epic官方枚举。
- 因此不是猜测：**有效NonPlayerGE+非玩家命中会走替代GE；清空该可选字段可进入原有完整流程。** 不改红光识别、不模拟命中、不改伤害、不改字节码、不强行播另一个技能。
- 实机普通暴徒ToNpc事件NonPlayerGE是无效UClass（空）；其Executor/Receiver时间线6.2667秒、GrabSuccess4.2秒，非循环且bStopAbility=true。多种BOSS事件为`/PBZCombatAsset/Prototypes/GameplayEffects/Inflictions/GE_GrabHit.GE_GrabHit_C`。
- 已读到的BOSS事件包括GuiChai_Red GEx01、阿花CA01GEx、双钩黄色鬼差GEx02、骨婉约多个GEx/Grab。对应Executed Ability均是真实GEd类。玩家事件在`/ActorData/Players/`下，不应修改。

## 已部署首个功能测试版 v0.26.1-native-grabs

新增`arena_grabs.lua`，已部署33Lua，hash一致，备份`D:\Claude CODE\影之刃0-backups\v0261-native-grabs-20261031-060009`。投技策略只对正在交战的参赛NPC资源族中，原本NonPlayerGE=已确认GE_GrabHit的Grab事件清空替代字段。写前保存Runtime/npc-grab-policy.tsv，写后读回空UClass；F4/停止/下次重载恢复原类。原目标Required/Ignored Tags、Executed Ability、命中与伤害流程都没改。没有hooks，没有字节码修改，没有人为启动投技/扣血。

这是**共享事件资源**：按参赛class_path的ActorData/Mobs族目录匹配，同族原生NPC也可能引用同一资源，不能宣称字段属于单个Actor。只改已证实的GE_GrabHit，其他替代GE与玩家资源不动。仅蓝红有活参赛者且battleActive时启用；名单变化先恢复旧族再重新应用；停止/一方无存活时恢复。每5秒扫描一次新加载的Grab事件，非每帧；最多512条。已经为空的ToNpc事件不写入。失败快照不修改，失败写入最多3次。

Arena.start新增prepareBattle，在关系/攻击指令前完成投技准备；prepare失败不发战斗指令。main restore同时执行资源恢复和原battle.reset。Support读取Execution Component.CurrentExecutionInfo与ASC.ActivatableAbilities.Items.ActiveCount，记录真实配对进入/退出；尚不知道原生Grab会否把信息写入组件（也可能仅写到能力实例）。若画面已配对而计数0，不能说没生效，需要再读能力实例的`Execution Info`。当前没有自动取消/强行改碰撞，依赖原生K2_OnEndAbility清理；F4可清理本Mod参赛对象。

Config.EnableNPCGrabs=true；EnableGrabStudy=false（不再自动重复只读读取）。策略8项回归、Arena流程、runtime18项和main隔离加载通过。尚无实际NPC投技验收。已请用户重载、F8开启，蓝双钩“鬼差高手：勾魂”、红陌刀“鬼差高手：斩骑”各1，开始交战，观察真实抓取红光命中后的成套动画、掉血、结束后AI恢复；最后F4核对资源恢复。部署前owned0/F8false/freecamfalse/pending0。

面板已筛到死镇/BOSS/搜索“鬼差高手”，仅这两张卡；没有替用户召唤/开战。截图`v0261-native-grabs-20261031-060009/panel-grab-pair.png`已在commentary展示。IAB浏览器2、tab1、变量keyPanel可继续使用；此前调试用CDP Runtime/Network/Log均已关闭。

## v0.26.1失败与v0.26.2当前接续点

v0.26.1于06:02:05加载，用户已开始双钩/陌刀对战。06:03:44/49/54共3次NonPlayerGE写入验证均false，原值仍是GE_GrabHit，npc_grab_events=0；因此投技根本没启用，不能拿此轮画面评价动画兼容。原日志没有记录setter错误字符串，只能确认Lua nil写法未生效，不虚构具体报错。

**已部署v0.26.2-native-grabs，33Lua hash一致**，备份`D:\Claude CODE\影之刃0-backups\v0262-native-grabs-20261031-060707`。改为从有效BP_BulletEvent_Grab类CDO读取其原生空UClass值（已实测默认字段为无效UClass），确认type=UClass且IsValid=false，作为可空类属性值复制到事件；不对空UClass调用任何解引用方法。只访问有效接收事件。现在日志包含called/read/after/verified及setter错误。新增模拟ClassProperty拒绝Lua nil的边界，在旧写法下失败，新写法8项通过；main隔离加载通过。

已请求用户：关F8、F4清理、重载，再同组测试；截至最后一次读取游戏**仍v0.26.1、两名参赛者、F8开启、grabs0**。不要声称新写法已实机通过。接下来先确认v0.26.2加载、native_empty_class赋值verified=true，再看原生配对/动画/恢复。若写入仍失败，日志现有具体错误可用；不要无依据换方向，更不要直接写进程内存。只读内存工具没做任何写入。

相关schema已核对：BP_RenewalNPC的`Execution Component`是UPBZExecutionComponent；组件有AbilitySystem/CurrentExecutionInfo。FGameplayAbilitySpec的Handle.Handle、ActiveCount、NonReplicatedInstances/ReplicatedInstances均已导出。弱引用可能直接变UObject或WeakObjectPtr.Get()，先核对类型，未知不当成功。目标应先用现有双钩鬼差/陌刀鬼差人形配对，最后仍需用户看到BOSS原红光命中后的整段动作及恢复，不能只以字段清空判定成功。

用户只能自己操作游戏，助手不可按键/召唤/开战。浏览器可操作筛选和验证绑定拒绝，但不点生成/战斗按钮。旧后台重启被自动审批阻止的历史仍有效，勿换工具绕过。
