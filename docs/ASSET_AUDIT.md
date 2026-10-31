# 完整目录与地图配置核对结果（v0.20.2）

2026-10-30。本轮完成了**当前游戏已挂载的磁盘资产注册表**的完整核对，并补齐可确认的角色候选。随后已解密物理资源目录，并与注册表逐包核对一致；未声称完成所有未加载地图的刷怪配置解包。

## 资产目录

| 核对项 | 实测结果 |
| --- | ---: |
| 缓存路径全部查询 | 19,736 |
| 独立GetAllAssets起始总数 | 267,049 |
| 逐目录实际导出 | 267,049 |
| 独立GetAllAssets结束总数 | 267,049 |
| 重复、查询错误、行错误、标签错误 | 均0 |
| 最大目录完整读取 | 32,817 |

旧版每目录只处理10000条，导致 `/Game/Maps/B08_09_10/PBZ_Pangzhen_WP/_Generated_` 少读22817条；这恰好是267049与旧244232的差。新扫描器没有丢弃该目录尾部。根路径空结果通过HasAssets=false交叉确认。

资产完整性范围严格是 `CURRENT_MOUNTED_REGISTRY_VERIFIED`，不是所有物理文件/未来DLC/未挂载内容的保证。267049也是资产记录数，不是怪物数量。

## 单位补齐和分类

完整索引结合本地CXX继承图得到852个有NPC/玩家/Character/Pawn继承证据的类：

- PBZCharacter_NPC派生类652个，含剧情、模板、变体等，不是652种战斗怪物。
- 玩家派生类7个、其它Character派生类189个、其它Pawn派生类4个。
- 与旧目录比较新增192条：玩家7、Character182、Pawn3；主要是HuaShira/ActorForSeqs演出角色。**没有新增符合PBZCharacter_NPC继承条件的类**，不能宣传为发现192种新怪物。

原raw catalog737条，合并后929条；保留77条仍无强继承根证据的旧候选，不强行认定为单位。面板继续排除63条已知非单位资产，因此显示866条候选，较旧674条增加192。默认主图鉴仍是177条。

新增玩家角色、演出角色候选和通用角色候选分类。模板等用途优先保留；因此UI用途数量与继承类别数量不要求相等。没有扩大两条既有生成许可，未知单位仍不能直接召唤。

## 地图刷怪配置与表数据

先后读取已加载场景的AISpawner.Class、RandomSpawnClasses、叙事/波次配置接口及NPC实例。只有明确Class字段归为配置证据；场上Actor观察独立标记。

累积保存123条配置样本，涉及55个不同类和3个地图区域ID：LuJiaCun、ZhengDaoDaYing、XiGu。配置样本来源于已加载分区，包含条件/随机配置，不表示当时都已刷出，也不能当作全部地图覆盖。相同底层World可以包含多个地图区域。

对2138个相关包查询cooked注册表引用：调用没有错误，但全部返回空、依赖边为0。可能没有保留运行时依赖图；不能据此推断其它地图不存在刷怪引用。

只读5种已加载且schema精确匹配的数据表，共361行：

| 表类型 | 行数 | 使用边界 |
| --- | ---: | --- |
| MapData | 15 | 包含Test、BigMap等项，不等于15张正式游戏地图 |
| ChapterData | 12 | 其中3条中文名为空，不伪造新剧情章节；原始排序不与UI归一化顺序混用 |
| CharacterAttributeTableData | 318 | 数值读回；AssetPath关联仍未读回成功，不按行名猜角色、不按血量分精英 |
| SeqHeadSwapRow | 6 | 精确区分游戏角色与高精度演出头部来源 |
| CodexDataStruct | 10 | 部分名称为本地化key，未冒充可显示中文名 |

## 物理资源包边界

主IoStore为version8、328220个chunk、66分区，目录索引15409392字节，flags11（压缩、加密、带目录）；主pak索引也加密。chunk数量不是资产/单位数量。已按[CUE4Parse头格式](https://github.com/FabianFG/CUE4Parse/blob/master/CUE4Parse/UE4/IO/Objects/FIoStoreTocHeader.cs)核对头信息。

目录索引在本地只读解密，没有读取游戏进程内存或上传游戏文件；解密方法与工具只保留在作者本地，不随仓库公开。

**物理目录现已解密：** 主IoStore目录304988条、主pak目录5585条、9个视频pak共400条，合计310973个文件条目。10个pak的主索引及完整目录SHA-1全部一致；IoStore目录树的计数、索引范围、可达性与无环校验通过。按FName大小写规则和实际uplugin描述文件名规范化挂载路径后，252284个物理资源包与252284个注册表包全部对应，双方差集均0。267049是资产对象记录数，不能和包数或文件数混用。

这些结果证明本次安装中已索引容器的目录与当前注册表一致；不等于每个资产正文已解析，也不等于所有角色可召唤。未加载地图的静态刷怪字段仍未完整解包。解析器、目录浏览入口和本地证据位置在作者本地记录中（不公开）。

## 实现、验证与产物

- Lua：asset_inventory.lua、asset_reference_audit.lua、spawn_catalog_export.lua、table_catalog_export.lua；全部只读，不LoadAsset、不生成、不调用Save/Activate，不启用诊断hook。
- 离线核对：tools/reconcile_catalog.py。只有目录独立总数验证完成才允许`--publish`，精确类路径和继承图匹配；不按怪物名字强推身份。反复运行以catalog.before-inventory.tsv为基线。
- 面板：显示完整索引统计、玩家/演出分类、“有刷怪配置证据”筛选，以及每个单位实际配置区域；图鉴归属和配置证据分开。
- Lua清单/引用/场景/表/主程序检查通过，离线合并4项、后端44项、标签25项、前端筛选回归和JS语法检查通过。相机与共享玩家查找源文本未变。
- Runtime保留asset-index.tsv、asset-path-audit.tsv、asset-index-status.tsv、asset-references.tsv、reference-queries.tsv、spawn-config-history.tsv、native-table-catalog.tsv、inventory-report.json、unit-evidence.json。原始资产、头文件和转储不入库。

运行中的v0.20.2已由用户重载确认，24个Lua文件哈希核对通过。解密目录接入后，面板后端更新为本任务PID36996；此次不修改或重载Lua。未新建或推送GitHub仓库。
