# AGENTS.md

这是《影之刃零》斗蛐蛐 Mod（UE4SS Lua）。**开始工作前先读 `docs/HANDOFF.md`**：项目目标、当前阻塞、已排除的方向、开发循环都在里面。

## 工作规则

- 用中文和用户沟通。
- 只有用户能操作游戏。改完代码先部署到游戏目录（命令见 HANDOFF 第 4 节），再请用户在 UE4SS 窗口点 **Restart All Mods**，然后按键测试、描述画面。你读 `D:\steam\steamapps\common\PBZ\platform\steam\ue4ss\UE4SS.log`。
- 每个实验都要在日志里打印"做了什么"和"读回的结果"。没读回验证，不要下结论。
- 实验结论写进 `docs/REVERSE_ENGINEERING.md`，包括失败的。HANDOFF 第 7 节列了已排除的方向，没有新证据不要重试。
- UE4SS 对象每一级先 `IsValid` 再往下调用：对失效对象做链式调用会让游戏原生崩溃，`pcall` 拦不住。
- 查游戏的类、属性、函数签名，先去 `D:\steam\steamapps\common\PBZ\platform\steam\ue4ss\CXXHeaderDump\` 搜头文件。
- 不要提交游戏资源、头文件导出、崩溃转储（见 `.gitignore`）。
