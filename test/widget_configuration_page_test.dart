import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verifin/app/app_lock.dart';
import 'package:verifin/app/native_widget_preview.dart';
import 'package:verifin/app/widgets/widget_catalog.dart';
import 'package:verifin/app/widgets/widget_instance_config.dart';
import 'package:verifin/pages/widget_configuration_page.dart';
import 'package:verifin/pages/app_lock_page.dart';

import 'support/test_harness.dart';

void main() {
  const homeWidget = MethodChannel('home_widget');
  const app = MethodChannel('verifin/app');
  const booksJson = '[{"id":"book-1","name":"个人"},{"id":"book-2","name":"旅行"}]';

  final calls = <String>[];
  final saved = <String, String>{};
  var bookReads = 0;

  void mockChannels({String books = booksJson, String? config}) {
    calls.clear();
    saved.clear();
    bookReads = 0;
    if (config != null) saved['${widgetConfigPrefix}42'] = config;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(homeWidget, (call) async {
          switch (call.method) {
            case 'initiallyLaunchedFromHomeWidgetConfigure':
              return '42';
            case 'getWidgetData':
              final key = (call.arguments as Map)['id'] as String;
              if (key == widgetBooksKey) {
                bookReads += 1;
                return books;
              }
              return saved[key];
            case 'saveWidgetData':
              final args = call.arguments as Map;
              saved[args['id'] as String] = args['data'] as String;
              calls.add('save');
              return true;
            case 'finishHomeWidgetConfigure':
              calls.add('finish');
              return null;
          }
          return null;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(app, (call) async {
          calls.add('app:${call.method}');
          if (call.method == 'widgetConfigurationInfo') {
            return <String, Object?>{
              'template': 'net_worth',
              'provider': 'top.talyra42.verifin.NetWorthWidgetProvider',
            };
          }
          return null;
        });
  }

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(homeWidget, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(app, null);
  });

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      zhMaterialApp(home: const WidgetConfigurationPage()),
    );
    await tester.pumpAndSettle();
  }

  bool saveEnabled(WidgetTester tester) =>
      tester
          .widget<FilledButton>(find.byKey(const Key('widget_save')))
          .onPressed !=
      null;

  NativeWidgetPreview draftPreview(WidgetTester tester) =>
      tester.widget<NativeWidgetPreview>(
        find.byKey(const Key('widget_draft_preview')),
      );

  testWidgets('未选账本时保存禁用，外观默认跟随系统且预览走样例态', (tester) async {
    mockChannels();
    await pumpPage(tester);

    expect(find.text('配置小组件'), findsOneWidget);
    expect(find.text('净资产'), findsWidgets, reason: '页头副标题应是模板名');
    expect(find.text('请选择账本'), findsOneWidget);
    expect(saveEnabled(tester), isFalse);
    expect(draftPreview(tester).sample, isTrue);
    expect(draftPreview(tester).appearance, WidgetAppearance.system);
    expect(draftPreview(tester).bookId, '');
  });

  testWidgets('选账本后可以保存，外观切换会同步到预览', (tester) async {
    mockChannels();
    await pumpPage(tester);

    await tester.tap(find.byKey(const Key('widget_book')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('旅行').last);
    await tester.pumpAndSettle();
    expect(find.text('请选择账本'), findsNothing);
    expect(saveEnabled(tester), isTrue);
    // 选了账本就换成真实数据预览。
    expect(draftPreview(tester).sample, isFalse);
    expect(draftPreview(tester).bookId, 'book-2');

    await tester.tap(find.byKey(const Key('widget_appearance')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('深色').last);
    await tester.pumpAndSettle();
    expect(draftPreview(tester).appearance, WidgetAppearance.dark);

    await tester.tap(find.byKey(const Key('widget_save')));
    // 保存成功后由原生关闭本页；测试里没有原生，页面停在「保存中」
    // （按钮里的进度圈会一直转），因此这里只推进固定的几帧。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(jsonDecode(saved['${widgetConfigPrefix}42']!), <String, Object?>{
      'bookId': 'book-2',
      'appearance': 'dark',
    });
    expect(calls, contains('app:refreshWidgetInstance'));
    expect(calls, contains('finish'));
  });

  testWidgets('读取已保存配置时回填账本与外观', (tester) async {
    mockChannels(
      config: jsonEncode(<String, String>{
        'bookId': 'book-1',
        'appearance': 'light',
      }),
    );
    await pumpPage(tester);

    expect(find.text('个人'), findsOneWidget);
    expect(find.text('浅色'), findsOneWidget);
    expect(draftPreview(tester).appearance, WidgetAppearance.light);
    expect(draftPreview(tester).bookId, 'book-1');
    expect(draftPreview(tester).sample, isFalse);
    expect(saveEnabled(tester), isTrue);
  });

  testWidgets('应用还没推送过账本时给出去向而不是空表单', (tester) async {
    mockChannels(books: '[]');
    await pumpPage(tester);

    expect(find.byKey(const Key('widget_save')), findsNothing);
    expect(find.textContaining('请先打开一次 Veri Fin'), findsOneWidget);
    expect(find.byKey(const Key('widget_open_app')), findsOneWidget);
  });

  testWidgets('页面失败态不谎报可保存', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(homeWidget, (call) async {
          if (call.method == 'initiallyLaunchedFromHomeWidgetConfigure') {
            return null;
          }
          return null;
        });
    await pumpPage(tester);

    expect(find.byKey(const Key('widget_save')), findsNothing);
    expect(find.textContaining('无法读取此小组件'), findsOneWidget);
  });

  testWidgets('启用应用锁时先验证，解锁前不读取账本', (tester) async {
    mockChannels();
    final lock = AppLockConfig.fromSecret(
      kind: AppLockKind.pin,
      secret: '123456',
    );
    await tester.pumpWidget(WidgetConfigurationApp(appLock: lock));
    await tester.pumpAndSettle();

    expect(find.byType(AppLockScreen), findsOneWidget);
    expect(find.byKey(const Key('widget_save')), findsNothing);
    expect(find.byKey(const Key('app_lock_forgot')), findsNothing);
    expect(bookReads, 0);

    for (final digit in '123456'.split('')) {
      await tester.tap(find.byKey(Key('pin_key_$digit')));
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(find.byType(AppLockScreen), findsNothing);
    expect(find.byKey(const Key('widget_book')), findsOneWidget);
    expect(bookReads, 1);
  });
}
