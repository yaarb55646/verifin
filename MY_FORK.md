# MY_FORK.md — 个人分支维护手册

本文件说明个人 fork 的功能差异、数据兼容与上游同步方法。执行规范以 [AGENTS.md](AGENTS.md) 为准，当前实现以源码、测试与构建配置为准。

## 仓库与版本

| 项目 | 值 |
| --- | --- |
| 个人仓库 / origin | `https://github.com/yaarb55646/verifin` |
| 开发分支 | `mine`；`main` 仅作上游镜像 |
| 上游 / upstream | `https://github.com/LumiDesk/verifin` |
| 当前对齐的上游源码 | `ef38742`（包含 v1.20.17 及其后的依赖、维护流程更新） |
| 应用版本 | `1.20.17+187`，随上游带入，不代表个人发版 |
| 数据库 | 个人 SQLite v20；该上游提交仍为 v19 |
| Android applicationId | `top.talyra42.verifin` |
| 许可证 | GPL-3.0-or-later，保留上游版权与 LICENSE |

个人开发保留独立提交，通过 merge 同步上游，不重写已上传历史。源码上传、验收构建、打标签和 Release 发布是独立授权事项。临时同步分支完成检查后，经用户确认才提交并并回 `mine`。

## 个人功能

### 一句话记账与分类联动

手动「记一笔」先打开文字输入，解析阿拉伯数字金额和备注，再进入详情页确认；可切回数字键盘。解析仅生成草稿，不自动落账。

| 输入 | 金额 | 备注 |
| --- | --- | --- |
| `午餐10.25元` | 10.25 | 午餐 |
| `房租1,200元` | 1200 | 房租 |
| `500+800` | 1300 | 空 |
| `买3斤苹果12` | 12 | 买3斤苹果 |
| `早餐` | 未识别 | 早餐 |

带单位的金额优先于裸数字，多候选取最后一个；纯算式仅在整段无汉字时求值。不解析中文金额、自然语言日期或账户名。

分类匹配顺序为真实分类名称/路径、自定义关键词、历史推测；多级路径如 `餐饮/午餐10.25元` 可消歧。同等候选不任意选择，自动识别开关与用户手动选择仍有效；AI/导入草稿不启用本地预选。

### 子分类常驻面板

记账详情页常驻展示当前父分类的直接子分类，一行五格，末尾提供新增。新增先确认名称再选内置图标或 emoji，取消不创建；更深层通过多级选择器选择。分类管理仍使用支持排序的列表。

### 看板分类图与排行

| Tab | 分类图 | 范围 |
| --- | --- | --- |
| 日常 | 个人 `CategorySharePanel`；另保留分类·标签排行 | 含今天的近 7 个日历日 |
| 月统计 | 上游 `_CategoryStatsPanel`，不重复展示个人占比卡 | 期间栏所选自然月 |
| 年统计 | 个人 `CategorySharePanel` 与既有排行 | 期间栏所选自然年 |

月度采用顶级实际支出，默认前 5 + 其他，可切全部、点分段查看金额和占比；不提供个人卡的收入、二级分类和显示金额开关。日常/年度个人卡保留这三项选择，仅影响当前视图，不持久化。

个人卡按当前账本净本位币金额计算：一级上卷整棵分类树，二级将更深分类归到对应二级，顶级直接金额独立保留，不重复累计。转账不计入收支，已到账退款冲减原支出，不计预算标记不影响收支统计。日常旧卡的「近7日 / 本周」切换不联动占比和排行。

面板开关与排序沿用三组配置并随备份保存。冷启动与备份恢复均把旧月度 `category_share` 映射到 `category_stats`，保留位置和开关；两者共存时新 ID 优先。日常/年度不映射；没有旧配置时按默认目录补入。

### 自定义记账关键词

主入口：我的 → 分类管理 → 分类菜单 → 编辑 → 记账关键词。
辅助入口：一句话确认页 → 备注下方 → 将关键词关联到当前分类。

- 分类级关键词支持支出/收入及其子分类，不参与转账或余额调整。
- 弹层内增删只改草稿，保存规则与保存账目分别确认，取消不写规则。
- 同账本归一化后的同词不能绑定多个分类（含收入/支出之间），不同账本互不影响。
- 包含匹配取最长词，英文按词边界匹配，支持大小写/全半角归一；同等候选不猜测。
- SQLite v20 的 `categories.keywords` 是 JSON 数组列；旧分类默认空，改名/移动保留、合并去重、删除清除，新账本不播种关键词。
- 关键词随分类备份；旧备份缺字段按空数组读取，备份 payload 仍为 v4。

详细口径见 [技术决策](docs/dev/tech-decisions.md)，验收见 [验收清单](docs/product/acceptance-checklist.md)。

## 工具链与验证

Flutter 3.47.2（与 CI 一致）、随附 Dart、Java 17+、Android SDK；NDK/CMake 要求见 [Android 开发](docs/dev/android-development.md)。通过本机检测定位安装位置，不将绝对路径、设备标识或环境变量值写入仓库。

```powershell
flutter --version
flutter pub get
flutter gen-l10n
dart format .
flutter analyze
flutter test
```

`pubspec.yaml` 与 `pubspec.lock` 跟随此次对齐的上游版本；依赖安装后检查 lock 差异，不手改锁文件、不顺手升级。测试通过不能替代 Android 构建：图片、压缩、偏好、SQLite、通知和生物识别等依赖还需 release/R8 验证。

新增兼容回归在 `test/monthly_panel_compatibility_test.dart`（冷启动、备份恢复、开关/排序、新旧共存与幂等）和 `test/suishouji_keywords_compatibility_test.dart`（真实 fixture 预览零写入、分类复用及关键词保留）。当前分支的测试结果以本轮执行输出为准，不把旧运行记录当作新版本通过证明。

本地诊断使用 `--flavor diagnostic` 隔离用户数据。正式交付由 CI 构建；同步源码不等于已有可验收 APK。界面截图说明见 [截图目录](docs/screenshots/README.md)。

当前仍有待修复的导入缺陷：[L16 · 不完整随手记 xlsx 可能静默漏导入](docs/dev/known-limitations.md#l16--不完整的随手记-xlsx-可能漏导入整张工作表且不报错)。原有测试通过不代表覆盖此异常输入；复现方法和修复要求以该条目为准。

## 个人 APK 与更新边界

1. 打开 [Build APK (mine)](https://github.com/yaarb55646/verifin/actions/workflows/mine-build.yml)。
2. 获得构建授权后，手动选择目标分支，保持 `run_checks` 开启。
3. 从本次运行的 Artifacts 下载 APK，产物保留 30 天。

该工作流仅由 `workflow_dispatch` 触发，不因 `mine` push 自动运行，不创建 Release、不独立修改版本号。实际 ABI 和包体大小以构建产物为准。使用既有签名，不重生成、不替换；安装前备份，直接覆盖个人版，不卸载或清数据。

本地 `github` flavor 的验收 APK 位于 `build/app/outputs/flutter-apk/app-github-release.apk`。`dart run scripts/clean.dart` 会删除整个 `build/`；需要保留安装包时，先将它复制到仓库外。

**应用内检查更新仍只查询上游正式 Release，并跳转浏览器，不下载或安装 APK，也不会发现个人 Artifacts。** 个人数据库已为 v20、当前上游包仍为 v19，不应把上游 APK 当作个人版安全升级包。更新个人功能必须使用个人构建；未来上游占用 v20 时还需重新设计兼容升级。

## 同步方法与重点文件

| 领域 | 主要入口 |
| --- | --- |
| 文字输入与草稿 | `lib/app/quick_entry_text.dart`、`lib/pages/quick_text_entry_sheet.dart`、`shell.dart`、`transactions_pages.dart`、`entry_detail_page.dart` |
| 分类匹配与 UI | `lib/app/category_suggest.dart`、`category_tree.dart`、`entry_subcategory_panel.dart`、`lib/pages/category_management_page.dart`、`sheets.dart` |
| 数据兼容 | `lib/app/models/category.dart`、Controller、`lib/data/app_database.dart`、`ledger_repository.dart`、`lib/app/backup/legacy_book_scope.dart` |
| 看板与面板配置 | `lib/pages/reports_page.dart`、`category_share_panel.dart`、`lib/app/report_analysis.dart`、`models/preferences.dart`、Controller `_normalizePanelSettings` |
| 国际化 | 两份 ARB；生成 Dart 通过 `flutter gen-l10n` 更新 |
| 个人构建 | `.github/workflows/mine-build.yml` |

用户授权同步后，先确认工作树干净，fetch 上游，检查提交范围和 schema 版本；用 `git merge-tree` 预演，再在临时同步分支 `git merge --no-commit --no-ff <upstream-sha>`。不使用整文件选上游来覆盖个人功能，不把无文本冲突等同于行为兼容。

解决冲突后，执行定向测试、全量分析/测试，核对锁文件、文档、备份和 Android 验收范围。经用户确认提交，再把验证后的同步分支并回 `mine`；上传授权后只推送 `origin mine`，不推标签、不发版。`main` 镜像更新单独进行。

上游维护者通过 PR 合入受保护 `main`，正式发布使用 `scripts/publish.dart`，需要 GitHub CLI 与独立发布授权。个人源码同步不走该发布脚本，本机没有 `gh` 时不为同步任务安装它。

**数据库版本冲突红线**：上游一旦也使用 v20，不得直接覆盖个人迁移、降级或假定双方结构相同；必须同时核对已安装个人 v20 与上游数据库结构，设计新版本兼容路径并验证全部历史迁移。
