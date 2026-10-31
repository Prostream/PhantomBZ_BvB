# 单位图鉴分类依据（v0.19，2026-10-30）

默认显示177条游戏图鉴直接角色记录，全部674条资产候选保留在另一视图。地图表示**图鉴归属**，不等于全部刷怪位置、首次出场章节或玩家实际遭遇地点。

## 官方字段

| 用途 | 数据字段 | 边界 |
| --- | --- | --- |
| 名称、BOSS | FCodexEnemyRow.EnemyClass / Enemy_CH_Hans_Name / bIsBoss | 完整类路径精确匹配；BOSS记录含形态和变体 |
| 地图归属 | FCodexEnemyRow.OwnMapID | 不从资源目录数字或击杀记录猜地图 |
| 地图名及章节 | FMapData.MapID / MapName / OwnChapterID / MapOrder / LevelName | GetMapData读回MapID必须与请求一致 |
| 章节名及顺序 | FChapterData.ChapterID / ChapterName / ChapterOrder | GetChapterData核对ID；读取原生本地化名称 |
| 图鉴排序、别名 | DisplayOrder / AliasEnemyClasses | 主视图只显示直接EnemyClass；别名保留canonical关联 |
| 物种 | ECodexEnemyType | 与战斗等级分开，未确认术语保留工作译名标记 |
| 剧情、模板、召唤、辅助用途 | 类/父类元数据、内部名线索、个别用户实测 | 没有原生角色字段支持的标为候选，不冒充官方定义 |

依据本地CXXHeaderDump/ProjectPBZ.hpp：325处FChapterData、374处FCodexEnemyRow、1053处FMapData、5517附近UBellManager。只查询当前World对应的唯一BellManager实例，不调用任意CDO、不生成单位、不Reveal图鉴、不修改存档。EnemyKillMapIDs及玩家击杀位置不参与静态归属分类。

虽然头文件定义了EPBZAIType的CommonEnemy、EliteMonster、Boss、NPC、Shop枚举，本次导出未找到它与当前单位类/图鉴行相连的可读字段。**仍不能可靠把所有非BOSS细分为小兵和精英。** 面板“普通敌人”表示图鉴非BOSS，不通过血量、Elite名称或目录编号猜等级。

## 19:36:14 实机读取

177行图鉴，181个精确类映射（含4个别名），181个映射均有OwnMapID。主图鉴177条分为75条BOSS类记录、101普通敌人、1机灵鬼特殊机制。机灵鬼的机制分类来自用户此前的明确实测反馈，不冒称来自bIsBoss字段。

| 地图ID | 游戏地图名 | 游戏章节名 | 主图鉴记录 | BOSS类记录 |
| --- | --- | --- | ---: | ---: |
| ZhuLinGuWu | 序章 | 未标注 | 5 | 3 |
| XiGu | 悲泣溪谷 | 逆流而上 | 26 | 9 |
| FuJiZhiLin | 血色森林 | 林中血，镜中蛇 | 32 | 9 |
| LuJiaCun | 陆家村地区 | 失心村 | 22 | 10 |
| PangZhen | 庞镇地区 | 死镇 | 19 | 5 |
| HouJie | 庞镇地区 | 死镇 | 17 | 9 |
| ZhengDaoDaYing | 正道大营 | 英雄？罪人？ | 9 | 7 |
| DengDingShanDao | 枷笼山 | 背叛与监禁 | 9 | 6 |
| MeiGuHu | 梅谷湖 | 湖 | 19 | 6 |
| MeiGu_YiJi | 梅谷湖 | 湖 | 1 | 1 |
| XiMeng | 戏梦山庄 | 破局 | 12 | 4 |
| DuanHunYa | 断魂山 | 断魂 | 6 | 6 |

这是本批图鉴覆盖的12个地图ID、9个具名章节，不是游戏全部地图或完整遭遇表。不同ID可能同名，面板附ID区分。序章没有OwnChapterID，保留“未标注章节”，不伪造第0章。其它实际出现地图还需要刷怪配置或实例证据。

## 数据和界面

- 默认主图鉴，章节/地图/类型联动筛选，按原生排序字段排列。全部候选另分剧情/NPC、召唤/分身、特殊/辅助、模板/测试、敌人变体和待分类。
- 未列入图鉴的派生类不会继承父类地图或章节，保持地图待查；父类参考名仍是非官方工作译名。
- 分类不改变召唤权限；当前仍为原先2个精确许可路径，普通暴徒每次1只、最多2只。
- 保持旧5列codex.tsv，新增12列Runtime/codex-locations.tsv。后端要求精确类、canonical及原生source对应，拒绝重复路径、未知来源或坏排序值。
- 实际API读回：primary_count=177、mapped_count=177、location_errors=0、codex_errors=0。

地图读取器、图鉴导出器、真实main的Lua检查通过；后端43项、标签25项、JS分类过滤回归和语法检查通过。浏览器实测“逆流而上→悲泣溪谷→BOSS”显示9条；全部候选的模板/测试显示51条；未验证召唤按钮仍禁用。相机和玩家查找与v0.18.3检查点源文本一致，没有新召唤或战斗实验。

v0.19已部署20个Lua文件且哈希一致，用户已关闭F8、清理并重载。旧部署保存在仓库外deployed-before-v019-20261030-193533。原始归属导出、头文件和运行转储不提交到仓库，本文件只保留方法和汇总。
