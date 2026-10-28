import 'dart:async';

import 'widget_service.dart';

/// Schedules widget projection updates and guarantees that app backgrounding
/// flushes the latest ledger state before the process may be suspended.
class WidgetRefreshCoordinator {
  WidgetRefreshCoordinator(
    this._flushPendingWrites,
    this._pushProjection, {
    this.debounce = const Duration(milliseconds: 250),
  });

  final Future<void> Function() _flushPendingWrites;
  final Future<void> Function({required bool force}) _pushProjection;
  final Duration debounce;

  Timer? _timer;
  Future<void>? _flushInFlight;
  bool _disposed = false;

  /// Debounces a data/locale change while the app remains interactive.
  ///
  /// **必须在这里推进数据版本**：`pushWidgetProjection` 的第一道闸门按「同一版本
  /// 已推送」跳过重复推送。以前的接线只在 `main.dart` 里接了 `schedule`，没有人调
  /// `markWidgetDataChanged`，于是每一次普通数据变化都在闸门处被静默丢弃，桌面组件
  /// 只剩冷启动 / 回前台 / 切后台三次强制推送——表现就是「记完账桌面数字不变，
  /// 除非再打开一次应用」。把推进放在 `schedule` 内部，任何调用点都不会再漏。
  void schedule() {
    if (_disposed) return;
    markWidgetDataChanged();
    _timer?.cancel();
    _timer = Timer(debounce, () {
      _timer = null;
      unawaited(_pushProjection(force: false));
    });
  }

  /// Pushes immediately and drops any pending debounce. Used for startup and
  /// resume, where the latest state must be published even without a data
  /// revision change.
  Future<void> pushNow({required bool force}) {
    if (_disposed) return Future<void>.value();
    _timer?.cancel();
    _timer = null;
    return _pushProjection(force: force);
  }

  /// Called when the app leaves the foreground: persist pending writes first,
  /// then publish the resulting controller state before the isolate can be
  /// cached or suspended.
  Future<void> flush() {
    if (_disposed) return Future<void>.value();
    final running = _flushInFlight;
    if (running != null) return running;
    final future = _flush();
    _flushInFlight = future;
    unawaited(
      future.then<void>(
        (_) => _clearFlush(future),
        onError: (Object error, StackTrace _) => _clearFlush(future),
      ),
    );
    return future;
  }

  Future<void> _flush() async {
    _timer?.cancel();
    _timer = null;
    await _flushPendingWrites();
    if (_disposed) return;
    // A forced publish still compares fingerprints, so unchanged content is
    // not rewritten. It additionally prepares the snapshot when the launcher
    // currently has no instance, allowing a widget added later to render data
    // without requiring the main application to be reopened first.
    await _pushProjection(force: true);
  }

  void _clearFlush(Future<void> future) {
    if (identical(_flushInFlight, future)) {
      _flushInFlight = null;
    }
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }
}
