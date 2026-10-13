import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verifin/app/models.dart';
import 'package:verifin/app/entry_subcategory_panel.dart';
import 'package:verifin/app/veri_fin_controller.dart';
import 'package:verifin/local_storage/local_storage.dart';
import 'package:verifin/main.dart';

import 'support/test_harness.dart';

/// 记账页是懒加载列表，备注框可能被挤到视口外而尚未构建。先滚动到备注框，
/// 再读/写它（与 `category_suggest_widget_test.dart` 同一约定）。
Future<void> _ensureNoteVisible(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.byKey(const Key('entry_note_field')),
    200,
    scrollable: find.byType(Scrollable).first,
  );
}

/// 打开首页的快速记账入口，返回文字输入框。
Future<Finder> openQuickTextEntry(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('quick_entry_fab')));
  await tester.pumpAndSettle();
  return find.byKey(const Key('quick_text_entry_field'));
}

/// 读备注框当前文本（先确保它已构建）。
Future<String?> noteText(WidgetTester tester) async {
  await _ensureNoteVisible(tester);
  return tester
      .widget<TextField>(find.byKey(const Key('entry_note_field')))
      .controller
      ?.text;
}

void main() {
  useTestDatabases();

  Category addLunch(VeriFinController controller) {
    final dining = controller.categories.firstWhere((c) => c.key == 'dining');
    controller.addCategory(
      type: EntryType.expense,
      label: '午餐',
      iconCode: 'category',
      parentId: dining.id,
    );
    return controller.categories.firstWhere(
      (c) => c.label == '午餐' && c.parentId == dining.id,
    );
  }

  Future<void> enterLunch(WidgetTester tester) async {
    await tester.enterText(
      find.byKey(const Key('quick_text_entry_field')),
      '午餐10.25元',
    );
    await tester.tap(find.byKey(const Key('quick_text_entry_submit')));
    await tester.pumpAndSettle();
  }

  testWidgets('新建午餐无历史即可识别，确认保存才写入真实子分类', (tester) async {
    final controller = await makeController();
    final lunch = addLunch(controller);
    controller.addAccount(
      Account(
        id: 'cash-lunch',
        bookId: controller.activeBook.id,
        name: '现金',
        type: AccountType.cash,
        groupId: null,
        initialBalance: 0,
        iconCode: 'cash',
        note: '',
        includeInAssets: true,
        hidden: false,
      ),
    );
    expect(controller.entries, isEmpty);
    await tester.pumpWidget(VeriFinApp(controller: controller));
    await tester.pumpAndSettle();
    await openQuickTextEntry(tester);
    await enterLunch(tester);
    expect(
      tester
          .widget<EntrySubcategoryPanel>(find.byType(EntrySubcategoryPanel))
          .selectedId,
      lunch.id,
    );
    expect(controller.entries, isEmpty);
    expect(await noteText(tester), '午餐');
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('save_entry_button')))
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.byKey(const Key('save_entry_button')));
    await tester.pumpAndSettle();
    expect(controller.entries, hasLength(1));
    final entry = controller.entries.single;
    expect(entry.type, EntryType.expense);
    expect(entry.categoryId, lunch.id);
    expect(entry.amount, 10.25);
    expect(entry.note, '午餐');
  });

  testWidgets('交易列表一句话入口同样识别午餐子分类', (tester) async {
    final controller = await makeController();
    final lunch = addLunch(controller);
    await tester.pumpWidget(VeriFinApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('最近交易'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('transactions_quick_entry_fab')));
    await tester.pumpAndSettle();
    await enterLunch(tester);
    expect(
      tester
          .widget<EntrySubcategoryPanel>(find.byType(EntrySubcategoryPanel))
          .selectedId,
      lunch.id,
    );
    expect(controller.entries, isEmpty);
  });

  testWidgets('明确分类名优先于同金额收入历史', (tester) async {
    final controller = await makeController();
    final lunch = addLunch(controller);
    final income = controller.categoriesForType(EntryType.income).first;
    controller.addEntry(
      LedgerEntry(
        id: 'history',
        bookId: controller.activeBook.id,
        type: EntryType.income,
        amount: 10.25,
        categoryId: income.id,
        accountId: '',
        note: '之前收入',
        occurredAt: DateTime(2026, 10, 12),
      ),
    );
    await tester.pumpWidget(VeriFinApp(controller: controller));
    await tester.pumpAndSettle();
    await openQuickTextEntry(tester);
    await enterLunch(tester);
    expect(
      find.byKey(const Key('entry_type_selected_expense')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<EntrySubcategoryPanel>(find.byType(EntrySubcategoryPanel))
          .selectedId,
      lunch.id,
    );
    expect(await noteText(tester), '午餐');
    expect(controller.entries, hasLength(1));
  });

  testWidgets('关闭自动识别不匹配，手动选分类不再被文字覆盖', (tester) async {
    final controller = await makeController();
    final lunch = addLunch(controller);
    controller.setAutoSuggestEnabled(false);
    await tester.pumpWidget(VeriFinApp(controller: controller));
    await tester.pumpAndSettle();
    await openQuickTextEntry(tester);
    await enterLunch(tester);
    expect(
      tester
          .widget<EntrySubcategoryPanel>(find.byType(EntrySubcategoryPanel))
          .selectedId,
      isNot(lunch.id),
    );
    controller.setAutoSuggestEnabled(true);
    await tester.pumpAndSettle();
    final transport = controller.categories.firstWhere(
      (c) => c.key == 'transport',
    );
    final chip = find.byKey(Key('entry_category_${transport.id}'));
    await tester.ensureVisible(chip);
    await tester.pumpAndSettle();
    await tester.tap(chip);
    await tester.pumpAndSettle();
    await _ensureNoteVisible(tester);
    await tester.enterText(find.byKey(const Key('entry_note_field')), '今天午餐');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<EntrySubcategoryPanel>(find.byType(EntrySubcategoryPanel))
          .selectedId,
      transport.id,
    );
    expect(controller.entries, isEmpty);
  });

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

    // 金额 5 已带入（支出方向显示带负号）。先断言金额：noteText() 会滚动到
    // 备注框，把金额区滚出视口，所以顺序不能反。
    expect(find.textContaining('5'), findsWidgets);
    // 落到记账页：备注已填「早餐」。
    expect(await noteText(tester), '早餐');
  });

  testWidgets('输入「打车32」后备注不被历史识别覆盖', (tester) async {
    final store = LocalKeyValueStore();
    final controller = await makeController(store);
    await tester.pumpWidget(VeriFinApp(controller: controller));
    await tester.pumpAndSettle();

    final field = await openQuickTextEntry(tester);
    await tester.enterText(field, '打车32');
    await tester.tap(find.byKey(const Key('quick_text_entry_submit')));
    await tester.pumpAndSettle();

    // 备注「打车」被视为用户已输入，不被历史识别覆盖，仍保持原文。
    expect(await noteText(tester), '打车');
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

    expect(await noteText(tester), '早餐');
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
