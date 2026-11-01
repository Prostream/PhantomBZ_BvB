# 数值统一开关

2026-10-31：用户要求后续召唤单位对齐第一只，减少不同章节BOSS的数值差距。用户明确接受生命/杀气上限、攻击/削杀气能力和防御倍率统一，体型、速度、招式、AI保留；清场重置基准。

## 当前状态

**v0.37.1：统一时也复制 1 级基准值。** 实机证实游戏按 1 级基准值算伤害：每一下扣掉对方血量上限的比例 = 攻击方 Attack_Lv1 × 招式倍率 ÷ 受击方 Health_Max_Lv1，显示的 Health_Max/Attack 不进伤害。此前各版只统一了显示的数值，读回一致但两只单位挨打、出手的伤害仍按各自的 1 级值。现在基准的 Health_Max_Lv1、Shachi_Max_Lv1、Attack_Lv1、ShachiAttack_Lv1、Infliction_Max_Lv1 最先写入，日志写出 1 级血量和 1 级攻击。依据和实测数据见 REVERSE_ENGINEERING.md「v0.37.0 发布后：伤害按 1 级基准值计算」；统一模式本身的实战效果还没单独测。

**v0.27.2-stat-match已实机通过阿花→魔渊组合。** 08:33:30加载；08:33:58和08:34:37两次第二只单位均读回109/109一致：生命9000、杀气800、攻击70、削杀气33。08:34:24用户清场使基准重置，08:34:31重新捕获首只。双方血条姓名/真实HP各2项验证通过，用户确认“血条和互斗正常”。35Lua源码/部署哈希一致；保留当前战斗，不需追加重载。

历史v0.27：用户已手动重启后台与Mod，开关开启和持久保存读回成功。魔渊基准读取117项，生命12000/杀气1200/攻击84/削杀气39.6000；F4后基准清空，再读取阿花9000/800/70/33。两次后续单位均在Attack描述校验阶段失败，未统一、回滚true，Arena按现有保护流程进入cleanup_pending，因此用户反馈无法开打。该版只有基准读取成功。

**v0.27.1已实测失败。** 用精确UFunction `/Script/GameplayAbilities.AbilitySystemBlueprintLibrary:IsValid`检查，08:18:21读到`属性描述无效: Attack kind=table cached_name=Attack`，回滚true；不是姓名字符串缺失。MakeAttribute返回表在再次传入时没有通过原生属性有效性检查，具体失效字段尚未证明。两只NPC的AI和正HP正常，但旧main将数值失败传播成activate=false，使Arena进入cleanup_pending；arenaSupport随后clear HUD，因此同时出现没有血条/不能开战。

**v0.27.2的两个修正：** 已验证安全回滚的数值失败改为生成成功附带明确警告，不再破坏正常激活/HUD/开战；回滚无法确认仍拦住。属性描述改用游戏原生GameplayEffect.Modifiers[1].Attribute，不重建Lua表。109个精确路径均在asset-index.tsv中核对到GameplayEffect类型；仅缓存效果UObject，每次重新取原位结构并做原生有效性、名称和数值校验。该原位传递已在上述实际匹配中通过。

最新读取蓝红各1、owned2、数值统一开启且matched1/failures0，F8开启、freecam关闭，用户仍在交战。IAB浏览器2/tab1，面板筛选逆流而上/BOSS。只有用户操作开关、召唤与战斗；不要自动清场或重载。

## 使用语义

- 默认关闭。开启后第一只由面板/快捷键成功初始化、具有完整战斗属性的NPC作为基准。
- 基准是出生时的数值快照，不再读取它后来的残血/增益；即使该NPC死亡，基准仍保留到所有本Mod登记实体清空。
- 后续手动召唤的NPC一次性对齐107项战斗属性，再以满生命/满杀气入场，共109项读回。蓝、红、未配队都适用。最初117项范围中的3个DefenceShachi攻击字段、7个Resistance_ShachiWeapon字段没有匹配的原生效果资产证据，v0.27.2不写这些扩展字段。
- 不追溯修改已有单位；BOSS技能召出的随从不自动套用BOSS血量。通用非NPC Actor路径不参与。
- 关闭只停止后续对齐，已有单位保持当前数值；重新开启重取基准。全部清理/自然失效导致登记数0也重取基准。部分清理不重置。
- 开关保存在Runtime/stat-match-settings.tsv；基准仅在当前Lua生命周期保存。发行包不要携带个人开关文件。
- 不做每帧补血/锁血；技能增减益、招式倍率和原生机制继续生效，不能承诺每一招伤害相同。

## 原生实现

`character_stats.lua`先验证Actor、AttributeSetBase与每级Outer，确认属性集属于该实例。字段来自CharacterBasics.hpp。统一Attack/ShachiAttack、物理及元素、削杀气相关攻防倍率、韧性/破防抗性，最后处理Health_Max/Shachi_Max；不写Level、速度、体型、AI、技能、异常累积量或玩家成长资源。

原生描述来自已核对路径`/PBZCombatAsset/Config/AttributesModifyEffect/GE_MA_<field>_1_Override.GE_MA_<field>_1_Override`。只读取效果资产，不修改它们。SGameAttributes.AttributeUtils.ModifyCharacterAttributeValue以EGameplayModOp.Override=3修改目标实例基础值；GetCharacterAttributeValue独立读回核心四项。没有写进程内存或修改共享属性表。

即时效果修改基础值，已有增减益可能使当前值不同于基础值（[Epic GAS属性说明](https://dev.epicgames.com/documentation/en-us/unreal-engine/understanding-the-unreal-engine-gameplay-ability-system)）。实现最多三次有界校准，利用实际base/current变化确定线性倍率，不安装永久覆盖效果。无法对齐或原生独立读回失败则回滚；先恢复上限，再恢复生命/杀气，避免资源被新上限夹住。原生硬覆盖、非线性限制等无法安全对齐的情况应明确失败，不假称统一。

`stat_match.lua`管理开关、冻结基准、事务与计数。接在手动spawn的AI初始化确认之后，同一个游戏线程内处理；不接adoptSummon。onUnitsChanged接清场重置。失败但已安全回滚的单位保持原生数值并可交战；只有回滚未知/失败才中止本批并保留给F4清理。不自动重放生成。

## 已做检查与待验证

- 生命周期/冻结快照/不追随残血/有界倍率校准/开关保存/清场重置/回滚7项通过。
- 回滚测试曾暴露“先恢复资源，再恢复上限”会留下被夹住的生命，已修正顺序并通过。
- Native adapter验证属性集归属、描述符读回、Override=3、失效对象保护。
- Runtime19项、Bridge19项、Arena、真实main隔离加载、后端47项及JS语法通过。
- 真实main激活回归在部署v0.27.1失败，在v0.27.2通过；Arena验证安全回滚警告不阻止蓝红开战。未确认回滚仍拒绝激活。
- 实机：开关持久化、基准捕获、清空重置、原位描述、两次109项读回、HUD与交战通过。
- 正常消耗：08:35:48阿花HP6836.999/Shachi55.520、魔渊HP8047.125/Shachi473.301；08:36:25分别HP5866.799/Shachi800和HP7600.875/Shachi305.001。杀气可自然回复，未被锁定；HP持续减少，基准仍保持出生快照。两个NPC的Attack/ShachiAttack持续70/33。
- 范围：仅这组实机组合；未逐一测试所有候选，未改变原生招式倍率/骨架/体型，也不保证每招实际伤害相等。关闭后不改已有单位等生命周期边界有离线检查；本轮没有为额外覆盖要求用户停止战斗。

最新备份：`D:\Claude CODE\影之刃0-backups\v0272-stat-match-20261031-082848`，含旧脚本、v0271-failed.log、v0272-user-confirmed.log、verified-game-state.json、35Lua哈希及source-checkpoint。基准、真实消耗和清场重置已取得实机证据。
