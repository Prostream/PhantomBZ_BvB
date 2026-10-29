# PhantomGladiator 交接文档

> 写于 2026-10-30 凌晨，交接对象：Codex（以及之后接手的任何人）。
> 读完这份就能接着干。更细的实验证据在 `docs/REVERSE_ENGINEERING.md`。

---

## 1. 项目目标

给单机动作游戏《影之刃零》(Phantom Blade Zero) 做一个"斗蛐蛐"Mod：**让怪物之间互相为敌、真实战斗，玩家可以召唤任意怪物上场，自己躲在一边观战。**

项目所有者（GitHub: LingYi-Liang）明确提出的要求：

- **战斗必须有真实反馈**：打中要有受击动作、要掉血、打死要有正常的死亡表现。站着互砍不掉血、凭空消失都算失败。用户原话："这样没有意义，必须有反馈。"
- **召唤出来的怪必须主动打对方**，不能罚站。
- **所有开关类功能可逆**：再按一次就取消。
- **所有功能可配置快捷键**，最终装进一个"修改器"式面板。
- **召唤能选任意怪**，包括没遇见过、已经杀光的；最终做成分类图鉴（小兵 / 精英 / BOSS），最好有头像。

长期规划见 `docs/DESIGN.md`：仇恨矩阵、竞技场赛制与押注、怪物组队打 BOSS、"养蛊"。

## 2. 现状一句话

**AI 层已打通，命中/伤害层没通。** 怪物能被设成真正的敌对、进入战斗状态、对着对方挥刀；但刀砍到对方身上不结算——不掉血、没有受击反应、没有死亡。这是当前唯一的主线阻塞，其余功能都已可用。

## 3. 环境

| 项 | 值 |
| --- | --- |
| 仓库 | `D:\Claude CODE\影之刃0`，远程 https://github.com/LingYi-Liang/PhantomGladiator （公开） |
| 游戏目录 | `D:\steam\steamapps\common\PBZ`，Steam AppID 4115450，build 26266538 |
| 引擎 | UE 5.7.4 Shipping，IoStore 打包，无 Denuvo |
| 游戏本体 | `platform\steam\PBZ.exe`（511MB）；`steam\PBZ.exe` 只是 1MB 启动器 |
| UE4SS | `platform\steam\ue4ss\`（experimental 3.0.1-1185），`dwmapi.dll` 注入；已装 `GameConfig/` 里的签名和内存布局 |
| Mod 部署位置 | `platform\steam\ue4ss\Mods\PhantomGladiator\`，`Mods\mods.txt` 已有 `PhantomGladiator : 1` |
| 日志 | `platform\steam\ue4ss\UE4SS.log`，所有 `[PhantomGladiator]` 输出都在这里 |
| 头文件全集 | `platform\steam\ue4ss\CXXHeaderDump\`（3470 个 .hpp，游戏内 Ctrl+H 生成）。查类、属性、函数签名首选这里 |
| 诊断文件输出 | `ProjectPBZ\Binaries\Win64\`（游戏进程的工作目录）：`brain_dump.txt`、`collision_matrix.txt` |
| gh CLI | `C:\Program Files\GitHub CLI\gh.exe`（不在 PATH 里），已登录 |
| Python | 3.11，分析脚本在 `tools/` |
| git 身份 | 仓库本地配置为 lingyi01525 |

## 4. 开发循环

1. 改 `Mods/PhantomGladiator/Scripts/*.lua`
2. 粗查语法：`python -I tools/lua_balance.py <文件>`（机器上没有 luac，这个只检查代码块配对）
3. 部署到游戏目录（PowerShell）：
   ```
   Copy-Item "D:\Claude CODE\影之刃0\Mods\PhantomGladiator\Scripts\*" "D:\steam\steamapps\common\PBZ\platform\steam\ue4ss\Mods\PhantomGladiator\Scripts\" -Force
   ```
4. **请用户**在游戏里的 UE4SS 窗口点 **Restart All Mods**（热重载，不用重启游戏）。日志出现 `[PhantomGladiator] loaded ✓` 才算生效。**只有用户能操作游戏。**
5. 用户按键测试并描述画面；你读 `UE4SS.log` 看数据。

注意：热重载会清空 Lua 状态（图鉴、配对记录等），召唤键会自动重建图鉴。

## 5. 按键（`config.lua` 可改）

| 按键 | 功能 |
| --- | --- |
| F1 | 扫描附近 NPC，登记进召唤图鉴 |
| Shift+F1 | 解剖最近一只怪的 AI 结构，写 `brain_dump.txt` |
| F2 | 全场互殴：附近 NPC 分两队，跨队设为敌对 |
| Shift+F2 | 诊断：每只 NPC 的阵营、对玩家关系、可疑效果、碰撞配置、仇恨列表、感知 |
| F3 | 决斗：最近两只 NPC 互杀，并启动战况监视 |
| Shift+F3 | 碰撞通道对照：玩家 vs 最近怪物的每个碰撞组件对 32 个通道的反应，写 `collision_matrix.txt` |
| F4 | 重置：恢复阵营、清除阵营覆盖、改回阵营标签 |
| F5 | 慢动作档位循环 |
| F6 / F7 | 自由镜头开关 / 强制退出 |
| F8 | 玩家中立化开关（怪物对玩家的阵营关系覆盖为中立） |
| F9 / Shift+F9 | 在面前召唤图鉴里选中的怪 / 切换要召唤的怪 |

## 6. 已验证可用

| 功能 | 实现方式 |
| --- | --- |
| UE 5.7 适配 | `GameConfig/` 两个签名 + `MemberVariableLayout.ini`（S-GAME 改了多个核心结构布局） |
| 召唤 | 优先用游戏官方刷怪函数 `BP_SGameAIFunctionLibrary.SpawnAIDefered` + `FinishSpawnAIDefered` + `ActivateAI`，失败退回 `BeginDeferredActorSpawnFromClass` |
| 敌对 | `UFactionComponent`（属性名 `"Faction Component"`）：`SetFactionRelationOverride(对手, 2, true)`，或 `SetFaction` 改阵营标签。怪物默认 `Faction.Enemy`，玩家 `Faction.Player` |
| 进入战斗 | 双方 `AI.State.Combat`，画面上确实在对着对方出招 |
| 玩家中立化 | 对每只怪 `SetFactionRelationOverride(玩家, 1, true)`，读回验证 |
| 慢动作 | 对所有 `WorldSettings` 写 `TimeDilation` |
| 自由镜头 | `CheatManager:ToggleDebugCamera`；Shipping 版调试相机没有 CheatManager，退出时现场构造一个再 `DisableDebugCamera` |
| 裁判模式（保底） | 直写 `BasicAttributeSet.Health` 扣血，血量到阈值调 `Kill(1)`。能分胜负，但没有受击和死亡动画（败者瞬间消失）。`config.lua` 里 `JudgeDamagePerTick = 15` 开启，目前为 0（观察原生伤害） |

## 7. 主线阻塞：已经试过什么

按时间顺序。**接手时请不要重复这些方向**，除非有新证据。

| # | 做法 | 结果 | 结论 |
| --- | --- | --- | --- |
| 1 | 写 UE 标准 `GenericTeamId`（Pawn 和 Controller 都写） | 无效 | 本作索敌不走 UE 标准阵营 |
| 2 | hook `BlueprintGetTeamAttitudeTowards` 改返回值 | 从未被调用 | 同上 |
| 3 | `SGameAIComponent:ForceIntoCombat(对方)` | 进入战斗，但会回落；**高频重发会打断出招变成站桩** | 只在脱战时补发（已实现） |
| 4 | AI 黑板目标键直写 | 被目标重选覆盖 | — |
| 5 | `HatredManagerComponent.AddActorToHatredList` | **一直被拒**，阵营改敌对后仍被拒 | 门禁另有条件；`HatredList` 数组直写可绕过 |
| 6 | 阵营关系覆盖为敌对 | ✅ 生效。同种怪默认**友好**，改后互相攻击 | 但**无伤害** |
| 7 | `SetFaction` 改到 `Faction.Player` | ✅ 按阵营表天然敌对 | 仍无伤害，阵营这条线到头了 |
| 8 | `ActivateAI` + 移除伏击/隐藏/免伤效果 | 召唤物身上根本没有这些效果（6/6 个效果类可查） | 排除"登场状态" |
| 9 | 改用官方刷怪函数召唤 | 结果相同 | 排除召唤方式 |
| 10 | 查碰撞开关 | 胶囊和模型都是 3（查询+物理） | 排除"碰撞被关闭"（早期这个结论是错的） |
| 11 | 碰撞通道对照（Shift+F3） | 玩家模型对通道 16/17/18/24/31 有反应，怪物模型全部忽略；怪物模型对 14 阻挡，玩家只重叠 | 推测 14 是玩家攻击通道，怪物攻击通道在 16/18/24/31 之中 |
| 12 | 把玩家这些通道反应复制到怪物身上（`CopyHurtChannels`） | 召唤当时读回验证成功（模型 16/17/18/24/31，胶囊 19/21），**但打了 75 秒仍满血；用户确认怪和怪身体仍然互相穿过** | 胶囊已改为阻挡"怪物"对象类型却仍不互挡，说明改动要么被游戏还原了，要么游戏不靠这些设置（见第 8 节 A） |
| 13 | `GameplayStatics.ApplyDamage` | 无效（本作伤害走 GAS） | — |
| 14 | `Kill(1)` | 瞬间消失，无死亡动画，偶尔不死 | 不是正常死亡流程 |
| 15 | `PlayAnimMontage` 播受击 | 返回成功但看不到；或选错动画（反复躺下）；高频播放会打断出招 | 不适合当受击反馈 |

## 8. 下一步建议（按优先级）

**A. 先确认碰撞改动有没有被还原（用户已回答：身体没有互相挡住）。**
胶囊改成阻挡"怪物"对象类型（通道 19）后，两只怪仍然穿模，有两种可能：
1. 游戏在进入战斗或切换状态时重新套用了自己的碰撞配置，把改动还原了。这样模型通道的改动多半也被还原，正好解释为什么还是不掉血。
2. 改动一直在，但游戏的推挤和命中不靠这些设置（怪物身上有专门的 `KnockPushCapsule`，平时为 NoCollision）。

检查方法：在 `StartDuelWatch` 里，开打后第 2、4、8 轮重新读一次双方模型和胶囊在通道 16/18/19/24/31 的反应（`GetCollisionResponseToChannel`）并打印。
- 被还原了：改成每轮重新写入，或 hook 游戏重设碰撞配置的地方（先在头文件里搜 `SetCollisionProfileName`、`SetCollisionResponseToChannel` 的调用方），再测伤害。
- 一直都在：碰撞通道这条线可以放下，直接做 B。

**B. hook 怪物的攻击检测**。怪物身上有 `UCharAttackCollisionComponent`（属性名 `CharAttackCollision`，定义在头文件 `AkashaEffects.hpp`），函数：
- `BeginAttack(MontageInstanceID, DamageID)` / `EndAttack(...)`
- `FireAttackLines(BeHitDetails, DamageCollisionID, LineStarts, LineEnds)`
- `FireEnvTraceLines(...)`、`GetHitPoints(...)`

用 `RegisterHook` 记录怪打怪时这些函数有没有被调用、线段在哪里。被调用了，说明问题在"检测到之后的筛选"；没被调用，说明怪物攻击不走这个组件，要去技能（GA / LGAAction）里找。

另外，**玩家身上有一个怪物没有的组件**：名字叫 `Collision`，对象类型 16，仅查询，对通道 2 和 14 重叠，疑似专门的受击框。复制通道无效的话，下一步看怪物攻击是不是只认这类组件。

**C. 对照游戏原生的 NPC 互打**。用户说在游戏里见过 NPC 互相打架，具体在哪、是友方 NPC 打怪物还是怪物打怪物，还没问清楚。去那个场景按 Shift+F2 和 Shift+F3，对比阵营、通道、组件。这是"照着能跑通的例子抄"，信息量最大。

**D. 参照游戏原生召唤系统**。头文件里有：
- `GA_SummonPassive`（怪物召唤小怪的技能，含 `bShareSummonTarget`、`EffectsApplyToAllSummons`），变体 `GA_SummonPassive_DogTrainer` 等
- `GE_SummonFactionOverride`、`GE_SummonLabel`、`GE_SummonAmount`
- 玩家杀器"草偶丝线"`GC_ShachiWeapon_CaoOuSiXian_Summon`、`GC_YingMei_SummonDamageShow`（召唤物伤害显示）

说明游戏里存在"非玩家单位打出真实伤害"的原生路径，但具体召唤单位的类还没找到。

**E. 保底方案：自建命中判定**（`docs/ASTRA_REVIEW.md` 第 1 节末尾）。hook 怪物出招的时间窗口，自己检测刀的轨迹有没有扫过敌方怪物，扫到就扣血、播受击、打死执行死亡。一定能做出可玩版本，代价是表现不是原生的。用户已同意把它作为保底。

**F. 暂不推荐**：用 UE 5.7 编辑器改游戏数据重新打包（pak/IoStore）。最彻底，但光搭环境就要一两天。

## 9. 代码结构

| 文件 | 内容 |
| --- | --- |
| `Mods/PhantomGladiator/Scripts/main.lua` | 全部逻辑（约 1650 行） |
| `Mods/PhantomGladiator/Scripts/config.lua` | 所有开关、按键、实验参数 |
| `Mods/PhantomGladiator/Scripts/teams.lua` | UE `GenericTeamId` 读写。实测对本作索敌无效，保留做兼容 |
| `Mods/PhantomGladiator/Scripts/hatred.lua` | 仇恨矩阵骨架，未启用 |
| `GameConfig/` | UE4SS 适配文件，装到游戏的 `ue4ss\` 目录 |
| `tools/` | 分析脚本，见第 11 节 |

`main.lua` 里的主要函数，按区块：

- 阵营：`GetFactionComp`、`ReadRelation`、`SetFactionRelation`、`SetFactionTag`、`RestoreFactionTags`、`ClearAllFactionOverrides`
- 召唤与登场：`SpawnViaAILib`、`FinishEntrance`、`GetAILib`、`ListSuspectGEs`、`StripSpawnStateGEs`、`DescribeCollision`、`CopyHurtChannels`
- 仇恨：`GetHatredComp`、`HatredListContains`、`AddHatred`
- 战斗：`ForceAttack`（阵营 + 仇恨 + 作战指令 + 黑板）、`StartDuelWatch`（战况监视、脱战恢复、裁判判伤）、`GetHP`、`JudgeDamage`、`PlayHitReact`
- 按键功能：`ScanNPCs`、`GlobalInfight`、`DuelNearest`、`ResetTeams`、`TogglePlayerNeutral`、`SummonSelected`
- 诊断：`DumpBrain`、`TargetDiag`、`DumpCollisionMatrix`

`main.lua` 里堆了不少已证实无效的实验代码（态度 hook、`teams.lua` 写入、`SeedHatred` 等）。可以整理，但**诊断功能先别删**。

## 10. 已知的坑

- **UE4SS 对空的或已失效的对象做链式调用会让游戏原生崩溃，`pcall` 拦不住。** 每一级都先 `IsValid`。
- `FindFirstOf` 可能拿到残留的旧对象（例如旧的调试相机、CheatManager）。要用 `FindAllOf` 遍历后按条件筛选。
- Lua 的 `local function` 必须先定义后使用。曾因 `FNameToString` 定义在后面，导致状态一直显示 `?`。
- FName 转字符串用 `:ToString()`。`GetOwnedGameplayTags` 不是反射函数，读不了。
- `K2_GetComponentsByClass` 在本作返回空数组。改用 `FindAllOf("ShapeComponent" / "SkeletalMeshComponent" / "StaticMeshComponent")` 后按 `GetOwner` 过滤。
- 属性名可能带空格：`pawn["Faction Component"]`、`pawn["Targeting Component"]`。
- 头文件导出里函数一律显示为 `void`，实际可能有返回值。
- 头文件导出（Ctrl+H）安全；**映射导出（Ctrl+Num6）会让游戏崩溃**。
- 日志里 `BPModLoaderMod` 的报错是 UE4SS 已知问题，与本项目无关。

## 11. 工具脚本（`tools/`）

都用 `python -I` 运行：

| 脚本 | 用法 | 用途 |
| --- | --- | --- |
| `lua_balance.py` | `<file.lua>` | 粗查 Lua 代码块配对 |
| `parse_dump.py` | `<crash.dmp>` | 读崩溃转储的异常地址和所在模块 |
| `aob_scan.py` | `PBZ.exe <签名配置目录> [pid]` | 在运行中的游戏内存里验证 UE4SS 特征码是否唯一命中 |
| `dump_mem.py` | `<pid> <十六进制地址> <字节数>` | 读游戏内存（用于核对结构布局） |

## 12. 文档索引

| 文档 | 内容 |
| --- | --- |
| `README.md` | 安装与使用 |
| `docs/DESIGN.md` | 产品规划（功能清单、修改器面板、图鉴、主动仇恨） |
| `docs/REVERSE_ENGINEERING.md` | 逆向证据和全部实测表 |
| `docs/ASTRA_REVIEW.md` | gpt-6-astra 对三个难题的咨询意见 |
| `docs/CONSULT_BRIEF.md` | 当时发给 Astra 的问题简报 |
