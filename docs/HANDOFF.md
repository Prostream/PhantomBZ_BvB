# PhantomGladiator 交接文档

> **当前运行v0.30-custom-keys。** 用户要求8项功能全部默认未绑定，包括原F6/F7/F2/F8，并将保护文案写全。已接入录键/组合键、清空、保存、具体占用者提示、旧键失效和旧配置迁移；新增面板进入/退出观战按钮。41Lua hash一致，用户已重启后台与Mod；API和实际页面8项均未绑定，既有单位键哈希保持。详见[FUNCTION_KEYS.md](FUNCTION_KEYS.md)。
>
> 功能键10、runtime20、桥接21、后端53项等离线检查通过；新功能绑定的真实按键触发尚待用户自行配置使用，未冒称完成实机验收。默认不再注册F1/F2/F3/F4/F6/F7/F8/F9，开发诊断键也默认关闭。之后提示用户操作时按实际配置或面板按钮，**不要再要求直接按固定F键**。当前已空场、观战关闭；继续前读实时状态。备份`D:\Claude CODE\影之刃0-backups\v030-custom-keys-20261031-113403`。
>
> 用户抱怨此次简单改动耗时过长；已承认重构/检查范围过大，正在收尾，不继续扩大检查或要求多轮测试。真实输出速率/加速是否生效没有可核对数据，不臆测。IAB浏览器2/tab1已刷新并展开新版快捷键设置，截图function-keys-empty.jpg。下方为历史版本。

> **当前运行v0.29-persistent-hud，用户已确认“显示正常，数字会变化”。** 用户要求存活血条常驻、血条上方加HP数字，并明确死亡后隐藏。已发现旧扩展池血条被游戏重绑到其它角色、缓存长期拒绝更新；新arena_hud/arena_hud_widget独立创建原生血条，增加当前HP/max数字，保持存活显示、死亡移除，隔离游戏重复条。39Lua hash一致；10:16–10:18阿花/魔渊两条名称/真实HP/数字/可见性读回全部2、pending0。详见[PERSISTENT_HUD.md](PERSISTENT_HUD.md)。
>
> v0.28.2观战锁血已通过用户和原生读回：Health_Min 0→977，约80秒HP977不变，退出下限恢复0且HP977；下一轮按HP1411新取下限。F6入口、隐藏、收音已确认；v0.28原锁血GE不阻止掉血、v0.28.1增益句柄失败导致F6回退均保留失败记录，当前直接写可恢复Health_Min，已安全回滚的可选保护失败不阻断镜头。详见[OBSERVER_MODE.md](OBSERVER_MODE.md)。
>
> **10:30最终已清空：** arena idle、owned0、F6/F8关闭、HUD/数字/pending与恢复记录均0。10:23:58阿花HP0后私有血条移除true；F4移除剩余条也true，死亡隐藏已实机观察。首轮清理遗留1条旧黑板恢复项，用户再次F4后确认对象无效并归零，不能宣称所有清理一次完成。无待执行测试请求。继续工作仍先读实时状态，勿自动操作游戏；无仇恨少数对象读失败不等于追击次数，也不宣称全目录兼容。备份`D:\Claude CODE\影之刃0-backups\v029-persistent-hud-20261031-101521`。下方为历史过程。

> **最新部署v0.28.1-health-floor，锁血修正等待实机。** v0.28用户已确认名字正确、人物站远时镜头附近声音正常、进入/隐藏/退出恢复正常；但09:15:28玩家hidden=true/can_damage=false且LockHealth有效时HP仍1285→1159，锁血未通过。v0.28.1按进入HP添加原生Health_Min持续覆盖，只撤销自己的句柄，不每帧补血；退出避免潜在基础HP欠值。37Lua hash一致，9项保护回归、adapter/数值统一/main等通过。备份`D:\Claude CODE\影之刃0-backups\v0281-health-floor-20261031-092620`。详见[OBSERVER_MODE.md](OBSERVER_MODE.md)。
>
> 09:27用户已F7退出、F8关闭、F4清理；助手确认owned0/flags0/relations0/freecam false，相机日记只剩头。已请求一次Restart All Mods，再用阿花/魔渊交战，人物留近处F6约20秒、F7退出；读取HP下限和恢复。名字/声音不用再测试，后台不重启。无仇恨累计1170失败来自三个对象阵营/仇恨组件不可读，不是1170次追击失败；新补丁过滤非当前世界对象并打印身份、召唤后立即更新黑板缓存，原因仍需实机区分。不要操作游戏或自动清场。
>
> 下方v0.27.2是数值统一验收记录，仍保留；四项趣味功能仍仅讨论，新增的是用户本轮明确授权的观战保护。

> **当前运行：v0.27.2-stat-match，数值统一已在阿花→魔渊组合实机通过。** 08:33:30加载；08:33:58与08:34:37两次魔渊应用并读回`verified=109/109`，与首只阿花一致：生命9000、杀气800、攻击70、削杀气33。08:34:24清场后基准重置，随后重新捕获。双方HUD姓名/HP验证均2，交战中HP/Shachi正常减少；用户明确确认“血条和互斗正常”。不扩大为全目录兼容或每一招伤害相等。
>
> 原生GameplayEffect.Modifiers[1].Attribute原位描述传递已通过此次实测，替代了无效的MakeAttribute Lua返回表。当前范围107项基础战斗属性+Health/Shachi，共109项；10个没有对应效果资产证据的扩展字段未写入。实例所有权、一次性出生快照、关闭/清空语义保持。修正后已验证回滚的数值失败不再误判为NPC激活失败；离线回归覆盖恢复警告和未知回滚门禁。35Lua部署hash一致，备份`D:\Claude CODE\影之刃0-backups\v0272-stat-match-20261031-082848`含验收日志/状态/源码快照。
>
> 最新读取仍在战斗：蓝红各1、owned2、F8开启、freecam关闭、数值统一开启，基准阿花、matched1/failures0。保留用户正在玩的场景，**不要自动清场或重载**。目前没有待执行的本轮重载请求。后台v0.27支持接口，详细失败与验证边界见[STAT_MATCH.md](STAT_MATCH.md)。四项趣味功能仍只讨论；打包/独立EXE未实施。下方均为历史记录。

> **当前运行并验收：v0.26.2-native-grabs。** 用户已确认NPC红光抓取可行，双方完整配套动作、结束后继续战斗。原生NonPlayerGE替代分支已定位，v0.26.1的Lua nil写法失败，v0.26.2原生空UClass写入与原配置恢复都有实机读回。只修改参赛NPC族共享Grab事件，保留原命中、Tag条件与双人能力；没有强行播另一招/补伤害/挂钩或写进程内存。详细范围和证据见 [NPC_GRABS.md](NPC_GRABS.md)。
>
> **最新读取仍有正在使用的场景：** 蓝红各1、owned2、F8开启、freecam关闭，3条投技资源快照正常启用，无投技恢复失败。不要自动清场或重载。更新前请用户先F7、关F8、F4并核对恢复。组件计数npc_grab_pairs=0未可靠观察此类配对，不能当作没有投技；用户画面已确认成功。
>
> 怪面术语与重复绑定占用者中文名提示也已完成并经浏览器验证。33Lua部署hash一致，验收日志/状态在`D:\Claude CODE\影之刃0-backups\v0262-native-grabs-20261031-060707`。没有发布或重建远程仓库。杀气锁定、自动精准防御、自动红光闪避、第一人称仍只讨论。下方按时间保留历史过程，以本段为准。

> **新任务（2026-10-31）：** 用户确认术语GuaiMian为“怪面”，面板显示已改为“怪面类”；保留原生枚举/资源路径。用户随后明确要求开始实现**NPC之间的投技**，此前“仅可行性讨论”的边界对该项已被新授权取代。四项趣味功能仍仅讨论。先打通一对人形NPC的一招，核对抓取、受技动画、伤害与释放恢复；不声称所有骨架通用。

> **最新部署：v0.26.2-native-grabs，等待用户重载后测试。** 已定位原生BP_BulletEvent_Grab的非玩家替代分支；v0.26.1实机Lua nil写入未生效（3次verified=false，grabs0），本轮改用CDO原生空UClass值，补充具体错误和读回日志。保留实际命中、目标Tag及原生双人能力，F4/停止恢复参赛族共享资源。33Lua hash一致，8项策略回归通过；尚未实测完整投技。目标是原红光命中后的整段双人动作，不是另加一招。已请求用户关F8/F4清理并重载，再测蓝“勾魂”红“斩骑”；最后读取仍旧版、两只在场、F8开启。完整实时接续点见 [WIP_NPC_GRABS.md](WIP_NPC_GRABS.md) 末尾。

> **当前运行并验收：v0.25.1-observer-input（2026-10-31 05:20:28加载）。** 用户已确认v0.25召唤卡顿及F6血量/杀气节奏“正常了”；新增反馈空格会让原角色跳跃，v0.25.1补上观察相机的动作输入阻挡，用户再次确认观察时不误操作、退出后操作恢复正常。F2、单位卡片键及此前血条/清理均保留。
>
> 05:20:35动作输入层原生读回block=true/priority10000/Owner为自建相机，原玩家关联不变；05:21:00 F6退出，视点恢复true、输入层撤销、自建Actor销毁true、move/look限制false。最新读取自由镜头关闭、owned0、F8关闭、待恢复关系/标志0；free-camera.tsv只剩版本头。继续工作仍先读实时状态。
>
> 31 Lua部署hash一致；相机10项回归及main集成通过。备份与本轮验收日志：`D:\Claude CODE\影之刃0-backups\v0251-observer-input-20261031-051943`。详见 [FREE_CAMERA_AND_SPAWN.md](FREE_CAMERA_AND_SPAWN.md) 最后一节。未发布、未重建远程仓库。投技仍未实现，四项趣味功能仍只讨论；这些不是本轮验收内容。下方旧版本记录仅作历史。

> **当前运行：v0.25-observer-camera（2026-10-31 05:11:05加载）。** 31 Lua 哈希一致；改为独立 CameraActor 观察，保留原玩家控制器与 Pawn。F6/F7 按键不变，WASD/鼠标/QE/Shift 控制；恢复记录在 Runtime/free-camera.tsv，F7可重试。旧 DebugCameraController 只保留退出逻辑。相机9项恢复/归属检查通过；05:11:35实机进入关联/视点读回成功，05:11:36位置变化，05:11:59用户F7退出并确认原生视点/输入/对象清理。不需再重载，等待战斗和召唤耗时实测。
>
> v0.24.1 已由用户明确反馈无效：F6约52秒内双方真实HP与Shachi不变，倍率1、骨骼0、可受伤、AI战斗中；唯一持续变化是 Mod 玩家引用丢失，而 DebugCamera.OriginalControllerRef.Pawn 仍有效。下一轮隔离相机接管方式，不再重复距离/骨骼修改。F2已由用户确认正常。
>
> **召唤卡顿已定位并取得改善读回：** 原先每次扫描约三千个类，最近6次耗时3.52–4.92秒。v0.25移除此步骤，直接解析所选精确路径，保留权限/类/世界验证；05:12阿花从处理到生成回执0.1411秒，05:13 GuiChai_Red为0.0111秒。首次其它资产加载仍可能有成本。F6空场开/关与F7退出均有实机恢复读回；用户已开始新一轮蓝红BOSS对照，场上可能有单位、F8可能开启，勿按旧空场状态重载。无需面板重启。
>
> 本轮详细记录、测试与限制见 [FREE_CAMERA_AND_SPAWN.md](FREE_CAMERA_AND_SPAWN.md)。投技**未实现**，仅做过可行性核对，用户询问时已明确说明；四项趣味功能仍只讨论。下面是历史记录。

> **v0.25后续战斗读回：** 05:14:41–05:14:59用户用两只黄色鬼差MoDao/ShuangGou在新F6下交战，原玩家引用一直有效；约12.7秒采样区间双方HP分别下降168.001/352.800、Shachi下降79.200/158.400。新视角下已有真实削减证据，整体攻击节奏仍等用户反馈。不是与旧阿花配对的逐招DPS比较；勿宣称所有BOSS通用验收。

> **当前运行：v0.24.1-team-bones（2026-10-31 04:50:51 加载）。** 30 个 Lua 哈希核对通过，新增 F2 循环切换下次召唤队伍，保留单位键设置。04:51:08–04:51:18 已读到 6 次 blue/red/neutral 循环，网页随后显示蓝队，F2 注册确认生效；未额外生成单位。无需重启 Python 面板。用户已开始新一轮测试，F8 已开启、参赛者可能存在，继续前读 Runtime，不要再按空场状态要求重载。
>
> **已实机确认：** BOSS 互斗；v0.23.1 姓名、真实 HP 显示与停止清理；v0.24 卡片快捷键召唤。BOSS 召唤物的原生主从/分队/索敌有具体读回，不等于全类型技能验收。
>
> **当前阻塞是 F6 战斗异常，未修好。** v0.24 关闭距离优化无改善；F6 约 20 秒有 10 次连续 HP 采样完全不变，退出后恢复失血。用户补充杀气也很慢，旧日志未采它。v0.24.1 仅对参赛 Mesh 固定完整骨骼刷新做对照，并只读 HP/Shachi/时间倍率/AI 状态和玩家引用，不改伤害或相机操作。04:53:20 阿花读回 visibility 1→0、HP9000/Shachi800、时间倍率均1；等待同对 BOSS 的 F6 开关对照结果。细节、失败证据和验证边界见 [BOSS_AND_CONTROLS.md](BOSS_AND_CONTROLS.md)。
>
> 杀气锁定、自动精准防御、红光自动 Shift、第一人称仍仅讨论；投技兼容未实现。CombatProbe hooks 继续关闭。以下 v0.22 及更早内容为历史记录，不覆盖本段状态。

> **当前运行：v0.22-open-catalog。** 按用户最新明确要求，取消总量上限、所有866个目录条目开放尝试召唤、每批1–8只；新增未配队独立计数与`clear_neutral`清理。00:46:24游戏加载，读回`spawn_mode=all_catalog`、`arena_max_units=0`；新后端PID39592，实际API866/866允许尝试、错误0。旧白名单/火狗隔离/总量2或24的规则均为历史，不再覆盖此明确用户要求。开放尝试不代表全目录兼容通过。
> 死亡HP0立即退出存活计数，尸体所有权保留供清理；网页轮询500ms。用户已实机生成3只未配队长枪暴徒，并确认死亡计数与清理正常。日志有3/3生成、3次HP0存活变化。独立清理命令id73成功；执行时对象已自然清空（确认0、待确认0），不能冒充非空销毁实测。最后读回蓝/红/未配队0、owned0、死亡待清理0、F8关闭。非空未配队清理不影响蓝红已通过离线回归，尚无同场实机隔离样本。
> 24个Lua部署hash一致，相机与共享玩家查找逐字未改，CombatProbe仍关闭。NPC继续原生成链；非NPC新增通用Actor延迟生成，先登记再Finish，不调用PBZ战斗AI，实际非NPC兼容待验证。后端重启被自动审批拒绝，明确授权后仍被拒绝；用户最终亲自运行`panel/重启面板.cmd`完成。不要再操作旧PID36996。详见 [SPAWN_AND_COUNTS.md](SPAWN_AND_COUNTS.md)。

> **面板整理（2026-10-30）：** 用户要求磁盘单位沿用原来的卡片、章节/地图筛选，并明确区分小怪/BOSS。下拉第三项现为“磁盘单位（已解密）”，第四项“原始文件目录”。精确包路径核对866个现有候选均在磁盘，其中852个有角色继承证据（NPC652、其它角色/玩家/Pawn200），14个身份未核对仍放“全部资产候选”。没有新增可确认单位。小怪是原“普通敌人”的显示名称，不声称已区分精英。
> 本轮纯前端部署：`tools/publish_disk_unit_index.py`生成本地忽略的`panel/static/disk_unit_index.js`，仅保存文件路径，不含资源正文/密钥。后端仍为原PID36996，Lua不变；一次服务重启动作被自动审批拒绝，随后撤回后端实验，未停进程。浏览器已验证悲泣溪谷17条小怪/12条BOSS记录（含别名），不需用户重载Mod。详情在作者本地记录中（不公开）。

> **最新补充：物理资源目录已解密并核对（2026-10-30），游戏 Mod 仍为 v0.20.2。** （解密方法与工具只保留在作者本地，不随仓库公开）10 个 pak 的主索引及完整目录 SHA-1 全部通过，主 IoStore 目录树完整遍历。共 **310973 个文件条目**，其中 **252284 个资源包与注册表逐包对应，双方差集均0**。因此下方“没有取得解密目录”已被本次结果取代；未加载地图的资源正文/刷怪字段仍待解析。
> 面板增加“图鉴范围 → 已解密磁盘目录”，支持搜索、文件类型和分页；与单位图鉴分开，无召唤入口。本次只更新面板与只读目录元数据，不改 Lua、不需 Restart All Mods。后端本任务 PID36996；密钥和原始清单保存在仓库外，密钥未进入 Runtime/源码。详细命令、验证和边界在作者本地记录中（不公开）。

> **最新：v0.20.2-catalog-audit（2026-10-30）。** 完整核对当前已挂载注册表267049资产、19736路径，独立起止总数一致，重复/查询/行/标签错误均0；旧扫描漏项22817来自庞镇_Generated_目录的10000上限。不是加密物理目录/未加载地图全覆盖声明。
> 目录已发布：raw929、面板866候选（原674+新增192），主图鉴仍177。新条目主要是玩家与演出/测试角色，没有新增PBZCharacter_NPC派生类；强继承证据NPC652、player7、character189、pawn4。分类与召唤许可独立。
> 刷怪配置历史123条、55类、3区域（LuJiaCun/ZhengDaoDaYing/XiGu）；注册表引用2138包全部空，无法还原全地图。已读5张精确schema表361行；属性表318行的AssetPath仍未解析，不按行名猜关联。详情及未完成边界见 [ASSET_AUDIT.md](ASSET_AUDIT.md)。
> 已部署24个Lua并读到v0.20.2加载；面板进程PID47360，已加入配置证据筛选和玩家/演出分类。所有原始运行数据仍在游戏Runtime/仓库外备份中；不批量召唤未知单位、不重启游戏、不启用CombatProbe。下方v0.19及更早内容为历史。

> **当前最新：v0.19-codex-classification（2026-10-30）。** 已实机导出181条图鉴类归属，覆盖本批12个地图ID和9个具名章节，主图鉴177条全部有地图归属；75条BOSS类记录（含形态/变体）、101普通敌人、1机灵鬼特殊机制。来源是OwnMapID→FMapData.OwnChapterID→FChapterData，不能当作全部刷新点或首次出场顺序。
> 面板默认177主图鉴角色，全部674候选另设视图；章节/地图/类型联动已实测。详见 [CATALOG_CLASSIFICATION.md](CATALOG_CLASSIFICATION.md)。小兵/精英仍缺少可靠绑定字段；无原生证据的特殊用途仍标候选。没有新增召唤许可或修改战斗/镜头，CombatProbe继续禁用。
> 用户已关闭F8、清理并重载；19:36:14游戏确认v0.19及归属读取完成。20个Lua文件哈希一致。面板当前任务进程PID 2804；后端43项、标签25项、地图/图鉴Lua测试、前端分类回归通过。下面v0.18.x为此前历史进展。

> **已恢复工作（2026-10-30 18:30 UTC+8），用户自行启动游戏。**
> 最新部署 **v0.18.3-spectator-consistency**：普通持刀“暴徒”（Sword_Blue）已在 v0.18.1 实机出现掉血、死亡，用户明确确认第一只由另一只怪打死，自己当时未出手；v0.18.2关闭诊断挂钩后再测可互斗，用户暂未遇其它问题，19:08:45存档文件已写入，19:11:03再次F4后恢复记录清零、arena idle。**单种普通NPC互伤已有证据；无hook一轮未崩，不代表长期稳定性或任意单位兼容通过。**
> 用户随后发现F8显示关闭但参赛怪不攻击玩家。已确定arena.start另有无条件NPC↔玩家Neutral，且spectator关闭时保留arena中立；v0.18.3删除这两处隐式免仇恨，让F8成为唯一控制。网页新增玩家资格与待恢复记录读回显示。开战不会自动忽略玩家，需要观战时显式开F8。**新版已加载，用户确认网页与F8同步。** 同步测试曾读到网页关闭；用户随后继续操作并又开启F8，19:20状态为requested=true、flag_readback=false、两队0，保留活动快照。不要把同步测试时的关闭显示当作当前状态；以Runtime状态文件为准。机灵鬼已排除互伤测试。
> **18:45 与18:55两次原生崩溃同为PBZ.exe+0x619C9F0读空指针。** 后一次完整日志紧邻玩家Health Post Func诊断回调；前一次用户在存档时遇到。重启后未召唤时用户存档正常。v0.18.2默认关闭整个CombatProbe挂钩，只保留原生战斗和直接HP读回做隔离，尚未证明根因或稳定修复。增加Runtime/run-*.log，防止UE4SS.log被重启覆盖。
> 生成先登记所有权再FinishSpawn；未知返回停止批次并跨热重载保留保护标记。普通暴徒目前是明确标注的有限测试（单次1只、最多2只）。自由视角及共享玩家查找保持原实现。
> 昨晚的父类工作译名集成已验证：中文标签25项、最新后端41项通过；面板服务当前PID 18068。已备份重开后的存档（24文件，约5.8MB），位置在 `影之刃0-backups/save-crash-20261030-184520/saves-after-clean-restart`。恢复前快照和历史交接见 [PAUSE_2026-10-30.md](PAUSE_2026-10-30.md)。下文较早版本记录仅作历史；最新结果见 REVERSE_ENGINEERING.md 末尾。
> 本轮源码与运行证据快照：`D:\Claude CODE\影之刃0-backups\checkpoint-v0183-20261030`。游戏和面板继续运行，未暂停；未提交/推送/新建GitHub仓库。下一步优先扩展经过单只验证的普通单位并观察稳定性，保持默认关闭CombatProbe；不再重试机灵鬼伤害或按未知名称批量生成。独立EXE仍按用户意见暂缓。


> 更新：2026-10-30，v0.16-spectator，优先核心功能。
> **已实机确认自由视角，以及空场景加载 Vessel Child 并生成两只蓝队怪物。** 全单位覆盖、无仇恨效果、任意怪兼容和真实战斗伤害仍未验收。

## 1. 项目目标

给《影之刃零》做斗蛐蛐 Mod：从游戏数据中建立全单位目录，前端自选单位、队伍和数量，按可配置快捷键召唤、开战和清理；命中后应有真实掉血、受击和正常死亡，玩家可以自由视角观战。

当前已取得一个真实类别的加载和召唤证据，继续验证“分队召唤 → 无仇恨观战 → 请求交战 → 恢复与清理”。目录完整性为 **UNKNOWN**，不能把当前注册表快照声称为已覆盖全部游戏单位。不能把定时扣血、随机受击动画或 `Kill(1)` 清场当作真实战斗的替代验收。

用户明确独立 Windows 原生 EXE 和界面包装现在可以不做，先把功能做好。该工作已暂停；`desktop/RuntimeClient.cs` 只是未编译 WIP，不是已交付修改器。现有本地面板继续用于核心功能测试，普通使用不应要求用户看调试窗口。

## 2. 当前状态与接手决定

**保留引擎适配、已找到的接口和诊断工具；重做实验控制与恢复，不全量推翻。**

- 自由视角已由用户确认。v0.15.1 空场景生成两只蓝队 Vessel Child，AI 和 HP=400 有读回，用户确认看见；这不是任意怪兼容性或交战通过的证明。
- 历史记录有阵营读回、战斗状态和出招观察，但怪物间真实伤害、受击、死亡尚未打通，不能称为“AI 层已完成”。
- v0.14 的 F9 在 `02:18:41` 明确失败于“没有有效怪物类”。旧图鉴依赖活实例且热重载丢失，不能满足已杀光或未遇见单位的召唤需求。
- v0.16 增加 F8 无仇恨与前端按钮；仅请求 NPC→玩家 Neutral、移除玩家仇恨、玩家 `CanBeHatredNow=false`，关闭时恢复。效果尚待用户测试，不动镜头、不造伤害。
- 旧版清理时 `K2_DestroyActor` 已接受，UObject 的 `IsValid` 仍为 true；稍后蓝队数归零而旧 message 滞后。v0.16 使用 `IsActorBeingDestroyed` 读回，并在 `status()` 中清除已进入销毁的记录、更新 idle；待实机复验。
- `03:05:06` 出现 `Ref was not function`，Runtime 心跳停止；PBZ 仍响应，不能写作游戏崩溃。v0.16 改为稳定游戏线程循环以减少跨线程引用操作，根因未证明解决。
- 本轮 **13 个 Lua 文件已部署**，本地测试面板已启动；备份见第 3 节。部署成功与离线测试通过不等于游戏验收。
- F6 / F7 相机函数及共享玩家查找函数逐字未动；F8 固定为无仇恨，三者均不在四个可重映射快捷键中。
- 原 GitHub 仓库已按用户要求删除；操作回执为网页成功、API 返回 404。本地代码与历史保留，当前不公开发布。

## 3. 环境

| 项 | 位置 / 记录 |
| --- | --- |
| 本地仓库 | `D:\Claude CODE\影之刃0`；原远程仓库已删除 |
| 游戏 | `D:\steam\steamapps\common\PBZ`，历史记录：Steam build 26266538、UE 5.7.4 Shipping |
| 游戏本体 | `platform\steam\PBZ.exe`；`steam\PBZ.exe` 是启动器 |
| UE4SS | `platform\steam\ue4ss\`，历史记录：experimental 3.0.1-1185；使用 `GameConfig/` 适配 |
| Mod 部署 | `platform\steam\ue4ss\Mods\PhantomGladiator\` |
| v0.16 部署前备份 | `D:\Claude CODE\影之刃0-backups\deployed-before-v016-20261030-033056` |
| Runtime | `D:\steam\steamapps\common\PBZ\platform\steam\ue4ss\Mods\PhantomGladiator\Runtime`；配置明确指定，面板与游戏必须使用同一目录 |
| 本地面板 | `http://127.0.0.1:8765`；入口 `panel/Run-Panel.ps1`，后端 `panel/backend.py`，页面 `panel/static/` |
| 日志 | `D:\steam\steamapps\common\PBZ\platform\steam\ue4ss\UE4SS.log` |
| 头文件 | `D:\steam\steamapps\common\PBZ\platform\steam\ue4ss\CXXHeaderDump\`；查类和签名先搜这里，禁止提交这些导出 |
| 相对诊断文件 | 游戏工作目录 `ProjectPBZ\Binaries\Win64\` 下的 `brain_dump.txt`、`collision_matrix.txt` |
| 纯 Lua 测试解释器 | `D:\texlive\2026\bin\windows\texlua.exe`，本轮已实际运行 |

## 4. 开发、部署与测试循环

**只有用户能操作游戏。助手只改代码、部署、读日志，不代替用户按键或重载关卡。**

1. 修改脚本，做静态检查和可运行的纯 Lua 测试。`python -I tools/lua_balance.py <文件>` 只检查块配对，不能代替 Lua 解析或游戏验证。
2. 部署到游戏目录并核对脚本哈希。本轮已完成 13 个 Lua 文件部署；以后修改仍需重新部署：

   ```powershell
   Copy-Item "D:\Claude CODE\影之刃0\Mods\PhantomGladiator\Scripts\*" "D:\steam\steamapps\common\PBZ\platform\steam\ue4ss\Mods\PhantomGladiator\Scripts\" -Force
   ```

3. 热重载前先**关闭 F8 无仇恨并等待恢复**，再按 **F4**，等取消、恢复及参赛者清理结果。恢复失败条目仍保留供重试，未完成时不要用热重载丢弃账本。用户不必读调试窗口，助手核对日志即可。
4. 用户在 UE4SS 窗口点 **Restart All Mods**。读取日志确认新版本加载；`loaded` 只说明 Lua 已加载，不说明游戏功能通过。
5. 打开面板，核对游戏心跳、版本和 ACK；用户扫描目录、选择、召唤和开战。助手读取日志，把观察、失败和未解问题写入 `REVERSE_ENGINEERING.md`。

**F4 的边界：**先使旧会话及已排队回调失效，再恢复当前 Lua 生命周期记录过的改动，清理范围仅限本 Mod 生成的参赛者，不能把地图原生怪物当作清场对象。它不能追溯 v0.12 的无快照改动，也不能保证恢复未记录的全部游戏状态。Restart All Mods 会清空 Lua 账本，不会自动复原游戏对象。

**首次从 v0.12 迁移：**加载新版后，请用户自行回标题重进或重新加载关卡，重建对象，再开始测试。不能把热重载当作干净场景。

## 5. v0.16 按键与现有测试面板

| 按键 | 用途与状态 |
| --- | --- |
| F6 / F7 | 保留自由视角开关 / 强制退出；用户已确认正常，代码逐字未动 |
| F8 | 固定无仇恨开关；前端也有按钮，效果待实测 |
| F9 | 召唤面板已同步的当前单位、队伍和数量；默认数量为 1，不自动开战 |
| F3 | 开始本 Mod 蓝红参赛者交战；不把地图原生 NPC 当作参赛者 |
| F4 | 停止探针、取消会话、恢复账本并清理仅本 Mod 生成的参赛者；以日志读回为准 |
| F1 | 从当前游戏资源注册表扫描候选单位路径，不要求场上有活 NPC |

面板可设置召唤、开战、停止、刷新目录四个快捷键，使用游戏 ACK 与状态读回确认生效。选择通过 `select_unit` 同步；尚未确认时快捷键可能仍使用上一单位、队伍或数量。F6 / F7 / F8 均保留，不进入动态改键。

`spectator_enabled` 是开启请求状态，不等于所有 NPC 已停止攻击。开启时只处理 NPC 对玩家的关系和仇恨、玩家可被仇恨标志；关闭恢复原记录。必须分别核对开启读回、画面行为和关闭恢复，不能把按钮亮起当作行为已通过。

`Config.EnableBattleExperiments=false` 继续关闭旧全场实验，不阻止面板的受管理参赛者流程。旧定时扣血、动画猜测等路径不能代替真实战斗。

面板服务本轮已在本机启动。以后从仓库根目录启动：

```powershell
powershell -File .\panel\Run-Panel.ps1
```

访问 `http://127.0.0.1:8765`。网页在线与游戏在线分开：只有 Runtime 中持续更新的游戏心跳才说明游戏桥在运行；`queued/pending` 不是执行成功。journal 记录同 ID 的执行状态，重复 ID 重发原 ACK；中断或执行量未知用 `uncertain`，不自动重放召唤。

## 6. 下一轮优先验证无仇恨与恢复

1. 按第 4 节关闭无仇恨、恢复并清理后，由用户点 **Restart All Mods**；助手确认 `v0.16-spectator`，面板等待游戏心跳恢复。
2. 用户按 **F8** 或点前端无仇恨按钮，观察 NPC 是否不再追打玩家；再关一次，检查原行为是否恢复。助手核对关系、仇恨标志和恢复日志。
3. 需要参赛者时，从已有候选中选择单位与蓝/红队，等待同步后召唤。已确认的 Vessel Child 可先复验；其他类别仍是新样本，不算已通过。
4. 用户另按 F3 请求交战，可用 F6 / F7 观战。描述互攻、罚站、掉血、受击和死亡；助手读取日志。
5. 结束前先关 F8 并等恢复，再 F4 清理；核对 `IsActorBeingDestroyed`、队伍计数和 idle 状态是否一致，不只看旧 message。

目录可通过 F1 / 前端继续扫描。上一轮 19736 条缓存路径尚未遍历完，当前 708 条粗候选中包含非单位；后端按 `nativeParent` 过滤已识别武器、技能、组件并禁用 Base 类。候选数不是可召怪物数，覆盖范围仍为 UNKNOWN。

本轮不再要求用户只让怪物攻击玩家或靠 F1 找附近活怪。正常受伤对照已有用户确认，但原生探针未捕获伤害；观察继续随实际斗蛐蛐流程进行。挂钩安装成功不等于捕捉到执行，零计数不能直接排除路径。

## 7. 历史实验记录与纠正

以下保留失败证据；结论仅限当时条件。没有新证据不重复相同写法，不能把一轮失败扩大成整个系统已排除。

| 历史做法 | 当时观察 | 现在允许的结论 |
| --- | --- | --- |
| 写 Pawn/Controller 的 `GenericTeamId` | 未解决索敌 | 该写法未奏效；不足以排除全部标准阵营路径 |
| 蓝图态度 hook 放在 `RegisterHook` 第三个回调参数 | 计数为 0 | **回调位置无效，旧“从未调用”排除结论作废**；蓝图路径应使用支持的第二回调 |
| v0.13.1 正常玩家受伤对照（01:56:58–01:57:29） | 用户确认掉血和受击；6 个原生入口 pre/post 均 0，PBZAttitude 达到 2000，触及事件预算 | 态度回调可观察，原生探针未捕获伤害；不能称伤害函数未执行。v0.14 默认不装高频态度探针 |
| v0.14 F9（02:18:41） | 日志明确“没有有效怪物类”，用户看不到召唤物 | 独立目录与按需加载已在下面的 Vessel Child 样本复验，不能推广到任意怪物 |
| v0.15.1 资源扫描（02:55:35） | 注册表读回 19736 条缓存路径；遍历未完成 | 证明获得真实扫描输入，不证明完整单位目录已导出 |
| v0.15.1 空场景召唤（03:00:06 起） | 真实 `BP_Monster_Vessel_Child_C` 路径 `LoadAsset` 返回 `found=true/loaded=true`；两只蓝队怪物生成，AI/HP=400 有读回，用户确认出现 | 一个具体类别的按需加载与召唤已得到实机证据；未证明正常交战或任意类别兼容 |
| v0.15.1 清理 | `K2_DestroyActor` 接受后 `IsValid` 仍 true；后来 `blue_count=0`，旧 message 滞后 | 不能只等 UObject 失效；v0.16 新增销毁状态读回和 status prune，待实测 |
| v0.15.1 扫描停滞（03:05:06） | 进度到 9004/19736 后 `Ref was not function`、无 traceback，心跳停止；游戏进程仍响应 | 调度/回调链异常，根因未定；稳定游戏线程循环是风险缓解，不能宣称故障已解决 |
| `ForceIntoCombat`、黑板写入、仇恨数组直写 | 曾短暂出招、目标回弹；高频强制会打断出招 | 只说明组合干预产生过观察，尚未验收稳定锁敌 |
| 官方 `AddActorToHatredList` | 列表未增加，阵营敌对后仍如此 | 门禁仍待定位；数组写入不是官方门禁已修好 |
| 关系覆盖 / `SetFaction("Faction.Player")` | 关系可读回敌对，仍未看到怪物间掉血 | Actor 关系变化不足；**撤销“阵营这条线到头了”** |
| 官方刷怪、激活、六类可疑 GE 检查 | 换刷怪方式未改善；所查效果当时不存在 | 未解决当前样本；不能排除所有登场状态或所有召唤类 |
| 胶囊与模型碰撞开关 | 读到 3（查询+物理） | 当时这些组件未整体关闭，身体互穿不等于攻击判定原因已确定 |
| 复制玩家碰撞通道 | 当场读回修改成功，约 75 秒仍满血；用户说身体仍互穿 | 单次复制未解决；持续读回、真正检测入口和过滤条件仍未知 |
| `GameplayStatics.ApplyDamage` | 未产生所需效果 | 该通用接口实验失败 |
| 直写 Health、`Kill(1)`、猜测蒙太奇 | 可改数值但无合格受击/死亡，有瞬间消失或打断出招 | 不满足真实战斗要求，不作为可玩保底承诺 |

## 8. 新证据与接下来的判断方式

`CXXHeaderDump/SGameCombatSystem.hpp` 的 `UBulletAttackModule` 包含 `TargetRequiredTags`、`TargetIgnoredTags`、`FactionCalculator`、`SetAttackerFaction`、`IsValidTarget`、`TryAttack` 和 `DealDamageToAvatar`。攻击模块有自己的标签与阵营筛选接口，Actor 的关系读回不能证明攻击模块接受了目标。接口存在是静态证据，当前样本是否走这些函数仍需 Trace。

v0.16 保留动态蓝图回调和原生攻击实例观察：蓝图路径从实际对象的 Class/父链读取，不猜资源路径；把 `PBZ_SweepTraceBullet.BulletOwnerAvatar` 与参赛者对应，再读攻击/扫掠模块及 `IsValidTarget` 返回值。离线测试已检查这些观察器的边界，但当前伤害修复仍未获得实机证据。`MyData` 等 DataAsset 可能共享，不允许为一对参赛者全局改写。

调度已从 `LoopAsync → ExecuteInGameThread` 每轮新引用改为 `LoopInGameThreadWithDelay` 的单个稳定回调；战斗/HP 观察同样使用该 API，Probe 单次延时使用 `ExecuteInGameThreadWithDelay`。停止必须明确 `CancelDelayedAction(handle)`，返回 true 不会停止游戏线程循环。此修改减少跨线程引用操作，但不能由纯 mock 推断实际 UE4SS GC/并发问题已修复。仅重载 Mod 可能恢复轮询，不保证底层调度异常已经消失。

资源目录使用当前 cooked Asset Registry 的真实 metadata，候选路径不是 NPC 身份证明。`npc_catalog` 登记完整 generated-class 路径，拒绝基类、遍历及非法格式；只对当前选中类别按需加载，读回 `IsAnyClass`、原始路径以及到 `PBZCharacter_NPC` 的继承后才交给生成流程。Blueprint 资产对象不能当 UClass；非 NPC 的合法路径也必须拒绝。当前导出的覆盖范围和部分资产的可加载性仍为 UNKNOWN。

`UCharAttackCollisionComponent:FireAttackLines` 也只是候选入口。观察到它不能直接证明故障在检测之后；观察不到也不能证明怪物不用该组件，需先核实 hook 安装、调用方式和正常攻击对照。旧的二分判断作废。

用户已确认见过普通怪物原生互打并掉血或死亡；具体单位和场景尚未给出，助手尚未独立采集。原生 NPC 互打场景、原生召唤技能可作为后续对照。自建命中判定仍只是备选设计；受击、格挡、死亡和不同怪物兼容性未解决前，不承诺“一定能做成”。

## 9. 代码与验证

| 文件 | 职责 |
| --- | --- |
| `Mods/PhantomGladiator/Scripts/main.lua` | 按键、游戏接口、实验流程与模块接入 |
| `Mods/PhantomGladiator/Scripts/config.lua` | 按键和实验门控；受管理擂台流程与旧全场实验分开 |
| `Mods/PhantomGladiator/Scripts/npc_catalog.lua` | 已知类目录、持久选择、合法 NPC 类校验、当前选中类的按需加载 |
| `Mods/PhantomGladiator/Scripts/asset_catalog_export.lua` | 分批读取当前游戏注册表，导出候选单位及实际路径，报告截断与未知覆盖 |
| `Mods/PhantomGladiator/Scripts/arena_controller.lua` | 单位/队伍/数量选择、逐个生成、参赛者管理、开战和清理 |
| `Mods/PhantomGladiator/Scripts/spectator_mode.lua` | F8 无仇恨请求、NPC→玩家关系及仇恨处理、玩家标志快照与关闭恢复 |
| `Mods/PhantomGladiator/Scripts/panel_bridge.lua` | TSV 输入/状态/ACK、持久 journal、同 ID 幂等和 uncertain 恢复 |
| `Mods/PhantomGladiator/Scripts/panel_runtime.lua` | 面板与动态快捷键共用动作、游戏线程分发、心跳与选择同步 |
| `panel/backend.py` / `panel/static/` | 本机串行命令队列与浏览器面板；不把网页可用等同游戏在线 |
| `desktop/RuntimeClient.cs` | 未编译的原生客户端 WIP；原生 EXE/界面工作已暂停，不是交付物 |
| `Mods/PhantomGladiator/Scripts/attack_profile.lua` | 有界读取实际攻击实例、目标资格和过滤字段，内容变化去重 |
| `Mods/PhantomGladiator/Scripts/combat_probe.lua` | 有界只读探针、实际类蓝图入口发现、安装状态与读回；态度探针默认关闭 |
| `Mods/PhantomGladiator/Scripts/battle_session.lua` | 会话取消、首次快照、写后读回、逆序恢复与失败重试；自身不调用 UE API |
| `Mods/PhantomGladiator/Scripts/teams.lua` / `hatred.lua` | 历史实验接口；不表示相关功能已验收 |
| `tests/test_battle_session.lua` | 纯 Lua 会话与恢复测试 |
| `GameConfig/` / `tools/` | 引擎适配、签名/转储分析、块配对检查 |

当前模块的离线验证入口如下，从仓库根目录运行，不接触游戏进程。擂台回归已覆盖 UObject 仍有效但 Actor 销毁中、延迟销毁后 status 归零，以及查询失败保留所有权；调度 mock 不能证明运行时 GC/并发安全：

```powershell
$luaTestExe = 'D:\texlive\2026\bin\windows\texlua.exe'
& $luaTestExe tests/test_battle_session.lua
& $luaTestExe tools/test_combat_probe.lua
& $luaTestExe tools/test_attack_profile.lua
& $luaTestExe tools/test_npc_catalog.lua
& $luaTestExe tools/test_asset_catalog_export.lua
& $luaTestExe tools/test_arena_controller.lua
& $luaTestExe tools/test_spectator_mode.lua
& $luaTestExe tools/test_panel_bridge.lua
& $luaTestExe tools/test_panel_runtime.lua
python -I panel/test_backend.py
```

主程序集成使用新入口 `tools/test_main_boot.lua`。必须传独立存在的测试目录，**不能使用真实游戏 Runtime**：

```powershell
$bootTestRuntime = Join-Path $env:TEMP ('PhantomGladiator-boot-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $bootTestRuntime | Out-Null
& 'D:\texlive\2026\bin\windows\texlua.exe' tools/test_main_boot.lua $bootTestRuntime
```

该入口加载真实 main 和所有 Lua 模块，验证空 NPC 条件下仍解析已知类、游戏线程分发、相机按键绑定与卸载失效；不执行真实资产加载或生成。`tests/test_main_controls.lua` 是 **v0.14 历史基线，不再作为当前测试入口**，旧流程的通过数不能套到 v0.16。

以上测试本身均为离线证据。实机已确认注册表缓存路径返回，以及一个 Vessel Child 类的加载和双怪生成；完整目录、其他类别、F8 行为与恢复、新清理读回、持续调度、蓝红主动交战和真实伤害仍须逐项验证。

## 10. 继续遵守的规则

- UObject 每一级先 `IsValid` 再访问下一级；`pcall` 只能拦 Lua 错误，不能拦原生崩溃。
- 缓存的 Pawn、组件、类和 Owner 都可能失效；不能只验证最外层。
- 每个实验记录版本、做了什么、读回什么；“调用未报错”与“读回满足目标”分开。
- `FindFirstOf` 可能返回旧对象；按有效性、Owner 和当前世界筛选。
- FName 用 `ToString()`；导出的函数可能缺返回类型，签名与参数方向仍需核对。
- 属性名可能带空格；组件枚举的替代方法也要检查对象有效性。
- 不生成 mapping dump（历史记录会崩溃），不提交头文件、资源、日志或崩溃转储。

历史细节见 [REVERSE_ENGINEERING.md](REVERSE_ENGINEERING.md)。`DESIGN.md` 是规划；`ASTRA_REVIEW.md` 与 `CONSULT_BRIEF.md` 是历史讨论，不能当作已验证结论。

### 最新验收更新

03:35用户确认F8“开启不再追打，关闭后恢复追打”，日志player flag与NPC关系恢复读回一致。当前蓝队有若干用户召唤单位，等待用户清理后蓝红各一开战；伤害与死亡尚未确认。v0.16稳定游戏线程pump已有连续心跳，但长期稳定性继续观察。
