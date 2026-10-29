# 《影之刃零》斗蛐蛐 Mod — 前期调研与设计草案

> 调研日期：2026-10-26（游戏 10-29 发售）
> 目标：NPC 互相仇恨 / 怪物互斗 / 自由视角 / 怪物组队打 BOSS

---

## 一、现有同类 Mod 调研

### 1. 只狼《Puppeteer Allies》（最接近的参照）
来源：https://www.nexusmods.com/sekiro/mods/2753

核心功能：
- **混乱机制**：对敌人投掷道具（灰/油）使其进入"混乱"状态，开始攻击身边其他敌人；全场没有别的敌人时才会转头打玩家
- **收买机制**：扔钱可以把敌人临时变成盟友
- **状态可视化**：被混乱/收买的敌人头上显示血条和架势条，观战时能看清战况
- **状态恢复**：混乱计时结束后敌人恢复正常而不是死亡

启示：*玩家主动"点燃"战斗* 比全局改阵营更有游戏性；战况 UI 是观赏体验的关键。

### 2. 艾尔登法环：Garden of Eyes 的 BOSS 对战系列
来源：https://www.gamepro.de/artikel/elden-ring-demigod-boss-showdown,3380937.html

- 让六大半神 BOSS（恶兆、拉塔恩、玛莲妮亚等）互殴，分多轮、带规则（禁用某些即死技能、调整血量倍率 NG+7）
- 本质是修改 FromSoft 的 **TeamType（阵营 ID）** + 把两个 BOSS 传送到同一竞技场
- 产出形式主要是视频内容——说明这类 Mod 的最大受众其实是**观赏/内容创作**

### 3. 法环 BOSS 召唤类 Mod
来源：https://itc.ua/en/news/mod-for-elden-ring-shadow-of-the-erdtree-allows-you-to-summon-bosses-like-pokemon/

- 把骨灰召唤物替换成 DLC BOSS（"宝可梦式"召唤），BOSS 作为盟友替你打架
- 黑神话也有同思路的 Mod（变身/召唤 BOSS 替代分身）
- 启示：**"收服怪物当队友"** 是斗蛐蛐的近亲玩法，实现上复用同一套阵营系统

### 4. 上古卷轴 5 竞技场系 Mod（玩法化的天花板）
来源：https://www.nexusmods.com/skyrim/mods/107292 等

- **Arenas of Skyrim**：多城市竞技场，NPC 对战 + **押注系统**
- **Live Another Life** 的斗兽场：1v1 / 团队赛 / 法师笼斗 / 大乱斗多种赛制，可观战、押注、参战、**做局操纵比赛**
- 启示：斗蛐蛐从"调试玩具"进化成"玩法"的关键 = 赛制 + 经济系统（押注）+ 观战体验

### 5. 可借鉴的官方设计
- **怪物猎人「生态互斗 (Turf War)」**：特定怪物组合相遇触发专属演出互殴并掉血——"互斗也可以有专属动画演出"
- **中土世界：暗影魔多「Nemesis 系统」**：NPC 之间有持久的等级、仇恨与复仇关系，输赢会改变它们的地位——斗蛐蛐 + 存档持久化 = 养成系斗蛐蛐

---

## 二、技术实现路径（UE5 / UE4SS）

来源：https://docs.ue4ss.com/

《影之刃零》是 UE5 游戏（Steam/EGS，纯单机），默认走 UE4SS 路线：

1. **解包侦察**：FModel / UAssetGUI 打开 `.pak`/`.utoc`，找敌人 Blueprint、DataTable（属性/阵营表）、AIController、Behavior Tree
2. **注入 + 转储**：装 UE4SS，用 Object Dumper 导出全部 UClass/UFunction；用 **Live View**（运行时属性查看器）盯着一个敌人，观察它索敌时哪些属性在变
3. **关键目标**（按 UE 惯例找，S-GAME 可能自定义）：
   - `GenericTeamId` / `IGenericTeamAgentInterface`（标准阵营接口）
   - `AIPerception` 组件的 Detection by Affiliation 配置
   - Behavior Tree 里的目标选择 Service/Task；或 C++ 侧的 `GetTargetActor` 类函数 → 用 UE4SS hook
4. **实验顺序**：Lua 控制台改单个敌人 TeamId → 看它是否攻击同伴 → 不行就 hook 目标选择函数强制换目标 → 都通了再写成正式 Lua Mod
5. **自由视角**：UE4SS 自带 free cam / `ToggleDebugCamera`，基本零成本
6. **生成怪物**：`SpawnActor` 敌人 Blueprint 类（注意本作是否用标准 NavMesh，不是的话 AI 可能原地罚站——Windrose 的 Mod 笔记就遇到过非标准导航）

风险项（发售后第一时间确认）：
- 是否有 Denuvo / 反篡改（影响注入难度，非死路）
- AI 在 Blueprint（好逆向）还是纯 C++（靠 hook）
- Pak 是否加密（AES key 一般可提取）
- BOSS 的索敌是否硬编码只认玩家（决定"组队打 BOSS"的工作量）

---

## 三、功能规划

### V1 — 基础斗蛐蛐（验证期）
- [ ] 自由飞行观战镜头（+ 慢动作 / 时停）
- [ ] 一键让场景内敌人互相为敌（全局阵营洗牌）
- [ ] 点名模式：选中 A 和 B，只让他们俩打
- [ ] 敌我血条/架势条可视化（学 Puppeteer Allies）
- [ ] 敌人无敌于玩家开关（防止观战时被打断）

### V2 — 仇恨值系统（核心创新）
不做简单的"敌对/不敌对"布尔值，做**仇恨矩阵**：
- 每对 NPC 之间有数值化仇恨度，受伤害累积、按时间衰减
- 超过阈值才翻脸 → 会涌现"混战中临时结盟、打完反目"的戏剧性
- 按门派/种族设定初始仇恨（武侠题材天然适合：门派世仇）
- 可选：仇恨关系写入存档 → Nemesis 式"宿敌"系统，上次打赢你的怪记得你

### V3 — 赛事化（玩法层）
- 竞技场模式：菜单选怪、选场地、设规则（禁招/血量倍率，学 Garden of Eyes）
- 锦标赛括号赛制 + 战绩榜
- 押注系统：用游戏内货币下注（学 Arenas of Skyrim）
- 导播模式：多机位自动切镜、击杀慢放回放

### V4 — 组队打 BOSS（压轴）
- 生成 N 只小怪，统一设为敌视 BOSS 的阵营
- 若 BOSS 索敌硬编码认玩家 → hook 其目标选择，按仇恨矩阵分配目标
- 创新点：**"养蛊"玩法**——小怪打赢 BOSS 的幸存者获得属性成长，可收为"蛊王"带着继续挑战更强 BOSS

---

## 四、发售日行动清单（10-29）

1. 安装游戏，把安装目录路径告诉 Claude
2. 确认引擎版本（exe 属性 / log）、有无 Denuvo
3. FModel 解包第一波：找 AES key（如需要）、浏览 `Content/` 结构
4. 试装 UE4SS（可能需等社区出适配版本）
5. Object Dump + Live View 定位阵营/索敌相关类
6. Lua 控制台做第一次"两个小兵互殴"实验 → 成了就是 V1 起点

---

## 五、修改器面板规划（2026-10-29 实测后确定的需求）

### 全量图鉴（不依赖玩家遇见过）
- 运行时走 **AssetRegistry** 按目录枚举全部 `BP_Monster_*` / BOSS 蓝图，烘焙成分类数据文件
- 分类维度：路径 + 命名规律（小兵 / 精英 / BOSS / 特殊）
- **头像**：游戏内 UI 直接引用游戏自带贴图（合法）；外部面板需本地导出，导出物不入仓库（版权）
- 跨地图召唤需先流送加载资产（参考 UE4SS 的 summon_unloaded_assets）；BOSS 的 AI 依赖竞技场脚本，跨图召唤可能站桩，逐个验证

### 修改器形态
- 近期：纯按键 + config.lua 改键（v0.3 已实现按键表）
- 中期：外部面板（本地 Web UI / 桌面窗口）↔ Lua 以文件 IPC 通信（面板写指令 JSON，Lua 轮询执行）
- 远期：UE4SS C++ Mod 画 ImGui，或借用游戏自身 UMG
- 所有开关类功能必须可逆（再按一次取消）：v0.3 的中立化/阵营快照恢复已照此实现

### 主动仇恨（解决"召唤出来罚站"）
- 配对后互相施加 1 点种子伤害（带加害者 Controller），触发 AI 受击感知立即锁定
- v0.3 已在决斗模式实装；召唤对战模式复用同一机制
- 后续与仇恨矩阵打通：种子伤害 = 人为注入初始仇恨值
