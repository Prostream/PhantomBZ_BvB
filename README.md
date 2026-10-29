# PhantomGladiator — 《影之刃零》斗蛐蛐 Mod

让《影之刃零》(Phantom Blade Zero) 的 NPC 互相为敌：全场混战、点名决斗、慢动作观战、自由镜头。
A UE4SS Lua mod for Phantom Blade Zero that turns NPCs against each other — battle royale, 1v1 duels, slow-mo spectating and free camera.

> **状态 / Status: v0.1 早期版本（发售日构建，适配进行中）**
> 游戏 2026-10-29 发售。通用框架与按键功能已就绪；阵营写入采用多策略尝试链，
> 对本作真实类名的适配仍在进行（见下方「适配指南」）。欢迎提 Issue 反馈每个策略的命中情况。

## 功能 / Features

| 按键 | 功能 |
| --- | --- |
| `F1` | 扫描场上 NPC，在 UE4SS 控制台列出类名与距离 |
| `F2` | **全场互殴**：把所有 NPC 随机分成 N 个阵营互相开打 |
| `F3` | **决斗模式**：离你最近的两个 NPC 捉对厮杀 |
| `F4` | 重置所有阵营 + 清空仇恨 |
| `F5` | 慢动作档位循环（1x → 0.5x → 0.2x → 0.05x） |
| `F6` | 自由镜头（DebugCamera，被剔除时用 UE4SS 自带 FreeCam 兜底） |

规划中（见 [docs/DESIGN.md](docs/DESIGN.md)）：仇恨矩阵（V2，骨架已在 `hatred.lua`）、竞技场赛制与押注（V3）、怪物组队打 BOSS + 养蛊（V4）。

## 安装 / Install

1. 下载 [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS)（UE5 用 experimental 版本），解压到游戏本体 exe 所在目录：
   `<Steam>\steamapps\common\PBZ\platform\steam\`
2. 把本仓库的 `Mods/PhantomGladiator/` 复制到 UE4SS 的 `Mods/` 目录
3. 在 `Mods/mods.txt` 加一行 `PhantomGladiator : 1`（或保留文件夹内 `enabled.txt`）
4. 启动游戏，UE4SS 控制台出现 `[PhantomGladiator] loaded ✓` 即成功

## 适配指南（帮我们把阵营打通）

本作信息（发售日实测）：**UE5 IoStore 打包，无 Denuvo**；pak 加密但使用默认 key GUID。
斗蛐蛐走 UE4SS 运行时路线，不需要解包。阵营写入按 `config.lua` 里的候选名依次尝试：
`GenericTeamId` 等属性 → `SetGenericTeamId` 等函数。若 F2 提示全部失败：

1. 用 UE4SS 的 **Live View** 选中一个敌人，观察它索敌/脱战时哪些属性变化
2. 把属性/函数名补进 `config.lua` 的 `TeamPropertyCandidates` / `TeamFunctionCandidates`
3. 仍不行就在 UE4SS Dump 里搜 `Target`/`Threat`/`Hostil` 关键词找目标选择函数，提 Issue 告诉我们

## 免责声明 / Disclaimer

- 本 Mod 仅供单机离线娱乐，不包含、不分发任何游戏资源文件
- 与 S-GAME 无任何关联；使用风险自负，建议先备份存档
- Not affiliated with S-GAME. Single-player use only. No game assets included.

## License

[MIT](LICENSE)
