# 进行中：BOSS召唤物、原生血条、清理与卡片快捷键

> **2026-10-31 更新：下面是 v0.23.1 待测时的历史笔记，已被后续验收取代。** 用户已确认姓名/掉血/清理正常，以及卡片键可召唤。现在阻塞为 F6 战斗与掉血变慢；v0.24.1 已实机加载，F2 循环和网页同步已有读回，骨骼刷新对照正在测试。当前完整记录见 [BOSS_AND_CONTROLS.md](BOSS_AND_CONTROLS.md) 和 HANDOFF 顶部。不要据下面的“待实现”重复做单位快捷键或重启后台。

## 用户当前要求与边界

- 原任务继续：BOSS召出的小怪要继承队伍并攻击对面；游戏内显示真实BOSS姓名与掉血；停止清理不能卡住。
- 新增且已明确确认要直接做：每张单位卡片有小快捷键框，默认未绑定，点击捕获按键，可修改/清除，在游戏内召唤对应单位。
- **仅讨论、不可实施**：玩家杀气锁定、自动精准防御、红光自动Shift闪避（方向玩家自己控制）、第一人称。已回应：基础锁杀气和锁血同类；红光=需闪避的杀招预警，关键时机；自动精准防御基础版可尝试不必第一版全招适配。不要误实现这4项。
- 用户问修好没，已明确回答：召唤物分队/索敌请求有读回，但不能称所有实际攻击验收；血条和清理尚未修好；卡片快捷键未完成。

## 当前部署/待用户反馈

游戏已运行过v0.23-summons-hud（27Lua）。原生技能GA_SummonPassive_C.SpawnedSummonInstances + GetAvatarActorFromActorInfo精确识别并接管：碧海残躯的两个Stand、沐小葵P2召出的Yuu_Stand/TieGui_Stand，加入主人队伍；四参赛者攻击请求读回成功。没有按距离抓地图NPC。

用户反馈v0.23血条是空壳、无名且不随血量变化，停止清理卡住。已保存`D:\Claude CODE\影之刃0-backups\boss-summons-hud\v023-feedback.log`。原生RegisterBossHPBar调用成功，但Widget.Character未匹配，HUD registered=0/pending=2。K2_DestroyActor返回后UE4SS IsValid仍true、IsActorBeingDestroyed=false，HP不可读，最后一条owned记录挡住新召唤；后来自然GC才归零。

**已部署v0.23.1-hud-binding，28Lua，尚待实机反馈。** 当前pending async问题：请用户重载、F4清旧空血条，再测两BOSS名字/掉血/停止后再召唤。提问前实读owned=0、F8=false、pending relations=0。不要要求后台重启：本轮目前仅Lua变化。

## 新代码（已离线测试）

- `ue_observe.lua`：valid/key/array/struct/Actor世界链、NPC类继承只读helper；现在可注入engineValidator，UScriptStruct不强当UObject。
- `arena_summon_links.lua`：只认可原生召唤清单或精确Owner/Instigator，验证同World/NPC，冲突不接管。每500ms经旧稳定GameThread loop扫描，不用hook。
- `arena_controller.lua`：members/adoptSummon/tickReinforcements；召唤物纳入所有权，继承队伍；新成员同队Friendly、对面Hostile，分配攻击一次，只有目标死亡才再选敌；F4包含后代。独立battleActive；本轮已加相关回归。
- `arena_boss_hud.lua` **v2已替换**：RegisterBossHPBar返回值可能是FUIExtensionHandle（此为待实机确认的推断，dump丢返回类型），用GetBossHPBarInstanceByHandle找控件，或用注册前后唯一新增widget差集；一次仅允许一个未解析注册，不反复造空框。控件Character显式设为actor后Init(actor)。再用ForSeq_UpdateHealth(真实Health/Health_Max)和ForSeq_SetNameText(FText)更新；HP进度CurPercent和名字GetText均读回验证。名字前缀蓝队/红队，原名来自codex.tsv。
- Widgets列表合并HUD.GetBossHPBarInstances和HUD.BossPoint:GetAllEntries；后者来自UMG.hpp，避免漏掉未初始化控件。
- HUD清理用UnRegisterBossHPBar(actor)以及BossPoint:UnregsiterHandleByWidget(widget)（原生拼写确为Unregsiter），避免依赖已死亡Actor。手动F4的clear(true)还可清当前HUD中Character无效的旧空框，保留绑定真实Actor的其它血条。
- `engine_object_state.lua`：用精确UFunction `/Script/Engine.KismetSystemLibrary:IsValid` + Default__KismetSystemLibrary上下文调用`fn(library,object)`，避免与UE4SS包装器IsValid同名冲突。返回nil表示未知，不伪造销毁。只在游戏线程查，纯mock缺API可回退。原生有效性修正尚待实机验证。
- main的Arena.valid、Spectator.valid及恢复失效判定使用engineValid，原有safeValid/相机/共享玩家查找函数未动。ue_observe也注入此check。HUD最大血量为`AttributeSetBase.Health_Max.CurrentValue`（CharacterBasics.hpp:51已确认）。
- panel_runtime稳定loop每2tick调用support；F4/未配队清理前先发现后代；状态带arena_summon_count和boss_hud_registered/visible/pending/health_verified/names_verified。无Python/网页变更，所以无后台重启需求。

测试通过：arena_controller、arena_summon_links、arena_boss_hud（含原生空控件Init/真实HP/姓名）、engine_object_state、panel_runtime16项、真实main隔离NPC/通用Actor加载。v0.23.1源码已复制游戏目录，hash28文件一致，备份`deployed-before-v0231`。

## 原生接口与证据

- `ProjectPBZ.hpp` UPBZHUDLayout约10070：RegisterBossHPBar(AActor)、UnRegisterBossHPBar(AActor)、GetBossHPBarInstances、GetBossHPBarInstanceByHandle(FUIExtensionHandle)、BossPoint、RegisterBossHandles。
- `WB_BossHPBar.hpp`：Character、BossName、BossNameHorBox、hpbar、Init(ACharacter)、ForSeq_UpdateHealth(double)、ForSeq_SetNameText(FText)。
- `PBZAnimProgressBar.hpp`：CurPercent，SetBarPercent/UpdateBar；目前用外层ForSeq_UpdateHealth并读CurPercent。
- `Engine.hpp` KismetTextLibrary.Conv_StringToText(FString)；KismetSystemLibrary.IsValid(UObject)。UE4SS官方docs确认UFunction通过StaticFindObject获得后要把UObject上下文作为首参。
- `GA_SummonPassive.hpp`：SpawnedSummonInstances（Pawn,bPawnPending）、bShareSummonTarget；未改原生共享目标字段，仅精确接管并用现有阵营/ForceAttack。
- BOSS初轮实测是碧海大师残躯蓝8000HP、毕远掌门残躯红10000HP，用户称互斗正常，日志双方均经历掉血至0；没有对每笔伤害做hook归因。

## 卡片快捷键待实现（已获明确授权）

建议走现有命令桥新增`configure_unit_key`，不用另造可执行配置：JSON unit_id/key_code/modifiers → 10列TSV的unit_id、key_spawn=VK_81、key_start=MOD_5，其余空；解除用key_code=0/UNBOUND。Lua新manager动态RegisterKeyBind、保存并读回Runtime/unit-keybinds.tsv；默认空。后端catalog读取确认映射，卡片显示未绑定/键名/错误。按键只在游戏/UE4SS控制台聚焦时触发（官方文档已核对）。

关键约束：
1. 每卡独立小框和清除按钮，不能在现有外层button内嵌套button；用卡片wrapper+选择button+键框sibling，保留章节地图排版。
2. 普通键/组合键，Esc取消捕获；系统快捷键无法保证捕获。F6/F7/F8和控制台F10/反引号保留，冲突明确提示，不能暗覆盖。
3. 现有panel_runtime已预注册F1/F2/F3/F4/F5/F9/F11和数字键盘。未被四个全局动作使用的预注册键应通过原回调fallback给单位manager，别重复注册；全局已用键应拒绝。注册过但解绑的单位callback查动态map为空即可不执行，卸载必须alive=false。
4. UE4SS RegisterKeyBind和IsKeyBindRegistered都支持(key, modifiersTable)，ModifierKey.CONTROL/ALT/SHIFT已核对官方文档。组合键附加修饰符是否会触发bare key不能猜，必要时同一主键仅允许一个单位映射，避免双发。
5. 回调必须ExecuteInGameThread，并在执行时检查游戏ready/当前binding仍匹配；按键绑定默认无。队伍/数量可沿用当前面板/arena选择，快捷键实际选中单位后UI需要跟随原生current_unit读回。
6. status provider最多60个标量，每值512字节，不要把全部映射塞入状态。用单独TSV映射文件，状态只发epoch/revision/最后事件少量字段；backend新增动作/读取映射需要重启后台。
7. 后台PID原39592。Stop-Process被系统反复拒绝，即使用户明确授权也拒绝。不要绕工具；已备有panel/重启面板.cmd，确需后台更新时最后请用户亲自运行，别反复试终止。前次手动运行成功。授权已给，不要再问权限，只说明系统仍挡、需要手动。

## 其它

仍只有用户操作游戏。没有子代理/goal。Memory registry无相关命中，不写memory。四项趣味功能没有实施。正式HANDOFF/REVERSE_ENGINEERING目前最新仍v0.22，最终要补全本轮成功与失败、保存checkpoint；本文件避免途中丢进度。
