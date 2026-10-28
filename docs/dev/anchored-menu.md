# 锚点菜单（anchored_menu）

Veri Fin 的锚点菜单使用 pub.dev 外部组件库 [anchored_menu](https://pub.dev/packages/anchored_menu)，当前依赖为 `^0.1.3`，直接导入：

```dart
import 'package:anchored_menu/anchored_menu.dart';
```

项目不再维护本地菜单实现、part 文件或同名包装组件。页面直接使用外部 API；应用只负责把设计令牌桥接到外部库的 `AnchoredMenuThemeData`。

## 适用范围

适合：

- 页面右上角的少量更多操作；
- 视图、排序、筛选等短枚举；
- 需要就地展示当前值的轻量设置；
- 最多只有少量选项、无需搜索的递进菜单。

不适合：

- 账户、分类、货币等长列表或可搜索列表；
- 连续输入、复杂表单和完整草稿编辑；
- 删除、覆盖数据等危险确认；
- 需要大段说明或容易超出屏幕的内容。

这些场景继续使用对应 Picker Sheet、普通 Sheet、Dialog 或全屏编辑页。

## 应用侧 API

外部库提供以下入口，页面按场景直接使用：

| 名称 | 用途 |
|---|---|
| `AnchoredMenuButton` | Header 图标触发器；`tooltip` 同时作为菜单语义标签 |
| `AnchoredMenuAnchor` | 任意控件触发；`builder` 获得 `openMenu` 与 `menuOpen` |
| `AnchoredMenuChoice<T>` | 2–8 项静态、受控单选的轻量适配层 |
| `AnchoredMenuItem` | 叶子操作或递进父项，支持图标、副标题、选中、禁用、语义色、子菜单和稳定 `id` |
| `AnchoredMenuDivider` | 相关操作之间的分割线 |
| `AnchoredMenuEntry` | 菜单项和分割线的封闭基类 |
| `AnchoredMenuAnchorBuilder` | 自定义触发器的构造签名 |

页面必须使用这些入口，不得自行调用 `showMenu`、`OverlayEntry` 或 `showGeneralDialog`。静态短单选优先用 `AnchoredMenuChoice<T>`；动态、可搜索或需分区的列表仍使用专用 Sheet。

## 应用主题桥接

`buildVeriFinTheme()` 在 `lib/app/app_theme.dart` 中安装 `AnchoredMenuThemeData`，保持菜单与 Veri Fin 的表面材质一致：

| 令牌 | 应用取值 |
|---|---|
| 面板表面 | `veriElevatedSurfaceColor(brightness)`，不透明实色 |
| 描边 | 深色 `white @ 12%`；浅色 `veriLine` |
| 前景 / 选中 | `colorScheme.onSurface` / `colorScheme.primary` |
| 面板圆角 | `veriRadiusXl`（24） |
| 行 Hover 圆角 | `veriRadiusLg`（16） |
| 最小宽度 | `168` |

菜单项标题和副标题沿用应用最终的 `titleSmall`（13px）与 `labelMedium`（11px）；外部库会在此基础上补齐字重。不要在页面调用点覆写颜色、圆角或字体。

## 宽度与定位

- 根菜单默认按内容自适应，最小 168dp；显式传入 `width` 时才固定宽度。
- 子菜单宽度优先级：当前父项 `AnchoredMenuItem.submenuWidth` > Anchor/Button 的 `submenuWidth` > 内容自适应。
- 所有宽度都会限制在弹层实际可用宽度内；窗口尺寸变化后重新按当前约束定位。
- 空间足够时向下展开，否则向上展开；右缘贴近触发器，并避开屏幕左右安全边距；高度不足时菜单内部滚动。
- 标题与副标题自然换行，不使用横向省略号；纯文本项不继承其他项的图标列。

## 状态与交互

- 菜单是受控展示组件；`selected`、`subtitle`、`enabled` 由页面状态决定，菜单不读取 Controller 或 KV。
- 叶子项先完成关闭动画，再调用 `onPressed`；父项只进入下一级。
- 子菜单从被点击行的累计实际位置展开，完整祖先卡片栈始终保留；每一级轻微缩小并向黑色混合，表面保持不透明。
- Android/系统返回只退一级，根层再关闭；点击菜单外部关闭整棵菜单。
- 根弹层 220ms 淡入/缩放，子菜单前进 280ms、返回 260ms；系统减少动态效果时使用静态过渡。
- 外部库提供方向键、Enter、Space、Escape 导航和 RTL 布局；应用不重复实现键盘或方向逻辑。
- 菜单项的稳定 key 默认使用前缀 `anchored`：`anchored_menu_item_<id>`、`anchored_menu_layer_<index>`。测试按这些 key 定位；如将来需要别的命名空间，显式传 `keyPrefix` 并同步测试。

## 测试

- `test/anchored_menu_test.dart`：在应用主题下覆盖菜单渲染、宽度、子菜单、返回、外部点击、动画和四级祖先栈。
- `test/anchored_menu_theme_test.dart`：断言浅深色主题都把表面、描边、选中色、圆角与最小宽度桥接给外部库。
- 页面业务回调由对应页面测试覆盖，例如 `test/accounts_assets_test.dart` 的资产操作菜单与嵌套显示设置。

升级 `anchored_menu` 时先阅读其 changelog，复跑以上测试，并在模拟器/真机检查资产加号菜单、二级菜单和系统返回。

## 维护检查清单

- 新增菜单前确认它比 Sheet/Dialog 更合适；
- 页面是否直接导入 `package:anchored_menu/anchored_menu.dart`；
- `id` 是否稳定且在树内唯一；
- 用户可见文案是否完成中英文 ARB；
- 是否只通过应用主题桥接视觉令牌，没有在页面覆盖样式；
- 深层菜单是否保留全部祖先层并可逐级返回；
- 是否运行 `flutter analyze`、相关 Widget 测试和全量测试。
