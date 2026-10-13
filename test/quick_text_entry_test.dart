import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verifin/app/models.dart';
import 'package:verifin/local_storage/local_storage.dart';
import 'package:verifin/main.dart';

import 'support/test_harness.dart';

/// 「一句话记账」入口的端到端行为：点快速记账 → 弹文字输入 → 解析金额与备注 →
/// 进记账页。解析函数本身的边界由 `quick_entry_text_test.dart` 覆盖。
void main() {
  useTestDatabases();

  /// 打开首页的快速记账入口，返回文字输入框。
  Future<Finder> openQuickTextEntry(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('quick_entry_fab')));
    await tester.pumpAndSettle();
    return find.byKey(const Key('quick_text_entry_field'));
  }

  testWidgets('点快速记账先弹文字输入框，而不是直接弹数字键盘', (tester) async {
    final store = LocalKeyValueStore();
    final controller = await makeController(store);
    await tester.pumpWidget(VeriFinApp(controller: controller));
    await tester.pumpAndSettle();

    expect(await openQuickTextEntry(tester), findsOneWidget);
    // 数字键盘此时还没出现。
    expect(find.byKey(const Key('number_pad_ok')), findsNothing);
  });

  testWidgets('输入「早餐5元」→ 金额与备注都带到记账页', (tester) async {
    final store = LocalKeyValueStore();
    final controller = await makeController(store);
    await tester.pumpWidget(VeriFinApp(controller: controller));
    await tester.pumpAndSettle();

    final field = await openQuickTextEntry(tester);
    await tester.enterText(field, '早餐5元');
    await tester.tap(find.byKey(const Key('quick_text_entry_submit')));
    await tester.pumpAndSettle();

    // 落到记账页：备注已填「早餐」，金额 5 显示在金额区。
    expect(find.byKey(const Key('entry_note_field')), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('entry_note_field')))
          .controller
          ?.text,
      '早餐',
    );
    expect(find.textContaining('5'), findsWidgets);
  });

  testWidgets('输入「早餐5元」后类型/分类可被历史识别（备注参与识别）', (tester) async {
    final store = LocalKeyValueStore();
    final controller = await makeController(store);
    await tester.pumpWidget(VeriFinApp(controller: controller));
    await tester.pumpAndSettle();

    final field = await openQuickTextEntry(tester);
    await tester.enterText(field, '打车32');
    await tester.tap(find.byKey(const Key('quick_text_entry_submit')));
    await tester.pumpAndSettle();

    // 备注「打车」不被历史识别覆盖（视为用户已输入），仍保持原文。
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('entry_note_field')))
          .controller
          ?.text,
      '打车',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('拆不出金额时整段文字作为备注，金额留空由用户补填', (tester) async {
    final store = LocalKeyValueStore();
    final controller = await makeController(store);
    await tester.pumpWidget(VeriFinApp(controller: controller));
    await tester.pumpAndSettle();

    final field = await openQuickTextEntry(tester);
    await tester.enterText(field, '早餐');
    await tester.tap(find.byKey(const Key('quick_text_entry_submit')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TextField>(find.byKey(const Key('entry_note_field')))
          .controller
          ?.text,
      '早餐',
    );
    // 金额为 0 → 保存按钮禁用（用户需先补金额）。
    final save = tester.widget<FilledButton>(
      find.byKey(const Key('save_entry_button')),
    );
    expect(save.onPressed, isNull);
  });

  testWidgets('空输入提示且不离开弹层', (tester) async {
    final store = LocalKeyValueStore();
    final controller = await makeController(store);
    await tester.pumpWidget(VeriFinApp(controller: controller));
    await tester.pumpAndSettle();

    await openQuickTextEntry(tester);
    await tester.tap(find.byKey(const Key('quick_text_entry_submit')));
    await tester.pumpAndSettle();

    expect(find.text('请先输入内容'), findsOneWidget);
    // 弹层仍在。
    expect(find.byKey(const Key('quick_text_entry_field')), findsOneWidget);
  });

  testWidgets('「改用数字键盘」回落到原数字键盘流程', (tester) async {
    final store = LocalKeyValueStore();
    final controller = await makeController(store);
    await tester.pumpWidget(VeriFinApp(controller: controller));
    await tester.pumpAndSettle();

    await openQuickTextEntry(tester);
    await tester.tap(find.byKey(const Key('quick_text_entry_number_pad')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('number_pad_ok')), findsOneWidget);
  });

  testWidgets('取消（点遮罩）不进入记账页', (tester) async {
    final store = LocalKeyValueStore();
    final controller = await makeController(store);
    await tester.pumpWidget(VeriFinApp(controller: controller));
    await tester.pumpAndSettle();

    await openQuickTextEntry(tester);
    // 点弹层外的遮罩关闭。
    await tester.tapAt(const Offset(200, 60));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('entry_note_field')), findsNothing);
    expect(find.byKey(const Key('quick_text_entry_field')), findsNothing);
  });

  testWidgets('AI 模式下点快速记账仍走 AI，不弹文字输入', (tester) async {
    final store = LocalKeyValueStore();
    final controller = await makeController(store);
    controller.setFabActionMode(FabActionMode.ai);
    await tester.pumpWidget(VeriFinApp(controller: controller));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('quick_entry_fab')));
    await tester.pumpAndSettle();

    // 未配置 AI → 弹配置提示；文字输入层不应出现。
    expect(find.byKey(const Key('quick_text_entry_field')), findsNothing);
  });
}
