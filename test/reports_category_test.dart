import 'package:flutter_test/flutter_test.dart';
import 'package:verifin/app/models.dart';
import 'package:verifin/local_storage/local_storage.dart';

import 'support/test_harness.dart';

void main() {
  useTestDatabases();

  testWidgets('看板分类统计按层级聚合到顶级分类', (WidgetTester tester) async {
    final store = LocalKeyValueStore();
    final controller = await makeController(store);
    final now = DateTime.now();
    final diningId = controller.categories
        .firstWhere((c) => c.label == '餐饮')
        .id;
    controller.addCategory(
      type: EntryType.expense,
      label: '咖啡',
      iconCode: 'dining',
      parentId: diningId,
    );
    final coffeeId = controller.categories
        .firstWhere((c) => c.label == '咖啡')
        .id;
    controller
      ..addEntry(
        LedgerEntry(
          id: 'coffee-report',
          bookId: controller.activeBook.id,
          type: EntryType.expense,
          amount: 40,
          categoryId: coffeeId,
          accountId: 'cash-report',
          note: '拿铁',
          occurredAt: now,
        ),
      )
      ..dispose();

    await pumpApp(tester, store);
    await openReportsMonthlyTab(tester);
    await tester.pumpAndSettle();

    // 占比卡插入排行之前；按真实标题定位，不依赖卡片序号或首屏高度。
    await tester.scrollUntilVisible(
      find.text('分类 · 标签排行'),
      200,
      scrollable: firstVerticalScrollable(),
    );
    await tester.pumpAndSettle();

    // 咖啡（子分类）的支出滚动计入顶级「餐饮」，看板不单列子分类。
    expect(find.text('餐饮'), findsWidgets);
    expect(find.text('咖啡'), findsNothing);
  });

  testWidgets('看板排行卡的标签分组展示各标签支出', (WidgetTester tester) async {
    final store = LocalKeyValueStore();
    final controller = await makeController(store);
    final now = DateTime.now();
    final tagId = controller.addTag('必要')!;
    controller
      ..addEntry(
        LedgerEntry(
          id: 'tag-report',
          bookId: controller.activeBook.id,
          type: EntryType.expense,
          amount: 60,
          categoryId: 'dining',
          accountId: 'cash-report',
          note: '',
          occurredAt: now,
          tagIds: <String>[tagId],
        ),
      )
      ..dispose();

    await pumpApp(tester, store);
    await openReportsMonthlyTab(tester);
    await tester.pumpAndSettle();

    // 期间栏占了页面顶部一行，排行卡在 800dp 测试视口里落到首屏之外，
    // 先滚到卡片再操作它内部的分组切换。
    await tester.scrollUntilVisible(
      find.text('分类 · 标签排行'),
      250,
      scrollable: firstVerticalScrollable(),
    );
    await tester.pumpAndSettle();

    // 排行卡默认按顶级分类分组，切到「标签」分组。
    await tester.scrollUntilVisible(
      find.text('标签'),
      200,
      scrollable: firstVerticalScrollable(),
    );
    await tester.ensureVisible(find.text('标签').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('标签').first);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('必要'),
      250,
      scrollable: firstVerticalScrollable(),
    );
    await tester.pumpAndSettle();

    expect(find.text('分类 · 标签排行'), findsWidgets);
    expect(find.text('必要'), findsOneWidget);
    // 多标签会重复计入，占比之和可能超过 100%，卡片里必须带这条说明。
    expect(find.textContaining('超过 100%'), findsWidgets);
  });
}
