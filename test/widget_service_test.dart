import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verifin/app/models.dart';
import 'package:verifin/app/veri_fin_controller.dart';
import 'package:verifin/app/widgets/widget_instance_config.dart';
import 'package:verifin/app/widgets/widget_projection.dart';
import 'package:verifin/app/widgets/widget_service.dart';

import 'support/test_harness.dart';

/// 投影刷新的三道闸门：同一版本不重复算、没有实例不写不刷、内容没变不重复写。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  useTestDatabases();

  const homeWidget = MethodChannel('home_widget');
  const app = MethodChannel('verifin/app');
  final calls = <String>[];
  final saved = <String, String>{};

  void mockChannels(Map<String, int> counts) {
    calls.clear();
    saved.clear();
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

  tearDown(() {
    resetWidgetProjectionCache();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(homeWidget, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(app, null);
  });

  test('桌面上没有实例时，数据变化不产生任何写入或刷新', () async {
    final controller = await makeController();
    addTearDown(controller.dispose);
    registerEntry(controller);
    mockChannels(const <String, int>{});
    resetWidgetProjectionCache();

    markWidgetDataChanged();
    await pushWidgetProjection(controller);

    expect(calls, <String>['app:widgetInstanceCounts']);
    expect(saved, isEmpty);
  });

  test('桌面上没有实例时，强制推送仍准备最新快照供之后新增组件读取', () async {
    final controller = await makeController();
    addTearDown(controller.dispose);
    registerEntry(controller);
    mockChannels(const <String, int>{});
    resetWidgetProjectionCache();

    await pushWidgetProjection(controller, force: true);

    final snapshots =
        jsonDecode(saved[widgetSnapshotsKey]!) as Map<String, dynamic>;
    final book = snapshots[controller.activeBook.id] as Map<String, dynamic>;
    expect((book['quick_entry'] as Map<String, dynamic>)['amount'], '20');
    expect(
      calls.any((call) => call.startsWith('update:')),
      isFalse,
      reason: '没有实例时只写共享快照，不向 Provider 发刷新广播',
    );
  });

  test('有实例时写入快照与账本，并只为该模板刷新与排程', () async {
    final controller = await makeController();
    addTearDown(controller.dispose);
    registerEntry(controller);
    mockChannels(const <String, int>{'quick_entry': 1});
    resetWidgetProjectionCache();

    await pushWidgetProjection(controller, force: true);

    expect(
      saved.keys,
      containsAll(<String>[
        widgetSnapshotsKey,
        widgetBooksKey,
        widgetLocaleKey,
      ]),
    );
    expect(
      calls,
      contains('update:top.talyra42.verifin.QuickEntryWidgetProvider'),
    );
    expect(
      calls,
      contains('schedule:top.talyra42.verifin.QuickEntryWidgetProvider'),
    );
    expect(
      calls.any((call) => call.contains('BudgetWidgetProvider')),
      isFalse,
      reason: '没有实例的模板不该被刷新',
    );

    final snapshots =
        jsonDecode(saved[widgetSnapshotsKey]!) as Map<String, dynamic>;
    expect(snapshots['version'], widgetSnapshotVersion);
    final book = controller.activeBook;
    final bookSnapshot = snapshots[book.id] as Map<String, dynamic>;
    expect(bookSnapshot['date'], isNotNull);
    expect(
      (bookSnapshot['quick_entry'] as Map<String, dynamic>)['amount'],
      '20',
    );
    expect(
      (bookSnapshot['budget'] as Map<String, dynamic>).containsKey('usage'),
      isFalse,
      reason: '没有预算时不该给出使用率',
    );
  });

  test('内容没变化时第二次推送不再写共享存储', () async {
    final controller = await makeController();
    addTearDown(controller.dispose);
    registerEntry(controller);
    mockChannels(const <String, int>{'quick_entry': 1});
    resetWidgetProjectionCache();

    await pushWidgetProjection(controller, force: true);
    final firstWrites = calls.where((call) => call.startsWith('save:')).length;
    expect(firstWrites, 3);

    calls.clear();
    markWidgetDataChanged();
    await pushWidgetProjection(controller);

    expect(calls.where((call) => call.startsWith('save:')), isEmpty);
    expect(calls.where((call) => call.startsWith('update:')), isEmpty);
  });

  test('同一数据版本再推一次连实例数都不问', () async {
    final controller = await makeController();
    addTearDown(controller.dispose);
    registerEntry(controller);
    mockChannels(const <String, int>{'quick_entry': 1});
    resetWidgetProjectionCache();

    await pushWidgetProjection(controller, force: true);
    calls.clear();
    await pushWidgetProjection(controller);

    expect(calls, isEmpty);
  });

  test('推送期间的新数据不会被旧版本标记为已发布', () async {
    final controller = await makeController();
    addTearDown(controller.dispose);
    registerEntry(controller);
    controller.onWidgetDataChanged = markWidgetDataChanged;
    resetWidgetProjectionCache();

    final firstSaveStarted = Completer<void>();
    final releaseFirstSave = Completer<void>();
    var saveCalls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(app, (call) async {
          if (call.method == 'widgetInstanceCounts') {
            return const <String, int>{'quick_entry': 1};
          }
          return null;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(homeWidget, (call) async {
          switch (call.method) {
            case 'saveWidgetData':
              if (saveCalls++ == 0) {
                firstSaveStarted.complete();
                await releaseFirstSave.future;
              }
              final args = call.arguments as Map;
              saved[args['id'] as String] = args['data'] as String;
              return true;
            case 'updateWidget':
            case 'scheduleWidgetUpdates':
              return null;
          }
          return null;
        });

    final firstPush = pushWidgetProjection(controller, force: true);
    await firstSaveStarted.future;

    controller.addEntry(
      LedgerEntry(
        id: 'entry-2',
        bookId: controller.activeBook.id,
        type: EntryType.expense,
        amount: 30,
        categoryId: 'dining',
        accountId: '',
        note: '',
        occurredAt: DateTime.now(),
      ),
    );
    final secondPush = pushWidgetProjection(controller);

    releaseFirstSave.complete();
    await Future.wait(<Future<void>>[firstPush, secondPush]);

    final snapshots =
        jsonDecode(saved[widgetSnapshotsKey]!) as Map<String, dynamic>;
    final book = snapshots[controller.activeBook.id] as Map<String, dynamic>;
    expect(
      (book['quick_entry'] as Map<String, dynamic>)['amount'],
      '50',
      reason: '后一次推送必须发布包含新交易的快照',
    );
  });
}

/// 记一笔支出，让投影有真实数据可对比。
void registerEntry(VeriFinController controller) {
  controller.addEntry(
    LedgerEntry(
      id: 'entry-1',
      bookId: controller.activeBook.id,
      type: EntryType.expense,
      amount: 20,
      categoryId: 'dining',
      // 全新账本没有播种账户，用「无账户」记一笔只影响统计口径，不影响余额。
      accountId: '',
      note: '',
      occurredAt: DateTime.now(),
    ),
  );
}
