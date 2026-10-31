# 全目录核对进行中（2026-10-30，v0.20）

> 本轮收尾结果已记录在ASSET_AUDIT.md。下文为过程记录，不能覆盖最终的866候选、55配置类、3区域结果。v0.20.2已经运行，新增候选已发布；未加载地图/加密物理索引仍未全覆盖。

用户明确要求继续查完整资产目录与地图刷怪配置，尽量补齐单位。此文件记录尚未完全收尾的工作，不是最终全覆盖声明。

## 已实机取得

- v0.20已部署23个Lua文件，备份 `D:\Claude CODE\影之刃0-backups\deployed-before-v020-20261030-204626`。用户20:53左右完成清理/重载，游戏一直在地图中。
- `asset_inventory.lua` 独立GetAllAssets(onDisk=true)起止均为267049；19736个cached paths全部查询，assets_seen/assets_reported=267049，duplicates/query_errors/row_errors/tag_errors=0。coverage=CURRENT_MOUNTED_REGISTRY_VERIFIED。
- 旧扫描漏掉的22817条恰好来自 `/Game/Maps/B08_09_10/PBZ_Pangzhen_WP/_Generated_`，本次returned/exported=32817，旧版每路径上限10000。
- 根路径空查询用HasAssets=false交叉确认，不能把所有false返回一律算错误。
- 只读当前已加载场景：5个NPC观察记录、96个AISpawner、96条配置、42个不同配置类。地图ID读回LuJiaCun和ZhengDaoDaYing，不能代表所有World分区/全部地图。
- registry引用查询2138个目标包，errors=0，edges=0，empty=2138。可能未保留cooked依赖数据；不能据此断言其它地图没有引用/刷新。
- 主IoStore：version8、328220 chunks、66 partitions、directory index15409392字节、flags11（压缩/加密/有目录）；主pak索引也加密。chunk数量不是资产/单位数量。尚未独立核对解密后的完整磁盘目录。
- `loaded-datatables.tsv`有312个已加载表：DT_MapData15行、DT_ChapterData12行、DT_CharacterAttributes318行（PBZCharacterAttributeTableData继承AssetPath）及SeqHeadSwapRow表。下一步可只读精确schema，避免任意资产加载。

## 离线对比工具

`tools/reconcile_catalog.py` 已完成初版，默认只审查、显式--publish才替换catalog.tsv。使用完整索引+本地CXX继承图+codex+spawn配置，绝不改生成许可。

运行（当前已验证完整索引）：

```
python -X utf8 -I tools/reconcile_catalog.py --runtime D:\steam\steamapps\common\PBZ\platform\steam\ue4ss\Mods\PhantomGladiator\Runtime --headers D:\steam\steamapps\common\PBZ\platform\steam\ue4ss\CXXHeaderDump
```

初步结果：旧raw catalog737条，合并候选929条；强继承证明NPC652、player7、character189、pawn4；新增192条=player7、character182、pawn3，新增NPC0。多数新增为HuaShira/ActorForSeqs演出角色，不能宣传为192种新怪。当前尚未--publish，面板仍是674候选/177主图鉴。

生成的Runtime/inventory-report.json与unit-evidence.json已经存在。最初配置单位数被defaultdict访问扩大成852，已修为42；不要使用旧中间数字。

## 已做离线检查

- test_asset_inventory.lua：10005条大目录不截断、空目录交叉确认、独立总量不符不宣称完整、9列契约。
- test_spawn_catalog_export.lua：current World/销毁保护、soft class不加载、随机配置、观察与配置分开、11列。
- test_asset_reference_audit.lua：包引用、空/剥离边界、不加载。
- test_reconcile_catalog.py：4项，精确路径、CPP与Blueprint区分、继承冲突/循环、未完成不能发布。
- panel_runtime16项及真实main加载通过。CombatProbe仍关闭，镜头未改。

## 源码比实际部署多出的修正（待下一次部署）

- asset_inventory/reference的clean(false)最初把false写成空字段；当前代码已修，游戏正在运行的v0.20还未重载此修正。运行时complete=true来自Lua内部严格布尔判定，起止总量与所有计数一致；旧manifest中的loading_start/end、truncated空值是这个序列化缺陷，不能冒称原始文件写了false。
- SpawnCatalog的FindAllOf成功返回nil应记为“无已加载实例”，当前源码已修；旧日志errors=2可能是没有loaded MonsterParty/NarrativeParty。不能把当前已加载调查当全地图覆盖。DataTable索引增加8192上限。

## 尚需完成

1. 发布前复核192新增条目的用途；后端接入unit-evidence，把player/character/演出类单列，避免落进普通怪。
2. 展示实际配置地图与图鉴归属的区别；不能给普通变体无证据继承图鉴地图。角色分类、引用线索与召唤许可独立。
3. 可继续读取已经加载的MapData/ChapterData/CharacterAttributeTableData/SeqHeadSwapRow；不加载未知Blueprint，不开地图、不触发Save/Spawn。
4. 完成对比后--publish，验证API和UI、保存最终报告/快照。若物理目录解密与未加载地图仍不可得，清楚报告覆盖边界，不写全游戏无遗漏。

不要操作游戏；需要重载先部署后由用户点击。当前新版代码以此文件和实机Runtime数据为准。
