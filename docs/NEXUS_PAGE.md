# Nexus Mods 页面内容（v0.37.5）

上传到 Nexus Mods 时各栏要填的内容（页面：nexusmods.com/games/phantombladezero/mods/363）。名称和简介直接写做什么，不用艺术化的名字。长描述用 BBCode，在编辑器的源码模式（工具栏最后一个按钮）里粘贴。以后发新版时，同步更新"文件"一节的版本号和校验值。

## 基本信息

- **Mod 名称**：Spawn Enemies and Bosses to Fight Each Other
- **分类**：Gameplay
- **版本**：0.37.5
- **作者**：LingYiLiang
- **语言**：Any（助手界面有六种语言）
- **简介（Short description，最多 350 字符）**：

```
Spawn any of the game's 177 enemies and bosses and make them fight each other. Features: Blue and Red teams, 1-100 units per spawn, custom stats (all 223 attributes), spawn difficulty and level, companions that follow you and fight for you, free camera with no aggro, undying teams, fight timer, hotkeys. One-click install app, 6 languages.
```

## 长描述（Full description，BBCode）

```
[size=4][b]Description[/b][/size]
Spawn any enemy or boss from the game's codex and make them fight each other. You choose the units, put them on the Blue or Red team, set their stats, difficulty and level, start the fight and watch from a free camera. Units can also be spawned as companions that follow you and fight on your side.
This is a UE4SS Lua mod with a desktop app (PhantomGladiator.exe) that installs the mod and controls it while you play.

[size=4][b]Main features[/b][/size]
[list]
[*][b]Spawn any of 177 enemies and bosses[/b] from the in-game codex (75 bosses and their forms), grouped by chapter and map, searchable, with their codex portraits. The portraits are saved on your PC from your own copy of the game the first time you enter a map.
[*][b]Teams[/b]: Blue, Red, No team (fight a boss yourself) and Companion. 1–100 units per spawn, no total limit, rematch with the last lineup.
[*][b]Unit stats[/b]: keep the game's values, copy the first unit's, or set your own for any of the game's 223 attributes (HP, Sha-Chi, attack, shield, damage and resistance multipliers, status buildup, execution thresholds, movement speed and more). The level-1 base values the game uses for damage are changed too, so the numbers really take effect.
[*][b]Spawn difficulty[/b] (Wayfarer to Sixty-Six Days, for stats and AI) and [b]spawn level[/b] (the level of the map enemies around you). Your save's difficulty stays as it is.
[*][b]Companions[/b]: any unit can follow you and fight for you. They teleport back from 100 m, can grab map enemies, and their own summons and a rider's mount join your side too.
[*][b]Fight options[/b]: an undying switch per team, a fight timer (can also show at the top of the game screen), and units that stay in the fight instead of walking back.
[*][b]Free camera[/b] with no aggro: your character is hidden and cannot be hurt while you watch.
[*][b]Extras for your own character[/b]: infinite Sha-Chi, auto perfect deflect and auto-dodge (experimental).
[*][b]Hotkeys[/b]: 8 function keys you can bind (none bound by default) and per-unit spawn keys.
[*][b]App[/b]: six languages (English, Simplified Chinese, Japanese, French, German, Spanish). Unit, chapter and map names, and the names on the in-game boss bars, follow your game's language once you have entered a map with the mod (Chinese until then). Light and dark themes, update check with SHA-256 verification and a release history.
[/list]

[size=4][b]Installation instructions[/b][/size]
[list=1]
[*]Download the main file and extract it to any folder outside the game folder.
[*]Run [b]PhantomGladiator.exe[/b]. Windows may show "Windows protected your PC" because the app is not code-signed: click More info, then Run anyway.
[*]Close the game. The first-run guide finds the game in your Steam library and installs UE4SS, the game's UE4SS files and the mod in one click.
[*]Start the game and load a save. When the app shows the green "Connected" badge, pick a unit and spawn it to Blue, pick another for Red, and press Fight.
[/list]
Vortex cannot install this file; use Manual download.

[size=4][b]Requirements[/b][/size]
[list]
[*]Windows 10/11 64-bit with the Microsoft Edge WebView2 runtime and .NET Framework 4.8 (both built into Windows 10/11).
[*]Steam version of Phantom Blade Zero. Tested on build 26266538; other builds are untested.
[*]No other download needed: UE4SS 3.0.1 is included.
[/list]

[size=4][b]Compatibility with other mods[/b][/size]
[list]
[*]If UE4SS is already installed in [i]platform\steam\ue4ss[/i], the installer keeps it, but it replaces the two game-specific UE4SS files (MemberVariableLayout.ini and the UE4SS_Signatures folder) with the versions tested with this mod, and enables the mod in mods.txt.
[*]Mods that also change the camera, AI, factions or enemy spawning may interact with the free camera, no aggro or companions.
[*]No function key is bound by default, so key clashes only happen if you bind one yourself.
[/list]

[size=4][b]Updating and uninstalling[/b][/size]
The app checks for updates when it starts and tells you when the in-game mod needs updating (Settings → Game). New versions are also posted here.
To uninstall, delete the app folder (its settings are in %LOCALAPPDATA%\PhantomGladiator) and the game's [i]platform\steam\ue4ss\Mods\PhantomGladiator[/i] folder. If you no longer need UE4SS, also delete [i]platform\steam\dwmapi.dll[/i] and [i]platform\steam\ue4ss[/i].

[size=4][b]Good to know[/b][/size]
[list]
[*]The mod changes objects in memory only while the game runs. It never edits game files or saves.
[*]No data is collected. The app goes online only to check for updates.
[*]No game files or images are included. Unit names are read from your game's codex in its language; portraits are saved on your own PC.
[*]Problems? Settings → Advanced puts a diagnostic report on your desktop. Post it in the Bugs tab with what you did.
[/list]

[size=4][b]Shout outs[/b][/size]
[list]
[*]UE4SS (MIT License): https://github.com/UE4SS-RE/RE-UE4SS
[*]Python 3.11 embeddable package (PSF License)
[*]Microsoft Edge WebView2 SDK
[/list]
Source code (MIT License): https://github.com/LingYi-Liang/PhantomGladiator
Unofficial fan project, not affiliated with S-GAME.

[size=4][b]中文说明[/b][/size]
斗蛐蛐 · 影之刃零怪物对战助手：召唤图鉴里的任意怪物和 BOSS 分成两队对打，可以设数值、难度、等级，可以召随从，自由观战。国内玩家建议从 GitHub 发布页下载，助手内置国内更新线路。完整中文说明：https://github.com/LingYi-Liang/PhantomGladiator
```

## 权限（Permissions）

建议与 GitHub 上的 MIT 许可保持一致（MIT 本来就允许转载和修改，只要求署名）：

- 转载（Upload）：可以，需署名
- 修改（Modification）：可以，需署名
- 转换（Conversion）：可以，需署名
- 素材使用（Asset use）：可以，需署名
- 收费 Mod 中使用素材：按 MIT 可以，需署名（如果你想禁止，这一项可以改，但只能约束 Nexus 上的这份文件）
- 赚取捐赠点数的 Mod 中使用素材：可以，需署名

## 文件（Files）

- **文件名**：Spawn Enemies and Bosses to Fight Each Other 0.37.5
- **版本**：0.37.5
- **分类**：Main Files
- **文件**：`dist/PhantomGladiator-0.37.5-win64.zip`（19.8 MB，需手动拖进上传框）
- **文件说明**：

```
Desktop app and mod. Extract and run PhantomGladiator.exe. SHA-256: a4c5a511444830c1ae5fb0bf5631e730433ef29ab8ba0647e1c4e3214dddae3e
```

## 图片

`docs/images/` 里的界面截图：arena.png（主界面）、arena-dark.png（深色）、stat-match.png（数值设定）、hotkeys.png（快捷键）、solo.png（暂不配队）、welcome.png（新手引导）。
