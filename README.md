# PhantomGladiator — 《影之刃零》斗蛐蛐 Mod

让《影之刃零》(Phantom Blade Zero) 的 NPC 互相为敌：全场混战、点名决斗、慢动作观战、自由镜头。
A UE4SS Lua mod for Phantom Blade Zero that turns NPCs against each other — battle royale, 1v1 duels, slow-mo spectating and free camera.

> **状态 / Status: v0.2 — 已在正式版实测可用 (2026-10-29, Steam build 26266538)**
> 扫描、全场互殴、决斗、慢动作、自由镜头均已在游戏内验证。阵营写入命中标准
> `GenericTeamId` 属性（S-GAME 未改动 UE 阵营接口）。Verified working in-game on release day.

## 功能 / Features

| 按键 | 功能 |
| --- | --- |
| `F1` | 扫描场上 NPC，在 UE4SS 控制台列出类名与距离 |
| `F2` | **全场互殴**：把所有 NPC 随机分成 N 个阵营互相开打 |
| `F3` | **决斗模式**：离你最近的两个 NPC 捉对厮杀 |
| `F4` | 重置所有阵营 + 清空仇恨 |
| `F5` | 慢动作档位循环（1x → 0.5x → 0.2x → 0.05x，对所有世界实例生效） |
| `F6` | 自由镜头开/关（智能判断当前状态） |
| `F7` | 强制退出自由镜头（F6 失灵时的保险丝） |

规划中（见 [docs/DESIGN.md](docs/DESIGN.md)）：仇恨矩阵（V2，骨架已在 `hatred.lua`）、竞技场赛制与押注（V3）、怪物组队打 BOSS + 养蛊（V4）。

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
