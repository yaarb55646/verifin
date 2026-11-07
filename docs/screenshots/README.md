# 截图目录

根 README「界面预览」引用三张 Android 截图（首页/资产沿用原图；看板随上游更新为 1080×2400）：

- `home.jpg` — 首页
- `assets.jpg` — 资产
- `reports.jpg` — 看板

`reports.jpg` 使用上游 v1.20.15 更新的月统计截图，展示期间栏、摘要、预算执行与「前5 / 全部」分类统计，符合个人 fork 当前月度图表方案。

该图不展示日常/年度个人占比与日常排行，也不是本次合并代码的真机验收截图；个人功能仍需在 Android diagnostic 环境另行验证。

更新界面后记得同步替换：用 diagnostic flavor（`--flavor diagnostic`，覆盖安装不丢演示账目）打开对应页面顶部，
确认模拟器为 1180×2556 / density 480（`adb shell wm size` / `wm density`），
`adb exec-out screencap -p > shot.png`，再转 JPEG 覆盖同名文件（如 `ffmpeg -i shot.png -q:v 3 home.jpg`）。
