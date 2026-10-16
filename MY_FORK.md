# MY_FORK.md — 个人分支维护手册

本文件说明个人 fork 的功能差异、构建环境、验证状态与上游同步方法。执行规范以 [AGENTS.md](AGENTS.md) 为准，当前实现以源码、测试与构建配置为准。

## 1. 仓库与分支

| 项目 | 值 |
| --- | --- |
| 个人仓库 / origin | `https://github.com/yaarb55646/verifin` |
| 开发分支 | `mine` |
| 上游 / upstream | `https://github.com/LumiDesk/verifin` |
| 分叉基点 | 上游 `v1.20.1`，提交 `937b6b0`；2026-10-16 已 rebase 到上游 `v1.20.3`（`main` 提交 `7ed8962`） |
| 本地目录 | `D:\CC Switch\Hello\verifin` |
| Android applicationId | `top.talyra42.verifin` |
| 应用版本 | `1.20.1+171`（个人功能未另行发版） |
| 当前数据库 | SQLite schema v20 |
| 许可证 | GPL-3.0-or-later，保留上游版权与 LICENSE |

普通开发提交推送到 `origin mine`，`main` 用作上游镜像。代码上传、个人验收构建与正式发版是独立操作；打标签和创建 Release 必须获得明确授权。

## 2. 当前个人功能

### 一句话记账与分类联动

手动「记一笔」先打开文字输入层，输入 `午餐10.25元` 后进入详情页，金额为 10.25、备注为「午餐」。当前账本新建「餐饮 → 午餐」后即可按真实分类名称匹配，无需历史交易。

- 识别顺序：分类名称/路径、自定义关键词、既有历史推测。
- 多级分类可写 `餐饮/午餐10.25元` 消歧；相同优先级的歧义候选不任意选择。
- 自动识别总开关与手动类型/分类选择仍有效，AI 和导入草稿不参与本地预选。
- 金额使用阿拉伯数字；不解析中文金额、自然语言日期或账户名称。
- 解析仅生成草稿，点击保存才写账；可点「改用数字键盘」回到原入口。

| 输入 | 金额 | 备注 |
| --- | --- | --- |
| `早餐5元` | 5 | 早餐 |
| `打车32块` | 32 | 打车 |
| `房租1,200元` | 1200 | 房租 |
| `500+800` | 1300 | 空 |
| `买3斤苹果12` | 12 | 买3斤苹果 |
| `早餐` | 未识别 | 早餐 |

带金额单位的数字优先于裸数字，多数字时取最后一个候选；纯算式只在整段无汉字时求值。拆不出有效金额时整段保留为备注，金额由用户补齐。

### 子分类常驻面板

记账详情页常用分类下显示当前父分类的直接子分类，每行五个格子，末尾提供「新增」。点击子分类直接选中，切换父分类同步换内容；更深层仍通过多级选择器选择。「新增」先确认名称再选图标（内置图标或 emoji），取消不创建。

分类管理继续使用支持排序的列表，并已增加关键词维护入口；没有改成宫格。

### 看板分类占比与日常排行

日常、月统计、年统计均增加「支出占比」圆环，右上角可切收入，右下角可勾选「二级分类」「显示金额」。日常增加既有「分类·标签排行」，复用月/年排行与下钻。

| Tab | 新增占比 / 排行取数范围 |
| --- | --- |
| 日常 | 含今天的最近 7 个日历日 |
| 月统计 | 跟随看板期间栏所选月份（上游 v1.20.2 引入期间切换） |
| 年统计 | 跟随看板期间栏所选年份 |

日常原统计卡的「近7日 / 本周」切换只影响该卡，不联动新增两卡。占比卡的范围标签仅在日常 Tab 显示（日常没有期间栏）；月/年 Tab 的期间由期间栏标注，卡片不再重复显示同一标签（与排行卡一致），但取数随所选期间刷新。口径切换控件（`VeriEntryTypeToggle`）通过 `keyPrefix` 区分：占比卡用 `category_share_dimension_`，排行卡沿用默认 `dimension_toggle_`，避免同页 key 重复。占比按当前账本净本位币金额计算；一级模式上卷整棵分类树，二级模式将更深分类归到对应二级，顶级直接金额单独保留，不重复累计父子。转账不计入收支，已到账退款冲减原支出，「不计入预算」不排除收支统计。

面板开关与排序使用既有三组配置并随备份保存，旧配置自动补入新面板。支出/收入与两个勾选框仅影响当前视图，不持久化。

### 自定义记账关键词

主入口：**我的 → 分类管理 → 分类菜单 → 编辑 → 记账关键词**。
辅助入口：**一句话确认页 → 备注下方 → 将关键词关联到当前分类**。

例如给「餐饮」添加「包子」，再输入 `包子3元` 自动预选餐饮；也可绑定子分类。辅助入口预填备注，可缩短成常用词。

- 新增/删除先修改弹层草稿，保存规则与保存账目独立，取消不写规则。
- 同一账本内相同归一词不能绑定到多个分类（收入/支出之间也检查），不同账本互不影响。
- 关键词包含匹配取最长词，英文按词边界匹配，支持大小写/全半角归一；同等候选不猜测。
- 仅支出/收入及其子分类支持，转账和余额调整不参与；AI/导入草稿不显示辅助入口。
- `Category.keywords` 存在 SQLite v20 的 `categories.keywords` JSON 数组列；旧分类默认空，改名/移动保留、合并去重、删除清除、新账本不播种。
- 关键词随账本备份保存，旧备份缺失字段按空数组读取；备份 payload 仍为 v4。

详细口径见 [技术决策](docs/dev/tech-decisions.md)，逐项验证见 [验收清单](docs/product/acceptance-checklist.md)。

## 3. Windows 工具与本地验收构建

| 工具 | 当前路径 / 版本 |
| --- | --- |
| Flutter | `E:\Dev\flutter`，3.47.2（与 CI 一致） |
| Dart | 随 Flutter，3.13.2 |
| JDK | `E:\Dev\jdk\jdk-17`，Java 17 |
| Android SDK | `E:\Dev\Android\Sdk` |
| Gradle 缓存 | `E:\Dev\gradle-home` |
| Android 用户目录 | `E:\Dev\android-home` |

在当前终端设置环境，不把个人绝对路径写入已提交构建配置：

```powershell
$env:Path = "E:\Dev\flutter\bin;E:\Dev\jdk\jdk-17\bin;E:\Dev\Android\Sdk\platform-tools;" + $env:Path
$env:JAVA_HOME = "E:\Dev\jdk\jdk-17"
$env:ANDROID_HOME = "E:\Dev\Android\Sdk"
$env:ANDROID_SDK_ROOT = $env:ANDROID_HOME
$env:GRADLE_USER_HOME = "E:\Dev\gradle-home"
$env:ANDROID_USER_HOME = "E:\Dev\android-home"
cd "D:\CC Switch\Hello\verifin"

flutter --version
flutter doctor -v
adb devices -l
flutter build apk --release --target-platform android-arm64 --flavor github
```

产物为 `build\app\outputs\flutter-apk\app-github-release.apk`，用于个人真机验收。使用项目既有 release 签名，不修改签名配置，不通过卸载或清数据解决安装问题。

2026-10-13 的实际产物为 **61,713,765 字节（约 58.9 MiB）**，包含 `arm64-v8a`、`armeabi-v7a`、`x86_64` 三种 ABI；即使命令指定 arm64，也应以 APK 元数据为准，不能据命令保证包体架构。

- 源码提交：`a70c17d`（包含此前两项功能提交）。
- 包名 / 版本：`top.talyra42.verifin` / `1.20.1`，versionCode `171`。
- Android 最低版本：API 24；targetSdk 36。
- `apksigner verify` 通过（APK Signature Scheme v2）。
- SHA-256：`1B11639780B48F44049F807DBF06EBC2FB55CE3582060F7CD671BCC25257CEB2`。
- 尚未完成真机安装验收；公共看板截图尚未包含新增卡片，见 [截图说明](docs/screenshots/README.md)。

Windows Kotlin 增量缓存异常使用本地 `E:\Dev\gradle-home\gradle.properties` 的 `kotlin.incremental=false` 绕过，不修改仓库 `android/gradle.properties`。工具检测与缺失时自动补齐见 [Android 开发说明](docs/dev/android-development.md)。

## 4. GitHub 按需构建与上传

### 同步源码

确认变更范围并完成验证，再提交具体文件、推送个人分支：

```powershell
git status --short --branch
git diff --check
git add <本次修改的文件>
git commit -m "docs: refresh personal fork documentation"
git -c http.sslBackend=openssl push origin mine
```

避免无检查的 `git add -A`；`build/` 产物、日志、参考图片与机密配置不作为源码上传。`jpg/` 使用本地 `.git/info/exclude` 忽略。

### 下载个人 APK

1. 打开 [Build APK (mine)](https://github.com/yaarb55646/verifin/actions/workflows/mine-build.yml)。
2. 点击 **Run workflow**，选择 **mine**，默认保持 `run_checks` 开启；`label` 可用于文件名附加标识。
3. 完成后从该次运行的 **Artifacts** 下载 APK，保留 30 天。

工作流只由 `workflow_dispatch` 手动触发，不因 `mine` push 自动运行，不创建 Release、不更新版本号。构建参数与本地相同，实际 ABI/包体大小以产物为准。

应用内「检查更新」仍读取 **LumiDesk/verifin 的上游 Release**，不会找到个人工作流的 Artifacts；更新个人功能使用手动安装。正式标签发布继续遵循 [AGENTS.md](AGENTS.md)，源码上传不等于发版授权。

## 5. 维护文件与上游冲突点

| 领域 | 主要文件 |
| --- | --- |
| 文字输入 | `lib/app/quick_entry_text.dart`、`lib/pages/quick_text_entry_sheet.dart` |
| 入口与草稿 | `lib/pages/shell.dart`、`transactions_pages.dart`、`entry_detail_page.dart` |
| 分类匹配与规则 | `lib/app/category_suggest.dart`、`category_tree.dart`、`models/category.dart` |
| 分类 UI | `lib/app/entry_subcategory_panel.dart`、`lib/pages/category_management_page.dart`、`sheets.dart` |
| 持久化 / 兼容 | `lib/data/app_database.dart`、`ledger_repository.dart`、Controller state/ops、`lib/app/backup/legacy_book_scope.dart` |
| 看板 | `lib/pages/reports_page.dart`、`category_share_panel.dart`、`lib/app/report_analysis.dart`、`models/preferences.dart` |
| 国际化 | `lib/l10n/app_zh.arb`、`app_en.arb`；生成 Dart 不手改 |
| 自动化验证 | `test/quick_entry*_test.dart`、`quick_text_entry_test.dart`、`category_keywords*_test.dart`、`category_share*_test.dart` 及持久化/迁移/备份测试 |
| 个人 CI | `.github/workflows/mine-build.yml` |

新增文件也可能与未来上游同名文件冲突。合并时优先关注记账入口、详情页、分类模型/Controller、SQLite 迁移和看板目录。

当前 v20 为个人关键词迁移；上游如果也使用 v20，不能直接覆盖双方迁移或视为同一结构。同步前核对两边 schema、已安装用户数据库与全部历史迁移，设计兼容升级后再验证，禁止回改已发布迁移或降级。

组件清单、README、产品/设计/技术文档和 CHANGELOG 必须随行为更新；减少冲突不能成为跳过必要文档同步的理由。版本字段由发版流程管理，未获授权时保持 `1.20.1+171`。

### 上游同步

以下为用户明确要求同步上游时的维护步骤，先确认工作树干净：

```powershell
git -c http.sslBackend=openssl fetch upstream --tags
git log --oneline mine..upstream/main
git diff --stat mine upstream/main
git checkout mine
git rebase upstream/main

# 冲突解决后逐文件 git add，再 git rebase --continue；放弃使用 git rebase --abort。
# 全部验证通过后再推送；只有本次确实重写历史时才用 --force-with-lease。
git -c http.sslBackend=openssl push --force-with-lease origin mine
```

上游镜像可另外在 `main` 上 `git merge --ff-only upstream/main` 后切回 `mine`。不把个人功能合入镜像分支。

## 6. 验证约定与当前状态

代码改动完成后按顺序执行：

```powershell
flutter pub get
dart format .
flutter analyze
flutter test
```

SQLite 变更同时验证迁移矩阵、模型往返、内存/SQLite 仓储契约、持久化及备份。仅文档修改可执行 diff、链接、路径校验；不把旧结果写成新一轮执行。

截至 2026-10-16，同步上游 v1.20.3 后的 `mine` 已通过 `dart format .`、`flutter analyze --no-pub`（No issues found）、`flutter test --no-pub`（**1285 项全部通过**）。真机验收与本地 APK 构建由用户继续进行。

定位当前文档提交用 `git log -1 --oneline`；定位最新功能源码用 `git log -1 --oneline -- lib test android`，避免将会随文档提交变化的 HEAD 写死在手册中。
