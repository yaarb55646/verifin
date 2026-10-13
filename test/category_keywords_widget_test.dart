import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verifin/app/models.dart';
import 'package:verifin/app/ai/ai_entry_parser.dart';
import 'package:verifin/app/veri_fin_scope.dart';
import 'package:verifin/l10n/app_localizations.dart';
import 'package:verifin/main.dart';
import 'package:verifin/pages/category_management_page.dart';
import 'package:verifin/pages/entry_detail_page.dart';
import 'package:verifin/pages/sheets.dart';

import 'support/test_harness.dart';

void main() {
  useTestDatabases();

  testWidgets('分类管理编辑菜单可新增与删除关键词并显示数量', (tester) async {
    final controller = await makeController();
    await tester.pumpWidget(
      VeriFinScope(
        controller: controller,
        child: zhMaterialApp(home: const CategoryManagementPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('餐饮'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('记账关键词').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('category_keyword_field')),
      '包子',
    );
    await tester.tap(find.byKey(const Key('category_keyword_add')));
    await tester.pumpAndSettle();
    expect(find.byType(InputChip), findsOneWidget);
    expect(controller.categoryById('dining').keywords, isEmpty);
    await tester.tap(find.byKey(const Key('category_keywords_save')));
    await tester.pumpAndSettle();
    expect(controller.categoryById('dining').keywords, ['包子']);
    expect(find.text('1 个关键词'), findsOneWidget);
    await tester.tap(find.byTooltip('餐饮'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('记账关键词').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('category_keywords_save')));
    await tester.pumpAndSettle();
    expect(controller.categoryById('dining').keywords, isEmpty);
  });

  testWidgets('编辑关键词冲突内联反馈，取消无写入', (tester) async {
    final controller = await makeController();
    await controller.saveCategoryKeywords('transport', ['包子']);
    await tester.pumpWidget(
      VeriFinScope(
        controller: controller,
        child: zhMaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showCategoryKeywordsSheet(
                  context: context,
                  categoryId: 'dining',
                ),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('category_keyword_field')),
      '包子',
    );
    await tester.tap(find.byKey(const Key('category_keywords_save')));
    await tester.pumpAndSettle();
    expect(find.text('“包子”已关联到“交通”'), findsOneWidget);
    expect(controller.categoryById('dining').keywords, isEmpty);
    await tester.enterText(
      find.byKey(const Key('category_keyword_field')),
      '豆浆',
    );
    await tester.tap(find.byKey(const Key('category_keyword_add')));
    await tester.pumpAndSettle();
    final sheetContext = tester.element(
      find.byKey(const Key('category_keywords_save')),
    );
    Navigator.of(sheetContext).pop();
    await tester.pumpAndSettle();
    expect(controller.categoryById('dining').keywords, isEmpty);
  });

  testWidgets('确认页辅助绑定不保存账目，下次包子3元自动预选并确认后落账', (tester) async {
    final controller = await makeController();
    controller.addAccount(
      Account(
        id: 'cash',
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
    await tester.pumpWidget(VeriFinApp(controller: controller));
    await tester.pumpAndSettle();
    Future<void> open() async {
      await tester.tap(find.byKey(const Key('quick_entry_fab')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('quick_text_entry_field')),
        '包子3元',
      );
      await tester.tap(find.byKey(const Key('quick_text_entry_submit')));
      await tester.pumpAndSettle();
    }

    await open();
    await tester.tap(find.byKey(const Key('entry_category_dining')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('entry_link_category_keyword')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('entry_link_category_keyword')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('category_keyword_field')))
          .controller!
          .text,
      '包子',
    );
    await tester.tap(find.byKey(const Key('category_keywords_save')));
    await tester.pumpAndSettle();
    expect(controller.categoryById('dining').keywords, ['包子']);
    expect(controller.entries, isEmpty);
    await tester.tap(find.byKey(const Key('save_entry_button')));
    await tester.pumpAndSettle();
    expect(controller.entries.single.categoryId, 'dining');
    expect(controller.entries.single.amount, 3);
    await open();
    expect(
      find.byKey(const Key('entry_category_selected_dining')),
      findsWidgets,
    );
    expect(controller.entries, hasLength(1));
    await tester.tap(find.byKey(const Key('save_entry_button')));
    await tester.pumpAndSettle();
    expect(controller.entries, hasLength(2));
    expect(
      controller.entries.every(
        (e) => e.categoryId == 'dining' && e.amount == 3,
      ),
      isTrue,
    );
  });

  testWidgets('已有关键词无历史自动预选且手动选择受尊重', (tester) async {
    final controller = await makeController();
    await controller.saveCategoryKeywords('transport', ['包子']);
    await tester.pumpWidget(
      VeriFinScope(
        controller: controller,
        child: zhMaterialApp(
          home: const EntryDetailPage(initialAmount: 3, initialNote: '包子'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('entry_category_selected_transport')),
      findsWidgets,
    );
    await tester.tap(find.byKey(const Key('entry_category_dining')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('entry_note_field')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(find.byKey(const Key('entry_note_field')), '买包子');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    // 滚回分类区检查用户选择没有被关键词覆盖。
    await tester.scrollUntilVisible(
      find.byKey(const Key('entry_category_selected_dining')),
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.byKey(const Key('entry_category_selected_dining')),
      findsWidgets,
    );
  });

  testWidgets('关闭自动识别时不应用关键词，AI 和导入草稿没有关联入口', (tester) async {
    final controller = await makeController();
    await controller.saveCategoryKeywords('transport', ['包子']);
    controller.setAutoSuggestEnabled(false);
    await tester.pumpWidget(
      VeriFinScope(
        controller: controller,
        child: zhMaterialApp(
          home: const EntryDetailPage(initialAmount: 3, initialNote: '包子'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('entry_category_selected_transport')),
      findsNothing,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    controller.setAutoSuggestEnabled(true);
    await tester.pumpWidget(
      VeriFinScope(
        controller: controller,
        child: zhMaterialApp(
          home: EntryDetailPage.draft(
            entry: LedgerEntry(
              id: 'draft',
              bookId: controller.activeBook.id,
              type: EntryType.expense,
              amount: 3,
              categoryId: 'dining',
              accountId: '',
              note: '包子',
              occurredAt: DateTime.now(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('entry_note_field')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('entry_link_category_keyword')), findsNothing);
    expect(controller.entries, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      VeriFinScope(
        controller: controller,
        child: zhMaterialApp(
          home: EntryDetailPage(
            initialAmount: 3,
            initialDraft: AiEntryDraft(
              type: EntryType.expense,
              amount: 3,
              currencyCode: 'CNY',
              categoryId: 'dining',
              accountId: '',
              toAccountId: null,
              note: '包子',
              occurredAt: DateTime.now(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('entry_category_selected_transport')),
      findsNothing,
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('entry_note_field')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('entry_link_category_keyword')), findsNothing);
  });

  testWidgets('360dp 大字号关键词弹层可滚动，长关键词不溢出', (tester) async {
    tester.view.physicalSize = const Size(360, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = await makeController();
    await controller.saveCategoryKeywords('dining', [
      '这是一条很长很长的常用食品关键词用于检查窄屏布局',
    ]);
    await tester.pumpWidget(
      VeriFinScope(
        controller: controller,
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showCategoryKeywordsSheet(
                  context: context,
                  categoryId: 'dining',
                ),
                child: const Text('打开'),
              ),
            ),
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byKey(const Key('category_keywords_save')));
    await tester.tap(find.byKey(const Key('category_keywords_save')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
