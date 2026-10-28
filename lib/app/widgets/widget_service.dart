import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';

import '../l10n_outside_context.dart';
import '../platform_bridge.dart';
import '../veri_fin_controller.dart';
import 'widget_catalog.dart';
import 'widget_instance_config.dart';
import 'widget_projection.dart';

/// 影响桌面投影的数据版本号。[markWidgetDataChanged] 只由真正会改变投影的落库
/// 咽喉点调用（交易、账户、账本、汇率、预算、预算周期、语言），**不再挂在
/// `notifyListeners()`**：改主题、折叠分区这类无关操作不再触发重算。
int _dataRevision = 0;
int _pushedRevision = -1;
String? _pushedFingerprint;
Future<void> _pushQueue = Future<void>.value();

/// 标记账目类数据已变化（调用方负责 250ms 防抖）。
void markWidgetDataChanged() => _dataRevision++;

@visibleForTesting
void resetWidgetProjectionCache() {
  _dataRevision = 0;
  _pushedRevision = -1;
  _pushedFingerprint = null;
  _pushQueue = Future<void>.value();
}

/// 把当前账本数据发布给桌面组件。
///
/// 三道闸门，按代价从低到高：①同一数据版本已推送过 → 直接返回；②桌面上没有任何
/// 实例（且非强制）→ 连投影都不算；③推送内容与上次完全相同 → 不写共享存储、不刷
/// Provider、不排闹钟。
///
/// [force] 供冷启动与回前台使用：即使用户此刻还没添加组件，也推一次，保证之后
/// 新添加的实例第一次渲染就能读到数据。
Future<void> pushWidgetProjection(
  VeriFinController controller, {
  bool force = false,
}) {
  final request = _pushQueue.then(
    (_) => _pushWidgetProjection(controller, force: force),
  );
  _pushQueue = request.catchError((Object error, StackTrace _) {});
  return request;
}

Future<void> _pushWidgetProjection(
  VeriFinController controller, {
  required bool force,
}) async {
  try {
    if (!force && _pushedRevision == _dataRevision) return;
    // Capture the revision represented by this payload. If data changes while
    // the platform writes are in flight, the next scheduled push must still
    // run instead of being mistaken for already published data.
    final revision = _dataRevision;
    final counts = await AppWidgetBridge.widgetInstanceCounts();
    if (!force && counts.isEmpty) return;
    final payload = _encodePayload(controller);
    if (payload.fingerprint == _pushedFingerprint) {
      _pushedRevision = revision;
      return;
    }
    await HomeWidget.saveWidgetData<String>(
      widgetSnapshotsKey,
      payload.snapshots,
    );
    await HomeWidget.saveWidgetData<String>(widgetBooksKey, payload.books);
    await HomeWidget.saveWidgetData<String>(widgetLocaleKey, payload.locale);

    // 只刷新真正有实例的 Provider：没有实例时既不发广播也不排闹钟。
    final active = WidgetTemplate.values.where(
      (template) => (counts[template.key] ?? 0) > 0,
    );
    await Future.wait(<Future<void>>[
      for (final template in active)
        HomeWidget.updateWidget(
          qualifiedAndroidName: template.providerComponent,
        ),
    ]);
    // 下一次本地午夜由 home_widget 负责重排（它同时处理开机与应用更新），
    // 每次推送重新计算也顺手覆盖了时区变化。
    final now = DateTime.now();
    final nextMidnight = DateTime(now.year, now.month, now.day + 1, 0, 0, 5);
    await Future.wait(<Future<void>>[
      for (final template in active)
        HomeWidget.scheduleWidgetUpdates(<DateTime>[
          nextMidnight,
        ], qualifiedAndroidName: template.providerComponent),
    ]);
    _pushedFingerprint = payload.fingerprint;
    _pushedRevision = revision;
  } on MissingPluginException {
    // 桌面与纯 widget 测试环境没有 home_widget 通道，静默跳过。
  } on Object catch (error) {
    controller.logger?.warning(
      'Widget projection update failed: $error',
      source: 'widgets',
    );
  }
}

/// 待写入共享存储的三份内容 + 用于「内容未变」比对的指纹。
({String snapshots, String books, String locale, String fingerprint})
_encodePayload(VeriFinController controller) {
  final now = DateTime.now();
  final snapshots = <String, Object?>{};
  for (final book in controller.ledgerBooks) {
    final snapshot = controller.widgetBookSnapshot(book.id, now);
    if (snapshot == null) continue;
    final projection = buildWidgetBookProjection(snapshot: snapshot, now: now);
    snapshots[book.id] = <String, Object?>{
      'date': projection.dateKey,
      for (final entry in projection.templates.entries)
        entry.key.key: entry.value.toJson(),
    };
  }
  // 版本号让原生侧能识别「旧版形状的快照」并退回「打开应用同步数据」，而不是把
  // 读不到的字段渲染成缺失值。改快照形状必须同时改 Kotlin 的 SNAPSHOT_VERSION。
  final snapshotsJson = jsonEncode(<String, Object?>{
    'version': widgetSnapshotVersion,
    ...snapshots,
  });
  final booksJson = jsonEncode(<Map<String, String>>[
    for (final book in controller.ledgerBooks)
      <String, String>{'id': book.id, 'name': book.name},
  ]);
  final locale = l10nForPreference(controller.localePreference).localeName;
  return (
    snapshots: snapshotsJson,
    books: booksJson,
    locale: locale,
    fingerprint: '$snapshotsJson\u0000$booksJson\u0000$locale',
  );
}
