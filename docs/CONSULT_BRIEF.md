# 咨询简报：UE5.7 游戏《影之刃零》NPC 斗蛐蛐 Mod 的三个难题

你是被咨询的 AI。背景：我们在给单机动作游戏《影之刃零》(UE 5.7.4, Shipping) 做
"让 NPC 互相战斗" 的 UE4SS Lua Mod。完整逆向笔记在 `docs/REVERSE_ENGINEERING.md`，
代码在 `Mods/PhantomGladiator/Scripts/`。请先读这两处，再回答末尾三个问题。

## 已确认的事实（全部实测）

1. 游戏 AI：自研 SGameAI 插件（StateTree 驱动），索敌不走 UE 标准阵营/态度接口。
   每个 NPC 有 `BP_PBZHatredManagerComponent`（HatredList = 打谁的名单）。
2. 把怪 B 写进怪 A 的 HatredList（官方 Add 有门禁，TArray 直写可绕过）+
   `SGameAIComponent:ForceIntoCombat(B)` 后，A 和 B **真的互相攻击过**（有攻击动作）。
3. 但 S-GAME 关闭了 NPC 之间的碰撞：互殴时模型互相穿透，攻击无命中、无受击、无伤害。
   UGameplayStatics.ApplyDamage 也无效（GAS 游戏）。直接写 Health 属性可扣血但不触发
   受击/死亡回调；补调 `APBZCharacter_NPC:Kill(Damaged)` 可触发正常死亡动画。
4. 我们在用"裁判模式"：Lua 循环每 2.5s 扣双方 HP，归零者调 Kill()。
5. 新回归：加了每 2.5s 重发 ForceIntoCombat 的"续命"后，怪物变成站桩不打，
   只是被裁判扣血到死——怀疑频繁 ForceIntoCombat 重置了 StateTree 状态机。

## 问题（请给具体可操作的方案，基于 UE5/GAS/UE4SS Lua 的工程现实）

1. **怎样让 NPC 互殴产生真实命中与伤害？** NPC 间碰撞被关闭（攻击判定互相穿透）。
   可能方向：改碰撞 preset/channel response（运行时改 Capsule/武器判定的
   ObjectType 或 Response）？hook 命中查询？还是别的？哪个最可行、风险最小？
2. **受击反馈怎么补最自然？** 裁判扣血时如何让受害者播受击动画/硬直？
   （PlayAnimMontage 找现成受击蒙太奇？触发 GameplayCue？或别的 GAS 惯用做法？）
3. **怎样让互殴状态稳定持续？** 只发一次 ForceIntoCombat 会在数十秒后回落
   （目标被清/脱战）；每 2.5s 重发又导致站桩。重发的正确节奏或更优的维持机制？
   （比如监测 CurrentStateTag 只在脱战时补发？或 hook 它的脱战函数？）

请按问题逐条回答，给出 UE4SS Lua 能落地的具体 API/步骤，不要泛泛而谈。
