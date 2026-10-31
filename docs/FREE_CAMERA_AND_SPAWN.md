# F6 控制器隔离与召唤卡顿

2026-10-31，v0.25-observer-camera。31 Lua 文件已部署并核对 SHA-256，05:11:05实机加载。Python 后台与单位绑定文件未改。进入、移动、F6/F7退出、两次快速召唤以及一组BOSS在F6下HP/Shachi继续下降均有原生读回；整体攻击节奏仍等用户反馈。

## v0.24.1 对照失败

用户明确确认 F2 切队正常，F6 下血量和杀气仍慢，退出恢复。不能将固定骨骼刷新报告为修复。

本轮使用阿花和 GuiChai_Red。04:57:15.399 进入旧调试相机，04:58:07.456 退出，历时约 52 秒。04:57:15.725 至 04:58:02.996 的连续只读采样保持：

| 参赛者 | HP | Shachi | Attack / ShachiAttack |
| --- | ---: | ---: | --- |
| 阿花 | 8678 | 551.7000 | 70 / 33 |
| GuiChai_Red | 7755 | 786.7501 | 70 / 33 |

世界和演出时间倍率均 1，Actor 时间倍率在 F6 采样中均 1，bCanBeDamaged=true，AI.State.Combat，anim_visibility=0。优化 wave 有过1/2切换，但双方 wave=1、骨骼0时仍不扣数值。退出后立即恢复：04:58:13 阿花 HP8214.98/Shachi347.10，GuiChai_Red HP7531/Shachi631.65。

**显著关联变化：** F6 前 `mod_player=91839971344`；进入后 `mod_player=nil`、`debug_original_pawn=91839971344`；退出恢复。现有 GetRealPlayerController 要求非 DebugCameraController 持有 UPlayer，与调试相机转移控制器的做法不兼容。已证明 Mod 失去玩家引用，尚未证明这是原生伤害停滞的全部根因。

## v0.25 相机修改

新模块 `free_camera.lua` 使用原生 CameraActor 加 `SetViewTargetWithBlend`，保留原 UPlayer↔PlayerController、Pawn 关联，不 Possess/UnPossess，不进入 ToggleDebugCamera。进入前后读回关联与视点；旧 DebugCameraController 仅保留退出兼容。

- F6 开关，F7 强制退出。WASD 移动、Q/E 升降、Shift 加速、鼠标转向。
- 进入时记录原视点、原移动/转向忽略状态，只增加自己需要的一层输入限制，退出只释放自己的增量。不会 Reset 全局输入标志。
- 原玩家模型留在原位置，未转成相机 Pawn；F8 无仇恨仍独立控制。
- 相机更新用稳定游戏线程定时器。每帧只访问已验证对象，不遍历全局控制器或 Actor；使用原生真实时间增量移动，核对实际位置。
- 保存 `Runtime/free-camera.tsv` 的对象完整路径/地址及恢复状态；卸载只取消回调，不碰引擎对象。下一次游戏线程核对精确身份后恢复；不对新的玩家控制器套用旧标志。
- 失败回滚、他人覆盖视点、对象失效、创建结果未知均有独立处理；创建结果未知不重复生成。
- v0.24.1 的参赛者优化/骨骼策略保持，以单独比较相机接管方式。没有修改伤害、杀气或全局时间倍率。

本地 SDK 已核对 CameraActor.CameraComponent、GetCameraLocation/GetCameraRotation/GetFOVAngle、FKey.KeyName、GetInputAnalogKeyState、GetViewTarget/SetViewTargetWithBlend、SetIgnoreMove/LookInput、GetRealTimeSeconds 和 K2_SetActorLocationAndRotation。接口语义参考 [Epic 摄像机文档](https://dev.epicgames.com/documentation/unreal-engine/API/Runtime/Engine/GameFramework/APlayerController/SetViewTargetWithBlend?application_version=5.5) 及 [UE4SS StaticFindObject 文档](https://docs.ue4ss.com/lua-api/global-functions/staticfindobject.html)。签名存在不表示本游戏相机已验收。

## 每次召唤卡数秒的已定位开销

Arena.spawn 每次都调用 Catalog.refresh({})，它在游戏线程扫描全部 BlueprintGeneratedClass 并重新检查很多已知类。空数组只是不传入地图 NPC，不代表没有全局扫描。

最近六轮刷新耗时分别为 **4.7728、4.9241、3.5985、3.5227、3.9451、3.9860 秒**。其中 04:56:39→04:56:43 的阿花扫描3268类、04:56:49→04:56:53 的 GuiChai_Red 扫描3409类。随后 LoadAsset 约0.106/0.213秒，生成到激活读回约0.015秒。用户观察到的数秒停顿有明确的多余扫描开销；不能因此声称任何首次资源加载都不会卡顿。

v0.25 将全量刷新移出召唤路径：注册/选择精确路径后，直接验证并解析这一类。Catalog 构造时只从保存的选择或配置的首个已知路径建立默认选择，不做资产加载；实际 UClass、继承、路径、玩家/世界和生成权限校验仍保留。F1/目录读取功能独立存在。

回归在旧代码上明确失败于“spawning an exact selected class must not perform a global catalog refresh”；修改后 Arena 回归、17 项 Catalog 回归及真实 main 的无NPC启动解析通过。新增测试阻止任何全局 discovery 调用，不用“按钮返回成功”冒充性能证明。实际卡顿改善等待用户实测和新日志计时。

## 验证与继续

相机9项离线检查通过：不切换玩家、移动读回、原输入状态保留、其它系统额外限制保留、失败回滚、卸载后回调失效、跨重载恢复、游戏接管视点不覆盖、未知生成不重试。main 的 NPC/通用 Actor 两条加载路径、activity、runtime18项通过；移除扫描后再次通过 Arena/Catalog/main NPC。

部署备份：`D:\Claude CODE\影之刃0-backups\v025-observer-camera-20261031-050824`，含 v0.24.1 失败日志、旧脚本和31文件哈希清单。部署前 actual state：自由镜头关闭、owned0、F8关闭、待恢复关系/标志0。后续以实时 Runtime 为准。

用户待测：先重载，空场 F6 进入/移动/退出；成功后再同组 BOSS 做 F6 战斗对照，并观察召唤卡顿。不要重复要求重启面板后台。

05:11:35.736 实机 F6 进入，原控制器/Player/Pawn关联验证通过，ViewTarget为唯一自建CameraActor。05:11:36.409得到输入后位置变化的实际读回。05:11:59.324 用户F7退出，原视点恢复verified=true、move/look限制读回false、自建相机原生失效removed=true。此时空场，不能代替NPC伤害验收。日志没有新Lua异常；不再要求重复重载。

05:12:02再次进入，05:12:10通过F6退出，同样读回原视点/输入限制恢复和自建相机销毁。两种退出入口都有实机证据。

新召唤路径第一批实机计时：阿花从05:12:39.991236开始处理，到05:12:40.132289生成回执，约**0.1411秒**（含约0.051秒LoadAsset）；GuiChai_Red从05:13:11.277962到05:13:11.289069，约**0.0111秒**，精确类查找直接命中。这两次没有全量目录刷新。数值表示这两次Lua召唤处理区间，不是任意资产首次加载或整个游戏帧时间的保证。

05:14:41.749–05:14:59.704 的新相机战斗样本使用 **GuiChai_Yellow_MoDao / GuiChai_Yellow_ShuangGou**，并非旧版阿花/GiuChai_Red配对，不把它当同一对逐招DPS比较。F6内每类4次采样，mod_player始终有效、时间倍率1：05:14:41.783→05:14:54.509，MoDao HP9484.7998→9316.7988、Shachi483.7201→404.5201；ShuangGou HP9286→8933.2002、Shachi766.3801→607.9802。**这组已证明新F6下双方持续产生真实血量和杀气削减，没有旧样本的整段冻结。** 尚需用户确认画面和攻击节奏，不声称任何BOSS兼容。退出通过F6，视点/输入/相机清理均读回成功。原始证据在备份的 `v025-combat-freecam.log`、`v025-freecam-samples.json`。

投技尚未实现。先前只核对到 NonPlayerGE、执行者/受技者能力及配套动画，不是 NPC 互摔验收。杀气锁定、自动精准防御、自动 Shift 红光闪避、第一人称仍只讨论。

## v0.25.1：用户验收与观察模式动作输入修复

用户对v0.25明确反馈：镜头能进入/移动/退出，召唤卡顿与F6血量/杀气削减“正常了”；但空格仍让原角色跳跃。可将本轮相机接管方式与召唤扫描问题记录为实测通过，不能扩大为所有BOSS长期稳定性保证。旧方案切换控制器与玩家引用失效已有日志；没有逆向定位到游戏内部具体哪条伤害分支，原因解释应限于调试相机接管方式不兼容。

动作泄漏是新增观察相机只调用SetIgnoreMoveInput/SetIgnoreLookInput，未覆盖跳跃、攻击、闪避等动作。v0.25.1在**自建CameraActor**上设置bBlockInput=true、InputPriority=10000，然后EnableInput(originalPC)；验证新InputComponent有效且Owner是该相机。原Pawn/PC的输入组件和映射不拆除、不禁用，原始按键仍给相机使用。退出先对自建相机DisableInput，再由其原生销毁读回确认清理，恢复记录新增input_owned并兼容旧记录。

本地Engine.hpp已确认这些字段/函数。语义依据：[Epic AActor输入栈说明](https://dev.epicgames.com/documentation/unreal-engine/API/Runtime/Engine/AActor)。输入阻挡测试在v0.25上失败于Space/attack仍传给玩家；修正后相机10项回归通过，涵盖原始移动读取、退出恢复、输入层创建失败回滚及热重载恢复。模拟输入栈本身不代替实机验收。

**实机验收：** 05:20:28加载v0.25.1；05:20:35读回block=true、priority10000、component_owner=observer，随后相机位置随输入变化；05:21:00通过F6恢复视点verified=true，撤销观察输入层，move/look=false，camera removed=true。用户测试空格、鼠标左键、Shift和退出后的角色操作，回复“正常了”。没有新Lua异常。最新状态：freecam=false、owned0、F8=false、pending flags/relations=0，恢复journal仅剩FreeCameraV1。

部署备份：`D:\Claude CODE\影之刃0-backups\v0251-observer-input-20261031-051943`；31个Lua源码与部署一致，验收原生日志为`v0251-confirmed.log`。本轮没有改投技或四项讨论功能，没有重启后台或发布远程仓库。
