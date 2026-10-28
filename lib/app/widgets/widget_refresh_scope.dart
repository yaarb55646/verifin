import 'package:flutter/widgets.dart';

import 'widget_refresh_coordinator.dart';

/// 把桌面投影的刷新协调器暴露给页面层，供**退出应用前**完成最后一次冲刷。
///
/// 为什么需要它：`SystemNavigator.pop()` 会 finish Activity，Flutter 引擎随之下线，
/// 挂在 `hidden` / `paused` 上的异步冲刷会被直接掐断——用户「记完账立刻按返回退出」时，
/// 快照就永远停在上一笔，直到下次冷启动补推。退出前必须先等这一轮发布完成。
///
/// 只暴露协调器，不暴露投影服务本身：页面不能自己算投影或改数据版本。
class WidgetRefreshScope extends InheritedWidget {
  const WidgetRefreshScope({
    super.key,
    required this.coordinator,
    required super.child,
  });

  final WidgetRefreshCoordinator coordinator;

  /// 取当前协调器；测试或独立页面没有挂 scope 时返回 `null`，调用方按「无需冲刷」处理。
  ///
  /// 用不建立依赖的查找：调用点在事件处理里（退出前冲刷），不需要因为协调器重建而重建。
  static WidgetRefreshCoordinator? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<WidgetRefreshScope>()?.coordinator;

  @override
  bool updateShouldNotify(WidgetRefreshScope oldWidget) =>
      !identical(coordinator, oldWidget.coordinator);
}
