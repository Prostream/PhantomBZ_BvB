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

## v0.31.1：难度只读探查（2026-10-31，已实机读回）

用户问召唤单位是否只按当前难度，能否切换难度。头文件与资产注册表的离线证据：

- `EDifficultMode`：Handicapped=0、Easy=1、Normal=2、Hard=3、NightMare=4（ProjectPBZ_enums.hpp）。
- 注册表有5个 `/PBZCombatAsset/Config/GlobalConfig_Combat_<难度>`（PDA_GlobalCombatConfig_C）和5个 `GlobalConfig_Combined_<难度>`。结构含 `Global Mob Level Offset`、`Global Mob Attribute Modifiers`、`Difficulty Settings By Mob Type`（按怪物类型标签给 `FPBZCharacterDifficultySettings`：AttributeModifiers + SkillTypeDataSetMultipliers）。`FGenericValueModifyData` 为 Type(枚举)+Value(float)。
- `PDA_ActorConfig` 有 `Difficulty Tag`；`UPBZBlueprintFunctionLibrary` 有 `GetDifficulty`/`GetDiffcultMode`；伤害计算器有按难度的杀气比例表；BOSS召唤阈值按难度；AI行为树有 `BTDecorator_SwitchDifficulty`。推测：难度选择哪套全局配置，单位初始化时按自身难度标签取修正。行为树与伤害公式读全局难度，单只单位无法只靠属性修改完全换难度。以上为推测，待读回。

新增 `difficulty_probe.lua`：游戏就绪后一次性记录 `GetDiffcultMode`/`GetDifficulty` 返回值、5套配置的标量与修正表（非常驻的4套用 LoadAsset 只读加载），以及首批登记单位类上含 Config/Difficult 的字段名和 `Difficulty Tag`。不写任何游戏对象。离线测试 `tools/test_difficulty_probe.lua` 使用拒绝写入的夹具通过；main启动、panel_runtime、单位键测试通过。42个Lua部署哈希一致，BUILD=v0.31.1-difficulty-probe。等待用户重载Mod后读取日志 `[DifficultyProbe]`。

**实机读回（14:33:33，UE4SS.log 1633–1751）**：用户重载后探查一次跑完，`配置探查完成=true`、`单位字段探查完成=true`，没有写游戏对象。

- 当前难度：`GetDiffcultMode` 和 `GetDifficulty` 都读回 1，即 **Easy**。
- 5套 GlobalConfig_Combat 全部常驻（`已在内存=true 本次加载=false`），没有触发 LoadAsset。
- 标量：Handicapped 的 Global Mob Level Offset=-1，Player Break Damage Multiplier=1.5，其余四档分别为0和1.0。Mob Break Duration 在 Handicapped/Easy 为3，Normal/Hard/Nightmare 为4。Mob Break Damage Multiplier 五档都是1.5。
- Global Mob Attribute Modifiers（Type:Value，Type 1 看起来是乘数，Type 0 看起来是加值，未验证）：
  - Easy：Health_Max 1:1.0、Shachi_Max 1:0.5、Attack 1:0.7、ShachiAttack 1:0.33、Resistance_ReflectShachi 0:-1.0，另有对应的 _Lv1 项。
  - Normal：只有 ShachiAttack(_Lv1) 1:0.66。
  - Handicapped/Hard/Nightmare：空。
  - Global Player Attribute Modifiers 五档都为空。
- Difficulty Settings By Mob Type（标签 `CharacterType.Difficulty.*`）：
  - Easy/Normal/Hard/Nightmare 各7类，SkillTypeDataSetMultipliers 全为0条。
  - Mob/Standard：Health_Max 在 Easy/Normal 为0.8，Hard/Nightmare 为1.0；Shachi_Max 0.4；ExecutionTargetBreakHealthThreshold 为0.4（Mob）或0.3（Standard）。
  - Elite：Shachi_Max 0.6 和处决阈值，四档相同。
  - MiniBoss/NormalBoss/GreatBoss/UltimateBoss：Shachi_Max 0.8、处决阈值、Resistance_ShachiWeaponShachi 0:0.5；Hard/Nightmare 另加 Resistance_ReflectShachi 0:0.2。
  - Handicapped 只有4个BOSS类，各一项 Resistance_ShachiWeaponShachi 0:0.5。
- **Hard 与 Nightmare 两张表逐项相同**。两者的差别不在这份配置里，候选位置是 `BTDecorator_SwitchDifficulty` 的AI分支、`AIScript_LevelOffset`/`GroupScript_Level*`/`PBZ_MobDomain` 的 `Offset By Difficulty` 等级偏移，以及 PBZCombatAsset 里按难度的杀气比例和召唤阈值表（未读）。
- 单位字段：魔渊（BP_Monster_MoTian_C）有 `Actor Config`（Difficulty Tag=CharacterType.Difficulty.UltimateBoss）、`Sense Config Key Override`，以及 `Global Config Handicapped/Easy/Normal/Hard/Nightmare` 五个对象引用。推测每个角色自带5套配置引用，初始化时按当前难度取一套，再按自己的 Difficulty Tag 取类型修正。这是推测，没有验证生效时机。

切换入口（头文件，未调用）：
- 游戏设置菜单有 `UDemoSetting_Difficulty`（TryToApply、SetReallyDifficulty、ApplyInternal(Current,Target)）。
- `UPBZGameSystem`（WorldSubsystem）有 `SetDifficultMode`/`SetDifficultMode_Setting` 和 `DifficultModeByte`。
- `UPBZGameInstance.DifficultMode`；`UPBZSettingsShared` 有 `SetPendingDifficultMode`/`SetDifficultMode`。
- `UPBZSaveLoadSubsystem.SetSaveGameDifficultyMode`；存档还记录 `GetCycleEndingDifficulty`/`CycleRecord`。

所以由Mod直接改全局难度会写进玩家存档和周目记录，风险高于只改召唤单位。

结论：
- 召唤出来的单位确实按当前全局难度（现在是 Easy）取数值。斗蛐蛐双方都是怪物，全局修正对两边同比例生效。难度主要改变战斗节奏（Easy 攻击×0.7、杀气攻击×0.33）和杂兵与BOSS的相对血量（Easy/Normal 杂兵血×0.8）。
- 按单位或按队伍换难度时，属性部分可以沿用数值统一已验证的属性写入路径：按两套配置的比值缩放 Health_Max/Shachi_Max/Attack/ShachiAttack。AI分支和伤害公式读的是全局难度，单只单位改不了。
- 尚未验证：游戏自带菜单能否在游戏中途切换难度，以及切换后已在场和新召唤的单位是否更新。

## v0.32.0：召唤难度下拉菜单（2026-10-31，数值已实机验证）

用户看了游戏难度菜单（入阵者/破局者/逆天者/六十六天；六十六天与逆天者难度相同，只是死亡上限66次），要求做一个下拉菜单：选哪档，召唤出来的就是哪档数值。四档对应 EDifficultMode 的 Easy/Normal/Hard/NightMare，探查读回当前1=Easy与“入阵者”一致；Handicapped 未在菜单出现。英文官方名 Wayfarer/Pathbreaker/Hellwalker/Sixty-Six Days（外部攻略网站，非游戏内读取），其他语言界面沿用英文名。

头文件新证据：`Global Config <难度>` 是蓝图变量（名字带空格），类型 `PDA_GlobalConfig_Combined_C`，定义在 `BP_RenewalNPC_C`（也在 BP_RenewalPlayer、BP_DamageInstigatorActor）。同一蓝图实现 GetGlobalCombatConfig、GetAttributeGlobalConfig、GetExecutionGlobalConfig、Get Global Combat Abilities Config、`Get Global Config` 等接口。推测原生组件通过这些接口按游戏难度从Actor自己的5个槽位取配置。

做法（`spawn_difficulty.lua`）：
- 不改全局难度、存档、类默认对象和配置资产。
- 延迟生成后、FinishSpawn前，把这只新Actor自己的5个 `Global Config` 槽位都指向所选难度的那份配置（取自它自己原来的对应槽位），逐个读回地址。读回不全就恢复原值，按游戏难度继续生成，不阻止召唤。
- 生成激活后再读回槽位，并记录 Health_Max/Shachi_Max/Attack/ShachiAttack 当前值。“跟随游戏”时也记录，便于同一单位跨难度对比。
- 选择存 `Runtime/spawn-difficulty.tsv`（SpawnDifficultyV1，写入后读回）。面板命令 `set_spawn_difficulty`，令牌放在 key_spawn 列。状态行 `spawn_difficulty_*` 带游戏当前难度。
- 移除了只读探查在 main 中的挂载（文件和测试保留）。

验收方法：同一单位（魔渊）分别用“跟随游戏(入阵者)”和“逆天者”各召一只，比较日志 `[SpawnDifficulty] 出生属性`。按配置表，攻击应约为1/0.7，杀气攻击约为1/0.33。如果数值不变，说明属性不走这些槽位，改用按配置比值缩放的方案。离线测试：spawn_difficulty 5项、panel_runtime 21项、bridge 21项、main_boot（npc/actor）、后端55项通过。43个Lua部署哈希一致，BUILD=v0.32.0-spawn-difficulty。备份在 `影之刃0-backups/v032-spawn-difficulty-20261031-145425`。

**实机读回（14:55–14:57，UE4SS.log 2987–3097）**：v0.32.0 加载后，用户在助手里选了六十六天（`设置读回 level=NIGHTMARE 游戏难度=Easy`），召唤了魔渊和阿花。两只的槽位写入读回都是5/5，生成后槽位读回也是5/5。对比同两类单位此前在 Easy 下的实机读数（StatMatch 基准日志，魔渊2次、阿花9次，数值一致）：

| 单位 | 难度 | Health_Max | Shachi_Max | Attack | ShachiAttack |
|---|---|---|---|---|---|
| 魔渊 | Easy（游戏） | 12000 | 1200 | 84 | 39.6 |
| 魔渊 | Nightmare（本Mod） | 12000 | 2400 | 120 | 120 |
| 阿花 | Easy（游戏） | 9000 | 800 | 70 | 33 |
| 阿花 | Nightmare（本Mod） | 9000 | 1600 | 100 | 100 |

比值和配置表吻合：Attack ×1/0.7、ShachiAttack ×1/0.33、Shachi_Max ×2，血量不变。Shachi_Max ×2 = (1×0.8)/(0.5×0.8)，说明全局修正和类型修正是**相乘**的；如果按 GAS 的加法累计，比值会是 0.8/0.3≈2.67。两只都是BOSS类，BOSS的 Health_Max 在各难度都是1.0，所以血条不变。用户看血条以为没生效，其实是预期结果。杂兵类（Mob/Standard）的血量在 Easy 是0.8，在 Hard/Nightmare 是1.0，才会看出血量差别。

结论：按单位切换难度的方法有效，游戏全局难度保持 Easy。AI 是否随之改变还没有证据。

## v0.32.1：AI难度只读探查（2026-10-31，已实机读回）

新证据：`PDA_GlobalConfig_Combined_C` 由 Combat/Mechanic/Technical 三个子配置组成，并提供 GetDecisionTreeOverride、GetAdditionalDecisionTrees、GetAbilityPool、GetStrategyConfig、GetDefaultAIScripts、GetDefaultParameterCollection(Pawn) 等AI相关取值函数。Combat 配置还有 `OverrideAIParameters`（FSGameAIParameterCollection：Bool/Int/Float/…/Name 共11张参数表）。行为树里的难度节点 `BTDecorator_SwitchDifficulty_C` 是**蓝图**装饰器（PerformConditionCheckAI(OwnerController, ControlledPawn)，字段 Difficulty），路径在 `/PBZCombatAsset/Prototypes/AI/`。

`ai_difficulty_probe.lua`（只读）：
- 游戏就绪后对比5档 Combined 的三个子配置引用、逐字段差异（结构体字段标为“未比较”），并列出每档的 OverrideAIParameters。
- 开战后开150秒窗口，挂钩难度装饰器（蓝图单回调）以及 GetDiffcultMode/GetDifficulty（原生pre/post），按调用者类、节点难度、是否本Mod单位（队伍/难度）计数并各记一次首见。时间到注销挂钩，并输出计数汇总。不返回值，不写字段。
- 离线测试用拒绝写入的夹具通过；main_boot（npc/actor）及全部Lua测试通过。44个Lua部署哈希一致（游戏目录与应用安装包），BUILD=v0.32.1-ai-difficulty-probe。

**实机读回（UE4SS.log 自3701行 v0.32.1 加载起）**：用户重载后，用六十六天召了魔渊（蓝）和阿花（红），然后开战。

- 数值再次读回：魔渊 12000/2400/120/120，阿花 9000/1600/100/100，与上一轮一致。
- 配置对比只跑完 Combat Config 的前几个字段就中断：`attempt to compare number with boolean`。原因是 `U.field` 返回 (值, 读取标志)，第二个返回值被当成了 depth。已修复，并在测试里补了数组字段。已读到的差异：
  - Mob Break Duration：3/3/4/4/4。
  - Mob SimpleExe Break Duration：4/5.5/4/4/4。
  - Player Break Duration：3/2/3/3/3。
  - DynamicBreakAdditionalDuration：17/16/11/11/11。
  - DynamicBreakReductionRate：0.012/0.01/0.014/0.014/0.014。
  - **Deflect Perfect Window Frames：8/10/8/8/6**（Nightmare 的玩家完美格挡窗口比 Hard 更短，这是 Hard 和 Nightmare 第一处读到的差别）。
  - Deflect Perfect Window Frames On Break：12/14/12/6/6。
  - 以上顺序为 Handicapped/Easy/Normal/Hard/Nightmare。Mechanic/Technical 与 OverrideAIParameters 未读到。
- 行为树装饰器 `BTDecorator_SwitchDifficulty_C` 在这两只单位上**未加载**（挂钩暂不可用）。它们实际用的是另外两个蓝图节点，头文件导出里都没有：
  - `BTDecorator_AboveDifficulty_C`：实例在单位自己的AI控制器下，路径 `BP_PBZAIController_C_…​.SGameBehaviorTreeComponent.BTDecorator_AboveDifficulty_C_0`。
  - `AICondition_AboveDifficulty_C`：在共享的技能池资产里，路径 `/PBZCombatAsset/ActorData/Mobs/042_AHua/AIConfig/AbilityPool_AHua_GuiTouDao_Normal…:AICondition_AboveDifficulty_C_8`。
- 两者都调用 `UPBZBlueprintFunctionLibrary.GetDifficulty(ContextObject)`，调用会经过 Lua 挂钩。150秒窗口内共有 GetDifficulty 366 次、GetDiffcultMode 70 次，按上下文分：
  - 阿花本体 159 次，魔渊本体 111 次（上下文就是本Mod单位，已识别为 red/Nightmare、blue/Nightmare）。
  - AboveDifficulty 行为树节点 35 次（通过外层链识别为阿花）。
  - 技能池条件 60 次（上下文是共享资产对象，无法归属到单位）。
  - World 70 次（GetDiffcultMode）。
  - 地图原生 BP_Renewal_Hun_C 1 次。
- 推论：AI 的“难度高于X才做”判断走的是 GetDifficulty 这一个函数库入口。它返回的是全局难度（此前读回1=Easy），所以本Mod单位现在是 Nightmare 数值、Easy 的 AI 分支。要让它们使用逆天者的AI，可以只对归属本Mod单位的调用改写 GetDifficulty 的返回值。尚未验证的有两点：UE4SS 能否改写这个原生函数的返回值；技能池条件这类共享上下文的调用，怎样知道正在评估哪只单位。

## v0.33.0：按单位改写AI难度查询（2026-10-31，后回调改写失败）

用户确认要让召唤单位的AI也按所选难度行动。UE4SS 开发版文档（docs.ue4ss.com/dev，RegisterHook）写明：回调返回非nil值时，会转换成UE值并替换原函数的返回值；返回nil保持原值。`/Script/` 路径有前后两个回调。本机 UE4SS 是 v3.0.1-1185-gdff435dd 实验版，这个行为是否已包含要靠读回确认。

`ai_difficulty.lua`：
- 第一只带难度的单位出现后，才对 `PBZBlueprintFunctionLibrary:GetDifficulty` 和 `GetDiffcultMode` 注册前后回调。前回调为空，后回调只在上下文属于本Mod选了难度的单位时返回该单位的难度值（Easy=1…Nightmare=4）。
- 归属判断：沿外层链最多8级查找，是本单位，或某级是控制器且 `K2_GetPawn` 是本单位。结果按地址缓存，每个tick清空。单位离场后，`spawn_difficulty:prune` 会删掉它的难度记录，避免地址复用后被误判。
- 地图怪、玩家、World 一律返回nil，即保持游戏难度。共享技能池里的 `AICondition_AboveDifficulty_C` 无法归属到单位，不猜，只计数为“未归属”。
- 读回：每只新单位在 Lua 中调用一次 `GetDifficulty(单位)`（期望为所选值）和 `GetDifficulty(World)`（期望为游戏值）。只读记录两个 AboveDifficulty 类的字段、函数及参数，以及首个实例的字段值，为后面处理共享条件做准备。每分钟输出一次计数汇总。
- 只读探查的战斗窗口关闭，保留配置对比（已修复两返回值的bug）。
- 离线：ai_difficulty 测试模拟 UE4SS 的后回调返回值，覆盖：未选难度不挂钩、读回、单位/控制器/行为树节点归属、地图怪与World不变、共享条件不猜、silence。全部Lua测试和后端55项通过。45个Lua部署哈希一致，BUILD=v0.33.0-ai-difficulty。

**v0.33.0 实机读回（UE4SS.log 自800行加载）**：
- 配置对比完整跑通。三个子配置中，Mechanic、Technical 五档共用同一个资产（`GlobalConfig_Mechanic`/`GlobalConfig_Technical`），只有 Combat 按难度分开，共16个字段不同。
- **OverrideAIParameters 按难度不同**：
  - Easy/Normal：autocombo权重=200、套路权重=100、非autocombo权重=200、非套路权重=600。
  - Hard/Nightmare：autocombo权重=100、套路权重=100、非autocombo权重=400、非套路权重=400，另加 MetaAI-自动切换Leader最小/最大时间=2/4。
  - Handicapped：空。
  - 这张表在角色自己的 Combat 配置里，按单位换槽位后理论上会一起换。是否被AI读取尚未读回。
- 其他差异：Player/Mob 破防时长、动态破防、格挡完美窗口（Nightmare 6帧，比 Hard 的8帧更短）、格挡快速点击惩罚、终极技充能倍率（Handicapped 特殊）、怪物等级偏移，以及已知的属性修正表。
- 改写失败：两只单位（魔渊、阿花，均 Nightmare）的 Lua 读回 `GetDifficulty(单位)` 都返回1（期望4），World 返回1。一分钟汇总为改写=0、未归属=0。说明后回调（第三参数）对这个原生函数**从未执行**；v0.32.1 用前回调能观察到调用。不能据此断定返回值改写本身不可用。
- 新证据：两个检查节点的类结构。
  - `AICondition_AboveDifficulty_C.EvaluateCondition(AIController) → bool`。
  - `BTDecorator_AboveDifficulty_C.PerformConditionCheckAI(OwnerController, ControlledPawn) → bool`。
  - 两者的局部变量都是 GetDifficulty → ByteToInt ×2 → GreaterEqual_IntInt，即 `GetDifficulty(self) >= Difficulty字段`。共享技能池条件带有 AIController 参数，因此可以按参数归属到具体单位。

## v0.33.1：前回调改写 + 直接改写两个检查节点（2026-10-31，已实机验证）

- GetDifficulty/GetDiffcultMode 的前、后回调用同一套判断，都返回本单位的难度值，并分别计数哪个回调真的执行。
- 两个蓝图检查节点在类加载后挂钩（非 /Script/ 路径，单回调在函数执行后运行）。按参数（共享条件用 AIController，行为树节点用 ControlledPawn）归属到本Mod单位，返回 `单位难度值 >= 节点Difficulty`。非本Mod单位返回nil。首次调用时记录全部参数的类型。
- 读回：
  - 每只单位在 Lua 中调用 `GetDifficulty(单位)` 和 `GetDifficulty(World)`，并附上前、后回调的计数。
  - 每类检查节点记下第一次改写时的节点和参数，再用 Lua 用同样参数调用一次。日志给出期望值、返回值，以及游戏难度下应得的答案，并注明“可区分/不能区分”（门槛不高于游戏难度时两者相同）。
- 离线：模拟 UE4SS 前后回调和蓝图单回调的返回值覆盖，测试覆盖：共享条件按控制器归属、地图怪用同一技能池仍按游戏、行为树节点、离场后恢复。全部Lua测试通过。45个Lua部署哈希一致，BUILD=v0.33.1-ai-difficulty-checks。

**v0.33.1 实机读回（UE4SS.log 自800行加载）**：六十六天下召唤魔渊（蓝）、阿花（红），开战约两分钟。
- **GetDifficulty 前回调改写生效**：Lua 读回 `GetDifficulty(魔渊)=4`、`GetDifficulty(阿花)=4`，`GetDifficulty(World)=1`，结果均为 true。
- 前、后回调都会执行（各162次/370次），但后回调从未把上下文归属到单位，只有前回调的“改写”日志。结论：本机 UE4SS 采用的是**前回调的返回值**；后回调里拿不到可用的上下文参数。
- 被改写的上下文：魔渊本体、阿花本体、`BTDecorator_AboveDifficulty_C`（经控制器归属到阿花）。
- 检查节点：
  - 行为树节点参数为 (BP_PBZAIController_C, 阿花)，共享技能池条件参数为 (BP_PBZAIController_C)，都能归属。两类节点的门槛都是 **3（Hard）**。
  - Lua 用同样参数调用读回：期望 true、返回 true；按游戏难度应为 false，因此**可区分**，两类都通过。
  - 两分钟累计：EvaluateCondition 61 次、PerformConditionCheckAI 36 次，全部改写为 true。改写共402次，读回成功4、失败0。
- `GetDiffcultMode` 56次全部以 World 为上下文，无法归属，保持游戏难度。
- 结论：召唤单位的“难度≥逆天者”判断（行为树分支和技能池条件）已按单位回答六十六天，游戏全局与地图怪保持入阵者。剩余未覆盖：以 World 为上下文的难度查询，以及原生 C++ 直接读取难度的代码（伤害计算器的难度表、BOSS召唤阈值、AIScript 等级偏移等）。用户是否看到逆天者新招式，尚未有画面确认。

## v0.34.0：召唤难度含AI（2026-10-31）

- 收尾：GetDifficulty 只在前回调返回难度值，后回调为空函数；读回日志改为“前回调计数”。只读探查 `ai_difficulty_probe.lua` 从 main 移除（文件和测试保留），避免每次加载都输出配置对比。
- 状态行新增 `spawn_difficulty_ai`、`spawn_difficulty_ai_verified`、`spawn_difficulty_ai_failed`。读回失败时，界面在召唤难度下显示警告，说明只换了数值、出招仍按游戏难度。
- 界面文案（六语）：选中难度时提示“之后召唤的单位按「X」生成”；说明改为“数值和AI的难度判断都按所选难度生效，不改存档难度”。
- 全部Lua测试、panel_runtime 21项、后端55项通过。45个Lua部署哈希一致；应用的 ui/backend/payload 已同步，modBuild=v0.34.0-difficulty-ai。

**v0.34.0 实机读回（15:41 加载，UE4SS.log 自1783行）**：用户在助手里选逆天者（`设置读回 level=HARD`），召唤魔渊、阿花并开战约三分钟。
- 数值：两只的槽位都是5/5。魔渊 12000/2400/120/120，阿花 9000/1600/100/100，与六十六天一致（两档的数值表相同）。
- AI：`GetDifficulty(魔渊)=3`、`GetDifficulty(阿花)=3`、`GetDifficulty(World)=1`。行为树节点和技能池条件的读回都是“门槛3，期望true，返回true，游戏难度下应为false（可区分）”。三分钟累计改写534次，读回成功4、失败0。后回调已改为空函数，日志里只有前回调计数，改写照常生效。
- 结论：收尾版行为与 v0.33.1 一致，可作为 0.34.0 发布。

发布前顺带修正了升级提示：老用户从 v0.30.0 更新助手后，游戏里的模组仍是旧版。原来的“版本不一致”横幅只给“检查更新”按钮（只能更新助手本身），提示文字还会显示成“vv0.30…”。现在改为：
- 游戏未启动时，如果组件检查发现模组已装但版本旧，就显示“模组需要更新”。
- 游戏运行中版本不一致时，按钮改为“更新模组”，跳到“设置 → 游戏”，那里的“一键安装”会整体替换模组。
- 组件列表里旧版模组显示“需要更新”，不再显示“未安装”。
- 六种语言同步更新，原型演示已核对。

## v0.35.0：随从（2026-11-01，能打不跟随）

B站评论区请求“随从：BOSS或精英怪跟着，能一直跟着、随时删除”。用户决定：用官方的跟随组件，阵营里加“随从”选项，数量不限，换地图或读档后自动召回，其余由助手决定。

官方组件证据（资产注册表与头文件）：
- SGameAI 插件自带一套 NPC 助战跟随：`/SGameAI/Data/IdleStateData_Follow`（闲置状态数据 USGameAIStateData 子类，含 BehaviorTreeAsset/Bindings/AssignParameters）、`/SGameAI/BehaviorTree/SubTree/BT_SGameAI_Idle_NpcHelper_FollowPlayer`、`BT_SGameAI_Idle_Follow`、`/SGameAI/StateTree/ActionStateTree/AST_Follow_Advanced`、`/SGameAI/StateTree/Evaluator/STEvaluator_GetFollowDestination`（字段有 Move_OffsetToPlayerRange、Teleport_OffsetToCameraRange、LastResetPlayerLocation，说明落后太远会传送到镜头附近）、`BTService_FollowTarget(_New)`。
- 游戏里的助战角色：`034_EMei/BP_Monster_EMei_Crossbow_NPChelper*`、`BP_Monster_EMei_NPCHelper_XiaoJu`、`StrategyConfig_EMeiCrossbow_NPCHelper`、长枪兵 NpcHelper 动画蓝图，以及西谷“营地一 npcHelper”任务流。
- 闲置状态由 `FAISpawnInfo.IdleStateData` 决定（SGameAIComponent.SpawnInfo；关卡刷怪器配置）；我们用 SpawnAIDefered 不带刷怪器，所以默认没有闲置状态。资产依赖在 cooked 包里被剥离（reference-queries 都是 empty_or_stripped），无法反查哪个刷怪器用了跟随状态。
- 其他可用接口：`BP_SGameAIFunctionLibrary.SyncHatredList(From,To)`（召唤物共享召唤者目标）、`ForceOffCombat/ForceIntoCombat`；UFactionComponent `SetFaction/GetCurrnetFaction/SetFactionRelationOverride`。

做法（`companion.lua`，阵营 `companion`）：
- 激活前：用 StaticConstructObject 新建一个 IdleStateData_Follow 实例（外层=该单位的 SGameAIComponent），写入 `SpawnInfo.IdleStateData` 并读回地址；把单位阵营设为玩家当前阵营并读回标签；单位↔玩家关系覆盖为友好（双向）并读回。AI 在写入前已经启动的，激活后 StopAI/StartAI 一次。
- 每0.5秒：玩家仇恨列表非空时，每2秒 SyncHatredList(玩家→随从)；生成后90秒内每5秒记录距离、AI状态标签和闲置状态数据，用来判断是否真的跟随。首次加载跟随类时只读输出它的字段和函数。
- 擂台：随从不参加开战、不被“停止并清理”带走，有单独的“解散随从”（dismiss_companions）；不做数值统一；血条和抓取只管蓝红方；F2 切换顺序 蓝→红→暂不配队→随从。单位快捷键也可以绑定到随从阵营。
- 同时修正召唤难度：AI难度挂钩改为“选了难度就挂上”，不再等第一只带难度的单位出现，使新单位初始化时的难度查询也按所选难度回答（ActorConfig 里另有 `AIConfig Nightmare`，可能在初始化时按难度挑选）；读回日志增加该单位的 AI 配置（默认/噩梦/当前）。
- 自动召回（换地图/读档）留到跟随在实机验证后再做。
- 离线：companion 5项、arena_controller（含随从分组、停止保留、单独解散）、ai_difficulty（选难度即挂钩）、panel_runtime 22项、后端56项、main_boot 等全部通过；原型演示里召唤随从、停止保留、解散均正常。46个Lua部署哈希一致，BUILD=v0.35.0-companion。

**v0.35.0 实机读回（UE4SS.log 自930行，06:07–06:13，地图 PBZ_Pangzhen_WP）**：用户把魔渊绑到单位快捷键（team=companion），用六十六天召唤 1 只。
- 跟随状态写入读回 true，阵营 Faction.Enemy → Faction.Player 读回 true，双向友好 0/0。AI 出生时已启动，重启一次后状态 AI.State.Idle，跟随数据保留。
- 跟随状态类只读：自身字段 `ActorToFollow`（软指针，本轮没设）、`FollowStartDistance=500`、`FollowStopDistance=200`；继承 `BehaviorTreeAsset=BT_SGameAI_Idle_Follow`、`bLoop=true`；函数 `AssignParameters(Blackboard)`、`OnSpawnAI(Spawner,Pawn)`（图里有软引用转对象、转换为 BP_AISpawner、`SetValueAsFloatByTag`）。即跟随目标和距离靠黑板“按标签”写入。
- 召唤约5秒后进入 AI.State.Combat，此后90秒观察期内一直是战斗状态，离玩家 2–13 m；HP 12000→约7800，被地图怪攻击。玩家仇恨列表一直为空，SyncHatredList 没有触发。
- 召唤难度部分：魔渊 `AIConfig  Default` 和 `AIConfig Nightmare` 都是 AIConfig_MoTian，魔渊没有单独的噩梦AI。AI难度挂钩在召唤前已经装好（出生时就有 `改写 GetDifficulty(pre) 上下文=BP_Monster_MoTian_C`）。
- 用户画面：**能正常和地图怪打架；没有跟随，也没有传送；随从和玩家互相不造成伤害。**

## v0.35.1：跟随目标、走/跑、100米传送（2026-11-01，召唤时原生崩溃）

用户要求：5 米内走路，10 米外跑步，100 米直接传送；正在和 BOSS 打的时候不传送。
- 跟随目标：创建跟随状态时尝试 `ActorToFollow=玩家`（软指针，Lua 是否能写入未知）。黑板出现后，列出全部键（名称、类型、对象值），调用一次 `AssignParameters(黑板)`；名字含 follow 的对象键全部写成玩家并读回。非战斗时每2秒检查一次，被清空就再写回。
- 走/跑：用角色自己的 `SetMovementMode(标签)`（BP_RenewalNPC），标签取 GlobalConfig_Mechanic 的 `Walking Tag`/`Jogging Tag`。非战斗时距离 ≤10 m 走、>10 m 跑；被 AI 自己的移动模式服务改掉时，最多每2秒再设一次。读回 `AIMovementMode`。
- 备用跟随：距离超过 5 m（官方起跟距离）且3秒内没有靠近 0.5 m 以上时，改用引擎的 `AIController.MoveToActor(玩家, 2m)`，每2秒重发。日志区分“官方跟随在靠近”和“备用跟随”。
- 传送：距离 ≥100 m 时传送到玩家身边 2.5 m（`K2_TeleportTo`，保留朝向，冷却3秒）。随从或玩家的仇恨列表里有 BOSS（`Actor Config` 的 Difficulty Tag 以 Boss 结尾）时不传送。
- 状态变化（Idle/Combat 等）全程记录，上限40行。
- 离线：companion 新增一项（跟随键、走/跑、卡住改用 MoveToActor、100米传送、BOSS战不传送）；全部 Lua 测试通过。46个Lua部署哈希一致，BUILD=v0.35.1-companion-follow。

**v0.35.1 崩溃（06:20:06，crash_2026_11_01_06_20_06.7456130.dmp）**：用户按召唤后游戏崩溃。本局运行日志 `Runtime/run-20261101-061923.log` 的最后一行是“官方跟随状态类 …”的只读描述（在 prepare 里加载跟随类时打印），没有出现 prepare 结尾的“准备 unit=…”。按代码顺序，接下来依次是：新建跟随状态对象、写 SpawnInfo.IdleStateData（v0.35.0 同样做过，没崩），以及本版新增的 `state.ActorToFollow=player`。

结论：**用 UE4SS Lua 给 `TSoftObjectPtr` 属性直接赋 UObject，会导致原生崩溃，pcall 拦不住。**不要再这样写软指针。

## v0.35.2：去掉软指针写入（2026-11-01，待实机读回）

- 删除 ActorToFollow 写入，跟随对象只通过黑板写入：`AssignParameters(黑板)`，再把名字含 follow 的对象键 `SetValueAsObject` 成玩家。
- 备用跟随从 `AIController.MoveToActor(…, FilterClass=nil, …)` 改为 `AIBlueprintHelperLibrary.SimpleMoveToActor(控制器, 玩家)`，避免给类参数传 nil。
- 测试夹具会记录对跟随状态对象的任何写入，并断言写入次数为 0，防止以后又写回去。全部 Lua 测试通过；46个Lua部署哈希一致，BUILD=v0.35.2-companion-follow。

## v0.35.3：难度挂钩改为按需、轻量（2026-11-01，待实机读回）

用户反映“游戏一卡一卡的”。本局（06:24:02 起，PBZ_Pangzhen_WP）还没召唤任何单位。06:24:59 因为召唤难度选着六十六天，v0.35.0 起的“选了难度就挂钩”立即注册了 GetDifficulty/GetDiffcultMode 挂钩。之后地图上**每只怪**每次查询难度，都会进入 Lua 回调做归属判断：沿外层链最多8级；每级 `U.key/U.valid` 都会经引擎有效性检查（原生 Kismet IsValid）；还会对每个对象 pcall `K2_GetPawn`（非控制器会抛 Lua 错误）。缓存每0.5秒清空一次。怪多的大地图上，这是卡顿的主要嫌疑。没有逐帧计时证据，修复后由用户对比确认。

修改（ai_difficulty.lua）：
- 只挂 `GetDifficulty`。`GetDiffcultMode` 在 v0.32.1–v0.35 的日志里只出现过 World 上下文，从未被本Mod单位使用。
- 不再“选了难度就挂钩”。改为在出生路径上调用 `ensure(单位, 难度)`：main 的 FinishSpawnViaAILib 在 spawn_difficulty 写入槽位之后、FinishSpawn 之前调用，所以单位初始化时的难度查询仍会被回答。最后一只带难度的单位离场10秒后，摘掉全部挂钩（含两个蓝图检查节点）。
- 归属改为查表：每个 tick 把带难度单位及其控制器的地址建成索引；回调里只读上下文对象、它的外层、外层的外层这三个地址，不做有效性检查，结果缓存到下一个 tick。日志消息只在第一次出现时才拼接。检查节点的门槛直接读 `node.Difficulty`。
- 离线：ai_difficulty 测试覆盖“没有带难度单位不挂钩、出生前挂钩并立即回答、单位/控制器/行为树节点归属、单位离场10秒后摘除全部挂钩”；全部 Lua 测试通过。46个Lua部署哈希一致，BUILD=v0.35.3-light-hooks。

## v0.35.4–v0.35.5：随从跑步、少打断、投技、卡顿计时（2026-11-01，待实机读回）

v0.35.3 实机（run-20261101-063110.log，06:31–06:36，PBZ_Pangzhen_WP）：
- 用户反馈：随从会跟着人走，但不会跑；卡顿又出现了；随从的投技对地图原生怪不起作用。
- 日志：
  - 黑板共49个键，跟随对象键指向玩家，读回1/1。
  - 移动模式标签：走路 `CharacterState.Native.Attitude.Walking`，跑步 `…Jogging`。切到 Jogging 读回正确，但画面上仍是走路。
  - 官方跟随从未让它靠近（没有“官方跟随在靠近”一行），全靠备用 SimpleMoveToActor，每2秒重发一次，距离一度拉到 48 m。
  - GetDifficulty 挂钩每分钟只调用几十到几百次（464/174/30），量不大，不像卡顿主因。
- 用户确认魔渊是人形NPC，跑步用冲刺即可。

修改：
- 跑步改用 GlobalConfig_Mechanic 的 `Sprinting Tag`（构建里没有时退回 Jogging）。走/跑被AI改回时，最多每5秒再设一次（原来2秒），日志同时记录 CharacterMovement.MaxWalkSpeed。
- 备用跟随不再每2秒重发：只有 `AIController.GetMoveStatus()` 不是 Moving(3)，并且距上次下令已超过3秒，才重新下 SimpleMoveToActor。走向某个 Actor 的移动会一直追着它，重发反而会打断起步。
- 投技：arena_grabs 的范围改为“开战且蓝红都有活单位时的蓝红族”加上“任何时候在场的随从族”。随从在场时，它所属族的共享 `BP_BulletEvent_Grab.NonPlayerGE` 会清空，让投技对地图怪走完整的双人动作；随从全部离场后恢复。共享资源和恢复记录的机制不变（见 NPC_GRABS.md）。Config.EnableNPCGrabs=false 时传空名单，整个功能关闭。
- 卡顿排查：
  - 投技事件重扫是 FindAllOf 全对象遍历。只有随从时改为每30秒一次，交战中仍是5秒。
  - 新增 `[Perf]` 日志：支持循环超过10 ms 时记录各步骤耗时（prune/aiDifficulty/companions/freeCamera/summonLinks/activity/grabs/reinforce/bossHUD），整个面板轮询超过15 ms 时也记录，各最多60行。
- 离线：companion（冲刺、移动中不重发、停下后重发）、arena_grabs 9项（新增“随从单独在场时启用，解散后恢复；只有蓝方时不启用”），以及全部 Lua 测试通过。46个Lua部署哈希一致，BUILD=v0.35.5-companion-grabs。

## v0.35.6：真正跑起来、卡顿源头（2026-11-01，待实机读回）

v0.35.5 实机（run-20261101-064533.log，06:45–06:57；魔渊之后又召了阿花，两只都是六十六天随从）：
- 用户确认：**和地图怪打架完全正常，投技对地图原生怪生效**；切换点位（快速移动）时传送生效。还是只会走、不会跑。
- 传送读回：两次各 583 m / 573 m 的远距离（用户快速移动后）都传送到 2.5–2.7 m 内；另有一次原距离 1001292.5 m（切图过程中的坐标）也传送成功。
- 移动模式：切到 `CharacterState.Native.Attitude.Sprinting`，调用和读回都成功，但 `CharacterMovement.MaxWalkSpeed` 一直是 80（魔渊）或 100（阿花），切换前后没变。**NPC 的移动模式标签不改变速度**，速度由 AI 自己的移动服务控制（BTService/STTask_SetAIMovementMode 里有 CachedMaxWalkSpeed、ShouldWalking）。
- 备用跟随按移动状态下令，`上次移动状态=0`（Idle）时才重发，不再每2秒打断。
- **卡顿源头**：`[Perf]` 显示召唤魔渊后，支持循环每0.5秒耗时 61–75 ms，其中 `aiDifficulty=47–70ms`，其余各步都在0–2 ms（另有 grabs=17 ms 只出现一次，是投技事件重扫）。原因是 aiDifficulty 每个 tick 都对两个蓝图检查节点函数调用 StaticFindObject，而魔渊的 AI 不用这两个节点，类未加载、查找失败。**UE4SS 里查找一个不存在的对象路径很慢**（每次约30 ms）。

修改：
- aiDifficulty：蓝图检查节点的查找最多每15秒一次。
- 随从跑步：超过10 m 且不在战斗时，直接把 `CharacterMovement.MaxWalkSpeed` 设为跑步速度。取值为该角色 ActorConfig `Sprint Parameters.ExplicitWalkSpeed`、玩家当前 MaxWalkSpeed×1.1、500 三者中的最大值。每个 tick 若被AI改回就再设一次。回到10 m内或进入战斗时，恢复它最初的走路速度。移动模式仍按走路/冲刺切换。
- 离线：companion（跑步速度、被改回后再设、10 m内恢复）、ai_difficulty（查找每15秒一次）及全部 Lua 测试通过。46个Lua部署哈希一致，BUILD=v0.35.6-companion-run。

## v0.35.7：跑步速度改走移动驱动（2026-11-01，待实机读回）

v0.35.6 实机（run-20261101-070524.log，07:05–07:07）：
- 卡顿已消除：`[Perf]` 只剩召唤时的单次 19–25 ms（companions 8–9 ms 是首次加载跟随类和黑板，grabs 5–13 ms 是投技事件扫描），aiDifficulty 降到 1–2 ms。
- 跑步：阿花和魔渊的跑步速度都取 1045（冲刺配置 ExplicitWalkSpeed=-1，即未配置；玩家 950×1.1）。直接写 `MaxWalkSpeed` 当下读回 1045，但切回走路时读到的已经是 80，说明下一帧就被改回。用户画面上仍然只会走。
- 阿花在离玩家 34.4 m 处不动：每5秒重发一次 SimpleMoveToActor，移动状态一直是 Idle，位置不变（疑似路径不可达）。用户猜阿花可能本来就没有跑步动画，魔渊应该有。

头文件证据：`ULocomotionDriverComponent`（角色字段 `Locomotion Driver`）提供 `UseCustomMaxSpeed(MaxSpeed, HasBlendArgs, ExplicitBlendArgs)`、`UseCustomMovementParameters` 和 `StopUseCustomMovementParameters`。速度由它按当前移动参数每帧维护，直接写 CharacterMovement 会被覆盖。

修改：跑步时调用一次 `Locomotion Driver:UseCustomMaxSpeed(跑速,false,{})`，1秒后读回 MaxWalkSpeed 记一行日志。回到10 m内或进入战斗时调用 `StopUseCustomMovementParameters()`，把速度交还给驱动。不再直接写 MaxWalkSpeed。离线测试和全部 Lua 测试通过。46个Lua部署哈希一致，BUILD=v0.35.7-companion-run。

## v0.35.8：跑步动作（2026-11-01，待实机读回）

v0.35.7 实机（run-20261101-070929.log）：
- 用户画面：**速度对了，但动作还是走路**，即走路动画配很快的移速。
- `UseCustomMaxSpeed(1045)` 生效，1秒后读回 1045。`StopUseCustomMovementParameters` 调用成功，但当下读回仍是 1045（可能有过渡）。
- 黑板里的官方跟随键是 `FollowTargetActor`，另有 `FollowStartDistance`/`FollowStopDistance`/`RunPointActor`。本局第一次出现“官方跟随在靠近玩家 6.3m → 5.8m”。

推测：NPC 追击用的是 Jogging，冲刺（Sprinting）状态在不少 NPC 上没有对应动画，于是退回走路动画。v0.35.3 试 Jogging 时看起来像走，是因为当时速度被压在80。

修改：跑步改用 Jogging 标签（构建里没有时才用 Sprinting），速度仍通过移动驱动设置。跑起来1秒后，只读记录一次：动画实例里名字含 gait/speed/walk/run/jog/sprint/attitude/locomotion/move/velocity 的字段及其值，以及能力组件身上含 Attitude/Locomotion/Movement 的标签，用来确认动画按什么切换走/跑。全部 Lua 测试通过；46个Lua部署哈希一致，BUILD=v0.35.8-companion-jog。

## v0.35.9：随从立即迎敌（2026-11-01，待实机读回）

用户反馈：召唤出来的随从要过几秒才去锁定敌对单位。日志佐证：每只随从召唤后都要 5–10 s 才从 AI.State.Idle 转入 Search，再过约1 s 才进入 Combat（例如 07:14:24 召唤魔渊，07:14:34 进入 Search，07:14:35 进入 Combat）。推测原因：SGameAI 用“警觉值”（黑板 Awareness/MinAwareness）慢慢积累后才开战；召唤时为装跟随状态重启了 AI，感知也被清零。

修改（companion.lua）：
- 随从不在战斗时，每秒一次调用自己感知组件的 `AIPerception:GetPerceivedHostileActors(out)`（出参取 `out.OutActors`，即已经感知到、按阵营判定为敌对的单位），开销很小。
- 从中挑选：离玩家 20 m 内、HP>0、不是玩家、不是本Mod任何队伍的单位，取离随从最近的一个，调用 `SGameAIComponent:ForceIntoCombat(目标)`（斗蛐蛐开战用的同一接口）。
- 日志记录目标、距离、感知到的敌对数量和调用后的状态，最多20行。
- 没有使用全对象扫描（FindAllOf），避免再造成卡顿。

离线：companion 新增一项（选最近、排除本Mod单位/死亡/过远、每秒最多一次、战斗中不触发）；全部 Lua 测试通过。46个Lua部署哈希一致，BUILD=v0.35.9-companion-engage。

## v0.35.10：跑步动画输入采样（2026-11-01，待实机读回）

v0.35.9 实机（run-20261101-072358.log，07:24–07:29）：
- 用户先召了一只暂不配队的 YuCong，3秒后召魔渊随从。魔渊 07:24:46 召唤，07:24:47 从 Idle 直接进入 Combat（此前要5–10 s）。本局没有出现“主动迎敌”日志，说明这次是它自己当即开战的。
- 跑步：Jogging 标签读回正确，`UseCustomMaxSpeed(825)` 生效（玩家 MaxWalkSpeed=750×1.1），1秒后读回825。`StopUseCustomMovementParameters` 后最大速度要到下一次才恢复80。
- 动画实例 `PBZ_ABP_Base_Template_MoTian_C` 的相关字段（采样时随从刚停下，速度为0）：`moveState=0`、`GameplayTag_IsSprint=false`、`SpeedWalkRun`（向量）、`DisplacementSpeed=0`、`HasVelocity=false`、`SpeedMultiplier=0.01`、VelocityBlend 等。角色本身没有 `AbilitySystemComponent` 字段，标签不可读。
- 画面是否为跑步动作，用户尚未说明。

修改：只读采样。我们让它跑时每秒记一次，共8次；它自己在战斗中实际速度超过 300 时记4次。内容包括实际速度、moveState、GameplayTag_IsSprint、SpeedWalkRun(x,y,z)、DisplacementSpeed、AIMovementMode、AI状态，以及能力组件（改从 SGameAIComponent.AbilitySystemComponent 取）上含 Attitude/Sprint/Move 的标签。用来对比两种情况下动画输入的差别。全部 Lua 测试通过；46个Lua部署哈希一致，BUILD=v0.35.10-anim-sample。


## v0.36.0：趣味功能（无限杀气、自动精准防御、自动闪避红光）（2026-11-01，待实机读回）

用户要求在助手左栏加「趣味功能」页，三个开关可自由组合；自动防御要在玩家出招中也触发。三项只作用于玩家角色。

头文件依据：
- 玩家属性集（CharacterBasics.hpp）有 `Shachi`、`Shachi_Min`、`Shachi_Max`；资源索引里有 `GE_MA_Shachi_Min_1_Override`，和观战锁血用的 `Health_Min` 是同一条已验证写入路径。
- `UDeflectComponent.ReceiveFrames`（TMap<int32, FDeflectReceiveFrame>）：攻击方提前登记每一下的 `HitGameTime`(double)、`IsDodge`、`IsHit`、`DeflectStrength/Direction`、`SourceAction`。推测 `IsDodge=true` 是不能格挡、只能闪避的红光招，待日志确认。
- 玩家蓝图 `BP_RenewalPlayer` 有 `Deflect Component`。格挡被动 `BP_PlayerDeflectPassive_C` 有 `Last Deflect Click`、`Perfect Window`、`Normal Window`、`Current Perfect Window Counter`（连点惩罚），以及 `Can Activate Ability On Frame(Can Trigger Auto Deflect)`、`Try Activate Stance Ability On Frame`、`Noob  Tested Handles`；完美闪避被动 `BP_PerfectDodgePassive_C` 有 `Try Auto Dodge(Handle, Frame)`。说明游戏自带一套"新手自动格挡/闪避"，开关条件未知（推测与难度有关），本版未使用。
- Enhanced Input（UE 5.3+）：`IEnhancedInputSubsystemInterface:InjectInputVectorForAction(Action, FVector, Modifiers, Triggers)`。`FInputActionValue` 没有反射成员，Lua 无法构造，所以用 FVector 版本。

修改（fun_features.lua）：
- 无限杀气：每 0.5 s 把 `Shachi_Min` 写成 `Shachi_Max` 并读回；杀气低于上限时直接写满（记录前10次，用来判断下限是否真的拦得住）。原始下限记在 `Runtime/fun-shachi-floor.tsv`，关闭时恢复；Mod 重载后由新实例在游戏线程恢复，卸载时不写游戏对象。
- 自动防御/闪避：开关开着时注册 `LoopInGameThreadWithDelay(1)` 逐帧读 `ReceiveFrames`，用 `GameplayStatics:GetTimeSeconds(玩家)` 算距命中时间。普通帧在 `Perfect Window` 的一半（读不到时 0.06 s）之前注入 `IA_Deflect`，`IsDodge` 帧在 0.10 s 前注入 `IA_Dodge`；每个 handle 只按一次，同类按键间隔 ≥0.12 s；自由观战时暂停。注入前用 `KismetSystemLibrary:DoesImplementInterface` 确认子系统实现了接口。
- 读回：按格挡后 0.5 s 内 `Last Deflect Click` 变化 = 游戏收到按键；按闪避后 `PerfectDodgeResultData.HitGameTime` 变化 = 完美闪避；预告在命中时间前消失 = 被消耗。第一次出现预告时若 `HitGameTime` 和游戏时间相差 30 s 以上，记"时间基准对不上"并不按键。还记录两个输入动作的 ValueType 和动作级触发器、逐帧循环两秒内的实际次数、每分钟汇总。
- 助手：左栏新增「趣味功能」页（三个开关、状态行、六语），后端新动作 `set_fun_feature`（key_spawn=功能，key_start=ON/OFF）。

离线：新增 test_fun_features（设置读回、锁定/恢复下限、重载后按日志恢复、按键时机、每帧只按一次、冷却、红光走闪避、暂停、时间基准不符、接口检查）；全部 Lua 测试、后端 57 项、界面脚本测试通过。47 个 Lua 部署哈希一致，BUILD=v0.36.0-fun-features。备份在 `影之刃0-backups/v036-fun-features-20261101-080635`。测试版助手 dist/PhantomGladiator-0.36.0，桌面快捷方式已指向它。

## v0.36.1：闪避按攻击类型判断（2026-11-01，待实机读回）

v0.36.0 实机（run-20261101-081129.log，08:13–08:15，玩家对暂不配队的六十六天魔渊）：
- 输入注入可行：`DoesImplementInterface` 读回 true；10 次格挡注入后 `Last Deflect Click` 都在下一帧变化，即格挡被动收到了按键。逐帧循环约 45 次/秒，单次最多 3 ms。
- 时间基准一致：预告的 `HitGameTime` 和 `GameplayStatics:GetTimeSeconds` 同一时钟。普通帧在命中前约 0.30 s 送达，`IsDodge` 帧约 0.50 s。
- 12 条预告：11 条可格挡（强度 Normal/Light/Knockback），1 条 `IsDodge`（按了闪避，没被打中，`PerfectDodgeResultData` 未变）。只有 handle=6 被打中：它在命中前 0.002 s 才送达，来不及按。
- 预告 handle 不连续（8–13、16–26 等缺号），同一时段魔渊在掉血。推测编号是全局计数，缺号是玩家自己出招发给魔渊的帧；未验证。
- 无限杀气：`Shachi_Min` 写成 700 并读回，3 分钟内 0 次重锁、0 次补满，下限一直拦得住。
- `Perfect Window`/`Normal Window` 读回 0（可能只在格挡时计算），提前量用了默认 0.06 s。

用户反馈：有些 BOSS 除了红光，还有可以闪避的攻击，第一版没算进去。

头文件与资源依据：`EDeflectBulletType` = CantDeflect 0 / Normal 1 / BlueEye 2 / RedEye 3 / PowerAttack 4 / HoldDeflect 5，存在每条预告的 `SourceAction`（`ULGAAction_DurationBulletWithDeflectBase.DeflectBulletType`，弹幕类动作叫 `DeflectType`）。资源里有「完美红光」「完美蓝光」UI 视频、蓝光教程、`GA_Hun_PerfectDodge_TroopKick_Blue/Red` 等完美闪避反击。第一版只看 `IsDodge`，蓝光如果不带这个标记，就被当成普通攻击去按格挡了。

修改：每条预告第一次出现时读 `SourceAction` 的攻击类型和预告里的 `CounterAbility`。闪避开着时，以下情况改按闪避：`IsDodge`；类型为红光、蓝光或不能格挡；反击技能名含 `PerfectDodge`。只开格挡时，不带 `IsDodge` 的仍按格挡。日志每条预告记录类型值、判断结果和反击技能名。助手里该开关改名为「自动闪避红蓝光」。

离线：test_fun_features 新增蓝光、完美闪避反击、重击三种情况；全部测试通过。47 个 Lua 部署哈希一致，BUILD=v0.36.1-fun-dodge-types。备份在 `影之刃0-backups/v0361-fun-dodge-types-20261101-082004`（含上一局日志）。测试版助手 dist/PhantomGladiator-0.36.1，桌面快捷方式已指向它。

## v0.36.2：只按"能不能格挡"决定（2026-11-01，待实机读回）

用户明确规则：只看攻击能不能被格挡，不能格挡的就闪避。v0.36.1 按颜色和反击技能名把蓝光、带完美闪避反击的招也改成闪避，不符合这条规则，已撤回。

修改：判定只有一条。预告带 `IsDodge`，或攻击类型为 CantDeflect(0)/RedEye(3) 时算不能格挡，按闪避；其余（普通、蓝光、重击、按住格挡，以及带反击技能的）都按格挡。只开格挡时，不能格挡的攻击不按任何键。日志仍记录每条预告的类型值、反击技能名和"→格挡/→闪避"判断，可以对照实际有没有挨打来修正。开关名改回「自动闪避红光」，说明改为"红光等不能格挡的攻击"。

待确认：蓝光实际能不能格挡；有没有不能格挡、却完全不发预告的攻击（若有，日志里不会出现它，需另找来源）。

离线：test_fun_features 改为验证红光/不能格挡→闪避，蓝光/重击/带反击→格挡，只开格挡时红光不按键；全部测试通过。47 个 Lua 部署哈希一致，BUILD=v0.36.2-fun-undeflectable。备份在 `影之刃0-backups/v0362-fun-undeflectable-20261101-082313`。测试版助手 dist/PhantomGladiator-0.36.2，桌面快捷方式已指向它。

## v0.36.3：掉血来源与格挡档位读回（2026-11-01，待实机读回）

v0.36.2 实机（run-20261101-082533.log，08:27:43–08:28:35，玩家对暂不配队的六十六天魔渊）：
- 15 条预告全部判断并按键：13 条普通（类型值=1）→格挡，2 条红光（类型值=3，IsDodge=true）→闪避。格挡被动 12/12 收到按键，没有一条 IsHit=true。本局没有出现蓝光或其他类型。
- 第二条红光带反击技能 `GA_Hun_BDEx_MoYuan_01_C`。
- 用户反馈：仍然掉血。日志没有玩家血量，无法区分是"没有预告的攻击"，还是格挡成功但不是完美档。
- 用户反馈：召出来的魔渊几刀就死。读回：魔渊 Health_Max=12000（BOSS 各难度相同），08:27:50–08:28:08 只格挡时 HP 一直 12000，只有杀气被削 2400→1996；08:28:11 起 13 秒内 HP 12000→757，同时玩家 `Shachi_Min` 当前值被游戏改成 1（基础值仍 700），每 0.5 s 都要补满杀气，说明玩家在连续消耗杀气（杀招/杀气武器）。结论：无限杀气让杀招不受限，是伤害高的原因，不是召唤数值出错。
- 杀气锁：杀气技能期间游戏会把 `Shachi_Min` 当前值压到 1，下限拦不住，由补满兜底（17 次），杀气一直在 694–700。
- 另见：`aiDifficulty` 每 15 s 查找未加载的检查节点仍有 67–70 ms 的单次卡顿（08:28:14、08:28:29），待单独处理。

头文件依据：`BP_StanceAction_Base_Player_C`（格挡技能实例）有 `Current Result Data`（FDeflectResultData，含 `DeflectResult` 标签和 `HitGameTime`）、`Perfect Pre Hit Time`、`Perfect Window`、`Great Window`、`Normal Window`，即格挡分完美/优秀/普通三档。格挡被动有 `Current Perfect Window Counter`（连点惩罚）。

修改（只加读回，不改按键规则和时机）：
- 每帧读玩家 `Health`，掉血时记录当时进行中的预告和 0.5 s 内刚结束的预告（类型、按过什么）；两者都没有就记"没有预告的攻击"。每分钟汇总加掉血次数和无预告掉血次数。
- 第一次按格挡后，慢循环每 3 s 至多一次全对象查找格挡技能实例（按 Deflect Component 匹配），记下四个时间窗口。之后每次按格挡，0.8 s 内读 `Current Result Data` 是否更新，记录结果标签（完美/优秀/普通等）；没更新也记一行。
- 按格挡被收到时，同时记被动的完美窗口、普通窗口和连点惩罚计数。
- 按键后的观察改为独立队列，不再随预告结束而中断。

离线：test_fun_features 新增"找到格挡技能后读结果档位、掉血关联刚结束的预告、无预告掉血、回血不记"；全部测试通过。47 个 Lua 部署哈希一致，BUILD=v0.36.3-fun-readbacks。备份 `影之刃0-backups/v0363-fun-readbacks-20261101-083243`（含上一局日志）。测试版助手 dist/PhantomGladiator-0.36.3，桌面快捷方式已指向它。

## v0.36.4：逐刀伤害读回（2026-11-01，待实机读回）

用户反馈：打召唤出来的魔渊，平 A 伤害高得不对劲（上一节"杀招不受限"的结论用户否认，作废）。

对照两局（都开着无限杀气、都打六十六天魔渊）：
- v0.36.0：玩家出手时杀气不减（0 次补满），魔渊每次读回掉 150–680。
- v0.36.2：玩家出手期间杀气每 0.5 s 少 3–6、`Shachi_Min` 当前值被游戏压到 1（17 次补满），魔渊每秒掉 1000–2500。

推测（未验证）：当前武器的被动按杀气（代码里叫 Anger）给平 A 加伤害并消耗杀气，例如 `UGA_SlitheringSword_PenetratePassive.AngerDamageCoefficient`、`UGA_ZhanMa_SustainedBloodPassive.AngerDamageBonusPerSecond/MaxAngerDamageBonus`（PBZCombatAsset.hpp）。无限杀气一直补满，加成就一直是满的。

修改（只加读回）：任一趣味开关开着就运行逐帧循环；每帧读本Mod召唤单位的 HP（名单由慢循环刷新），掉血时记录掉了多少、玩家杀气在这一刀前后的值、`Shachi_Min` 当前值、无限杀气开关状态；每分钟汇总按开/关分别累计伤害和次数，以及受伤时玩家杀气减少合计。验证方法：同一把武器，开着无限杀气砍一会儿，再关掉砍一会儿，对比每刀伤害和杀气消耗。

离线：test_fun_features 新增逐刀读回一项；全部测试通过。47 个 Lua 部署哈希一致，BUILD=v0.36.4-fun-hit-probe。备份 `影之刃0-backups/v0364-fun-hit-probe-20261101-084142`。测试版助手 dist/PhantomGladiator-0.36.4，桌面快捷方式已指向它。

## v0.36.5–v0.36.6：召唤单位等级、格挡按力度提前（2026-11-01，待实机读回）

用户反馈：把趣味功能全关了，打召唤出来的单位仍然"像砍小兵"。v0.36.4 的"武器被动吃满杀气"推测作废：伤害高和无限杀气无关。

v0.36.3 长局（run-20261101-083501.log，08:35–08:48，魔渊、阿花，召唤难度六十六天）读回：
- 格挡结果 52 条（另 18 次 0.8 s 内没有新结果）：Perfect 15、Normal 25、空标签 11。按力度分：Light 9/9 完美；Normal 6/26 完美；Knockback 0/4 完美。按键时距命中都在 0.041–0.060 s，时机本身分不开完美和普通，差别在攻击力度。
- 格挡被动的 `Perfect Window`/`Normal Window` 不是时长，是时间点，等于 `Last Deflect Click + 0.4`（点击后 0.4 s 内接受预告）。格挡技能实例是 `GA_Hun_Tang_Stance_C`，它的 `Perfect Pre Hit Time` 等读出 -11000/627.99 这类值，不是秒数，不能用。
- 连点惩罚计数 54 次为 0、2 次为 1，影响很小。
- 掉血：有一条预告（handle=61，普通）在命中后一直没从 ReceiveFrames 消失，导致之后所有掉血都被归到"进行中预告"，"无预告掉血=0"不可信。大额掉血 -648/-288/-272.8 发生时 0.5 s 内没有预告结束，推测来自没有预告的攻击；另有连续 -0.8/帧的持续掉血（来源未知）。
- 预告类型：普通 53、红光 4、蓝光 2、重击 4。

头文件依据：怪物属性集有 `Level`（CharacterBasics.hpp）。地图怪的等级由所在区域给出：`APBZ_MobDomain_C`（`Level Area Name`、`Level Offset`、`Offset By Difficulty`、`Level Area Table` → `DT_AIAreaLevel`，行结构 `FAIAreaLevelTableStructure{Parent, LevelOffset}`）、`AIScript_LevelOffset`、`GroupScript_Level*`、全局 `Global Mob Level Offset`。召唤单位不经过这些，推测停在类默认等级。资源索引有 `GE_MA_Level_1_Override`，可走已验证的属性写入路径。

修改：
- spawn_level.lua（v0.36.5）：召唤激活后，读新单位、玩家以及地图怪（CollectNPCs，排除本Mod单位，优先玩家 200 m 内，没有就用全部已加载）的 `Level`。召唤单位低于地图怪最高等级时写到同级并读回，同时记录写入前后的生命上限；不降级；5 s 内重复召唤复用同一次扫描。character_stats 允许写 `Level`。
- fun_features.lua（v0.36.6）：格挡提前量按力度——Light 0.06 s；其余在 0.09 s 和 0.13 s 之间轮换试验，结果行记录力度、提前量、按键时距命中。预告在命中后 1 s 仍未消失就按结束处理并忽略，直到它从列表消失。

离线：新增 test_spawn_level（提升到附近地图怪最高级、排除本Mod单位和远处、同批复用、不降级、无参照不改、远处兜底、写入未读回算失败）；test_fun_features 新增力度提前量和残留预告两项；全部测试通过。48 个 Lua 部署哈希一致，BUILD=v0.36.6-level-and-leads。备份 `影之刃0-backups/v0365-spawn-level-20261101-085021`（含 08:49 的日志）。测试版助手 dist/PhantomGladiator-0.36.6，桌面快捷方式已指向它。

### v0.36.6 实机读回（run-20261101-085517.log，08:55–08:59，趣味功能全关）

- 等级：召唤的阿花 `Level`=0，附近地图怪（白鹤门弟子 Knife/FishRod）=18，玩家=1。第一只阿花提升到 18 并读回 18.0/18.0，生命上限仍 9000。后两只召唤时没有已加载的地图怪，保持 0。
- 伤害对照：18 级的阿花 08:56:51–08:57:04 约 10 s 被打死（每秒 -540 至 -2365）；0 级的阿花 08:58:15–08:58:28 约 13 s 被打死（每秒 -630 至 -2680）。等级对受到的伤害没有可见影响，"像砍小兵"不是等级造成的。spawn_level 的作用未得到证据，发布前应撤回或重新验证。
- 用户补充：在哪里打都伤害高，不只召唤单位。用户怀疑自动防御/闪避启用了隐藏的最低难度（Handicapped）并作用到全局。读回不支持：
  - 每局 `GetDiffcultMode(World)` 都读回 1（Easy，入阵者），没有 0（Handicapped）。助手的"跟随游戏（当前：…）"用的也是这个值。
  - 本Mod所有版本（含 git 历史）都没有调用 SetDifficultMode/SetPendingDifficultMode/SetSaveGameDifficultyMode 等任何写难度的函数。
  - GetDifficulty 挂钩本局只改写了两类上下文：`BP_Monster_AHua_GuiTouDao_C`（3 次）和它的 `BTDecorator_AboveDifficulty_C`（13 次），没有玩家或地图怪。
  - 自动防御/闪避只注入 IA_Deflect/IA_Dodge 按键；关闭无限杀气时 `Shachi_Min` 已恢复到 0 并读回。
  - 本Mod唯一改共享对象的是 arena_grabs 的 `NonPlayerGE`（NPC 投技），与玩家伤害无关。游戏目录没有其他 pak/LogicMods，UE4SS 只开着默认的 CheatManager/Console 类 mod。
- 待定：伤害高是游戏本身（入阵者：普通怪攻击 ×0.7、杀气 ×0.5，破防更快，破防伤害 ×1.5）还是本Mod未知的副作用。判定方法：完全停用本Mod并重启游戏，在同一处打同样的地图怪对照。

### 停用对照（2026-11-01 09:08–09:20）

- 09:08 按用户要求停用：mods.txt `PhantomGladiator : 0`，enabled.txt 改名为 enabled.txt.disabled，原文件备份在 `影之刃0-backups/mod-disable-20261101-090849`。09:12 游戏重启，UE4SS.log 读回 `Mod 'PhantomGladiator' disabled in mods.txt.`，本Mod未加载。
- 用户结果：停用后打小兵伤害正常。09:20 已恢复两处开关，与备份逐字节一致，下次启动游戏生效。
- 这次对照有两个混杂因素：一是同时重启了游戏；二是比较的对象是地图小兵，而此前的抱怨都是针对召唤出来的 BOSS（"几刀就砍死""像砍小兵一样"）。所以它只能说明停用+重启后地图小兵正常，不能说明开着本Mod时地图小兵也异常。
- 开着本Mod时排除过的项（v0.36.6 那局 08:55，游戏 08:54:57 新启动，趣味功能全程关闭）：
  - 没有写过玩家的杀气属性（本局没有"无限杀气开始"）。
  - GetDifficulty 挂钩只在有按难度召唤的单位时存在，单位销毁后从名单移除（"移出已销毁登记…IsValid=false"），最后一只离场后挂钩摘除。所有日志里被改写的上下文只有召唤单位（魔渊、阿花、余从）、它们的 `BTDecorator_AboveDifficulty_C` 和 `BP_PBZAIController_C`，没有玩家和地图怪。
  - hatred.lua 的伤害钩子从未被调用（没有任何引用），属于废弃代码。
- 新方向（待验证）：地图怪生成时的 `FAISpawnInfo` 带 `MobDomain`（TSoftObjectPtr）和 `MobGroupName`，由此获得区域等级、分组脚本（`GroupScript_Level*`、`UMobGroupScript_FactionDamageMultiplier.FactionDamageMultipliersWithPlayer`）和 `ExtraScripts`（`AIScript_LevelOffset`、`UAIScript_FactionDamageMultiplier_opt`）。召唤单位没有区域和分组，等级为 0。出生后再把等级提到 18 没有可见效果，可能因为等级相关数值在出生时就已算好。`MobDomain` 是软指针，Lua 写软指针在 v0.35.1 导致过原生崩溃，这条路不能走。

## v0.36.7：出生前写角色等级字段（2026-11-01，待实机读回）

用户确认：开着本Mod时，只有召唤出来的怪脆，地图原有的怪正常。

头文件依据（BP_RenewalNPC.hpp）：角色本身有 `double Level`（0x0DF8，与属性集里的 `Level` 属性是两回事），旁边是 `MobGroup`、`Mob Group Bound Actor`、`Spawner`（ABP_AISpawner_C）、`SpawnerInterface`、`ExtraAIScripts`，函数有 `GetCombatLevel()`、`GetAttributeActorConfig()`、`GetAttributeGlobalConfig()`。地图怪由区域刷怪点生成，推测刷怪点在出生前写入这个等级字段，角色初始化时据此算出属性。召唤单位不经过刷怪点，字段为 0。`UAttributeComponent`（角色上叫 `Attribute Component`）另有 `GlobalConfig`、`DefaultDamageCalculator`、`PreCalculationModification`/`PreTakeDataModification`（伤害修正，结构体 0x250，不适合从 Lua 拷贝）和 `ReinitializeAttributes()`。

修改：
- spawn_level.lua 改为在 FinishSpawn 之前（召唤难度写配置之后）把召唤单位的 `Level` 字段写成玩家附近地图怪的最高等级字段（没有就用全部已加载），读回；不降级；同批 5 s 内复用扫描。v0.36.5 那种出生后改属性 `Level` 的做法撤掉，character_stats 不再允许写 `Level`。
- 激活后只读并排记录召唤单位和它参照的地图怪：等级字段、`GetCombatLevel()`、属性 `Level`、`Health_Max`、`Attack`、`Shachi_Max`、`ShachiAttack`、物理抗性与三种受伤倍率、`Resistance_Poise`、杀气防御相关两项。用来判断等级字段会不会改变初始化出来的数值，以及召唤怪和地图怪还差在哪里。

离线：test_spawn_level 改为验证出生前写字段、排除本Mod单位与远处、出生后并排记录、同批复用、不降级、无字段或无参照不改、远处兜底、写入不生效算失败；全部 Lua 测试通过。48 个 Lua 部署哈希一致，BUILD=v0.36.7-spawn-level-before。备份 `影之刃0-backups/v0367-spawn-level-before-20261101-093202`。模组开关已恢复（mods.txt=1、enabled.txt 在），需要重启游戏生效。测试版助手 dist/PhantomGladiator-0.36.7，桌面快捷方式已指向它。

### v0.36.7 实机读回（run-20261101-093725.log，09:37–09:38，死镇区域）

- 出生前：附近已加载地图怪 2 只（白鹤门弟子 Knife/FishRod），等级字段都是 18。召唤的阿花等级字段 0→18，读回 18。
- 出生后并排读回：

| | 召唤阿花（0 级，v0.36.6 及以前） | 召唤阿花（出生前写 18） | 地图怪白鹤门弟子 Knife（18） |
|---|---|---|---|
| 等级字段 / 战斗等级 / 属性 Level | 0 / – / 0 | 18 / 18 / 18 | 18 / 18 / 18 |
| Health_Max | 9000 | 104652 | 7441.92 |
| Attack | 100 | 210.9 | 147.63 |
| Shachi_Max | 1600 | 12695.2 | 1269.52 |
| ShachiAttack | 100 | 161 | 53.13 |
| 物理抗性 / 三种受伤倍率 / 韧性 / 杀气防御 | 0 / 1,1,0 / 0 / 0 | 同左 | 同左 |

- 结论（有读回）：角色的等级字段在出生前写入，就会作用到初始化出来的血量、攻击、杀气；出生后再改属性 `Level`（v0.36.5–v0.36.6）没有作用。召唤的怪"像砍小兵"的原因是等级为 0，拿的是最低一档数值。减伤类属性在两边都是默认值，不是原因。
- 玩家对 18 级阿花约 20 s 打掉约 5600（每秒约 250–1460），之前 0 级同样打法约 10 s 打死 9000。09:38:14 阿花 HP 回满一次，推测是脱战回血。
- 未决：参照"附近地图怪的最高等级"是不是用户想要的规则；附近没有地图怪时（例如前期地图或空地）目前保持 0 级。
- 用户确认（09:40）：召唤出来的怪"这下正常了"。

## v0.36.8：附近没有地图怪时沿用上次的等级（2026-11-01）

- spawn_level.lua：每次扫到地图怪，就把最高的等级字段和单位名记下来，并写入 `Runtime/spawn-level.tsv`（`SpawnLevelV1\t<等级>\t<单位>`），值变了才写。召唤时附近和已加载地图都没有地图怪，就沿用这条记录，日志写"沿用上次记录的等级"；从没扫到过就保持原等级（0）。文件损坏则忽略。
- 离线：test_spawn_level 新增"扫到后保存、无地图怪时沿用、重载后从文件沿用、换区域后更新、坏文件忽略"；全部 Lua 测试、后端 57 项、界面脚本测试通过。48 个 Lua 部署哈希一致，BUILD=v0.36.8-spawn-level。备份 `影之刃0-backups/v0368-spawn-level-20261101-094055`（含 v0.36.7 实机日志）。测试版助手 dist/PhantomGladiator-0.36.8，桌面快捷方式已指向它。沿用路径还没有实机读回。

## v0.36.9：怪物数值公式完整读回（2026-11-01）

用户要求把具体倍率查清再发评论。头文件依据：`PDA_ActorConfig."Attribute Data"`（`FPBZCharacterAttributeData`）的 MaxHealth/MaxShachi/Attack/ShachiAttack 是 `ULevelValueBase` 对象，子类 `ULevelValue_Plain{base,Grow}` 或 `ULevelValue_ScaledCurve{base,CurveScale,NormalizedCurve}`，都有 `GetValue(Level)`（SGameCombatSystem.hpp）；`EGenericValueModifyType`：Add=0、Multiply=1、AddMultiplier=2、Override=3、Max=4、Min=5（SGameUtils_enums.hpp）。

新增只读 stat_formula_probe.lua：召唤后对召唤单位和它参照的地图怪，读配置的等级取值（类型、base、CurveScale、曲线名）、在 0/1/2/5/10/15/18/20/25/30/40 级调用 `GetValue`、曲线自身 0–40 级的 `GetFloatValue`、当前难度配置里对应属性的全局系数和该单位类型系数，算出预测值，和实际属性及 `_Lv1` 属性并排记录。

实机读回（run-20261101-103933.log，死镇，地图怪白鹤门弟子 19 级；召唤难度六十六天，游戏难度入阵者）：

- 四项都是 `LevelValue_ScaledCurve`，且 **CurveScale 等于 base**，`GetValue(L) = base + base×curve(L) = base×(1+curve(L))`，在 11 个等级上全部吻合。
- 所有怪共用四条曲线：`CV_AttributeCurve_Monster_Health/Shachi/Attack/ShachiAttack`，0 级和 1 级都是 0（倍数 1）。倍数（1+曲线）：

| 等级 | 血量 | 杀气上限 | 攻击 | 削杀气 |
|---|---|---|---|---|
| 1 | 1 | 1 | 1 | 1 |
| 5 | 3.032 | 1.95 | 1.111 | 1.073 |
| 10 | 6.07 | 3.415 | 1.296 | 1.221 |
| 15 | 9.87 | 4.634 | 1.652 | 1.512 |
| 18 | 11.628 | 7.9345 | 2.109 | 1.61 |
| 19 | 12.209 | 8.9695 | 2.212 | 1.663 |
| 20 | 12.8 | 9.7515 | 2.309 | 1.73 |
| 25 | 18.51 | 12.7875 | 2.917 | 1.876 |
| 30 | 19.55 | 13.29 | 3.02 | 1.897 |
| 40 | 23.07 | 14.72 | 3.14 | 1.996 |

  完整 0–40 级曲线值见该日志 `[StatFormula] 曲线` 行。
- 基础值（角色配置里的 base）：魔渊 `ActorC_MoTian` 血 12000、杀气 3000、攻击 120、削杀气 120，类型 UltimateBoss；魔渊（龙珠 01）`ActorC_MoTian_LongZhu_01` 8000/1500/100/100，UltimateBoss；阿花 `ActorC_AHua_GuiTouDao` 9000/2000/100/100，GreatBoss；白鹤门弟子（刀）`ActorC_BaiheDisciple_Knife` 800/800/100/100，Standard。
- **魔渊 1.2 倍的出处**：`DT_CharacterAttributes` 里 `ActorC_MoTian` 的 MaxHealth_Base 是 10000，但游戏实际使用的是角色配置里的 LevelValue，base=12000。属性表和配置不一致，以配置为准。
- 难度：最终值 = `GetValue(战斗等级)` × 全局系数 × 类型系数（都是 Multiply），三只单位共 16 项全部吻合（比值 1）。本局读到的：入阵者全局 Health_Max ×1、Shachi_Max ×0.5、Attack ×0.7、ShachiAttack ×0.33；Standard 类型 Health_Max ×0.8、Shachi_Max ×0.4；六十六天无全局系数，UltimateBoss/GreatBoss 类型 Shachi_Max ×0.8。两档的 Global Mob Level Offset 都是 0，战斗等级=等级字段。
- `_Lv1` 属性 = 1 级时的值再乘难度系数（例：白鹤门弟子 Health_Max_Lv1=640=800×0.8，Shachi_Max_Lv1=160=800×0.5×0.4，Attack_Lv1=70，ShachiAttack_Lv1=33）。
- 和此前结论一致：v0.31.1 读到的魔渊入阵者 0 级 12000/1200/84/39.6 = 12000、3000×0.5×0.8、120×0.7、120×0.33。

这一节把"基础值 → 等级曲线 → 全局系数 → 类型系数"整条链读实了。区域如何给出等级（PBZ_MobDomain、DT_AIAreaLevel、各层偏移）仍只有头文件依据，没有读回。

## v0.36.0：发布（2026-11-01）

用户批准发布，要求在更新公告里写明数值问题：召唤出来的单位为什么在不同地方数值不一样。发布内容是 v0.36.0–v0.36.8 的趣味功能和召唤等级，以及上一节读实的数值公式（写进公告和 README）。

发布前的改动：
- 数值公式探针默认关闭：config.lua 新增 `Config.EnableStatFormulaProbe=false`，main 只在它为 true 时创建探针。开着时每召唤一只单位多写约 14 行日志，调查数值时再开。探针文件和测试保留。
- 格挡提前量：v0.36.6 起较重的攻击在 0.09 s 和 0.13 s 之间轮换试验，但 v0.36.6 之后的三局（085517、093725、103933）都没开自动防御，日志里没有一条格挡结果，这组试验从未在实机上运行过。发布版所有力度都按实测过的 0.06 s 按格挡（v0.36.3：Light 9/9 完美，Normal 6/26，Knockback 0/4），`Fun.HEAVY_LEADS` 列多个值时仍会轮换，留给下次试验。
- BUILD=v0.36.0-fun-levels。

发布时仍未实测：
- 附近和已加载地图都没有地图怪时，沿用 `spawn-level.tsv` 记录的等级（文件里已有死镇的 19 级记录，但还没有一次召唤走到这条路径）。
- 较重的攻击提前按能不能提高完美格挡率。
- 区域如何给出等级（PBZ_MobDomain、DT_AIAreaLevel、各层偏移）只有头文件依据；"死镇 18～19 级"是地图怪读回。

离线：Lua 47 项（含 main_boot npc/actor）、后端 58 项通过。

## v0.37.1：阵营「不倒下」和战斗用时（2026-11-01，待实机读回）

B 站有人想让杂兵打 BOSS、测要打多久，但杂兵血条撑不住。用户要求做成不冗余的形式：不新开页面，给已有的阵营加开关，给已有的胜负结果加用时。

修改：
- immortal_teams.lua：蓝方、红方、随从各一个「不倒下」开关，保存在 `Runtime/immortal-teams.tsv`（`ImmortalTeamsV1\tblue=0\tred=0\tcompanion=0`）。支持循环每 0.5 s：开着的阵营里还没锁的单位，把 `Health_Min` 基础值写成当时的 HP 并读回（和自由观战给玩家锁血是同一条写法，observer_guard.lua，v0.28.2 实机 HP 80 s 不变）；读回不到就恢复原下限，最多试 3 次，算一次失败。已锁的单位每次检查：下限被游戏改低就重写（计"重新锁定"），HP 仍低于下限就把 HP 补回去（计"血量低于下限"，用来判断下限挡不挡得住真实伤害）。关掉开关恢复每个单位原来的下限；单位离场就不再跟踪。暂不配队不提供（那是玩家自己打的）。
- 锁住的单位和原下限记在 `Runtime/immortal-floors.tsv`。Mod 重载后新实例在游戏就绪的第一轮，按记录从地图 NPC 里找回旧单位，下限仍等于当时写入值的才恢复原值，然后清空记录。卸载时不写游戏对象。
- 放在支持循环的召唤关系接管之后、增援之前：新加入的单位先锁血，再被派去打敌人。
- arena_controller.lua 战斗计时：开战后第一次读到双方都有存活单位时开始，某一方存活和读不到的都为 0 时结束；被打光的一方补了新单位就重新开始；停止并清理时清零。时间用游戏时间（GameplayStatics.GetTimeSeconds，暂停不计、跟随慢动作）。状态行 `battle_clock`（running/ended/空）、`battle_seconds`。
- 后台新动作 `set_team_immortal`（team=blue/red/companion，enabled），线上格式 team 列放阵营、key_start 放 ON/OFF；状态行 `immortal_*`。
- 助手：战场卡片蓝红两边底部、随从卡片里各一个「不倒下」小开关；两边都开时提示分不出胜负，但允许（可以看无尽对打）；交战中在「交战中」旁显示用时，结束时胜负结果和通知里写「用时 m:ss」；不倒下没生效的次数显示在战场下方。六种语言。

离线：新增 test_immortal_teams（设置读回、锁定、重新锁定、补血、加入/离场、关闭恢复、随从、写不进时三次放弃、未就绪不动、重载后按记录恢复、卸载不写）；test_arena_controller 新增计时（开始、读不到不算结束、结束、补兵重开、停止清零、没有游戏时钟不计时）；test_panel_runtime、后端新增对应用例。界面原型里实测：蓝方开不倒下后红方 BOSS 先倒下、显示「用时」；两边都开时提示并持续计时。Lua 48 项、后端 59 项通过。

待实机确认：NPC 身上 `Health_Min` 能不能挡住真实伤害（尤其是一刀超过当前血量的伤害、投技、处决类）；挡不住时补血能不能保住单位；计时与画面是否一致。

### v0.37.1 实机读回（run-20261101-123247.log）与 v0.37.2

- 不倒下：12:41:58 打开蓝方后，场上 4 只蓝方立即锁定（下限写成各自当时的 HP 5465.2 / 19767.6 / 16976.9 / 2848.9，读回一致）；12:43:03 新召的 8 只出生即锁在 19767.6。12:43:05–12:43:54 蓝 8 打红 8，红方全灭，蓝方一只未倒，`生命读回 team=blue` 在这段时间一条都没有（HP 没变），也没有"重新锁定""血量低于下限"。用户反馈"似乎没问题了"。在这之前的 12:37 两只蓝方被玩家砍死，当时只开过随从的开关（12:35:04 开、12:35:25 关），蓝方没开。
- 计时：模组侧正确（12:35:52–12:36:54 用时 62.01 s，12:43:05–12:43:54 用时 47.92 s），但助手里看不到。原因：panel_bridge.lua 每次最多写 100 项状态，`pairs` 顺序随 Lua 状态的哈希种子变化，多出的随机丢弃。这次 status.tsv 正好 104 行（100 项 + 4 个协议字段），丢了 battle_clock、fun_supported、current_count、total、arena_unreadable_count、function_keys_revision 等 12 项。按 git 统计：v0.35.0 最多 95 项，v0.36.0 加了趣味功能后最多 107 项（常见约 102 项），**已发布的 v0.36.0 每次进游戏会随机丢 2–6 项**，可能表现为助手显示未连接/未进入地图、趣味功能显示"模组较旧"、计数不对等。用户选择不单独发热修，和新功能一起发 v0.37.0。
- v0.37.2 修复：上限改为 256 项，超出时记一条日志；test_panel_bridge 新增 150 项全部写入，test_panel_runtime 检查状态项数低于 200。
- v0.37.2 召唤数量（用户要求去掉数量限制，预设改为 1、5、10、50）：单次上限 8 → 100（arena_controller MAX_BATCH、panel_bridge 数量列与回执、unit_keybinds、backend MAX_SPAWN_COUNT、助手步进器），场上总数仍不限。保留 100 是因为一批召唤在同一次游戏线程调用里完成（每只约 0.1 s），只防手滑输错数字卡死游戏。出生位置改为每排 5 个（随从每排 4 个）、间距 3 m，50 只约在前方 33 m、侧面 16 m 内；单只暂不配队仍在正前方。界面预设 1/5/10/50，输入框超过 100 自动改成 100，六语说明改为 1–100。离线：Lua 48 项、后端 59 项通过；原型里核对了预设、输入上限和召唤按钮文字。

## v0.37.3：脱离战斗后重新迎敌、画面顶部计时（2026-11-01，待实机读回）

v0.37.2 实机（run-20261101-125613.log）：50 只双锄女暴徒召唤用时约 1.4 s（一批召唤期间面板轮询 1439 ms），开战时 51 条开战请求全部读回 true，状态都是 AI.State.Combat。之后魔渊掉血是一阵一阵的：12:58:43 开战到 12:58:59 掉了约 5.3 万，随后多次长时间不掉（12:59:34–13:00:00 共 26 s，13:00:27–13:01:36 共 69 s）。用户截图：小怪"输出完一轮之后会回到原地站着"，站在出生的方阵里。以前日志里见过的状态只有 Idle、Combat、Search，Combat → Idle 的转换在随从身上出现过。推测：AI 打完一轮后退出战斗，回到出生点（SpawnInfo）待机；开战时只下达一次攻击，原来的增援逻辑只在目标死亡时才重新下达。50 只同时在场时支持循环每次 20–50 ms（activity、aiDifficulty 占大头），召唤那一下 109 ms。

修改：
- arena_controller.lua：交战中，蓝红单位的 AI 状态不是 Combat 时，按之前分配的目标重新迎敌，同一单位至多每秒一次；在 Combat 中的单位不碰（每帧强制会打断出招）。目标死亡后改为找被分配最少的敌人，不再全部挤向第一个。前 20 次逐条记录，之后每 10 s 汇总一次。
- main.lua：`inCombat` 读 SGameAIComponent.CurrentStateTag；`engage` 先补仇恨（AddHatred）再 ForceIntoCombat，读回状态。阵营关系和黑板目标沿用开战时写的。和随从的"不在战斗时每秒迎敌"是同一做法（companion.lua，v0.35）。
- battle_clock_hud.lua：助手「观战」里新增「画面顶部显示计时」开关（`Runtime/clock-hud.tsv`）。开着时，交战中在游戏画面正上方显示 m:ss，结束后保留最终用时，清场后移除。控件用和私有 BOSS 血条相同的构造方式：建一个 WB_BossHPBar 私有实例，把它的控件树换成只有一个文本（字号 30、居中、带阴影），不调用 Init，Character 指向玩家；放在视口上方居中（宽 360、距顶 14）。换地图后重建；创建失败就等下一场交战再试；Mod 重载后新实例会移除上次留下的计时（按控件树根名 PG_ClockRoot 识别，不碰 BOSS 血条）。
- 后台动作 `set_clock_hud`（key_start=ON/OFF），状态行 `clock_hud_*`；六语。

离线：test_arena_controller 新增重新迎敌（在战斗中不动、出战斗后按原目标拉回、每秒至多一次、回到战斗后不再强制、目标死后找被打最少的敌人）；新增 test_battle_clock_hud（格式、设置、显示/更新/保留/移除、换世界、失败重试、重载后清理且不碰 BOSS 血条）；后端、面板运行时各加一项。Lua 49 项、后端 60 项通过。原型里核对了开关、提示和通知。

待实机确认：重新迎敌后 BOSS 是否持续掉血、单位是否还会成片回到原地；50 只时的卡顿是否可以接受；游戏画面上的计时是否出现在正上方、字是否清楚。

## v0.37.4：不死不休、减少多单位时的每轮开销（2026-11-01，待实机读回）

用户问能否改成"不死不休"，不用定时检查。头文件依据：`BP_SGameAIComponent_C`（`/SGameAI/BP_SGameAIComponent`）覆写了 `ShouldExitCombatAfterAction`，另有 `ForceOffCombat`、`ForceIntoCombat`、`Set Current State`、`StateBlockMap`。AI 每打完一个动作调用前者决定是否退出战斗。

修改：
- combat_lock.lua：交战中（开战且蓝红都有存活）挂钩 `ShouldExitCombatAfterAction`，对本 Mod 蓝红单位的 AI 组件回答 false（不退出），其他 AI 照游戏原答案；用的是 ai_difficulty.lua 已实测的蓝图挂钩方式（回调在函数之后运行，非 nil 返回值即结果）。战斗结束后立即不再改写，10 s 后摘钩；AI 组件地址按单位缓存，每轮只做一次 GetAddress。前 20 次改写逐条记录，摘钩时记合计。
- 重新迎敌降为保险：每 2 s 检查一次（原来每 0.5 s、每只每秒一次）。
- 每轮开销：支持循环一轮只取一次单位名单和状态（以前十来个模块各自调用，每次都要逐个单位向引擎确认存活）；不倒下锁住的单位每轮只读一次血量，血量低于锁定值时才做完整属性读写；activity 已稳定的单位每 5 s 才复查一次，F6 只读采样每轮最多 4 只（以前 50 只每 5 s 写 51 行日志）；趣味功能每帧的单位受击探测在场上超过 4 只时停止；场上超过 12 只时，每只单位的血量变化日志至多 5 s 一条（倒下时总会记）。

离线：新增 test_combat_lock（只在交战时挂钩、只改蓝红、其他 AI 不变、战斗结束 10 s 摘钩、再开战重挂、单位离场不再回答、找不到函数时只报一次）；test_immortal_teams 新增"锁住时不做属性读写、跌破才补"；test_arena_activity 改为 10 轮复查一次并新增大批单位采样上限；重新迎敌测试改为 2 s 间隔。Lua 50 项、后端 60 项通过。

待实机确认：挂钩后蓝红单位是否一直留在战斗里（日志"留在战斗中"计数、重新迎敌汇总应很少）；50 只时 `[Perf] 支持循环耗时` 是否明显下降。

### v0.37.4 实机读回（run-20261101-132433.log）与 v0.37.5

- 每轮开销下降：50 只时支持循环 14–24 ms（v0.37.2 是 20–50 ms），activity 平时 0–1 ms，immortal 1 ms。
- 退出战斗挂钩生效（`留在战斗中` 持续出现），但单位仍然成批掉到 AI.State.Idle：保险的重新迎敌每 10 s 触发 41–96 次，共 880 次；用户描述"经常反方向慢慢走，像没锁定 BOSS，然后突然回头"，截图只有一小撮在打。魔渊 13:26:42 剩 2848 血后 75 s 没再掉血，重新迎敌一直在触发。
- 关键读回：每次迎敌都要先补仇恨，官方 `AddActorToHatredList` 每次都没把魔渊加进去，于是走数组直写（`参赛者配对数组写入` 一局 1632 次）。即仇恨管理器不接受另一只怪物当目标，直写的条目随后又被去掉，单位没有可仇恨的对象，就退到 Idle 往出生点走；保险每 2 s 拉回一次，于是"走开、回头"反复。ShouldExitCombatAfterAction 只是退出途径之一。
- v0.37.5：combat_lock.lua 交战中再挂钩 `BP_SGameHatredManagerComponent_C`（`/SGameAI/Tools/Hatred/`；BP_PBZHatredManagerComponent 没有覆写）的 `CheckCanHatredTarget` 和 `CheckActorCanBeHatred`：仇恨管理器属于本 Mod 蓝红单位、被问的是对面阵营的本 Mod 单位时回答 true，其他（同阵营、暂不配队、随从、地图怪、玩家）照游戏原答案。`RemoveActorFromHatredList` 只观察：本 Mod 对阵双方之间的移除计数并记录前 8 条。每 10 s 汇总四项计数，摘钩时记合计。蓝图之间的调用能不能被 UE4SS 挂钩拦到尚未验证，看计数即可判断。
- 离线：test_combat_lock 改为四个挂钩（只在交战时、只放行对面阵营、移除只计数、10 s 汇总、摘钩、再开战、单位离场、缺函数照常挂其余）。Lua 50 项、后端 60 项通过。

待实机确认：`允许仇恨` 计数是否出现；`参赛者配对数组写入` 和重新迎敌次数是否大幅下降；画面上是否不再成批走开。

### v0.37.5 实机读回（run-20261101-133317.log）与 v0.37.6

- 四个挂钩都注册成功。仇恨检查改写生效：每 10 s `允许仇恨` 65–309 次、`允许被仇恨` 同数；`RemoveActorFromHatredList` 移除对阵双方的次数为 0；退出判断每 10 s 改写 162–369 次。
- 但单位仍然掉回 AI.State.Idle：重新迎敌每 10 s 34–100 次（共 502 次，和 v0.37.4 相近）；迎敌前官方加仇恨仍多数失败，`参赛者配对数组写入` 491 次。魔渊 24 s 内掉到 6.8 万，之后 40 s 只掉了 1.2 万。
- 结论：这两条都不是全部原因。仇恨条目不是被 RemoveActorFromHatredList 移掉的（可能是整表清空，或脱战根本不看仇恨表）；官方 AddActorToHatredList 内部的检查很可能不经过我们挂的蓝图入口（蓝图之间的调用拦不到），或另有门槛。
- v0.37.6（只加观察，不改行为）：交战中再挂 `CallTransition`、`Set Current State`、`ForceOffCombat`（AI 组件）和 `RemoveAllActorsFromHatredList`、`ClearNPCHatredForOwner`（仇恨管理器），只对本 Mod 蓝红单位计数，按标签汇总，每个标签前 3 条逐条记录；重新迎敌记录迎敌前仇恨表长度和离目标距离；保险间隔从 2 s 缩到 1 s。
- 离线：test_combat_lock 改为 9 个挂钩并验证观察计数与汇总；重新迎敌测试改为 1 s。Lua 50 项、后端 60 项通过。

### v0.37.6 实机读回（run-20261101-134149.log）与 v0.37.7

- 脱战路径找到了：每次都是 AI 组件 `CallTransition(AI.Transition.CombatToIdle)` → `Set Current State(AI.State.Idle)` → 仇恨管理器 `RemoveAllActorsFromHatredList`（整表清空，不是逐个移除）。`ForceOffCombat`、`ClearNPCHatredForOwner` 一次都没有；`RemoveActorFromHatredList` 移除对阵双方只在两段时间各出现几十次。
- 频率：每 10 s 约 50–98 次 CombatToIdle，50 只蓝方即每只约 10 s 一次，节奏均匀，像计时触发；三场战斗都一样。脱战时距魔渊 1.9–9.0 m、仇恨表已为 0（拉回时测）。所以不是距离或仇恨检查的问题，是 AI 状态机自己在打一阵后切回 Idle；`ShouldExitCombatAfterAction` 改成"不退出"拦不住这条。
- v0.37.7：转换已经发生后才轮到回调，无法拒绝，因此在 CallTransition 回调里看到本 Mod 交战单位的 CombatToIdle 时，立刻安排在下一个游戏线程 tick 把它按原目标拉回（`arena:reengage`，补仇恨 + ForceIntoCombat），每只每 0.5 s 至多一次以防循环；1 s 一次的保险检查保留。前 20 次逐条记录，10 s 汇总里加"即时拉回累计"。
- 离线：test_combat_lock 新增 CombatToIdle 触发拉回（只对交战单位、0.5 s 限频、其他转换不触发）；test_arena_controller 新增按单位立即拉回（目标倒下、未知单位、已停止时拒绝）。Lua 50 项、后端 60 项通过。

待实机确认：画面上是否还会走开；"即时重新迎敌"读回是否 Combat；每 10 s 的 CombatToIdle 次数是否不变（预期不变，只是立刻被拉回）。

### v0.37.7 实机读回（run-20261101-135035.log）与 v0.37.8

- 即时拉回生效：每次 CombatToIdle 都在下一帧拉回，累计 408 次，等于 CombatToIdle 总数；读回都是 AI.State.Combat。1 s 保险的触发降到每 10 s 24–30 次（之前 34–100）。
- 但魔渊 13:51:44 开战后只在前 30 s 掉血（139536 → 99593），13:52:15 之后约 40 s 没再掉血。即时拉回时单位离魔渊 8.5–15.4 m（v0.37.6 在 1 s 保险拉回时是 1.9–9 m）。即单位一直处在战斗状态，却站在外圈不出手，约 10 s 后又超时切回 Idle。
- 推测：攻击令牌（MetaAI：`BP_MetaAIController_C` 的 `CurrentTokenCount`/`RequestToken`/`HasToken`，行为里用 `Condition_HasAttackToken_C`、`AITask_RequestAttackToken`），同时只有少数单位拿到出手名额，其余在外圈等待。资源里还有 `GE_DisableMetaAI` 和 `GE_DangHuiSummon_NoMetaAI`（荡魂召唤物不进 MetaAI），说明游戏自己也会让某些单位绕开这套名额。
- v0.37.8：交战中挂钩 `/SGameAI/Core/AICondition/Condition_HasAttackToken.Condition_HasAttackToken_C:EvaluateCondition`（和召唤难度已实测的 AICondition 同一种挂法），参数是单位的 AI 控制器；属于本 Mod 蓝红交战单位时回答 true，其他照游戏原答案。计数进 10 s 汇总（"允许出手"）。
- 离线：test_combat_lock 改为 10 个挂钩，新增令牌条件只对蓝红放行。Lua 50 项、后端 60 项通过。

待实机确认："允许出手"是否有计数；魔渊是否持续掉血；CombatToIdle 次数是否下降。若令牌条件不是唯一的入口（还有 AITask_RequestAttackToken），下一步再看任务层或给单位上 GE_DisableMetaAI。

### v0.37.8 实机读回（run-20261101-135639.log）与 v0.37.9

- 攻击令牌条件挂钩注册成功（`token pre=10`），但对本 Mod 蓝红单位一次都没被问到（允许出手=0）。这些单位的出手不经过 `Condition_HasAttackToken`，令牌推测没有证据。CombatToIdle 每 10 s 33–77 次，全部即时拉回；1 s 保险每 10 s 36 次；魔渊 30 s 内从 13.9 万到 8.8 万。
- 用户反馈："好多了"，但"还是有那个情况"（仍有单位走开）。
- v0.37.9（整理，不改已生效的行为）：combat_lock 只保留四个挂钩——退出判断、两个仇恨检查、CallTransition（CombatToIdle 时即时拉回）。去掉令牌条件（从未触发）和只为找脱战路径加的观察挂钩（Set Current State、ForceOffCombat、RemoveActorFromHatredList、RemoveAllActorsFromHatredList、ClearNPCHatredForOwner），它们对世界上每个 AI 都要进一次 Lua 回调。10 s 汇总改为四项计数。
- 离线：test_combat_lock 改为四个挂钩；Lua 50 项、后端 60 项通过。

剩下的走开：可能是同一单位 0.5 s 内再次脱战（等 1 s 保险），或在战斗状态里被挤在外圈走位。要再查，需要按距离和移动状态做人群快照。

## v0.37.10：自由观战空格上升、Ctrl 下降（2026-11-01）

用户决定剩下少量小怪走开的情况先不查（"无所谓不重要"），要求自由观战下空格也能上升、Ctrl 下降。free_camera.lua 的升降改为 max(E, SpaceBar) − max(Q, LeftControl, RightControl)，同时按不叠加、上下同时按抵消。观察期间玩家动作输入已被拦截（v0.25.1 实机：空格不会让角色跳），所以空格只控制镜头。助手六语和 README 的操作说明同步。离线：test_free_camera 新增升降一项，Lua 50 项、后端 60 项通过；实机待用户试。

## v0.37.11：数值设定（按游戏 / 统一成第一只 / 自定义），自定义覆盖全部 223 项属性（2026-11-01）

用户转来评论，希望 BOSS 的血量、杀气等"全维度数值"都能自定义，并要求"所有数值都可以操作"。

- 属性表：`CharacterBasics.hpp` 的 `UBasicAttributeSet` 共 223 个 `FGameplayAttributeData`（218 项 + 5 个 `_Lv1` 一级基准值）。数值统一只复制其中 107 项战斗属性（`Stats.fields`，不变）；自定义可以填全部 223 项（`Stats.allFields`，头文件顺序）。
- 写入路径：`AttributeUtils.ModifyCharacterAttributeValue`（Override=3）依赖 `/PBZCombatAsset/Config/AttributesModifyEffect/GE_MA_<属性>_1_Override`。按 asset-index.tsv 统计，这类资源（`_0_/_1_` × Add/Div/Mul/Override）各 211 个；223 项里 209 项有，14 项没有：`Infliction_Max_Lv1`、杀气防御的 Amplification/DealtVulnerability/DealtReduction 三项、`Resistance_ShachiWeapon*` 七项、`UltimateChargeGainRateMultiplier`、`ExecutionTarget{Normal,Break}HealthThreshold`。另有 `ThunderEnergy`、`WindEnergy` 的效果资源，但不在这个属性集里。
- 这 14 项改为直接写属性集里该字段的 BaseValue 和 CurrentValue（先原地写，读不回再整体赋值），再从字段读回；它们没有原生描述符，只能读字段本身。是否被游戏的聚合器改回，要看实机隔拍读回。
- 自定义逐项写入：先写各项上限，再写普通项，再写下限（Health_Min、Shachi_Min），最后写当前值（Health、Shield、Shachi、绝技、魂影、觉醒和各异常积累）。每项写后读回（字段 + 原生取值），游戏不接受的项单独回滚，连带恢复受它限制的当前值，并把字段名报给助手卡片；其余项照常生效。全部不接受才算失败。只设了血量或杀气上限、没设当前值时，仍以满血、满杀气入场。
- 助手：数值设定卡片三种模式；自定义有四个常用输入框，「全部属性」窗口按 32 组列出 223 项，可搜索，每项显示游戏里的属性名。六语标签齐全（离线脚本核对 97 个标签键）。
- 实验 `stat_field_probe.lua`（`Config.EnableStatFieldProbe`，测试版开）：载入后召唤的第一只蓝/红方单位，223 项逐项写入测试值（一般为原值 ×1.5，原值为 0 时写 1；当前值写原值 ×0.5，上限不够时临时抬高上限），隔一个支持循环（0.5 s）读回字段和原生取值，再恢复原值。每项一行日志，最后汇总 ok / base_only / reverted / unchanged / error / unreadable 的数量，并把整张属性表和测试前比较，找出被连带改动的项再恢复。
- 离线：test_character_stats 对 223 项逐项写入读回（209 项走原生效果、14 项写字段，含"拿到的是结构体副本"的情况）；test_stat_match 新增逐项回滚、写入顺序、不可读项；test_stat_field_probe 覆盖抬高上限、隔拍读回、连带改动和单位消失；后端 62 项（223 项按模组顺序写进请求文件）。Lua 49 个测试文件、启动测试两种模式全部通过。

待实机：自检日志里 223 项各是什么结果；14 项直接写字段的会不会被改回；自定义数值在交战里是否生效（血量、攻击、移动速度等）。

### v0.37.11 实机读回（run-20261101-144926.log）与 v0.37.12

- 自检跑在第一只召唤的双镐疯妇（等级 18、难度 Nightmare）上：测试前 223/223 项可读；汇总 ok=223，没有 base_only、reverted、unchanged、error、unreadable。每项写入后立即读回、隔 0.5 s 读回和原生取值都等于写入值。直接写字段的 14 项同样隔拍保持，例如 `Resistance_ShachiWeaponShachi` 0→1、`ExecutionTargetNormalHealthThreshold` 0.15→0.225（处决阈值是比例）、`Infliction_Max_Lv1` 1000→1500。`FinalWalkSpeed` 100→150 也没被游戏在 0.5 s 内改回。
- 连带改动：改血量上限再改回后，当前血量按比例缩小（19767.6 → 13178.4 = 19767.6 ÷ 1.5），杀气同理。说明游戏改上限时会按比例调整当前值。自定义的写入顺序是先写上限、最后写当前值，只设上限时再补满，所以不受影响。自检结束时的整表对比把这两项恢复了。
- `Awakening_Max` 从 0 写到 1 后写不回 0（恢复=false，整表对比后仍是 1）。游戏可能把它限制在至少 1。自定义填 0 会被判为没接受，并恢复原值。
- 召唤失败：从第二只召唤开始全部"激活确认=0"（截图：双镐疯妇召唤失败）。原因在自检模块：测试前快照存在 `self.start`，覆盖了 `start` 方法；之后每次召唤调用 `fieldProbe:start` 都报 "attempt to call a table value"，被 arena 的 pcall 当成激活失败，日志只写 detail=unknown。
- v0.37.12：快照改名为 `self.before`；main.lua 用 pcall 包住自检启动，失败只写日志，不影响召唤；arena 在激活回调报错时把错误写进 detail（"脚本错误: …"），不再只写 unknown。test_stat_field_probe 增加"自检进行中和结束后再次召唤"两项，用旧代码跑这条测试会失败。自检已达目的，`Config.EnableStatFieldProbe` 改回 false。

### v0.37.12 实机读回（15:01 起）与 v0.37.13

- 召唤恢复正常：14 次召唤全部"激活确认"，含一次 10 只。
- 自定义数值没有生效，而且没有到达游戏。面板队列里 id=913 `set_stat_mode`（自定义：血量上限 99999、杀气上限 99999、攻击 999、削杀气 999）状态为 failed，消息"投递前资格检查失败，未执行：unknown command fields: revision"。请求文件 stat-custom-request.tsv 已写好（R929B5E4B9DA5），但模组日志里没有这条命令。之后用户切回了"按游戏"（id=916）。
- 原因：后端入队时给自定义命令生成 revision 存进 payload，投递前会对存储的 payload 再校验一次，而校验的允许字段里没有 revision。之前的测试只调了 `_wire`，没走 `tick()` 的投递前复核。
- v0.37.13（只改助手，模组不变）：校验接受 revision，格式必须是 R 加 12 位大写十六进制，存在时沿用、不存在才生成，所以请求文件和命令里的 revision 一致。test_backend 新增"入队后投递前复核"：自定义、按游戏、不倒下、画面计时四种命令都要走完 tick → 待回执 → 成功；用旧代码跑，自定义这条失败。test_panel_bridge 新增按后端格式（CUSTOM + revision 列）送达处理函数。

### v0.37.13 实机读回（15:07 起）

- 用户在交战中切到自定义（血量上限 9999、杀气上限 9999、攻击 999、削杀气 999）：命令 id=932 成功，模组设定读回为 custom，保存到 stat-match-settings.tsv。之前召唤的单位不受影响（按设计）。
- 之后召唤的红方大头娃娃：`自定义应用并读回 verified=6/6 rejected=0`（四项 + 满血、满杀气），出生读回 HP=9999.0（同一单位按游戏是 12790.8）。交战中 9999 → 9453.6 → 4545 → 1272.6，约 3 s 后被 10 只蓝方打倒；血量上限生效，掉血正常。
- 攻击 999 已由字段和原生取值读回确认；日志没有采样蓝方血量，伤害变化没有单独量化。
