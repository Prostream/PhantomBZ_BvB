# v0.28 观战联动与名字修正

2026-10-31。用户报告数值统一后BOSS姓名串台、无仇恨偶尔不生效、人物站远后自由镜头听不到打斗。用户明确确认联动语义：F6进入时自动开启无仇恨、锁血、隐藏玩家和相机收音；F6再次切换或F7退出时恢复进入前状态。F8独立功能仍保留；原四项趣味功能中的杀气锁定、自动精准防御、自动红光闪避、第一人称仍未实现。

## 当前验证状态

**v0.28.2-observer-floor已通过本轮实机。** 用户确认“摄像机恢复，观战没有掉血”。09:45:38进入时Health_Min的base/current均从0读回977；09:46:59退出时均恢复0，HP仍977；期间约80秒没有HP变化日志。之后09:47:34再次进入，按当时HP1411读回新的下限1411。原先已确认的名字、镜头收音、玩家/装备隐藏与退出恢复保持。快照`v0282-observer-floor-20261031-094341`含验收日志/状态/37Lua源码。

最终实现直接使用已验证的ModifyCharacterAttributeValue写玩家实例Health_Min，保存原基础值并在退出还原，不再创建新锁血增益。失败且原值回滚验证成功时仍允许进入相机，并在面板明确提示保护未生效；不再把可恢复的锁血失败耦合到整个F6入口。10项保护回归、原生adapter、main和runtime19项通过。恢复也兼容此前版本的确切效果句柄。无仇恨组件缺失时增加按原生组件类寻找并校验Owner，扫描仍限当前世界；部分非参赛对象组件读取仍有失败，未把这些计数当作真实追击次数，未宣称所有特殊单位均兼容。

**v0.28.1失败记录：** AddAttributeBuff(Health_Min,Override,value,-1)没有得到可确认的有效句柄/新增效果。09:28多次进入回退、恢复记录清零，用户反馈“按F6没反应/不能进入”。不确定其内部拒绝原因，不把猜测的duration语义写成事实。该路径已移除；下面保留先前计划与过程，以下面日期/版本区分历史。

**最新已部署v0.28.1-health-floor，等待重载后的锁血验证。** 用户已确认v0.28名字持续正确、人物远处时镜头附近声音正常，隐藏与进入/退出也正常。但09:15:28日志在hidden=true/can_damage=false/原生LockHealth有效时读到HP从1285降至1159，因此旧版不满足锁血要求，不能将效果句柄存在当作防伤害通过。

v0.28.1新增可撤销的原生Health_Min持续覆盖，值为进入镜头时的HP，使用已核对的`AttributeUtils.AddAttributeBuff(actor, Health_Min, Override=3, value, duration=-1)`和自己的句柄。原生Health_Min描述取自准确的GE_MA_Health_Min_1_Override资产；该字段不进入NPC数值统一名单。逐次读取Health_Min，退出移除自己的效果；若属性系统在当前值下保留更低基础HP，移除前一次性校正到可见HP，避免解除时突然结算隐藏伤害，不每帧补血。

无仇恨09:14:35–09:15:28有三个NPC地址阵营/仇恨组件不可读，累计readFailures1170后停止增长；没有玩家AI目标清除失败证据。这不是1170次真实追击，也尚未证实原来偶发问题的完整根因。v0.28.1限制扫描为当前世界实例，排除模板/其它世界对象并打印全名；召唤后强制刷新实际黑板绑定，避免缓存窗口。不要把尚未读回的对象分类写成已确定的根因。

新补丁37Lua hash一致，备份`D:\Claude CODE\影之刃0-backups\v0281-health-floor-20261031-092620`。9项保护回归、原生adapter、数值统一7项、当前世界筛选main集成、无仇恨与目标模块通过。09:27用户已退出/关闭/清理，助手核对owned0、F8/freecam false、恢复记录0、相机日记只剩头；已请求重载后阿花/魔渊交战，角色留近处F6约20秒再F7，核对真实HP/下限/退出恢复。后端无需重启。下方保留v0.28过程。

v0.28-observer-guard已部署37个Lua文件并核对哈希。用户已先F7退出旧相机、关F8、F4清理，助手核对owned0/flags0/relations0后请求重载。

用户确认“进入、隐藏和退出恢复都正常”。09:12实机两次进入成功，记录LockHealth_count=1、owned handle、can_damage=false、玩家仇恨资格false、hidden_actors=8、入场HP1285。09:12:35退出：原距离探针及bUsePlayerAsDistanceProbe恢复，原生锁血句柄移除读回0，模型及玩家资格恢复，视点恢复true、相机销毁确认。之后用户再次进入，相机/F8当时处于开启状态；不能把前次退出状态当作当前状态。

声音三个位置已读取：CurrentListenerComponent、CurrentDistanceProbeComponent、CurrentCharacterSfxListenerComponent随镜头改变。游戏会定期重设探针；观战期间每约0.5秒检查，发现改回时重新请求，日志有verified=true。新角色音效监听组件刚生成时一帧可为0,0,0，随后更新到镜头附近。用户已确认角色站远、镜头靠近时“可以正常听见”。

用户已确认“两边名字都正确”。原生姓名后续重写实际被捕捉并纠正，例如09:15:23魔渊从无队伍前缀名称恢复到“红队 · 暗魔天堡之主：魔渊”，HUD visible/names/health均2。该轮实际数值统一开关为关闭，不冒称均衡开启样本；名称来源是自己的class_path，与属性基准无关。锁血未通过，见顶部失败及补丁状态。

## 实现与恢复边界

- `arena_boss_hud.lua`每次同步读实际BossName.GetText，按该参赛者class_path与队伍校正。原实现只缓存首次成功，原生界面后续重写时仍误报names_verified=true。成功校正不消耗失败重试预算；连续写入失败才限制重试。没有复制基准单位的名字或修改图鉴/资源名称。
- `observer_guard.lua`挂到`free_camera.lua`进入、低频维护和退出流程。保持原Player/Controller/Pawn关联，不重新启用DebugCameraController。相机日记增加本次保护对象、原值和确切效果句柄，热重载恢复按完整路径与地址定位旧对象。
- 只给玩家ASC施加原生`/PBZCombatAsset/Prototypes/GameplayEffects/GE_LockHealth.GE_LockHealth_C`；核对精确类路径、CDO无限时长和原有效果数量。已存在同类效果时不另加/移除；新加效果只按自己的句柄撤销，使用原生stack count确认移除。句柄不是本构建FActiveGameplayEffect的反射字段，使用GetActiveEffects原生查询，不猜结构偏移。没有每帧写Health，也没有修改NPC战斗数值。
- 玩家bCanBeDamaged及自身/附着装备Actor.bHidden逐个记录原值；只处理实际附着链属于玩家的实体，保留原来隐藏的装备。无效旧玩家不访问其仍可能有效的ASC，更不改替代玩家对象。
- 音频使用世界`PBZSoundFXSubsystem`的真实监听组件与距离探针。新Ak组件必须归属自建CameraActor；通过PBZSetDistanceProbe切换，并读CurrentDistanceProbeComponent。`bUsePlayerAsDistanceProbe`原值持久化。引擎SetAudioListenerOverride附着相机，退出ClearAudioListenerOverride恢复引擎默认监听方式；该引擎API没有反射getter，不能声称保存过其它Mod的未知Listener override。
- `spectator_targets.lua`只对当前NPC控制器绑定的PBZ_TargetingHandler_AI黑板Target Key/LastSensedActorKey，以及AI Focus中等于玩家的引用执行清除，保留NPC对NPC目标。列表有界缓存，不为每个NPC重复全局扫描；不调用ForceOffCombat。
- 手动NPC生成在ActivateAI前后立即执行现有无仇恨请求；F6期间F8关闭请求会解释由相机保持，退出再恢复原状态。`spectator-state.tsv`保存NPC→玩家关系/玩家资格的原值，读回保存成功才写引擎；热重载先恢复精确旧对象，有未知读回保留记录。正常退出前已有F8开启的用户，退出后仍保持开启。

## 检查与证据

名字原生重写回归在旧实现失败，修正后通过；持续多次重写、换队和真实HP显示均覆盖。观战保护7项、相机12项、无仇恨生命周期/持久化/生成/镜头占用、目标隔离、main实际模块加载、runtime19项及JS语法通过。离线mock只验证控制流程，不证明游戏命中规则或听感。

备份：`D:\Claude CODE\影之刃0-backups\v028-observer-guard-20261031-091027`。包含旧v0.27.2脚本、旧日志、部署哈希；后续运行证据在同目录继续追加。只更新本地源码和已授权的游戏Mod目录；无后台重启、发布或GitHub仓库变更。

原生签名来自本地SDK：Engine.APlayerController、GameplayAbilities.UAbilitySystemComponent/AbilitySystemBlueprintLibrary、ProjectPBZ.PBZSoundFXSubsystem、WB_BossHPBar、PBZ_TargetingHandler_AI。弱指针按[UE4SS FWeakObjectPtr.Get说明](https://docs.ue4ss.com/lua-api/classes/fweakobjectptr.html)取得对象后再次校验；监听覆盖参数与[Epic SetAudioListenerOverride说明](https://dev.epicgames.com/documentation/unreal-engine/API/Runtime/Engine/GameFramework/APlayerController/SetAudioListenerOverride?application_version=5.5)核对，项目实际签名以本地游戏导出为准。
