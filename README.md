# PhantomGladiator — 《影之刃零》斗蛐蛐 Mod

让《影之刃零》(Phantom Blade Zero) 的 NPC 互相为敌：全场混战、点名决斗、慢动作观战、自由镜头。
A UE4SS Lua mod for Phantom Blade Zero that turns NPCs against each other — battle royale, 1v1 duels, slow-mo spectating and free camera.

> **状态 / Status: 开发中 (v0.12, 2026-10-30, Steam build 26266538)**
> 召唤、敌对、观战功能可用：怪物能被设为敌对、真实互相出招。**怪物之间的攻击还不能造成伤害**
> （命中层未打通），可用"裁判模式"结算胜负作为替代。进展与已排除的方向见
> [docs/HANDOFF.md](docs/HANDOFF.md)。
> Work in progress: monsters engage each other, but monster-on-monster hits don't deal damage yet.

## 功能 / Features

| 按键 | 功能 |
| --- | --- |
| `F1` | 扫描场上 NPC，登记进召唤图鉴 |
| `F2` | **全场互殴**：附近 NPC 分两队，跨队设为敌对 |
| `F3` | **决斗模式**：最近两个 NPC 捉对厮杀，并显示战况 |
| `F4` | 重置阵营与所有关系覆盖 |
| `F5` | 慢动作档位循环（1x → 0.5x → 0.2x → 0.05x） |
| `F6` / `F7` | 自由镜头开关 / 强制退出 |
| `F8` | 玩家中立化开关（怪物不再理你） |
| `F9` / `Shift+F9` | 在面前召唤怪物 / 切换要召唤的怪 |
| `Shift+F1/F2/F3` | 诊断：AI 结构 / 阵营与目标 / 碰撞通道 |

敌对关系走游戏原生的阵营组件（`UFactionComponent`），召唤走游戏官方刷怪函数。
怪物之间的伤害目前可用"裁判模式"代为结算（`config.lua` 中 `JudgeDamagePerTick`）：
能分出胜负，但没有原生的受击和死亡表现。

规划中（见 [docs/DESIGN.md](docs/DESIGN.md)）：怪物间原生伤害、修改器面板、全量分类图鉴、竞技场赛制与押注、怪物组队打 BOSS。

## 安装 / Install

1. 下载 [UE4SS experimental-latest](https://github.com/UE4SS-RE/RE-UE4SS/releases/tag/experimental-latest)，
   解压到游戏本体 exe 所在目录：`<Steam>\steamapps\common\PBZ\platform\steam\`（511MB 的
   `PBZ.exe` 旁边，不是 1MB 启动器那个目录）
2. **关键一步**：把本仓库 `GameConfig/` 里的内容复制到 `platform\steam\ue4ss\`
   （两个签名文件 + `MemberVariableLayout.ini`）。原版 UE4SS 读不了本作魔改过的
   UE 5.7 引擎，没有这步会无限扫描或直接崩溃，见下方「本作引擎适配说明」
3. 把本仓库的 `Mods/PhantomGladiator/` 复制到 `ue4ss\Mods\` 目录，并在
   `Mods/mods.txt` 加一行 `PhantomGladiator : 1`
4. 启动游戏，UE4SS 日志出现 `[PhantomGladiator] loaded ✓` 即成功

## 本作引擎适配说明 (UE 5.7 / 发售日实测)

- **UE5 IoStore 打包，无 Denuvo**；pak 加密但使用默认 key GUID
- 原版 UE4SS 缺 `GUObjectArray`/`GNatives` 的 5.7 特征码：`GameConfig/UE4SS_Signatures/`
  里的两份签名取自 UE4SS 官方其它游戏配置（MGS Delta / Split Fiction / Far Far West），
  经内存扫描验证在 `PBZ.exe` 中均唯一命中
- S-GAME 修改了多个引擎核心结构的内存布局（`TUObjectArray` 字段重排、`FField` 的
  Next/Owner 互换、`UStruct` 中段插入 0x50 字节哈希表等），`GameConfig/MemberVariableLayout.ini`
  描述了真实布局。该文件来自 [KintaroModding/ue4ss](https://github.com/KintaroModding/ue4ss)
  的 PBZ 适配包（其 `TUObjectArray` 部分与我们的独立内存实测完全一致），致谢原作者
- 已知问题：蓝图类 Mod（BPModLoader/LogicMods）在本作不可用；UE4SS 的 mapping dump
  (Ctrl+Num6) 含蓝图类型时会崩溃，勿随意使用

## 免责声明 / Disclaimer

- 本 Mod 仅供单机离线娱乐，不包含、不分发任何游戏资源文件
- 与 S-GAME 无任何关联；使用风险自负，建议先备份存档
- Not affiliated with S-GAME. Single-player use only. No game assets included.

## License

[MIT](LICENSE)
