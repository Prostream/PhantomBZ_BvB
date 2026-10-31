# v0.29 常驻血条与生命数字

2026-10-31。用户报告血条不能常驻，要求在血条上方显示具体生命。用户明确选择：**死亡后隐藏，只让存活单位常驻**。范围延续原功能，为蓝红参赛BOSS；未扩展到所有小兵或特殊实体。

## 原因与变更

v0.28.2实机日志多次出现`[BossHUD] 拒绝覆盖绑定到其它角色的控件`，持续约数分钟。原实现从游戏BossPoint扩展池取得控件并缓存；游戏复用/重绑后，缓存仍指向那个控件，原安全门禁拒绝改写其他角色，导致对应血条停止更新。这是具体绑定失效证据，不是推断为数值基准复制了姓名。

v0.29新增`arena_hud.lua`管理生命周期，`arena_hud_widget.lua`创建独立的原生WB_BossHPBar实例。使用本机完整资产索引核对的`/Game/PBZContent/UI/Hud/WB_BossHPBar.WB_BossHPBar_C`，保留原血条样式，不再借用游戏可复用的扩展池控件。只隐藏角色确实属于已显示参赛者的原生重复条，结束后恢复原可见性；无关原生BOSS条不改。

每个私有WidgetTree增加Overlay和TextBlock，在原内容上方留28个布局单位显示“当前生命 / 最大生命”。数值读取实际Actor属性；有小数时显示一位。名字按自己的class_path/队伍读取。蓝红左右分列、多只按各队顺序排列。控件、根Overlay、生命条、名字和数字保持可见，且不拦鼠标；绑定异常时释放自己的控件后重建，不覆盖游戏其它控件。

保持hp>0才显示；死亡或实体失效移除，F4清空自建条。创建失败每Actor最多3次，清理重置；不自动重复召唤、不改变战斗数据。旧`arena_boss_hud.lua`保留为历史回归材料，main已改用arena_hud。

## 验证

- 管理器回归：独立归属、控件重绑恢复、真实HP/max、死亡隐藏、创建失败上限与清理重试通过。
- 渲染适配回归：根树归属、数字位于原内容上方、实际文本读回、被隐藏后的显示恢复、原生重复条隔离、错误绑定拒绝、移除通过。
- main实际加载、runtime19项、JS语法通过；39Lua部署hash一致。
- 10:16:08加载；10:16:18/24分别创建阿花/魔渊独立控件。初始数字9000/9000及12000/12000读回正确；初始CurPercent内部读回尚未验证。首次受击后visible/name/hp/number均true，随后多分钟保持，数值分别更新至5369.1/9000和8325/12000等。当前API两条visible/name/health/number均2、pending0。
- 用户明确确认“显示正常，数字会变化”。后续第二轮10:23:58阿花HP从76.26降到0，约0.3秒后其私有血条移除读回true；10:24:16 F4移除剩余血条，读回true。死亡隐藏和实际移除现已有实机证据。
- 此次F4保留了1条旧战斗黑板恢复记录（与私有UI无关），10:30:51用户再按F4后确认黑板对象已无效、丢弃过期记录，恢复true。最终arena idle、owned0、F6/F8关闭、HUD/数字/pending与恢复记录均0。该旧恢复重试边界保留记录，不声称单次清理在所有情形都完成。

备份`D:\Claude CODE\影之刃0-backups\v029-persistent-hud-20261031-101521`，包含观战验收/旧重绑日志、v029-user-confirmed.log、39Lua源码快照及最终清空状态。游戏仍在运行；以最新状态为准，不自动操作游戏。

原生接口按本地UMG/SlateCore/WB_BossHPBar头文件核对，包括本构建HitTestInvisible=3。新UWidget对象使用[UE4SS StaticConstructObject](https://docs.ue4ss.com/dev/lua-api/global-functions/staticconstructobject.html)创建并验证Outer，再通过原生UMG父容器持有，不依靠Lua变量延长失效对象寿命。
