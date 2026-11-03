# PhantomBZ_BvB

[简体中文](README.md) | **English**

A faction battle and boss-versus-boss (BvB) filming tool for **Phantom Blade Zero**. This independently maintained project is a development preview; in-game validation of this derivative is not yet complete.

Based on **[PhantomGladiator by LingYi-Liang / 泠依_01](https://github.com/LingYi-Liang/PhantomGladiator)**. Thank you to the original author for the native NPC combat system, research into game stats, grab adaptations, and free camera implementation. We retain the MIT license, copyright notice, and Git history. [Upstream version and attribution (Chinese)](UPSTREAM.md) · [Original README](docs/UPSTREAM_README.md)

This project is public and open source. You are welcome to download or clone the repository, follow the instructions below, and modify it under the MIT license. Keep the license and copyright notice when redistributing. The repository provides source code and installation scripts; it requires an existing PBZ-compatible UE4SS installation and Python. It is not an all-in-one installer with bundled dependencies.

## Initial release goals

- Blue-versus-red faction battles with explicit team relationships and the game's native AI, hit detection, damage, and death handling.
- Native stats and spawn levels, with matching difficulty settings for the game and summoned units.
- A free camera and player aggro suppression. Participating bosses stay still during introductions while the rest of the world continues running.
- Saved lineups and positions, with a reset that respawns the participants and waits for you to start the match.
- Combined health bars for both teams. Unreadable health values are not treated as zero.

[Match rules (Chinese)](docs/BVB_REQUIREMENTS.md) · [Development and validation notes (Chinese)](docs/BVB_DEVELOPMENT.md)

We do not distribute game assets, saves, SDK headers, or dumps. The tool does not manufacture results through scripted damage or forced deaths. Upstream test results do not establish that this derivative has passed the same in-game checks.

The source remains under `Mods/PhantomGladiator`, but the installer uses a separate `PhantomBZ_BvB` directory and Runtime. Do not load both mods at the same time. Do not use the upstream auto-updater, as it could overwrite this project's changes.

License: [MIT](LICENSE).

## Getting started

To fight the four Ghost Officers yourself, load your save, exit the free camera, and click **开启主角仇恨**. Once **主角可被锁定** appears, select Huoliuxing, Zhanqi, Gouhun, and Duanchang in turn and click **召唤为主角对手** for each. Each opponent can act as soon as it spawns. Use **清场** to clear the encounter and **恢复拍摄无仇恨** to return to filming. Spawns and match resets respect your aggro choice for the current mod session.

With a PBZ-compatible UE4SS installation and Python 3.10+ already available, run `Install-BvB.ps1` with your game directory, then run `Start-BvB.ps1`. Open [the local control panel](http://127.0.0.1:8766/bvb.html).

The initial preset is Huoliuxing (火流星), Zhanqi (斩骑), Gouhun (勾魂), and Duanchang (断肠) versus Biyuan's Remains (毕远残躯), Bihai's Remains (碧海残躯), Wu Lengshuang (乌冷霜), and Yubi (玉璧). These names are transliterations or descriptive translations for identification, not a claim about the game's official English localization. Use a first-playthrough save on 逆天者 difficulty (`Hard` internally). Start with one boss on each side to check the introduction hold and combat start before trying the full preset.

The **lineup editor** (调整阵容) supports complete rosters for both teams: search and add units, remove, replace, duplicate, switch teams, and reorder. Drafts are saved in the local browser, and you can also import the lineup saved by the game-side mod. Clicking **Apply lineup and reposition** (应用阵容并重新布置) clears the current match participants, respawns and saves the new lineup, and holds them still until you start combat. Applying a lineup replaces the previously saved positions and is unavailable during combat. The BvB control panel currently uses Chinese labels; this file provides English documentation.

Offline checks have passed. Special sources of friendly fire, the in-game hold behavior, and participant identity and victory detection across boss phases still require in-game validation; see the development notes. Run `python tools/package_bvb.py` to build a development package. It does not include UE4SS or game assets.
