import 'dart:async';

import 'package:flutter/widgets.dart';

/// 向主界面暴露当前是否处于锁屏状态；外部入口必须先通过 [waitUntilUnlocked]。
class AppLockSessionScope extends InheritedNotifier<ValueNotifier<bool>> {
  const AppLockSessionScope({
    super.key,
    required ValueNotifier<bool> locked,
    required super.child,
  }) : super(notifier: locked);

  static bool isLocked(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<AppLockSessionScope>()
            ?.notifier
            ?.value ??
        false;
  }

  /// 等待用户完成解锁；应用锁未启用或已经解锁时立即返回。
  static Future<void> waitUntilUnlocked(BuildContext context) {
    final notifier = context
        .dependOnInheritedWidgetOfExactType<AppLockSessionScope>()
        ?.notifier;
    if (notifier == null || !notifier.value) {
      return Future<void>.value();
    }
    final completer = Completer<void>();
    void listener() {
      if (notifier.value || completer.isCompleted) {
        return;
      }
      notifier.removeListener(listener);
      completer.complete();
    }

    notifier.addListener(listener);
    listener();
    return completer.future;
  }
}
