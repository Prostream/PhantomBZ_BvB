# 《影之刃零》AI 逆向工程笔记

> 基于发售日版本 (Steam build 26266538, UE 5.7.4) 实测，2026-10-29 深夜战果。
> 工具：UE4SS experimental (2026-10-29 构建) + 本仓库 GameConfig 适配 + Lua 运行时实验。

## 一、引擎适配（前置，已解决）

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
| 态度 hook | hook 两个 BlueprintGetTeamAttitudeTowards 改返回值 | ❌ 函数从未被调用（计数=0） |
| 作战指令 | SGameAIComponent:ForceIntoCombat(对方) | ⚠️ 调用成功，行为无变化（单用时） |
| 黑板直写 | SetValueAsObject(TargetKey, 对方) | ⚠️ 写入成功，被每帧重选覆盖 |
| 官方拉仇恨 | AddActorToHatredList(对方) | ❌ 被门禁静默拒绝（列表无变化） |
| 仇恨数组直写 | HatredList[#+1] = 对方 | ✅ 写入成功且**怪物真的互相攻击了几秒** |
| 玩家除名 | RemoveActorFromHatredList(玩家) | ✅ 调用成功（效果待确认） |

**里程碑观察（2026-10-29 23:26）**：仇恨直写 + ForceIntoCombat + 黑板写入三件套后，
召唤的两只怪**互相攻击了数秒**——但 (1) 互相不掉血；(2) 几秒后目标回弹到玩家。

## 四、剩下的两个保险丝（下次攻坚目标）

### 保险丝 A：怪打怪不掉血（伤害过滤）
- 本作伤害走 GAS（GameplayEffect）；`PBZAbilityTargetRuntime` 里有
  `IsPlayerInCasterHatredList`——技能目标过滤疑似写死"玩家"
- 存在 `GE_HiddenTagsCanNotBeHatred`：**身份/可被打 由 GameplayTag 决定**
- 候选解法：
  1. 找到玩家的身份标签，用 `BP_SGameAIFunctionLibrary.AddLooseGameplayTagIfNone`
     给怪物贴上（一个标签可能同时修好仇恨门禁+伤害+感知）
  2. 标签枚举难点：ASC 的 GetOwnedGameplayTags 非反射函数。备选：
     读 GE 类默认对象的 GrantedTags；或 hook `CheckActorCanBeHatred`（post 改出参）
  3. 直接 hook 伤害管线里的过滤函数（待定位）

### 保险丝 B：目标几秒后回弹玩家
- 无伤害 → 仇恨不强化 → 重选时非法条目被清
- 候选解法：
  1. LoopAsync 每 1–2 秒重新执行三件套（续命式，难看但立刻能用）
  2. 修好保险丝 A 后伤害会自然强化仇恨，可能自愈
  3. hook `PBZ_TargetingHandler_AI:FindTargetsRated`（post 改写出参数组）

### 其它待办
- 用 `BP_SGameAIFunctionLibrary.SpawnAI/FinishSpawnAIDefered` 替换手搓召唤
  （走正规注册流程，AI 可能更完整）
- `GetTargetTypes` 出参的 FGameplayTag 读取还没解对（显示 nil），修法同标签枚举
- 阵营快照 ReadTeam 返回结构体代理的取值问题
