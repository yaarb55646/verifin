# 截图目录

根 README「界面预览」引用的三张 Android 模拟器截图（1180×2556，使用 diagnostic flavor 的虚拟账目）：

- `home.jpg` — 首页
- `assets.jpg` — 资产
- `reports.jpg` — 看板

最近一次重拍：2026-10-11（看板改为「日常 / 月统计 / 年统计」三 Tab 之后，深色主题；`reports.jpg` 取「月统计」Tab，能同时看到 Tab 结构与摘要 / 预算 / 排行卡）。

当前看板已增加分类占比卡，日常也有分类·标签排行；现有 `reports.jpg` 尚未包含这些新增卡，需在 Android diagnostic 环境重拍后替换。

更新界面后记得同步替换：用 diagnostic flavor（`--flavor diagnostic`，覆盖安装不丢演示账目）打开对应页面顶部，
确认模拟器为 1180×2556 / density 480（`adb shell wm size` / `wm density`），
`adb exec-out screencap -p > shot.png`，再转 JPEG 覆盖同名文件（如 `ffmpeg -i shot.png -q:v 3 home.jpg`）。
