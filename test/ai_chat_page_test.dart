import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:verifin/app/ai/ai_agent_engine.dart';
import 'package:verifin/app/ai/ai_completion_event.dart';
import 'package:verifin/app/ai/ai_error.dart';
import 'package:verifin/app/ai/ai_settings.dart';
import 'package:verifin/app/models.dart';
import 'package:verifin/app/veri_fin_scope.dart';
import 'package:verifin/pages/ai_chat_page.dart';
import 'package:verifin/pages/ai_settings_page.dart';
import 'package:verifin/pages/transaction_detail_page.dart';

import 'support/test_harness.dart';

/// 按调用顺序返回结构化补全事件。
AiAgentStreamTransport _scripted(List<List<AiCompletionEvent>> responses) {
  var index = 0;
  return (messages, tools) async* {
    final events = index < responses.length
        ? responses[index]
        : const <AiCompletionEvent>[];
    index += 1;
    for (final event in events) {
      yield event;
    }
  };
}

List<AiCompletionEvent> _answer(String text) => <AiCompletionEvent>[
  AiContentDelta(text),
  const AiCompletionFinished(AiFinishReason.stop),
  const AiStreamDone(),
];

Future<void> _pumpAsync(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 10)),
  );
  await tester.pump();
  await tester.pumpAndSettle();
}

Future<void> _pumpRealAsyncFrames(WidgetTester tester) async {
  for (var index = 0; index < 5; index += 1) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 2)),
    );
    await tester.pump();
  }
}

void main() {
  useTestDatabases();

  testWidgets('未配置 AI 时显示引导按钮', (tester) async {
    final controller = await makeController();
    await tester.pumpWidget(
      VeriFinScope(
        controller: controller,
        child: zhMaterialApp(home: const AiChatPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('去配置 AI'), findsOneWidget);
    expect(find.byKey(const Key('empty_state_illustration')), findsOneWidget);
    expect(find.textContaining('只读查询账目'), findsNothing);
    expect(find.text('对话只存本机，不含在备份内'), findsNothing);
    expect(find.byTooltip('AI 设置'), findsNothing);
    controller.dispose();
  });

  testWidgets('已配置 AI 时右上角设置按钮进入 AI 设置', (tester) async {
    final controller = await makeController()
      ..setAiSettings(
        const AiSettings(baseUrl: 'http://x/v1', apiKey: 'k', model: 'm'),
      );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      VeriFinScope(
        controller: controller,
        child: zhMaterialApp(home: const AiChatPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('AI 设置'), findsOneWidget);
    await tester.tap(find.byTooltip('AI 设置'));
    await tester.pumpAndSettle();

    expect(find.byType(AiSettingsPage), findsOneWidget);
    expect(find.text('AI 设置'), findsOneWidget);
  });

  testWidgets('Composer 输入限制为 8000 字符', (tester) async {
    final controller = await makeController()
      ..setAiSettings(
        const AiSettings(baseUrl: 'http://x/v1', apiKey: 'k', model: 'm'),
      );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      VeriFinScope(
        controller: controller,
        child: zhMaterialApp(home: const AiChatPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'a' * 8001);
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text.length, 8000);
  });

  testWidgets('底部输入区为单块 Composer，账本与发送位于同一操作行', (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = await makeController()
      ..setAiSettings(
        const AiSettings(baseUrl: 'http://x/v1', apiKey: 'k', model: 'm'),
      );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      VeriFinScope(
        controller: controller,
        child: zhMaterialApp(home: const AiChatPage()),
      ),
    );
    await tester.pumpAndSettle();

    final composer = tester.getRect(find.byKey(const Key('ai_chat_composer')));
    final input = tester.getRect(find.byType(TextField));
    final book = tester.getRect(find.byKey(const Key('ai_chat_book_selector')));
    final send = tester.getRect(find.byKey(const Key('ai_chat_send_button')));
    expect(composer.left, greaterThan(0));
    expect(composer.right, lessThan(393));
    expect(input.top, lessThan(book.top));
    expect(book.width, greaterThan(80));
    expect(book.top, greaterThanOrEqualTo(input.bottom));
    expect((send.center.dy - book.center.dy).abs(), lessThan(2));
  });

  testWidgets('已配置：发问 → 工具卡片 + 流式答复', (tester) async {
    final controller = await makeController();
    final bookId = controller.activeBook.id;
    controller
      ..setAiSettings(
        const AiSettings(baseUrl: 'http://x/v1', apiKey: 'k', model: 'm'),
      )
      ..addEntry(
        LedgerEntry(
          id: 'e1',
          bookId: bookId,
          type: EntryType.expense,
          amount: 300,
          categoryId: 'dining',
          accountId: 'cash',
          note: '',
          occurredAt: DateTime.now(),
        ),
      );

    final transport = _scripted(<List<AiCompletionEvent>>[
      <AiCompletionEvent>[
        const AiToolCallDelta(
          index: 0,
          id: 'call_1',
          name: 'summary',
          arguments: '{"range":"thisMonth"}',
        ),
        const AiCompletionFinished(AiFinishReason.toolCalls),
        const AiStreamDone(),
      ],
      _answer('本月支出合计 300 元。'),
    ]);

    await tester.pumpWidget(
      VeriFinScope(
        controller: controller,
        child: zhMaterialApp(home: AiChatPage(debugTransport: transport)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '本月花了多少');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.pump();
    await _pumpAsync(tester);
    await _pumpAsync(tester);

    // 用户气泡
    expect(find.text('本月花了多少'), findsOneWidget);
    // summary 工具的结果卡（标题含「收支汇总」）
    expect(find.textContaining('收支汇总'), findsWidgets);
    expect(find.text('查询收支汇总'), findsOneWidget);
    expect(find.byKey(const Key('ai_answer_provenance')), findsOneWidget);
    expect(find.text('基于账本查询 · 1 次'), findsOneWidget);
    expect(find.textContaining('{"tool"'), findsNothing);
    // 统计卡里的净额/支出行
    expect(find.text('支出'), findsWidgets);
    controller.dispose();
  });

  testWidgets('零工具金额回答显示未查询账本警告', (tester) async {
    final controller = await makeController()
      ..setAiSettings(
        const AiSettings(baseUrl: 'http://x/v1', apiKey: 'k', model: 'm'),
      );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      VeriFinScope(
        controller: controller,
        child: zhMaterialApp(
          home: AiChatPage(
            debugTransport: _scripted(<List<AiCompletionEvent>>[
              _answer('本月支出 1200 元。'),
            ]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '本月花了多少');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.pump();
    await _pumpAsync(tester);

    expect(find.text('未查询账本，请勿据此判断账目'), findsOneWidget);
  });

  testWidgets('对话账本按页面选择，不改变全局活动账本', (tester) async {
    final controller = await makeController()
      ..setAiSettings(
        const AiSettings(baseUrl: 'http://x/v1', apiKey: 'k', model: 'm'),
      );
    final defaultBookId = controller.activeBook.id;
    final defaultBookName = controller.activeBook.name;
    controller.addLedgerBook('旅行账本', baseCurrencyCode: 'USD');
    final travelBookId = controller.activeBook.id;
    final expenseCategory = controller
        .categoriesForBook(travelBookId)
        .firstWhere((category) => category.type == EntryType.expense);
    controller.addEntry(
      LedgerEntry(
        id: 'travel-entry',
        bookId: travelBookId,
        type: EntryType.expense,
        amount: 25,
        categoryId: expenseCategory.id,
        accountId: '',
        note: '旅行午餐',
        occurredAt: DateTime.now(),
      ),
    );
    controller.addEntry(
      LedgerEntry(
        id: 'travel-cny-entry',
        bookId: travelBookId,
        type: EntryType.expense,
        amount: 10,
        currencyCode: 'CNY',
        categoryId: expenseCategory.id,
        accountId: '',
        note: '旅行人民币支出',
        occurredAt: DateTime.now(),
      ),
    );
    controller.switchLedgerBook(defaultBookId);
    addTearDown(controller.dispose);

    final transport = _scripted(<List<AiCompletionEvent>>[
      <AiCompletionEvent>[
        const AiToolCallDelta(
          index: 0,
          id: 'call_book',
          name: 'summary',
          arguments: '{"range":"thisMonth"}',
        ),
        const AiCompletionFinished(AiFinishReason.toolCalls),
        const AiStreamDone(),
      ],
      _answer('旅行账本支出 25。'),
    ]);
    await tester.pumpWidget(
      VeriFinScope(
        controller: controller,
        child: zhMaterialApp(home: AiChatPage(debugTransport: transport)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining(defaultBookName), findsWidgets);
    await tester.tap(find.byKey(const Key('ai_chat_book_selector')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(
        ValueKey<String>('anchored_menu_item_ai_chat_book_$travelBookId'),
      ),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(
        ValueKey<String>('anchored_menu_item_ai_chat_book_$travelBookId'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('旅行账本'), findsWidgets);

    await tester.enterText(find.byType(TextField), '帮我汇总');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.pump();
    await _pumpAsync(tester);

    expect(controller.activeBook.id, defaultBookId);
    expect(find.textContaining('25'), findsWidgets);
    expect(find.textContaining('单位：'), findsWidgets);
  });

  testWidgets('AI 交易结果卡只读，不跳转交易详情', (tester) async {
    final controller = await makeController()
      ..setAiSettings(
        const AiSettings(baseUrl: 'http://x/v1', apiKey: 'k', model: 'm'),
      );
    final bookId = controller.activeBook.id;
    final category = controller.categories.firstWhere(
      (item) => item.type == EntryType.expense,
    );
    controller.addEntry(
      LedgerEntry(
        id: 'readonly-entry',
        bookId: bookId,
        type: EntryType.expense,
        amount: 12,
        categoryId: category.id,
        accountId: '',
        note: '不可点击午餐',
        occurredAt: DateTime.now(),
      ),
    );
    addTearDown(controller.dispose);

    final transport = _scripted(<List<AiCompletionEvent>>[
      <AiCompletionEvent>[
        const AiToolCallDelta(
          index: 0,
          id: 'call_tx',
          name: 'queryTransactions',
          arguments: '{"range":"thisMonth"}',
        ),
        const AiCompletionFinished(AiFinishReason.toolCalls),
        const AiStreamDone(),
      ],
      _answer('找到一笔交易。'),
    ]);
    await tester.pumpWidget(
      VeriFinScope(
        controller: controller,
        child: zhMaterialApp(home: AiChatPage(debugTransport: transport)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '最近交易');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.pump();
    await _pumpAsync(tester);

    expect(find.text('不可点击午餐'), findsOneWidget);
    await tester.tap(find.text('不可点击午餐'));
    await tester.pumpAndSettle();
    expect(find.byType(TransactionDetailPage), findsNothing);

    await controller.deleteEntries(<String>{'readonly-entry'});
    await tester.pumpAndSettle();
    expect(find.text('不可点击午餐'), findsOneWidget);
  });

  testWidgets('清空聊天记录', (tester) async {
    final controller = await makeController()
      ..setAiSettings(
        const AiSettings(baseUrl: 'http://x/v1', apiKey: 'k', model: 'm'),
      );
    await tester.pumpWidget(
      VeriFinScope(
        controller: controller,
        child: zhMaterialApp(
          home: AiChatPage(
            debugTransport: _scripted(<List<AiCompletionEvent>>[
              _answer('你好呀'),
            ]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('清空对话').hitTestable(), findsNothing);
    final settingsBefore = tester.getCenter(find.byTooltip('AI 设置'));
    await tester.enterText(find.byType(TextField), '在吗');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.pump();
    await _pumpAsync(tester);
    expect(find.text('在吗'), findsOneWidget);
    expect(tester.getCenter(find.byTooltip('AI 设置')), settingsBefore);
    expect(
      tester.getCenter(find.byTooltip('清空对话').hitTestable()).dx,
      lessThan(settingsBefore.dx),
    );

    await tester.tap(find.byTooltip('清空对话').hitTestable());
    await tester.pumpAndSettle();
    await tester.tap(find.text('清空'));
    await tester.pumpAndSettle();
    expect(find.text('在吗'), findsNothing);
    controller.dispose();
  });

  testWidgets('网络错误保留友好文案并提供重新回答', (tester) async {
    final controller = await makeController()
      ..setAiSettings(
        const AiSettings(baseUrl: 'http://x/v1', apiKey: 'k', model: 'm'),
      );
    await tester.pumpWidget(
      VeriFinScope(
        controller: controller,
        child: zhMaterialApp(
          home: AiChatPage(
            debugTransport: (messages, tools) async* {
              throw AiException(
                AiErrorCode.network,
                detail: 'HttpException: secret upstream detail',
              );
            },
            debugCompleteTransport: (messages, tools) async {
              throw AiException(
                AiErrorCode.network,
                detail: 'HttpException: secret upstream detail',
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '帮我查一下');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.pump();
    await _pumpAsync(tester);

    expect(find.text('无法连接到服务器'), findsOneWidget);
    expect(find.text('重新回答'), findsOneWidget);
    expect(find.textContaining('HttpException'), findsNothing);
    expect(find.textContaining('secret upstream'), findsNothing);
    controller.dispose();
  });

  testWidgets('流式期间发送按钮切换为停止并保留部分正文', (tester) async {
    final controller = await makeController()
      ..setAiSettings(
        const AiSettings(baseUrl: 'http://x/v1', apiKey: 'k', model: 'm'),
      );
    addTearDown(controller.dispose);
    final stream = StreamController<AiCompletionEvent>();

    await tester.pumpWidget(
      VeriFinScope(
        controller: controller,
        child: zhMaterialApp(
          home: AiChatPage(debugTransport: (messages, tools) => stream.stream),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '慢慢回答');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.pump();

    expect(find.byIcon(Icons.stop_rounded), findsOneWidget);
    stream.add(const AiContentDelta('已经收到的正文'));
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text('已经收到的正文'), findsOneWidget);
    expect(find.byType(GptMarkdown), findsNothing);

    await tester.tap(find.byIcon(Icons.stop_rounded));
    await tester.pump();

    expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
    expect(find.byIcon(Icons.stop_rounded), findsNothing);
    expect(find.text('已经收到的正文'), findsOneWidget);
    expect(find.byType(GptMarkdown), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    unawaited(stream.close());
  });

  testWidgets('降级重试最终失败时不会显示重试完成', (tester) async {
    final controller = await makeController()
      ..setAiSettings(
        const AiSettings(baseUrl: 'http://x/v1', apiKey: 'k', model: 'm'),
      );
    addTearDown(controller.dispose);
    var calls = 0;

    await tester.pumpWidget(
      VeriFinScope(
        controller: controller,
        child: zhMaterialApp(
          home: AiChatPage(
            debugTransport: (messages, tools) async* {
              calls += 1;
              throw AiException(
                calls == 1
                    ? AiErrorCode.protocolUnsupported
                    : AiErrorCode.network,
              );
            },
            debugCompleteTransport: (messages, tools) async {
              throw AiException(AiErrorCode.network);
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '触发降级');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.pump();
    await _pumpRealAsyncFrames(tester);

    expect(find.text('完成'), findsNothing);
    expect(find.text('失败'), findsWidgets);
    expect(find.text('无法连接到服务器'), findsOneWidget);
  });

  testWidgets('离开并重开页面后不恢复旧对话', (tester) async {
    final controller = await makeController()
      ..setAiSettings(
        const AiSettings(baseUrl: 'http://x/v1', apiKey: 'k', model: 'm'),
      );
    final transport = _scripted(<List<AiCompletionEvent>>[
      _answer('这次回答只在当前页面保留'),
    ]);

    await tester.pumpWidget(
      VeriFinScope(
        controller: controller,
        child: zhMaterialApp(home: AiChatPage(debugTransport: transport)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '分类排行');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.pump();
    await _pumpAsync(tester);
    expect(find.text('这次回答只在当前页面保留'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      VeriFinScope(
        controller: controller,
        child: zhMaterialApp(home: AiChatPage(debugTransport: transport)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('分类排行'), findsNothing);
    expect(find.text('这次回答只在当前页面保留'), findsNothing);
    addTearDown(controller.dispose);
  });

  testWidgets('Markdown 远程图片不会触发网络加载', (tester) async {
    final controller = await makeController()
      ..setAiSettings(
        const AiSettings(baseUrl: 'http://x/v1', apiKey: 'k', model: 'm'),
      );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      VeriFinScope(
        controller: controller,
        child: zhMaterialApp(
          home: AiChatPage(
            debugTransport: _scripted(<List<AiCompletionEvent>>[
              _answer('![remote](https://example.com/tracker.png)'),
            ]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '看看图片');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.pump();
    await _pumpAsync(tester);

    expect(find.text('出于隐私考虑，未加载图片'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Image && widget.image is NetworkImage,
      ),
      findsNothing,
    );
  });
}
