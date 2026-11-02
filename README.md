# PhantomBZ_BvB

《影之刃零》势力战与 BvB 拍摄工具。独立开发仓库，目前为开发预览，尚未完成本项目的游戏内验收。

基于 **[LingYi-Liang / 泠依_01 的 PhantomGladiator](https://github.com/LingYi-Liang/PhantomGladiator)** 二次开发，感谢上游的原生 NPC 战斗、数值研究、投技适配及自由镜头实现。保留 MIT 许可、版权声明及提交历史。[来源版本](UPSTREAM.md) · [原版说明](docs/UPSTREAM_README.md)

## 首版目标

- 蓝红势力战：完整阵营关系，原生 AI、命中、伤害和死亡。
- 原生数值与出生等级，游戏和召唤难度一致。
- 无仇恨自由镜头，介绍期间定住参赛 Boss，不暂停整个世界。
- 保存阵容与站位，一键重新生成，重置后等待开战。
- 两队总血量展示，未知读数不当作零。

[比赛规则](docs/BVB_REQUIREMENTS.md) · [开发与验收](docs/BVB_DEVELOPMENT.md)

不分发游戏资源、存档、头文件或转储；不使用脚本扣血或强制死亡制造结果。上游实测不等于本项目实测。

源码沿用 Mods/PhantomGladiator，安装为独立 PhantomBZ_BvB 目录与 Runtime，不同时加载两者。不使用上游自动更新器，以免覆盖本项目改动。

许可：[MIT](LICENSE)。
