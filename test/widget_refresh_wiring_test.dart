import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verifin/app/models.dart';
import 'package:verifin/app/veri_fin_controller.dart';
import 'package:verifin/app/widgets/widget_instance_config.dart';
import 'package:verifin/app/widgets/widget_refresh_coordinator.dart';
import 'package:verifin/app/widgets/widget_service.dart';

import 'support/test_harness.dart';

/// 生产接线回归：只按 `main.dart` 的方式接线（数据变化 → `coordinator.schedule`），
/// 防抖到点后必须**真正发布**一次投影。
///
/// `pushWidgetProjection` 的第一道闸门按「同一数据版本已推送」跳过重复推送，版本号
/// 只由 `markWidgetDataChanged()` 推进。历史上 `main.dart` 只接了 `schedule`，
/// 没有人推进版本号，于是每次普通数据变化都在闸门处静默返回，桌面组件只剩冷启动 /
/// 回前台 / 切后台三次强制推送——线上表现是「记完账桌面数字不变，除非再打开一次
/// 应用」。
///
/// 既有用例看不出来：`widget_projection_signal_test` 只断言 `onWidgetDataChanged`
/// 被调用（它确实被调用了），`widget_service_test` 则在每个用例里**自己**调
/// `markWidgetDataChanged()`，等于替生产代码补了接线。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  useTestDatabases();

  const homeWidget = MethodChannel('home_widget');
  const app = MethodChannel('verifin/app');
  final saved = <String, String>{};
  final calls = <String>[];

  void mockChannels(Map<String, int> counts) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(app, (call) async {
          calls.add('app:${call.method}');
          if (call.method == 'widgetInstanceCounts') return counts;
          return null;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(homeWidget, (call) async {
          switch (call.method) {
            case 'saveWidgetData':
              final args = call.arguments as Map;
              final key = args['id'] as String;
              saved[key] = args['data'] as String;
              calls.add('save:$key');
              return true;
            case 'updateWidget':
              calls.add(
                'update:${(call.arguments as Map)['qualifiedAndroidName']}',
              );
              return null;
            case 'scheduleWidgetUpdates':
              calls.add(
                'schedule:${(call.arguments as Map)['qualifiedAndroidName']}',
              );
              return null;
          }
          return null;
        });
  }

  setUp(() {
    saved.clear();
    calls.clear();
    resetWidgetProjectionCache();
    mockChannels(const <String, int>{'quick_entry': 1});
  });

  tearDown(() {
    resetWidgetProjectionCache();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(homeWidget, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(app, null);
  });

  /// 按 `main.dart` 的正式接法组装：数据变化与语言变化都只挂 `schedule`。
  Future<VeriFinController> wiring() async {
    final controller = await makeController();
    final coordinator = WidgetRefreshCoordinator(
      controller.flushPendingWrites,
      ({required bool force}) => pushWidgetProjection(controller, force: force),
    );
    addTearDown(coordinator.dispose);
    addTearDown(controller.dispose);
    controller.onWidgetDataChanged = coordinator.schedule;
    controller.localePreferenceListenable.addListener(coordinator.schedule);
    addTearDown(
      () => controller.localePreferenceListenable.removeListener(
        coordinator.schedule,
      ),
    );
    // 冷启动的强制推送：它会写一次快照并把版本号对齐（与线上一致）。
    await pushWidgetProjection(controller, force: true);
    saved.clear();
    calls.clear();
    return controller;
  }

  /// 等防抖（250ms）到点，再等平台通道往返完成。
  Future<void> waitForDebouncedPush() async {
    await Future<void>.delayed(const Duration(milliseconds: 320));
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }

  test('记一笔后，只挂 schedule 也会真正写入快照并刷新 Provider', () async {
    final controller = await wiring();

    controller.addEntry(
      LedgerEntry(
        id: 'entry-wiring',
        bookId: controller.activeBook.id,
        type: EntryType.expense,
        amount: 20,
        categoryId: 'dining',
        accountId: '',
        note: '',
        occurredAt: DateTime.now(),
      ),
    );
    await waitForDebouncedPush();

    expect(
      saved[widgetSnapshotsKey],
      isNotNull,
      reason: '账目变化后必须发布新快照，而不是被「同一数据版本」闸门静默跳过',
    );
    expect(
      calls,
      contains('update:top.talyra42.verifin.QuickEntryWidgetProvider'),
      reason: '发布后必须刷新有实例的 Provider',
    );
  });

  test('语言变化同样会推进版本号并重新发布', () async {
    final controller = await wiring();

    controller.setLocalePreference(LocalePreference.en);
    await waitForDebouncedPush();

    expect(
      saved[widgetLocaleKey],
      'en',
      reason: '桌面文案随应用语言变化，语言切换必须重新发布（它也在快照指纹里）',
    );
  });

  test('同一批数据只防抖发布一次，版本号不会被重复推送消耗', () async {
    final controller = await wiring();

    controller.addEntry(
      LedgerEntry(
        id: 'entry-a',
        bookId: controller.activeBook.id,
        type: EntryType.expense,
        amount: 10,
        categoryId: 'dining',
        accountId: '',
        note: '',
        occurredAt: DateTime.now(),
      ),
    );
    controller.addEntry(
      LedgerEntry(
        id: 'entry-b',
        bookId: controller.activeBook.id,
        type: EntryType.expense,
        amount: 10,
        categoryId: 'dining',
        accountId: '',
        note: '',
        occurredAt: DateTime.now(),
      ),
    );
    await waitForDebouncedPush();

    expect(
      calls.where((call) => call == 'app:widgetInstanceCounts').length,
      1,
      reason: '同一轮防抖只该发布一次',
    );
  });
}
