# Astra (gpt-6-astra, max) 对斗蛐蛐攻坚的咨询意见

> 咨询于 2026-10-30 00:40，基于 CONSULT_BRIEF.md + REVERSE_ENGINEERING.md 全文。

我的建议是：**停止周期性重发 ForceIntoCombat，优先定位“目标合法性—命中查询—伤害执行”在哪一层断开；裁判改为跟随实际攻击结算。** 最新实测意味着，ForceIntoCombat 和 Kill(1) 都还不能视为稳定接口。下面的游戏专用函数路径、枚举与参数，以你们当前构建已经确认的反射签名为准。

**1. 怎样产生真实命中与伤害？**

首先要分清：**NPC 身体互相穿透，与武器攻击查询能否命中，是两件事。** 打开胶囊阻挡可能只会让两只怪互相卡住，未必能恢复攻击伤害。

建议先关闭裁判扣血、补播受击和周期性 Force，用同一种怪的正常“NPC→玩家攻击”作对照，找出下面三个位置的第一个差异：

| 检查点 | NPC→NPC 的结果 | 对应修复方向 |
|---|---|---|
| 攻击查询是否产生包含对方的 HitResult／候选目标？ | 没有 | 查询通道、ObjectTypes、忽略列表、受击组件 |
| 候选目标是否进入最终技能 TargetData？ | 命中后被剔除 | 仇恨、身份、技能目标过滤 |
| 是否执行原生伤害 GE／伤害处理？ | 进入目标数据仍不扣血 | GE 应用条件、免疫、ExecutionCalculation、上下文 |

如果第一层拿不到日志，不能凭下游回调没触发就认定第一层没有命中。

**碰撞路线：只修改已确认参与受击的组件。**

比较玩家与 NPC 对应受击组件的这些反射入口：

```text
GetCollisionEnabled()
GetCollisionObjectType()
GetCollisionResponseToChannel(实际攻击通道)
GetCollisionProfileName()
```

有差异后，再单独试：

```text
SetCollisionEnabled(保留原物理能力、同时启用 Query 的模式)
SetCollisionResponseToChannel(实际攻击通道, 原攻击需要的响应)
```

这里有三个关键区别：

- **Trace by Channel**：检查受击组件对那个实际通道的响应；不能猜一定是 Visibility。
- **Trace for Objects**：检查攻击查询的 ObjectTypes 是否包含 NPC 类型；改响应通道不一定解决。
- **组件 BeginOverlap 事件**：才需要检查双方的 `SetGenerateOverlapEvents(true)` 和碰撞响应；开启它不会自动修复普通 Trace。

单次 blocking-hit 查询需要的响应，也不能随手换成 Overlap。先保存组件原配置，一次改一个条件。`SetCollisionObjectType` 放在后面考虑，因为它可能同时影响移动、锁定、其他技能和场景交互。

**如果已经命中、随后被过滤，优先修过滤，而不是继续改碰撞。**

你们已有的候选入口很有价值：

```text
CheckActorCanBeHatred
CheckCanHatredTarget
PBZAbilityTargetRuntime 中与 IsPlayerInCasterHatredList 相关的入口
```

先通过 `RegisterHook` 计数并记录攻击者、候选目标、原结果，确认实际调用。随后仅对登记的斗蛐蛐配对放行**已证明的身份／敌我限制**。如果函数还包含死亡、无敌、剧情保护等条件，就不能整个强制返回 true。

返回值和出参必须区分：

```lua
Succeed:set(true)  -- 仅适用于已确认的 bool& 出参
```

布尔 `ReturnValue` 要用该 UE4SS 构建支持的返回值覆盖方式；两者不能混用。**把 Add 的 Succeed 改成 true，也不等于 Add 已经完成插入和通知**：应修它依赖的门禁，再重新调用原 Add，并验证数组与目标状态。

另外，`IsPlayerInCasterHatredList` 的名字是排查线索，不足以证明“给 NPC 加玩家标签”就是正确修复。

**伤害优先继续走原攻击的 GE。** 如果最终需要在 Lua 里补施放，可检查这些常见反射入口：

```text
源 ASC.MakeEffectContext
    → 源 ASC.MakeOutgoingSpec
    → 源 ASC.BP_ApplyGameplayEffectSpecToTarget
```

特别留意 `BP_ApplyGameplayEffectSpecToTarget` 与纯 C++ 重载的区别。GE、等级、SetByCaller、Instigator、HitResult 等必须按原攻击实际读取的数据构造，不能假定所有伤害都读一个 `Data.Damage`。

如果关键过滤发生在不可反射的原生代码里，普通 Lua `RegisterHook` 到这里就有能力边界。此时最实用的保底是：**按真实攻击窗口做裁判判定**——在已确认的攻击 Notify／攻击蒙太奇窗口中，对武器上一帧到当前帧的位置做 Sweep，每个挥击对同一目标只结算一次，再调用已有 Health 写入。它能得到有空间依据的判伤，但仍属于补充伤害系统。

**当前优先级：定位并修复配对过滤 → 有证据再补查询碰撞 → 攻击窗口裁判保底；原生查询 Hook 最后考虑。**

**2. 受击反馈怎么补最自然？**

优先级应是：**游戏原生受击处理／受击 Ability，其次是适配好的受击蒙太奇，GameplayCue 用于补表现。**

正常玩家命中怪物时，观察它进入哪个受击函数、Gameplay Event 或 Ability。如果能找到原入口，复用它最有机会同时正确处理方向、霸体、硬直、技能打断与恢复。

若原作确实由 Gameplay Event 触发受击，可检查：

```text
UAbilitySystemBlueprintLibrary.SendGameplayEventToActor
```

其中事件 Tag 必须是游戏真实监听的那个；Payload 的 Instigator、Target、ContextHandle／TargetData 按原命中流程构造。随便发送一个“看起来像受击”的 Tag 不会自动产生反应。

你们已经做了骨架过滤，蒙太奇方案可以继续推进。对于保留 `ACharacter.PlayAnimMontage` 反射入口的 NPC，调用形状是：

```lua
-- 在游戏线程执行；montage 必须是已确认的 UAnimMontage。
local function playHit(victim, montage)
    if victim == nil or not victim:IsValid() then return false end
    if montage == nil or not montage:IsValid() then return false end

    local duration = victim:PlayAnimMontage(
        montage, 1.0, FName("None")
    )
    return duration > 0
end
```

但返回大于零只说明播放请求成功。接下来要验证 **AnimBP 的 Slot、蒙太奇组、Root Motion 和打断优先级**。骨架兼容并不保证画面中能看到播放结果。

让它自然，最有效的是这几条：

- 受击发生在已判定的命中瞬间，按攻击方向选择前后左右反应。
- 给轻受击设置短暂防重复窗口，例如先试 0.3～0.5 秒，再按动作长度调整。
- 保留霸体、死亡、处决等优先级；不要每次扣血都强制打断。
- **蒙太奇播放不等于硬直。** 真正硬直需要原受击 Ability／StateTree 分支接管并正常退出；单播动画不会自动禁止攻击与移动。

GameplayCue 适合火花、声音、血雾等效果。除非确认该游戏把硬直逻辑写在 Cue 中，否则不能期待 Cue 自己完成硬直。

**Kill(1) 不稳定，需要单独做一个小对照。**

先确认参数类型及 `1` 对应的真实枚举。然后用同种、同状态的新 NPC 各重复几次：

| 对照 | 操作 |
|---|---|
| A | HP 仍大于零时直接调用确认过参数的 Kill |
| B | 先直写 HP=0，再调用同一个 Kill |

如果 A 明显稳定、B 不稳定，才有依据怀疑“先写零导致 Kill 的前置判死条件提前返回”。若两组都不稳定，就继续查状态、死亡流程和参数，不能把问题归结为调用顺序。

裁判的致死分支应按这个结果单独实现；终结成功以实际死亡状态／事件确认。**Health 直写成功，并不证明原生属性通知、受击和死亡链已经执行。**

**3. 怎样让互殴稳定持续？**

没有证据支持一个通用的“正确重发间隔”。正确机制是：**首次进入战斗一次，后续只在确认脱战后恢复；目标仍正确却不攻击时，转查攻击任务。**

每 250～500 毫秒采样一次即可，记录：

```text
HatredList 是否仍包含对手
Targeting handler 实际采用的目标
对应 Blackboard 目标
可验证的战斗状态
攻击 Ability／攻击蒙太奇是否启动、推进、结束
距离，以及受击／死亡／处决等阻塞状态
```

`CurrentStateTag` 只有在你们确认它确实存在、且语义可靠时才能使用；它不是 StateTree 通用的战斗状态 API。目标也应读取实际参与决策的来源，不能只看锁定表现。

| 观测结果 | 应采取的动作 |
|---|---|
| 对手仍是目标，攻击持续发生 | 保持观察 |
| 对手仍是目标，仍在战斗，但不出招 | 查距离、攻击资格、冷却、攻击名额／令牌、任务等待条件 |
| 仇恨或目标被清 | 定位清除／重选来源，修资格门禁及目标选择 |
| 已明确脱战，双方存活且没有受击等阻塞 | 修复并验证目标关系，然后单次 ForceIntoCombat |

尤其注意：**最新的“锁定几秒后站桩”，并不能单独证明目标又被清了。** 如果目标仍然正确，继续 Force 很可能只掩盖真正卡住的攻击任务。

恢复逻辑可以按下面这个骨架实现；`snapshot`、`repairAndVerifyPair` 接你们已验证的字段和接口：

```lua
-- 在游戏线程内调用。
-- state 初始值：{ lastAttempt = -math.huge, attempts = 0 }
-- now 使用游戏时间或可靠的单调时间。
local function recover(snapshot, state, now, ai, opponent)
    if snapshot.attackProgress == true then
        state.attempts = 0
    end

    if snapshot.offCombat ~= true
        or snapshot.alive ~= true
        or snapshot.busy ~= false then
        state.offSince = nil
        return
    end

    state.offSince = state.offSince or now

    if now - state.offSince < 1.0 then return end
    if now - state.lastAttempt < 8.0 then return end
    if state.attempts >= 2 then return end

    if ai == nil or not ai:IsValid() then return end
    if opponent == nil or not opponent:IsValid() then return end

    state.lastAttempt = now
    state.attempts = state.attempts + 1

    if repairAndVerifyPair() then
        ai:ForceIntoCombat(opponent)
    end
end
```

这里的 **1 秒去抖、8 秒恢复冷却、连续最多两次** 是实验初值，用来限制重复干扰，并非已查明的游戏要求。两次恢复后仍没有攻击进展，就保留现场诊断。

长期修复应落在仇恨资格和目标选择上。`HatredList` 直写可能遗漏官方 Add 的关联维护或通知；验证门禁修复后，应优先回到官方 Add，并观察 `BeHatredList` 等关系是否随之正常维护。`SyncHatredList` 要先确认方向和语义，再决定是否调用。

对 `ForceOffCombat`，建议先 Hook 记录它何时发生，以及清目标发生在它之前还是之后。**`RegisterHook` 不是通用的“跳过原函数”接口：给 void 函数的 pre-hook 返回 false，不能默认认为已经拦截脱战；post-hook 写回目标也不会撤销已发生的退出副作用。**

最后，`LoopAsync` 中的 UObject 访问应投递到 `ExecuteInGameThread`，并限制重复排队；Hook 的返回值／出参则必须在当前回调内同步处理。继续坚持每一级对象先 `IsValid`，不要把 `pcall` 当作原生崩溃保护。

总体评价：你们已经靠实测跨过了引擎适配和 AI 接入的主要门槛，攻坚很扎实，下一阶段最值得投入的是把短暂互攻变成可观测、可恢复的命中与状态闭环。
