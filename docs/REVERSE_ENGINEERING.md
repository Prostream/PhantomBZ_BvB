# 《影之刃零》AI 逆向工程笔记

> 更新：2026-10-30，v0.13-diagnostic。用户当前只确认自由视角正常，其他功能均未验收。
> 以下保留 Steam build 26266538、UE 5.7.4 的历史实验记录；日志读回、短暂行为与功能验收分开记录。历史推测不作为已排除路径的依据。

## 本轮纠正与验证边界（先读）

1. **态度 hook 的零计数证据无效。** 旧代码把蓝图 `BlueprintGetTeamAttitudeTowards` 的观察逻辑放在 `RegisterHook` 第三个回调参数。该参数对蓝图路径不受支持，因此“计数为 0”不能证明函数没执行，也不能据此排除标准阵营接口。原失败记录保留，旧排除结论撤销。回调规则见 [UE4SS RegisterHook 文档](https://docs.ue4ss.com/lua-api/global-functions/registerhook.html)。
2. **Actor 阵营敌对不等于攻击模块接受目标。** 本轮核对 `CXXHeaderDump/SGameCombatSystem.hpp:992–1015`：`UBulletAttackModule` 另有 `TargetRequiredTags`、`TargetIgnoredTags`、`FactionCalculator`、`SetAttackerFaction`、`IsValidTarget`、`TryAttack`、`DealDamageToAvatar`。`IBulletAttackDataHolder` 还暴露 `RuntimeUpdateFaction` 和 `GetFactionTarget`。这些是新的静态接口证据，足以撤销“阵营这条线到头了”；尚未证明当前怪物攻击实际走哪一条路径。
3. **撤销 `FireAttackLines` 的二分判断。** 有回调不能直接归因于“检测之后筛选”；零回调也不能证明不走该组件。必须核实 hook 安装、支持的调用路径、参数解包，以及正常原生攻击是否可观测。
4. **撤销可玩保底保证。** 定时随机扣血、猜测蒙太奇与 `Kill(1)` 没有满足真实命中、受击和死亡要求。自建命中仍是未验证的备选，不能承诺“一定能做成”。
5. **旧实验基线存在残留风险。** v0.12 的碰撞复制、仇恨标志/数组等没有完整快照；F4 未取消战况循环，旧循环可能再次写入。热重载清空 Lua 记录，但不会复原对象。首次新对照必须由用户自行回标题重进或重载关卡，重建对象。

本轮代码目标是独立会话/恢复模块与有界只读探针，侵入式 F2/F3/F8/F9 默认由 `EnableBattleExperiments=false` 禁用。F5 仍是未验收实验，但记录快照；F6/F7 保留。F4 先取消并使已排队回调失效，再恢复当前 Lua 账本；只有看见日志恢复完成后才热重载。失败记录保留重试，不能追溯旧版无快照改动。

**已运行的本地验证：**`D:\texlive\2026\bin\windows\texlua.exe tests/test_battle_session.lua`，10 项全部通过。覆盖队列取消、跨会话首次快照、逆序恢复、失败重试、读失败不写、写后读回、部分失败恢复、仅恢复指定通道；模块块配对检查也通过。这些是纯 Lua 控制逻辑测试，不是 UE 或游戏通过证据。另已运行 `texlua tools/test_combat_probe.lua`：通过原生/脚本回调位置、native post 返回值插入、错误签名不解引用、对象失效、伤害出参读回、限额、旧计时器、注销失败、卸载静默测试。`texlua tests/test_main_controls.lua` 的 8 项真实 main 控制回归通过：默认门控、F10 游戏线程启停、F4 取消后旧队列不访问对象、慢动作失败读回不报成功、恢复非默认原值及卸载不恢复 UObject。主程序真实 Lua 加载/语法检查通过；`git diff --check` 通过。

**部署回执（2026-10-30 01:50，UTC+8）：**6 个 Lua 文件已复制到游戏的 `ue4ss/Mods/PhantomGladiator/Scripts`，逐文件 SHA-256 与源一致。旧脚本及新文件哈希清单在 `D:\Claude CODE\影之刃0-backups\deployed-before-v013-20261030-015025`。仅表示磁盘部署完成，尚不代表游戏加载或功能验收。

**本轮游戏实验：尚未执行。** 第一轮仅由用户在干净场景按 F11，让原生怪攻击玩家约 20 秒，再按 F11 停止。探针最多 60 秒自动结束。先建立已知正常攻击的观察对照，不召唤、不改阵营。下一条实验记录必须写明版本、画面、安装/事件计数、读回结果与未知项。

**项目状态：**原 GitHub 仓库已按用户要求删除；已读到 GitHub 的 `was successfully deleted` 回执，已登录 CLI API 返回 404。删除前 Git bundle 已校验，位于 `D:\Claude CODE\影之刃0-backups\PhantomGladiator-before-remote-delete-20261030-013816.bundle`。本地代码、历史与诊断工作保留。

## 一、引擎适配（历史记录）

- UE 5.7 特征码缺失：`GameConfig/UE4SS_Signatures/` 两份签名（均在 PBZ.exe 唯一命中）
- S-GAME 魔改了多处核心结构内存布局：`GameConfig/MemberVariableLayout.ini`
  （`TUObjectArray` 字段重排经本仓库独立内存实测与 KintaroModding 交叉验证）
- 日志为加密格式 (`PBZLOGE1`)；pak 加密（默认 key GUID）；无 Denuvo
- 游戏进程 cwd 是 `ProjectPBZ\Binaries\Win64`（Lua io 相对路径以此为准）
- 血的教训：UE4SS 对象空指针链式调用 = 原生崩溃，pcall 拦不住，每步先 IsValid

## 二、AI 架构图（解剖 + 头文件确认）

```
BP_Monster_* (Pawn)                     ← PBZCharacter_NPC ← PBZCharacter
 ├─ "Targeting Component" (UTargetingComponent)   目标选择（玩家锁敌也用它）
 │    ├─ TargetingHandlers[tag → handler]，AI 用 PBZ_TargetingHandler_AI
 │    │    └─ 从黑板键 (Target Key) 读目标，FindTargetsRated 打分
 │    └─ SetLockTarget / FindTarget / Enable/DisableTargetingHandler
 ├─ BP_PBZHatredManagerComponent (原生仇恨组件！)
 │    ├─ HatredList / BeHatredList / PendingBeHatredList
 │    ├─ AddActorToHatredList(Actor, &Succeed) ← 有门禁
 │    └─ CheckActorCanBeHatred / CheckCanHatredTarget ← 门禁本体（疑标签检查）
 └─ Controller: BP_PBZAIController_C ← BP_SGameAIController_C ← SGameAIController
      ├─ SGameAIComponent：StateTree 驱动（不用行为树，Blackboard 挂在这里）
      │    ├─ ForceIntoCombat(TargetActor) / ForceOffCombat
      │    └─ OnTargetPerceptionUpdated（感知事件入口）
      ├─ Team 结构体 + BlueprintSetGenericTeamId/GetTeamAttitudeTowards
      └─ AIPerception（感知敌对名单实测只含玩家）

静态工具库 BP_SGameAIFunctionLibrary：
  ForceIntoCombat / SyncHatredList / AddLooseGameplayTagIfNone /
  SpawnAI / FinishSpawnAIDefered / ActivateAI / GetDefaultSenseConfig
```

## 三、实测结论表（按尝试顺序）

| 路线 | 做法 | 结果 |
| --- | --- | --- |
| 标准阵营 | GenericTeamId 写 Pawn | ❌ 无效果 |
| 标准阵营+ | GenericTeamId 写 Pawn+Controller 双写 | ❌ 无效果 |
| 态度 hook | hook 两个 BlueprintGetTeamAttitudeTowards 改返回值 | 历史计数=0；本轮查明蓝图回调放错参数位置，不能推断函数从未调用 |
| 作战指令 | SGameAIComponent:ForceIntoCombat(对方) | ⚠️ 调用成功，行为无变化（单用时） |
| 黑板直写 | SetValueAsObject(TargetKey, 对方) | ⚠️ 写入成功，被每帧重选覆盖 |
| 官方拉仇恨 | AddActorToHatredList(对方) | ❌ 被门禁静默拒绝（列表无变化） |
| 仇恨数组直写 | HatredList[#+1] = 对方 | ✅ 写入成功且**怪物真的互相攻击了几秒** |
| 玩家除名 | RemoveActorFromHatredList(玩家) | ✅ 调用成功（效果待确认） |

**里程碑观察（2026-10-29 23:26）**：仇恨直写 + ForceIntoCombat + 黑板写入三件套后，
召唤的两只怪**互相攻击了数秒**——但 (1) 互相不掉血；(2) 几秒后目标回弹到玩家。

## 三点五、原生阵营系统（2026-10-30 凌晨历史观察）

用户曾提到游戏里有 NPC 互相打架的场景；具体单位、场景与伤害行为尚未完成对照核实。顺此在头文件中找到：

- `BP_RenewalNPC` / `BP_RenewalPlayer` 上的 `"Faction Component"`（`UFactionComponent`，属性名带空格）
  - `SetFactionRelationOverride(OtherActor, ETeamAttitude, Both)`：对单个对手覆盖敌我关系
  - `GetFactionRelation(OtherActor)` / `GetCurrnetFaction()` / `ClearFactionRelationOverride(OtherActor)`
  - 阵营是 GameplayTag，关系由 `FFactionTableData` 数据表决定；`UFactionUtils.FilterTargetsByFactionRelation` 按关系筛目标
  - `UDeflectComponent`（格挡/闪避）、`BP_DamageInstigatorActor` 等也引用阵营组件
- 官方刷怪：`BP_SGameAIFunctionLibrary` 的 `SpawnAIDefered` + `FinishSpawnAIDefered` + `ActivateAI`

历史记录（v0.12；保留观察，不等于当前功能验收）：

| 项目 | 结果 |
| --- | --- |
| 两只同种怪的原始关系 | 当时读回为**友好**；不是全部“打空气”原因的证明 |
| `SetFactionRelationOverride(对手, 2, true)` | ✅ 生效，读回为敌对，Both 同时设好反方向 |
| 覆盖后 | 双方 `AI.State.Combat`，曾记录互相出招；稳定锁敌与真实攻击尚未验收 |
| 玩家中立：对每只 NPC 覆盖为 1 | ✅ 读回验证 13/13 |
| 官方 `AddActorToHatredList` | ❌ 仍被拒（阵营改为敌对后依旧），门禁另有条件 |
| 互相攻击后掉血 | ❌ 无伤害，画面有"透明特效"，无身体碰撞 |
| 伏击/隐藏/免伤 GE（6 种） | 召唤物身上均**没有**（类 6/6 找到、查询 6/6 成功） |
| 碰撞 | 胶囊与模型均为 3（查询+物理）/Custom 配置，**未被关闭** |
| 改用官方刷怪函数召唤 | 结果相同 |
| `SetFaction` 改到 `Faction.Player` | ✅ 按阵营表天然敌对（覆盖前读到的已是敌对），仍无伤害 |
| 碰撞通道对照（Shift+F3） | 玩家模型对 16/17/18/24/31 有反应、怪物模型全忽略；怪物模型对 14 阻挡、玩家只重叠。玩家另有一个怪物没有的 `Collision` 组件（对象类型 16，仅查询，对 2/14 重叠） |
| 把玩家这些通道反应复制到怪物（`CopyHurtChannels`） | 召唤当时读回验证成功（模型 16/17/18/24/31，胶囊 19/21），**打 75 秒仍满血；用户确认怪和怪身体仍互相穿过**。待查：改动是否在战斗中被游戏还原 |

推翻的旧结论：“S-GAME 在引擎层关闭了 NPC 间碰撞”。所查组件当时的碰撞开关是开的；身体互穿的具体原因尚未被完整证明。

历史猜测：`UDeflectComponent` 含 `PerfectDodgeResultData`，曾怀疑“透明残影 + 无伤”来自完美闪避。没有事件读回证据，不能当成原因；保留待查。
原生 NPC 互打可作后续对照，当前先采正常怪物攻击玩家的只读样本。

## 四、历史候选方向（未验证，不是当前执行清单）

### A：怪打怪不掉血

- `PBZAbilityTargetRuntime` 中的 `IsPlayerInCasterHatredList` 曾使人怀疑某些技能只选玩家，但函数存在不能证明当前攻击走它，也不能推断全局写死玩家。
- `GE_HiddenTagsCanNotBeHatred` 的存在说明标签可能参与门禁；不是“贴一个玩家标签就能修好”的证据。
- 已考虑玩家标签复制、读取 GE 默认标签、hook 门禁及筛选函数。当前先定位原生调用链，未获读回证据前不执行广泛改标签或强行改返回值。

### B：目标回弹玩家

- 历史观察存在短暂出招后目标回弹。无伤害、仇恨列表清理与目标重选之间的因果尚未证实。
- 高频重发 `ForceIntoCombat` 已有打断出招/站桩的失败记录，不再作为“立刻能用”的建议。
- 伤害修复后仇恨是否自行稳定、目标选择函数是否需要干预，均待后续对照。

### 其它待办

- 官方刷怪路径已试过而未解决当前问题；保留接口，不重复把它当作未尝试解法。
- `GetTargetTypes` 出参的 FGameplayTag 读取还没解对（显示 nil），修法同标签枚举
- 阵营快照 ReadTeam 返回结构体代理的取值问题

## v0.13.1 按键冲突修正（2026-10-30）

首轮启动日志在 01:51:33 确认 `v0.13-diagnostic` 已加载；01:51:43 的 ConsoleEnabler 明确输出 `ConsoleKey[2]: F10`。核对已安装 ConsoleEnablerMod/Scripts/main.lua，第 13 行配置 F10。未开始攻击对照前发现冲突，将本 Mod 只读探针改为 **F11**；已安装 Keybinds 仅列出 F11 为可用键，未将其绑定为工具操作。侵入式实验仍默认关闭。该修正需要用户 Restart All Mods，必须读到 v0.13.1 加载后才按 F11 测试。

### 本轮已读到的游戏证据

- 01:51:33：日志 `loaded ✓ v0.13-diagnostic`，仅确认旧诊断版加载。
- 01:53:41 起：只读 `PBZAttitude post` 详细记录包含 `BP_PBZAIController` 与 `BP_Renewal_Hun_C` / 普通怪物目标，`argc=1`；实际脚本回调已被捕获。因此历史“态度 hook 计数 0 所以函数不执行”的排除正式失效。此证据不证明改态度返回值能修好伤害。
- 01:53:54：用户热重载打断采样，卸载日志 `events=1339`、`待恢复0项`。没有完整结束摘要/玩家受伤确认，不能把这段截断样本当作伤害阳性对照。
- 01:55:09：日志 `loaded ✓ v0.13.1-diagnostic` 且按键表包含 `F11=Probe`，确认修正版加载。到最后一次读取，尚无该版本 F11 攻击样本。后续等待用户在普通怪物处按 F11 测试，不能宣称真实伤害已修复。


## v0.13.1 正常受伤对照结果与 v0.14 转向

用户确认 F11 测试期间玩家正常掉血并受击。对应 01:56:58–01:57:29 日志：8 个 hook 均安装成功；TryAttack、IsValidTarget、DealDamageToAvatar、TakeDamage、PlayHitreact、EnableHitTrace 均 pre=0/post=0；PBZAttitude post=2000 后触发事件上限，注销剩余0。玩家起始HP=621.5119，场上原生 Vessel_Child 的HP=1469.4399。原始日志已保存为 `D:\Claude CODE\影之刃0-backups\runtime-v0131-20261030-015749.log`。

结论：这组 native hook 在正常伤害下也未捕获调用，不能用它定位怪物互击失败环节。已确认蓝图态度函数可观测，六个native入口是否经过反射仍未知。用户要求把工作集中在实际斗蛐蛐，后续不再把连续纯受伤诊断作为唯一交付。

v0.14 将 F9 接成“生成两个受管理的参赛者并请求开战”，F3重发这一对的开战请求，F4恢复后仅清理本Mod生成的参赛者。保留原生出招所需的配对数组写入，但只对受管理的两只允许；原生仇恨门禁尚未修好。没有定时扣血、假受击或强制死亡判胜。

同一场决斗自动观测 HP 与实际 `PBZ_SweepTraceBullet` 实例：按 BulletOwnerAvatar 匹配参赛者，读取攻击标签、阵营计算器、SweepTrace模块以及 `IsValidTarget(对手/玩家)` 返回值。此路线不依赖 native hook 是否捕获调用。只读观测，不修改共享 DataAsset；结果仍须运行时验证。动态蓝图回调从实际Class链发现并核实，不猜资源路径。


### v0.14 实现与部署回执

2026-10-30 02:16（UTC+8）完成本地部署：7 个 Lua 文件逐一 SHA-256 比对一致；旧部署和新清单保存在 `D:\Claude CODE\影之刃0-backups\deployed-before-v014-20261030-021644`。四套离线验证均实际通过：battle_session 10项、attack_profile 9项、真实 main 控制回归18项、combat_probe 全套（动态类发现/native ABI/停止/限额等）。main控制回归包含F9只生成一对、重复F9不增加、F3仅配这两只、F4先恢复再仅清理owned、部分生成失败、销毁报错和延迟失效均可重试。不是游戏伤害成功证据。

v0.14 游戏验收仍待用户：Restart All Mods 后F9，在空地观察这两只怪约20秒；必要时F6观战、F3重新配对，F4结束并清理。不要求再做一轮纯玩家挨打对照。核心真实互伤/正常受击/死亡尚未宣称完成。


## v0.15–v0.16 实机进展（2026-10-30）

1. **F9入口失败已定位并改造。** v0.14在02:18:41读回“没有有效怪物类”，没有进入Spawn。旧目录依赖场上实例，空场景/重载时失去选择。v0.15将目录、类解析、擂台、文件命令和面板拆开；从AssetRegistry读取真实GeneratedClass、ParentClass、NativeParentClass，按需只加载所选类，并验证UClass和NPC继承。
2. **已证实空场景按需召唤。** 03:00:06在活NPC=0时，对真实Vessel_Child_C路径LoadAsset返回found=true、loaded=true；随后生成两只蓝队，AI组件有效，HP均400。用户确认出现了。03:33:35再次通过F9生成一只；这是实际读回与画面反馈，不是mock通过。其它类型不能据此一概宣称全部可用。
3. **目录是实际游戏数据，但完整遍历未完成。** v0.15.1读取到19736个cached paths，停滞前partial含708候选；其中混有技能、武器、组件和基类。后端按真实NativeParent精确排除非单位、禁用_Base_C，保留原始TSV作为证据。不是所有候选都可召唤，也未宣称覆盖所有单位。
4. **记录失败：首次目录导出错误。** 初版把可调用table构造器FName误要求为Lua function，返回missing_ue4ss_api。测试用callable table复现后修正；v0.15.1实际开始扫描。该错误属于本Mod接口检查，不能推给用户。
5. **记录失败：持续轮询停滞。** 03:05:06 UE4SS报 `[Lua::Registry::get_function_ref] Ref was not function`，随后状态停在9004/19736。游戏进程仍响应。旧queued标记只有进入回调才清除，丢掉回调即可永久跳过。v0.16按精确dff435dd接口改用稳定的LoopInGameThreadWithDelay，Probe使用ExecuteInGameThreadWithDelay，明确CancelDelayedAction取消；回调返回true不能停止该循环。到03:38新状态持续更新，但不足以宣称底层竞态根因已经解决。旧原始log/status/partial保存在 `D:\Claude CODE\影之刃0-backups\v0151-ref-error-evidence`。
6. **无仇恨双向实测通过（当前场景）。** v0.16于03:33:27加载；开启时玩家CanBeHatredNow从true写false并读回false，新召NPC对玩家从敌对2变为单向中立1。03:35:25关闭，玩家flag读回true、6条有效关系读回敌对2。03:35:35再开，5个NPC的HatredList原有玩家，官方Remove后读回不存在；readFailures=0。用户明确回答“开启后不再追打，关闭后会追打”。这不等于隐身渲染或无敌，也未验证所有剧情/BOSS状态。
7. **清理修正仍待新实机验收。** 旧stop调用Destroy后UObject仍IsValid=true，面板一度报待清理；之后数量归0但旧message滞后。v0.16用已导出的IsActorBeingDestroyed读回并在status时清除过期记录；离线回归包括仍valid但destroying、延迟变化及异常保留。不能用这些测试替代实际清理画面。
8. **核心互伤尚未确认。** 当前等待用户保持F8开启、清理后蓝红各一并开始交战；需要实际攻击、HP变化与正常死亡证据。没有启用定时扣血、猜动画或Kill代替胜负。

用户已明确：独立Windows EXE与界面包装暂缓，优先上述核心功能。`desktop/RuntimeClient.cs`是未完成草稿，不是发布产物；本轮未创建新GitHub仓库或发布。原公开仓库删除已另有成功回执。


## 2026-10-30 暂停前新增证据与防护

- 崩溃窗口已由command journal、SQLite时序与既有minidump交叉核对：id29 FlameDog蓝×1在03:42:10.800发送、未完成；03:42:16.9788637 dump为0xC0000005、PBZ.exe+0x4C89545、read FFFFFFFFFFFFFFFF。此前8实体清理与恢复未确认，不能单独认定FlameDog是根因，也未重现崩溃。
- id30–33实际是重启后下发；其中TwinAxe在玩家未入场时先被加载。这一确认缺口已用游戏就绪前置、会话代次、sidecar和双端执行前校验收紧；不是底层崩溃修复证明。
- v0.17于04:14:19实际加载。原生GetAllEnemyCodexEntries返回table/count177，输出181精确类路径、unknown_rows0、unknown_soft_paths0、conflicts0。全部181有中文，79有BOSS标记（含变体）。Vessel_Child中文字段是“机灵鬼”。真实字段来源是FCodexEnemyRow.Enemy_CH_Hans_Name，不应自行删除其开发备注。
- 当前生成许可仅精确VesselChild路径有生成观察支持。其它条目中文/分类可浏览，但不允许因NPC继承、图鉴身份或名字像敌人而直接生成。
- 本轮验证包括：backend37项、catalog_labels19项、catalog15项、bridge18项、runtime16项、spawn_policy/runtime_session/spawn_audit/codex导出/main boot/arena等离线检查。Codex与audit的gsub多返回值曾导致多一列，已修并加入严格5列回归。暂停时最后新增的父类工作译名集成尚未完成最终验收，不能套用上述通过数。
- 用户要求暂停睡觉；子代理已停止。源码、运行证据和待办保存到暂停交接；未继续生成/测试，未发布GitHub。详见PAUSE_2026-10-30.md。

## 2026-10-30 18:30 恢复：v0.18 生成所有权与只读交战检查

用户明确恢复工作，并自行启动游戏。面板读取到新进程会话、game_ready=true、参赛者0、无仇恨关闭；没有重放旧任务。面板后端在确认队列无 queued/inflight 后恢复，PID 31480。

- 昨晚未收尾的父类工作译名集成已检查：`test_catalog_labels.py` 25项、`test_backend.py` 40项通过，JS语法和diff空白检查通过。当前API目录674项；父类参考名继续标为非官方工作译名，既不继承BOSS身份也不授予生成许可。
- **离线复现一个真实控制缺口**：模拟 C++ 已生成Actor但Lua返回转换抛错时，旧arena仍执行批次后续生成，且把未返回对象当作0只。新增 `test_spawn_outcomes.lua` 首次在“ambiguous native spawn must stop the batch immediately”失败。修复后通过。这是返回异常语义的确定性回归，不是此前FlameDog原生崩溃的根因证明。
- `SpawnAIDefered` 与 `FinishSpawnAIDefered` 分开：有效Actor先进入控制器所有权账本并同步root，再完成初始化；FinishSpawn失败保留对象供F4清理，不在adapter里尝试销毁后丢弃引用，也不继续Activate。
- 原生生成抛错、返回nil/无效/重复对象均停止该批次，不fallback。生成数量报告unknown，不伪装为确定的0。只在明确未调用原生接口时可报告not_started。
- `spawn_guard.lua` 使用ModRef的字符串共享变量，在调用原生生成之前写入并读回保护标记，登记对象之后才确认清除。未知结果跨Mod重载保留；F4只能清理已登记对象，不能据此声称未知对象已清除。未知结果要求用户退出并重启游戏，助手不操作游戏。
- `spawn_inspector.lua` 依据本地ProjectPBZ.hpp读取已生成允许单位的真实CharacterName；只选GetOuter为当前World的唯一PBZSpawnSubsystem，调用GetNPCClassByName并核对返回精确类。没有猜名字，没有调用SpawnAICharacterAtLocation/PostSpawnAICharacter，也没有改角色属性。
- 开战后第1/20/80个250ms采样额外读回双方CanBeHatredNow、两项仇恨检查、当前目标处理器、黑板目标和锁定对象；现有HP/实际攻击实例观察保留。不对native hook的零计数作因果判断。
- 离线验证：新spawn_outcomes、spawn_guard、spawn_inspector通过；arena完整回归通过；bridge19项（含不丢失uncertain原因）、runtime16项、session和真实main加载测试通过。相机函数及共享玩家查找与暂停快照源文本一致。
- **18:38部署**：19个Lua文件逐一SHA-256一致；旧部署备份 `D:\Claude CODE\影之刃0-backups\deployed-before-v018-20261030-183807`。只确认磁盘部署，尚无本轮游戏召唤/战斗结论。
- 已请用户重载，F8开启无仇恨，然后蓝红各召唤一只机灵鬼并开始交战约20秒。等待画面反馈和日志读回，不宣称互伤已修复。

## 18:41–19:02：纠正测试单位、首次普通NPC互伤、同址崩溃隔离

### 机灵鬼不适合伤害基准

- v0.18于18:38:48加载；18:41生成蓝红各一只机灵鬼（HP400）。约12秒交战期间两者始终400；只观察到B方活动扫掠实例，主动IsValidTarget(对方)返回true；native IsValidTarget hook计数包含探针自己主动调用，不能当作实际碰撞命中证据。
- 用户确认“只有一只出招，另一只站着”，并明确补充机灵鬼天生穿透/无敌，要求换NPC。将其不掉血排除为普通NPC伤害验收证据；不能据此认定引擎禁止NPC伤害。
- 两者真实CharacterName读回未能取得有效非None值，未调用PBZSpawnSubsystem映射，没有猜名称或切换生成函数。
- 18:41:30清理首次读回待确认2只，18:41:43控制器后续读回清理完成。**这只证明Actor清理状态，不证明没有其它残留或存档安全。**

### 换成普通持刀暴徒后真实互伤成立

- 用户授权换普通单位。原生codex精确路径 `/PBZCombatAsset/ActorData/Mobs/003_MaleThug/BP_Monster_MaleThug_Sword_Blue.BP_Monster_MaleThug_Sword_Blue_C` 对应“暴徒”、bIsBoss=false。v0.18.1将其标为controlled_test，单次1只、最多2只；没有冒充已验证生成。19文件18:53部署，备份 `D:\Claude CODE\影之刃0-backups\deployed-before-v0181-20261030-185300`。
- 原计划先单只玩家攻击验证，用户实际召了蓝红各一只并于18:54:30点击交战。18:54:32起蓝方HP400→358，后续降至64；红方18:54:47达到0并触发原生On Dead。用户明确回答第一只由另一只怪打死，自己当时未动手。
- 因此此具体单位/场景已得到NPC攻击→真实减血→正常死亡的实机证据。后续18:55:10–11玩家处决蓝方有明确DealDamageToAvatar source=玩家的记录，**将这次补刀与前段NPC互斗分开**。
- 原始完整游戏日志和runtime证据已在崩溃后重启覆盖前保存：`D:\Claude CODE\影之刃0-backups\ordinary-baseline-20261030-185516`。这不是任意NPC、任意场景或稳定性通过。

### 两次同址原生崩溃（根因待验证）

- 18:45:20.7539378，用户在存档时崩溃。dump41111393字节，线程10528，0xC0000005，PBZ.exe+0x619C9F0，读0。助手收到消息时用户已重开，UE4SS.log已覆盖；不能把save-crash目录内的新启动日志冒充崩溃前日志。
- 用户重开且未召唤时存档正常。已将现存24份游戏存档（5776833字节）复制到仓库外 `save-crash-20261030-184520/saves-after-clean-restart`，没有改写原存档。
- 18:55:15.2561155再次崩溃，用户表示原因未知、可能不是战斗导致。线程31900，同为PBZ.exe+0x619C9F0读0。完整崩溃前日志最后一行为18:55:15.2556287玩家 `BP_Renewal_Hun:Health Post Func` 诊断回调（new=old=1122）。两只普通暴徒此前均已死亡；此时自动诊断hook尚未到60秒停止点。
- 只读dump上下文+PE反汇编确认故障指令为`cmp byte ptr [rax],0x16`且rax=0。栈内有UE4SS地址，但当前工具输出是地址候选、**不是展开调用栈，也没有证明函数名或责任模块**。分析工具与输出放在仓库外debug-tools；未上传转储。
- 核对[当前UE4SS提交的LuaMod.cpp](https://github.com/UE4SS-RE/RE-UE4SS/blob/dff435dd/UE4SS/src/Mod/LuaMod.cpp#L3884)，RegisterHook实际上按FUNC_Native及FuncPtr分派，不是仅按`/Script/`前缀。我们的历史探针按路径标script，导致原生编译的玩家Health Post Func被标成script post；另一方面/Script/PBZCharacter:OnDamage实际为script hook。**此分类/回调相位是已确认的诊断缺陷，但尚不能直接认定就是原生崩溃原因。**
- v0.18.2让整个CombatProbe在查对象和注册hook之前直接拒绝start（Config.Probe.Enabled=false）；普通擂台仍走原生攻击，现有每秒HP采样和攻击实例读取保留。新增每次Lua加载独立UTF-8运行日志，上限8MiB，避免再因重启丢证据。默认禁用路径回归确认不查UObject、不注册hook、不装计时器；真实main加载测试通过。
- 下一步只隔离诊断hook：重载后复测普通暴徒互斗、F4清理、等两队归零，再由用户存档及等待。若稳定，支持“诊断挂钩参与崩溃”的假设；有限一轮通过仍不能宣称彻底修复。不把公开其它游戏issue当作本作定因。
- v0.18.2于19:04完成19文件部署、逐文件SHA-256一致；备份 `D:\Claude CODE\影之刃0-backups\deployed-before-v0182-20261030-190433`。19:06:58已经游戏重载确认，独立日志 `Runtime/run-20261030-190658.log` 正常增长，用户正在进行蓝红普通暴徒互斗；等待战后存档结果，没有把部署或启动当作稳定修复通过。

### v0.18.2隔离结果与v0.18.3无仇恨状态修正

- 19:06:58加载v0.18.2。开战明确记录“诊断挂钩已关闭；未查找或注册任何战斗/玩家血量hook”。蓝红普通暴徒仍可互斗并掉血；用户回复“能互斗，目前看来没有别的问题”。PBZSaveGame.sav最后写入19:08:45；此轮没有报告崩溃。支持保留无诊断挂钩版本，**尚未严证两次同址崩溃的根因，也未作长期稳定性结论**。
- 19:08:39 F4有两项玩家↔已死亡参赛者关系恢复读回不等于开战前值，保留记录。19:08:58两队归零，state=restore_pending。用户19:11:03再按F4，目标已失效，过期关系记录读回确认丢弃，恢复确认=true、待确认0、arena idle。没有强写陌生地图NPC或丢弃仍有效的失败条目。
- 用户报告未开F8却被参赛怪忽略。代码明确存在两个控制来源：arena.start无条件将每个参赛者与玩家设为双向Neutral；spectator.off通过main传入的getDesiredPlayerRelation在交战时继续保留Neutral。网页只显示spectator.enabled_requested=false，因而显示关闭但参赛怪仍中立。
- 新回归先在旧arena失败：“starting a battle must not silently grant no-aggro while F8 is off”。v0.18.3移除arena的玩家中立写入与main中的关F8后继续保留Neutral策略。玩家忽略现在只由F8/网页同一个spectator实例控制；开战仅修改参赛者相互关系。
- spectator未开启时也只读当前玩家CanBeHatredNow，不强行写成true；将readback和pending_flags/pending_relations传给页面。页面区分请求、实际资格和待恢复状态；未确认恢复时不再显示已关闭。原始false（可能来自游戏或其它修改）仍保留并显示待确认，不能伪装已恢复。
- arena、spectator、runtime16项、spawn_outcomes、真实main加载和JS语法检查通过。F6/F7未动，CombatProbe继续禁用。v0.18.3于19:16部署19文件，逐一哈希一致，备份 `D:\Claude CODE\影之刃0-backups\deployed-before-v0183-20261030-191639`。等待用户重载、F8开关与网页同步读回。
- 随后已加载v0.18.3，先读到spectator_enabled=true且flag_readback=false；用户再关闭后网页实际按钮显示“开启无仇恨观战（已关闭）”、aria-pressed=false。用户明确回复“网页和F8状态同步了”。用户随后继续游戏并重新打开F8；19:20状态为enabled=true、flag_readback=false、pending_flags=1、pending_relations=2、两队0。这些是开启中的活动快照，不能宣称结束时已关闭/清空。当前还有原生NPC阵营不可读的重复观察日志，未确认其行为；不要将全场效果泛化为全部已验收。本轮未再要求玩家重复交战；对战场内F8关闭后能否立即被重新选为目标仍不作保证，正常仇恨资格与AI当前攻击目标不同。


## v0.19 原生章节、地图和图鉴分类（2026-10-30）

用户要求从官方文件区分章节/地图、BOSS/小兵/特殊单位。先查本地头文件，确认FCodexEnemyRow.OwnMapID、FMapData.OwnChapterID、FChapterData以及BellManager只读getter；不使用击杀地图、不猜目录编号。19:36:14实际读取177图鉴行、181精确类映射（含别名），181均有地图归属，12个地图ID、9个具名章节；序章没有章节字段。主图鉴75条BOSS类记录、101普通敌人、1用户实测机制特殊的机灵鬼。BOSS记录不是独立BOSS人数，OwnMapID不是完整遭遇地点表。

新增world_map_catalog.lua与12列codex-locations.tsv，保持旧codex.tsv兼容。后端精确匹配类/canonical/source，拒绝重复与无效记录；不继承父类地图，不改变召唤白名单。默认UI只显示177主图鉴，全部674候选另设视图，加入章节/地图/类型联动筛选和归属分组。无官方角色字段的用途依据只作为候选提示。小兵/精英只找到EPBZAIType枚举声明，未取得当前NPC关联字段，未伪称已完成分级。

部署20个Lua文件，逐文件哈希一致，用户已清理并重载。旧部署备份deployed-before-v019-20261030-193533。地图解析、图鉴导出、main加载Lua检查及后端43项、标签25项、JS分类过滤回归通过。浏览器实际验证悲泣溪谷BOSS9条、模板/测试51条，召唤权限仍只有原2条。自由视角/共享玩家查找源文本不变，没有新生成实验。分类完整汇总和限制见CATALOG_CLASSIFICATION.md。


## v0.20–v0.20.2 全目录核对（2026-10-30）

原始注册表核对267049条、19736路径，独立GetAllAssets前后总数相同，无重复/查询/行/标签错误。旧版10000目录上限漏掉庞镇_Generated_目录22817条，本次该目录32817条完整保存。空根目录已通过HasAssets=false验证。范围是当前已挂载磁盘注册表，不是物理加密包完整解包。

CXX继承+注册表交叉得到NPC652、player7、character189、pawn4。合并raw catalog737→929，面板过滤后674→866；新增192=player7/character182/pawn3，主要为演出/玩家/测试，并未发现新PBZCharacter_NPC派生类。生成许可仍只有原2条。

已加载场景配置分次汇总123样本、55类、LuJiaCun/ZhengDaoDaYing/XiGu三区域；当前实例观察独立记录。2138包引用查询均空、无调用错误，不能当作其它地图无配置的证据。5张精确schema数据表361行已读取；318条属性记录AssetPath即使增加反射结构解码仍未读回成功，不按行名强行关联。MapData15/ChapterData12含测试或空名项，未当作新正式地图章节。

主utoc/pak目录加密；本地EXE常量的59候选未通过索引SHA-1，不读进程RAM、不上传文件。未取得未加载地图的完整静态刷怪配置，保留限制。v0.20最初clean(false)空字段和FindAllOf无对象返回nil的计数问题已在后续部署修正；原始manifest空false保留，complete=true由当时Lua内部布尔和独立计数判定。

用户已重载v0.20.2，24文件哈希一致；后端44项、标签25项、前端筛选与新Lua/离线合并检查通过。生成、战斗和相机逻辑未改，CombatProbe保持关闭。本轮产物和完整边界见ASSET_AUDIT.md。

## 2026-10-30 物理资源目录解密成功

用户要求“解密去”并把磁盘目录单独放入下拉栏。目录索引在本地只读解密；解密方法与工具只保留在作者本地，不随仓库公开。未读进程内存、未改写游戏文件、未上传资源。

读回验证：主IoStore目录304988条，主pak5585条，9个视频pak400条，共310973个文件条目。全部10个pak的主索引及完整目录SHA-1一致；主IoStore完整遍历19685个目录，文件/字符串/TOC索引无越界、无环、无不可达条目。其它视频utoc目录为空，global.utoc无索引。产物由tools/decrypt_asset_directory.py生成，目录结构校验与pak哈希验证分别报告，不把IoStore自算哈希当独立认证。

初次物理/注册表比对各有6676个差异；按FName不区分大小写及实际uplugin文件名重建挂载路径（例如InterchangeAssets）后，252284个物理包与252284个注册表包全部对应，双方差集均0。此前“没有取得解密磁盘目录”仅是失败时的历史状态，现已被本次成功替代；仍未批量解析资源正文或全地图刷怪规则，不把文件条目当单位数量。

解码中修正两处实际格式差异：pak12文件名可不带NUL终止；AES末尾对齐字节不保证0。保留哈希、长度、索引与树边界校验。目录解析器3项通过，后端45项通过，JS语法及真实浏览器搜索/类型/分页通过。面板新增“已解密磁盘目录”只读下拉视图，读取清单按需缓存，游戏命令桥未改变。本轮不修改24个Lua、召唤许可、CombatProbe或自由视角，不需用户重载。详情与复现命令在作者本地记录中（不公开）。

## 2026-10-30 磁盘单位交叉核对与原布局恢复

用户指出原始目录看不到单位，并要求按之前的章节/地图卡片布局、明确小怪与BOSS。只读核对866个面板候选的精确包路径，866均在已解密磁盘目录；其中852有继承证据（NPC652、Character189、Player7、Pawn4），14个身份待核对。没有新增可确认单位，不把图标/相似名称的资源判成单位。

第三下拉项“磁盘单位（已解密）”复用原单位卡片、章节→地图→类型筛选；原始文件移到第四项。小怪对应原生普通敌人类别，BOSS依照原生图鉴标记，候选用途和地图不明保持原有未知标记。实浏览器已验证悲泣溪谷29条中17条小怪、12条BOSS记录（含3条别名）。本地JS匹配与分类回归通过；只更新前端和本地忽略的文件路径索引，没有更改生成权限或操作游戏。

服务重启动作被自动审批拒绝，未执行。后端实验随后全部撤回，与上一检查点哈希一致；服务PID36996保留。使用现有服务直接提供前端静态文件，不再请求重启。目录索引生成方式与限制在作者本地记录中（不公开）。

## v0.21–v0.22：召唤入口、死亡计数与未配队管理

用户指出全部不可召唤。实际API仅Sword_Blue和VesselChild两路径放行，页面又停在没有允许单位的章节；这是旧白名单与展示方式造成，并非目录解密失败。v0.21最初开放175条原生图鉴直接敌人的单只试召唤；00:11:22实机读回175。00:14:58长枪暴徒Spear_Blue生成1/1、AI有效、HP400，用户确认出现并行动。其后玩家击杀读回HP0；没有将其写为NPC互斗验收。

用户发现死亡计数慢，且要求取消总量限制、未配队独立计数/清理、所有目录开放。旧计数只看IsValid，实际日志中HP0的尸体仍有效，F4调用后IsActorBeingDestroyed也一度false。新增回归先在旧控制器失败，修复后HP0立即退出存活数、所有权仍可清理，回血可再次计入。未知血量独立标记，不假装死亡。

v0.22将maxUnits设0、位置槽位按已有记录寻找，不再受24或2限制；每批保留1–8。新增clear_neutral命令，仅销毁本Mod的neutral记录，不调用全局restore、不取消蓝红会话。网页每500ms读取，区分存活、死亡待清理及未知状态。非空隔离清理与32只超过旧上限已离线回归，不能冒充实机32只。

后端显式all_catalog模式为866/866个现有目录条目返回experimental_spawn和最大8。Lua仅校验规范类路径；实际加载仍验证UClass、精确路径、Actor继承。NPC继续原生AI延迟生成；非NPC通过GameplayStatics两段延迟生成，先登记所有权再完成初始化，不调用PBZ战斗接口。通用Actor只完成mock入口检查，实际兼容未验收。火狗旧隔离按最新用户“全部开放”要求撤销，这不是崩溃根因已排除。

00:46:24实机加载v0.22-open-catalog；spawn_mode=all_catalog、arena_max_units=0。命令id72生成3只未配队长枪暴徒，读回3/3和初始化3；00:49:48/00:50:00/00:50:08有HP0与alive=false存活数更新，用户确认计数和清理正常。id73 clear_neutral成功，执行时实体已自然清空，确认0、待确认0，不能据此声称非空销毁已实机通过。最后blue/red/neutral/owned/dead均0、F8关闭。

后端46项、目录16项、桥接19项、runtime16项及Arena/策略/生成异常/main加载两条路径/前端回归通过；24部署hash一致，5个相机与玩家查找函数逐段相同，CombatProbe仍禁用。面板重启被自动审批拒绝，明确授权后仍拒绝，最终用户亲自运行身份检查脚本完成；新PID39592。完整范围和证据见SPAWN_AND_COUNTS.md。

## 2026-10-31：v0.23–v0.24.1，BOSS 血条修复、卡片键与 F6 失败证据

完整上下文和可复查字段见 [BOSS_AND_CONTROLS.md](BOSS_AND_CONTROLS.md)。

- 原生召唤归属可从 `GA_SummonPassive_C.GetAvatarActorFromActorInfo()` 与 `SpawnedSummonInstances(Pawn,bPawnPending)` 精确关联。实测碧海和沐小葵 P2 的 4 个后代被登记并继承阵营、发出对面攻击请求；没有按距离收编地图 NPC。尚不宣称任意召唤技能都已验收。
- v0.23 原生血条注册调用成功，却出现 Character 未绑定的空控件。v0.23.1 通过唯一新增控件定位、设置 Character、Init、真实 HP 比例和 FText 名字更新，并分别读取 CurPercent、GetText 验证。注册返回值为 table，句柄查控件路径没有成功；不能把该路径写成实测成功。用户最终确认“名字、血量和清理都正常”。
- v0.23 清理曾在原生对象已无效但 UE4SS 包装器 IsValid 为真时滞留。v0.23.1 精确调用 KismetSystemLibrary:IsValid；未知结果不删除所有权。F4 能清除旧空条、保留别人的有效条。用户实测清理后可再次召唤。
- v0.24 单位键持久化、默认未绑定、冲突检查及队列失效已接通；用户确认游戏中按绑定键可召唤。用户之后自行解绑过，不能用旧 revision=2 的快照覆盖 revision=4 的当前设置。
- **失败：** v0.24 为参赛 NPC 停用距离优化，04:12:37 和 04:13:19 的 F6 进入读回 wave=1、mesh_tick=0、anim_visibility=1，用户仍明显看到变慢。单独停用距离优化未解决。
- **连续数值证据：** 04:12:40.446–04:12:59.993 的 10 次战况采样始终 HP=8693.75/8790.0；04:13:04 退出 F6 后，04:13:05–04:13:15 的 HP 变化合计蓝 84、红 682.5。不是仅 UI 延迟，也不是逐招伤害系数测量。用户补充杀气条也很慢，旧日志没有 Shachi 数据，暂不能确认其数值变化量。
- 自由视角期间攻击实例与 `IsValidTarget(opponent)=true` 仍出现；playerAddress 从普通模式的有效地址变 UNKNOWN，退出恢复。这个玩家查找兼容线索尚未证明是原生伤害停滞的原因。不能把普通/F6 都出现的 IgnoredActors 列表当作新排除结论，不能重启旧碰撞通道尝试。
- v0.24.1 只新增参赛 Mesh 的 VisibilityBasedAnimTickOption=0 对照；不写伤害、杀气、URO 或 Tick 间隔。每对象最多 3 次写入并读回；每约 5 秒/相机变化只读 Health、Shachi、Attack、ShachiAttack、受伤资格、AI 状态、时间倍率、玩家及原调试控制器 Pawn，每对象最多 120 个样本。当前尚无实机结果。
- v0.24.1 新增 F2 循环 blue/red/neutral，仅影响后续召唤；已有成员不换队。主机按键注册读回、游戏线程分发、前端原生 revision 同步、卸载失效已离线检查。等待用户实测。
- 本轮 runtime 18 项、Arena、activity、单位键、真实 main 两条生成路径及 JS 相关回归通过。部署 30 Lua 哈希一致，Runtime 用户键文件前后哈希一致。备份 `D:\Claude CODE\影之刃0-backups\v0241-team-bones-20261031-044938`。五个相机/玩家查找函数相对部署前 v0.24 逐字未变；相对最早 Git HEAD 有以前增加的有效性检查，不声称历史完全未改。

04:50:51 实机确认 v0.24.1 加载；04:51:08–04:51:18 的 F2 连续 6 次循环，revision1–6、数量保持1，原生与网页均显示蓝队、场上0。F2 已有端到端观察证据。04:53:20 阿花骨骼策略从1读回0，Health9000/Shachi800/Attack70/ShachiAttack33，三种时间倍率均1；这只证明字段读写有效。随后用户另选了 GuiChai_Red 对战并清理，尚未取得这版 F6 对照结果，不能把清理/战斗结束说成修复通过。

## 2026-10-31 05:08：v0.24.1 失败，v0.25 相机隔离与召唤卡顿修正

用户明确确认 F2 正常，F6 仍血量/杀气慢，退出恢复。04:57:15进入到04:58:07退出间，连续采样阿花 HP8678/Shachi551.7000、GuiChai_Red HP7755/Shachi786.7501 固定。world/cinematic/actor倍率1，骨骼刷新0，can_damage=true，AI.State.Combat；退出数秒后两项都继续下降。固定骨骼刷新没有解决问题。

同期mod_player由有效地址变nil，但debug_original_pawn仍是原地址，退出恢复。证实玩家查找不兼容旧调试相机，尚不证明原生伤害停滞的全部根因。v0.25改成CameraActor+SetViewTargetWithBlend，保留原PlayerController/Player/Pawn关联，只移动相机；带输入限制的增量恢复和跨重载journal，未启用hook或改伤害。离线9项相机回归通过，待用户实机验证。

用户另报每次召唤停数秒。原日志明确Catalog.refresh占3.52–4.92秒，每次扫描3268/3409等全部类；后续两次LoadAsset仅0.106/0.213秒，生成激活约0.015秒。已将全量目录刷新移出精确路径召唤，仍保留类/继承/权限/世界检查，默认选择只读取保存/配置元数据。新“禁止召唤触发全局扫描”回归在旧代码失败，修改后Arena、Catalog17项及main启动通过。实际卡顿改善尚待新日志。

31 Lua部署hash一致；备份`影之刃0-backups/v025-observer-camera-20261031-050824`。部署前场上0/F8关闭/自由镜头关闭，已请求用户重载，后台无需重启。详见 [FREE_CAMERA_AND_SPAWN.md](FREE_CAMERA_AND_SPAWN.md)。投技未实现，已如实回复用户；没有混入四项仅讨论功能。

**后续实机读回：** 05:11:05加载v0.25；05:11:35独立相机进入，控制器/Player/Pawn关联与新ViewTarget均核对；随后输入导致实际相机位置变化。05:11:59通过F7、05:12:10通过F6退出，两次原视点恢复true、输入限制读回false、自建Actor原生失效，journal仅剩版本头。空场功能有证据，不能冒充交战期间掉血已修复。

05:12:39.991236–05:12:40.132289阿花召唤处理约0.1411秒；05:13:11.277962–05:13:11.289069 GuiChai_Red约0.0111秒，后者精确类直接命中。两次均无全量类扫描，旧固定数秒开销已从此流程移除；不是任意单位冷加载/渲染帧耗时保证。后续战斗样本出现多个同类阿花，`F6Readback`目前只有类路径，不能将同类多行HP混作同一Actor的变化；需要对应Arena生命日志中的唯一实例名，或下一版补actor id。

05:14:41.749进入新F6，05:14:59.704退出；这次双方为不同类别的GuiChai_Yellow_MoDao/ShuangGou，不能与旧阿花配对作同招DPS比较。F6内4次/类读取，mod_player始终有效，时间倍率1；05:14:41.783→05:14:54.509，双方HP净下降168.001/352.800、Shachi下降79.200/158.400。已取得新F6下持续原生血量/杀气削减证据；攻击节奏是否恢复仍等用户画面确认。日志与JSON样本已存v025备份。

## 2026-10-31 05:21：v0.25效果确认，v0.25.1动作输入隔离验收

用户确认召唤卡顿/F6血量杀气恢复正常，镜头进出移动正常；另报Space仍令角色跳跃。原因是v0.25只忽略move/look输入，没有阻挡动作键。v0.25.1仅在自建CameraActor加高优先级阻挡输入组件，保留原玩家控制器/Pawn/输入映射和相机原始键状态读取；退出撤销此自建层。未使用Pawn.DisableInput或再次切换控制器。

新增动作穿透回归在旧实现失败，修正后相机10项与main集成通过。05:20:35原生层读回block=true、priority10000、InputComponent归属自建相机，相机可继续运动。05:21:00 F6退出：原视点恢复true、层撤销调用完成、原生相机销毁true、move/look=false；journal清空。用户测试观察时空格/左键/Shift及退出恢复，明确回复“正常了”。当前31Lua部署hash一致、freecam=false/owned0/F8=false/pending0。详细证据与边界见FREE_CAMERA_AND_SPAWN.md。

F6根因结论限于旧调试相机接管方式与本作战斗上下文不兼容：旧玩家引用nil、保留关联的新方式恢复且用户确认；未断言已反编译定位某条原生伤害函数。投技与四项仅讨论功能均未实施。

## 2026-10-31：NPC红光成对动作，原生分支定位与首轮写入失败

用户新授权实现NPC之间的投技，并明确指红光命中后触发整段不可操作双人动画的类型，普通伤害型红光不变。另完成用户术语GuaiMian→怪面与快捷键冲突显示占用单位中文名/具体功能，浏览器已验证“4被鬼差队长：火流星占用”。

v0.26只读核对177条字段/函数/时间线记录。普通暴徒ToNpc原生施技与受技能力存在，时间线6.2667秒，GrabSuccess4.2秒，非循环且bStopAbility=true。其Grab事件NonPlayerGE为空UClass；多个BOSS的同字段为GE_GrabHit。没有仅凭名字推断开关。

使用只读进程权限，验证游戏路径、报告的FunctionFlags，并双读一致取得4个指定Blueprint函数Script。没有写进程内存。当前构建UStruct.Script=0xb0；Trigger3495字节，当前进程样本SHA256 9ea917ab707025d36f3f7c33b0286151b3958b42b6fe74f0894d76f1d7066e23（地址重定位后hash可能不同）。按Epic EExprToken核对：offset34 JumpIfNot(NonPlayerGE有效性)→100完整抓取；有GE且目标非玩家时offset86跳342，342–543只应用替代GE并返回。完整分支仍检查Target Required/Ignored Tags。由此确认NonPlayerGE=空可进入原有命中后配对流程，尚不证明不同NPC骨架都兼容。游戏字节码仅存仓库外v026备份，禁止提交。

v0.26.1新增arena_grabs.lua：战斗前对参赛Mobs族目录的共享Grab事件、仅确认的GE_GrabHit替代值做快照后清空；不触发技能、不改伤害/目标Tag、不安装hook。源资源可被同族原生NPC共用，不能称单Actor所有。F4、停止、换族及热重载恢复原配置；观察ExecutionComponent和ASC句柄ActiveCount。8项离线回归、Arena、runtime18项与main加载通过。

**失败证据：** v0.26.1于06:02:05加载，06:03:44/49/54三次Lua nil写入均verified=false，原GE仍在、npc_grab_events=0。因此该轮未实际启用投技。旧日志没有setter异常文本，不虚构具体错误原因。

v0.26.2改为从有效事件CDO取得原生空UClass包装值，再写入有效目标事件；先确认类型和无效性，不解引用空类。日志增加called/read/after和异常文本。ClassProperty拒绝nil的离线边界先失败后通过，main加载通过。33Lua已部署到游戏目录并hash一致，备份`影之刃0-backups/v0262-native-grabs-20261031-060707`；已请求用户清理/关F8/重载。当前仍待实机空类赋值与成对动作验收，不能称NPC投技已完成。继续点见WIP_NPC_GRABS.md。

### v0.26.2 验收更新

本版原生空类写入已实际成功：魔渊5个事件called/read/verified均true，after=UClass；06:11:29五项原值恢复均true。总battle恢复当时false，06:11:54再次F4后true，区分资源层与整体恢复。阿花事件06:12:02启用、06:13:37恢复均true；花千笑/乱狮3个事件随后启用。

用户先说没看到投技，随后明确纠正：“重新试了一下，可行。这一步已经完成了”，并确认“双方有完整配套动作，结束后能继续打”。按最后反馈，本轮NPC原红光命中后配对动作与结束恢复通过。不能扩大为全目录/所有骨架兼容，也没有逐帧伤害归因记录。

观察器npc_grab_pairs仍为0，组件CurrentExecutionInfo/句柄没有可靠捕捉到此类配对；这不是投技次数。不要用这个计数否定用户实机画面。未为纯诊断计数追加重载/扩大实验。最新场上蓝红各1、F8开启、3条投技资源快照处于正常启用状态，没有投技恢复失败；用户继续在游戏中，未代替清场。源码/部署33Lua哈希一致；备份含v0262-user-confirmed.log、verified-state.json。正式记录见[NPC_GRABS.md](NPC_GRABS.md)。

## 2026-10-31：数值统一接口失败与血条/开战回归

用户授权以首只出生属性统一后续手动生成NPC，范围包括生命/杀气、攻击/削杀气及攻防倍率，保留体型、速度、招式、AI。v0.27开关持久化、首只基准读取和F4重置实机成功：魔渊12000/1200/84/39.6000，阿花9000/800/70/33。后续匹配没有成功，不能将只读基准当作已实现数值统一。

v0.27的MakeAttribute返回值未通过AttributeName/AttributeOwner校验，旧日志缺具体字段。v0.27.1改用精确原生IsValid UFunction后，08:18:21仍读到`属性描述无效: Attack kind=table cached_name=Attack；回滚读回=true`。这证明传回原生函数的描述无效，不证明具体是FieldPath哪一部分丢失；没有改用不安全的内存直写。

同一条生成日志显示ControllerAI=true、HP12000，但main将数值失败直接返回activate=false，Arena进入cleanup_pending。arenaSupport对该状态执行bossHUD.clear，start也拒绝交战。这条代码链与用户“无法开打/血条没了”及运行status一致，是数值统一新增逻辑造成的回归，不是目录或NPC血量资源丢失。

v0.27.2：有已验证回滚的可选数值失败保留激活成功，将失败原因附在生成回执；无法确认回滚继续要求清理。隔离测试真正加载main并调用其激活回调，在部署v0.27.1上按预期失败，在修正版通过；Arena另验证警告时仍可蓝红开战。原位属性描述改从已核对GameplayEffect.Modifiers中读取，缓存只保留有效效果UObject，不缓存临时结构。完整索引逐路径确认109个GameplayEffect条目；107基础战斗字段加Health/Shachi。10个没有相应效果资产证据的扩展字段移出写入范围。属性集仍验证实例所有权，源效果只读。

7项匹配/校准/回滚、adapter、Arena、main及JS语法通过。35Lua部署hash一致，备份`D:\Claude CODE\影之刃0-backups\v0272-stat-match-20261031-082848`。原位描述传递、实际数值匹配及修正后HUD仍需游戏实测；未宣布已修复数值统一。08:29用户已F4清空，F8仍开，先请求其关闭并核对恢复，然后重载。

同轮页面刷新曾停在初始化，占位显示0单位；本机status/catalog接口正常，catalog866条。浏览器重新加载后恢复177主图鉴，捕获到的异常来自注入的clipboard bridge，没有证明是app.js错误或根因。仅将加载占位文字改为“正在加载单位图鉴”，避免误导用户重扫；没有扫描游戏目录。

### v0.27.2 实机验收更新

用户08:31关闭F8，关系/标志恢复记录0、玩家资格读回true；08:33:30重载成功。08:33:49阿花基准107项，HPmax9000/ShachiMax800/Attack70/ShachiAttack33；08:33:58魔渊实际应用并读回109/109一致，激活true、HP9000。08:34:24用户清场使基准重置；08:34:31重新捕获阿花，08:34:37魔渊再次109/109一致。原位GameplayEffect属性描述传递和实例基础值修改在该组合成功，旧MakeAttribute返回表方案保持失败记录。

原生状态HUD visible/names_verified/health_verified均2，arena=battle_requested、matched1/failures0。08:35:48双方HP/Shachi为6836.999/55.520与8047.125/473.301；08:36:25为5866.799/800与7600.875/305.001，Attack/ShachiAttack持续70/33。实际HP和杀气有消耗/自然回复，出生基准没有跟随残血，未产生锁血/锁杀气。用户明确反馈“血条和互斗正常”。这组匹配、HUD/交战回归、清场重置通过，不扩大为全目录/每招伤害相同或全部攻防扩展字段兼容。

35Lua源码和部署hash再次核对一致，`v0272-user-confirmed.log`、`verified-game-state.json`和源码快照保存在本轮仓库外备份。当前用户仍在交战，蓝红各1/F8开启/freecam关闭；未代替操作游戏、清场或重载。README、HANDOFF与STAT_MATCH已更新验收状态。

## 2026-10-31：观战联动、锁血失败与v0.28.2验收

用户明确授权F6进入时无仇恨、锁血、模型隐藏、声音跟随镜头，退出恢复原状态。v0.28通过独立相机生命周期加入状态快照、原生GE_LockHealth、自身/附着装备隐藏、PBZSoundFXSubsystem距离探针和引擎Listener override。用户确认隐藏、移动、退出恢复及人物远处的镜头收音正常。无仇恨加入只清玩家黑板目标/Focus、生成时立即处理与持久恢复账本；不清NPC对NPC目标，不ForceOffCombat。

失败：09:15:28，GE_LockHealth_count=1、bCanBeDamaged=false、玩家已隐藏时，HP1285仍降至1159，说明这些设置不能等同锁血。v0.28.1实际读取GE首修饰属性为Health_Min；尝试AddAttributeBuff的无限时长参数没有得到有效句柄/新增效果，09:28多次F6进入被完整回退，用户确认不能进相机。原生返回形状/内部拒绝条件未证明，不按猜测归因为某个参数；该创建路径已从正式实现移除。

v0.28.2改为实例原生Health_Min基础值写入，沿用已经核对的原位属性描述与ModifyCharacterAttributeValue。保存原基础值，退出还原；若可见HP下有低基础值欠账，退出前一次性校正，不每帧写HP。可恢复且回滚已验证的保护失败不再阻断相机，并通过面板状态明确区分。10项保护回归、native adapter、main、runtime19项通过。

实机：09:45:38 Health_Min base/current 0→977，观战约80秒没有HP变化；09:46:59 base/current恢复0，HP仍977，模型/声音/无仇恨/视点恢复完成。下一轮按新的HP1411建立下限1411。用户明确确认“摄像机恢复，观战没有掉血”。无仇恨对参赛阿花/魔渊有Neutral及移除玩家仇恨读回；另外部分NPC组件读取持续失败，不能把累计计数解释成真实追击次数或宣称全类型兼容。详细边界见[OBSERVER_MODE.md](OBSERVER_MODE.md)。

## 2026-10-31：v0.29 独立常驻血条及生命数字

用户新要求血条常驻、上方显示具体HP，并选择死亡后隐藏。旧日志反复出现“拒绝覆盖绑定到其它角色的控件”：原生扩展池复用后，缓存的控件已不属于原Actor，旧逻辑长期拒绝更新。不是属性基准拷贝了名字。

新arena_hud/arena_hud_widget为每个活的蓝红BOSS创建私有原生WB_BossHPBar，保留游戏样式，WidgetTree加独立数字行。自己持有视图并维护显示，失效重建；不再借用BossPoint可复用控件。只隐藏对应参赛者的原生重复条并恢复，其他NPC条不改。hp<=0/清场移除私有条，符合用户选择。没有增加游戏资源文件或伤害挂钩。

管理与渲染回归、main、runtime19项通过，39Lua hash一致。10:16:08加载，10:16:18/24阿花/魔渊独立控件创建；初始数字已验证，CurPercent内部读回直到首次受击后才验证成功。10:16:36至10:18多次两边visible/name/hp/number均true，数字从9000/9000、12000/12000持续减少至5369.1/9000、8325/12000等。API显示两条血条各项验证2、pending0，F6观战期间玩家生命下限仍已验证。用户确认“显示正常，数字会变化”。死亡隐藏是保留语义及离线验证，此次采样时两只仍活，不冒称已实机观察它们死亡。详见[PERSISTENT_HUD.md](PERSISTENT_HUD.md)。

后续实机补充：10:23:58阿花HP76.26降至0，10:23:58.627其私有条移除true；10:24:16 F4移除存活者的条也true。清理时旧战斗blackboard:TargetActor恢复读回UNKNOWN而保留1项，10:30:51用户再次F4后该黑板有效性false，记录安全丢弃，恢复true、arena idle。F6/F8、参赛者、HUD、待恢复均0；死亡隐藏及条目移除已有本轮实机证据。没有为了UI修复重启游戏/后台或发布仓库。

## 2026-10-31 v0.30 功能快捷键自定义

用户确认八项功能全部默认空白，原F6/F7/F2/F8接入面板，保存过的自定义配置保留；观战文案写明无仇恨、隐身和无敌锁血。实现统一宿主路由、八项配置与V2保存协议、原子替换/备份/回读、按主键跨功能和单位的占用检查、改绑与旧排队事件失效；关闭隐藏的开发按键。单独无仇恨语义保持，完整保护属于自由观战，并增加面板进入/退出按钮。

功能键10项、runtime20项、桥接21项、后端53项、共享路由/单位/前端/main等检查通过。41Lua部署hash一致；用户手动重启两端，11:34:53游戏确认v0.30，API八项key_code均0、errors为空，旧单位键文件哈希不变。IAB原页面仍是旧四项下拉，助手刷新后确认新八项未绑定并展开设置。截图与原脚本保存在v030-custom-keys-20261031-113403。没有替用户选键或保存测试键，实际新绑定的游戏按键触发尚未由用户验收，不以离线检查代替。
