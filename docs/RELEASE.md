# 发布流程

发布一个新版本（例子里新版本是 `X`，上一版是 `P`）。所有命令在仓库根目录运行。

## 准备

- 依赖包放在 `dist/deps/`（不会提交）。缺哪个，就按 `tools/package/build.py` 里 `DEPS` 的链接下载；打包时会核对 SHA-256，对不上就停下。
- UE4SS 用的是实验版 3.0.1-1185，GameConfig 是按这个版本验证的。UE4SS 官方的 experimental 发布已经换成了更新的构建，所以从本项目 v0.37.5 的发布包里原样取出 `app/payload/ue4ss`。

## 步骤

1. 测试：
   - Lua：每个 `tools/test_*.lua` 都用 texlua 跑；`test_main_boot.lua` 分 `npc`、`actor` 两种模式各跑一次，第一个参数是空的临时 Runtime 目录。
   - `python -I panel/test_backend.py`
   - `python -I tools/test_update_check.py`
   - `python -I tools/test_app_update.py`（原地替换：正在运行的程序改名换新，失败时恢复）
   - `python -I tools/test_update_install.py`（整套更新：检查、下载、校验、安装，新版接手并清理）
   - `node --check panel/prototype/*.js`
2. 更新说明：写六种语言的 `notes.json`，然后运行 `python -I tools/release/changelog.py . X <ISO 时间，带时区> notes.json`。这会生成助手里的"更新记录"。
3. 对齐换行：`python -I tools/release/align_eol.py . dist/PhantomGladiator-P`。
4. 打包：`MSYS_NO_PATHCONV=1 python -I tools/package/build.py --deps dist/deps --version X`，记下打印的 SHA-256。
5. 对比：`python -I tools/release/compare_packages.py dist/PhantomGladiator-P dist/PhantomGladiator-X`。最后一行必须是 `gameconfig: identical`，除非这次本来就要改 GameConfig。
6. 提交并推送，然后发 GitHub Release：
   - `gh release create vX dist/PhantomGladiator-X-win64.zip dist/PhantomGladiator-X-win64.zip.sha256 --target <提交> --title "vX · 标题" --notes-file <说明>`
   - 把两个文件下载回来，核对 SHA-256。
7. 更新清单：`python -I tools/release/manifest.py . X <sha256> <字节数>`，提交"发布清单：vX"并推送。
8. 刷新 CDN 缓存：`curl https://purge.jsdelivr.net/gh/LingYi-Liang/PhantomGladiator@main/release/latest.json`。然后检查 cdn.jsdelivr、raw.githubusercontent 上的清单是不是 X；fastly 常常慢一些，助手会取所有来源里最新的那个。
9. 本机：把 Scripts 部署到游戏的 Mods 目录并核对哈希，桌面快捷方式指向 `dist/PhantomGladiator-X`。
10. Nexus Mods：在 Files 页上传新的 zip。包有 19 MB，超过浏览器扩展的上传上限，要用户自己拖进去。显示名最多 50 个字符，版本单独填；关掉"Allow mod manager download"，设为主文件；更新日志从文件行菜单的"Add changelog"添加。文件可能被自动安全检查隔离，要用户发邮件给 support@nexusmods.com 申请审核，详见 `docs/NEXUS_PAGE.md`。
