# liquid_glass_widgets（本地 vendor）

[`liquid_glass_widgets`](https://pub.dev/packages/liquid_glass_widgets) 1.13.0，MIT，
Copyright (c) 2024–2026 Sebastian Degenaar，见同目录 `LICENSE` 与
`THIRD_PARTY_NOTICES`。

**为什么 vendor**：Veri Fin 只在可选的液态玻璃底部导航中使用该库的
`GlassTabBar.bottom`，需要把第三方实现与业务页面解耦，并且避免运行时依赖
pub.dev 的版本漂移。应用通过根 `pubspec.yaml` 的 `path:` 依赖引入本目录。

**使用边界**：只允许根导航适配层 `lib/app/root_navigation_liquid_glass.dart`
引用本包；不得在卡片、菜单、弹层、页面背景或其它界面中引入玻璃材质。
本目录保留上游的 `lib/`、`shaders/`、`ios/`、`pubspec.yaml`、许可证与更新记录；
未复制上游的 example、skills 等开发资料。

**同步方式**：从同一版本的 pub 发布包更新 `lib/`、`shaders/`、`ios/` 与
`pubspec.yaml`，不要在本目录做业务定制。应用侧的尺寸、颜色、key 和文案必须在
`root_navigation_liquid_glass.dart` 适配层表达。
