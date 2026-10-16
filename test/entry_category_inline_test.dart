import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verifin/app/entry_sheets.dart';
import 'package:verifin/app/icon_catalog.dart';
import 'package:verifin/app/models.dart';
import 'package:verifin/app/entry_subcategory_panel.dart';
import 'package:verifin/app/veri_fin_controller.dart';
import 'package:verifin/app/veri_fin_scope.dart';
import 'package:verifin/pages/entry_detail_page.dart';
import 'package:verifin/pages/sheets.dart';

import 'support/test_harness.dart';

/// 覆盖记账页三列分类胶囊和现有多级分类选择器的组合交互。
void main() {
  useTestDatabases();

  String idOfLabel(VeriFinController controller, String label) {
    return controller.categories.firstWhere((c) => c.label == label).id;
  }

  /// 造一个带「餐饮 → 午餐 → 工作午餐」层级的控制器。
  Future<VeriFinController> controllerWithSubcategories() async {
    final controller = await makeController();
    final diningId = idOfLabel(controller, '餐饮');
    controller
      ..addCategory(
        type: EntryType.expense,
        label: '早餐',
        iconCode: 'dining',
        parentId: diningId,
      )
      ..addCategory(
        type: EntryType.expense,
        label: '午餐',
        iconCode: 'dining',
        parentId: diningId,
      );
    final lunchId = idOfLabel(controller, '午餐');
    controller.addCategory(
      type: EntryType.expense,
      label: '工作午餐',
      iconCode: 'dining',
      parentId: lunchId,
    );
    return controller;
  }

  Future<void> pumpPage(
    WidgetTester tester,
    VeriFinController controller,
    Widget page,
  ) async {
    await tester.pumpWidget(
      VeriFinScope(
        controller: controller,
        child: zhMaterialApp(home: page),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('分类使用三列紧凑胶囊，子分类在下方面板常驻', (tester) async {
    final controller = await controllerWithSubcategories();
    await pumpPage(
      tester,
      controller,
      const EntryDetailPage(initialAmount: 30),
    );

    expect(find.byKey(const Key('entry_category_grid')), findsOneWidget);
    // 默认选中第一个顶级分类（餐饮），下方面板常驻它的子分类。
    expect(find.byKey(const Key('entry_subcategory_panel')), findsOneWidget);
    expect(find.text('早餐'), findsOneWidget);
    expect(find.text('午餐'), findsOneWidget);
    expect(find.byKey(const Key('entry_category_more_dining')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('entry_category_dining'))).height,
      closeTo(31, 2),
    );
  });

  testWidgets('省略号打开现有多级选择器并回填三级分类', (tester) async {
    final controller = await controllerWithSubcategories();
    await pumpPage(
      tester,
      controller,
      const EntryDetailPage(initialAmount: 30),
    );

    await tester.tap(find.byKey(const Key('entry_category_more_dining')));
    await tester.pumpAndSettle();
    expect(find.byType(CategoryPickerSheet), findsOneWidget);
    expect(find.text('工作午餐'), findsOneWidget);

    final workLunch = find.text('工作午餐');
    await tester.ensureVisible(workLunch);
    await tester.pumpAndSettle();
    await tester.tap(workLunch);
    await tester.pumpAndSettle();

    expect(find.byType(CategoryPickerSheet), findsNothing);
    // 选中三级分类后，顶级胶囊仍显示叶子名称（下方面板不展示三级）。
    expect(find.text('工作午餐'), findsOneWidget);
    expect(find.byKey(const Key('entry_category_more_dining')), findsOneWidget);
  });

  testWidgets('编辑子分类交易时在顶级胶囊中显示叶子名称', (tester) async {
    final controller = await controllerWithSubcategories();
    final lunchId = idOfLabel(controller, '午餐');
    final entry = LedgerEntry(
      id: 'e1',
      bookId: controller.activeBook.id,
      type: EntryType.expense,
      amount: 30,
      categoryId: lunchId,
      accountId: '',
      note: '',
      occurredAt: DateTime(2026, 7, 12, 12, 0),
    );

    await pumpPage(tester, controller, EntryDetailPage.draft(entry: entry));

    expect(find.byType(CategoryPickerSheet), findsNothing);
    // 顶部胶囊显示叶子名称「午餐」，下方面板里它作为子分类格子也被高亮。
    expect(find.text('午餐'), findsNWidgets(2));
    expect(find.byKey(const Key('entry_category_more_dining')), findsOneWidget);
  });

  testWidgets('点子分类格子直接选中，无需再弹选择器', (tester) async {
    final controller = await controllerWithSubcategories();
    await pumpPage(
      tester,
      controller,
      const EntryDetailPage(initialAmount: 30),
    );

    // 子分类格子的 key 带随机 id，用文字定位。
    await tester.tap(find.text('早餐'));
    await tester.pumpAndSettle();

    // 不弹选择器，直接选中；顶级胶囊显示叶子名。
    expect(find.byType(CategoryPickerSheet), findsNothing);
    expect(find.text('早餐'), findsNWidgets(2));
  });

  testWidgets('切换父分类时子分类面板跟着换内容', (tester) async {
    final controller = await controllerWithSubcategories();
    final transportId = idOfLabel(controller, '交通');
    controller.addCategory(
      type: EntryType.expense,
      label: '地铁',
      iconCode: 'transport',
      parentId: transportId,
    );
    await pumpPage(
      tester,
      controller,
      const EntryDetailPage(initialAmount: 30),
    );

    // 初始：餐饮的子分类。
    expect(find.text('早餐'), findsOneWidget);
    expect(find.text('地铁'), findsNothing);

    await tester.tap(find.byKey(const Key('entry_category_transport')));
    await tester.pumpAndSettle();

    // 切到交通：面板换成交通的子分类。
    expect(find.text('地铁'), findsOneWidget);
    expect(find.text('早餐'), findsNothing);
  });

  testWidgets('面板末尾有「新增」入口', (tester) async {
    final controller = await controllerWithSubcategories();
    await pumpPage(
      tester,
      controller,
      const EntryDetailPage(initialAmount: 30),
    );

    expect(find.byKey(const Key('entry_subcategory_add')), findsOneWidget);
  });

  testWidgets('子分类面板按实际可用宽度在一行显示五格', (tester) async {
    final controller = await controllerWithSubcategories();
    final diningId = idOfLabel(controller, '餐饮');
    for (final label in <String>['晚餐', '零食', '夜宵']) {
      controller.addCategory(
        type: EntryType.expense,
        label: label,
        iconCode: 'dining',
        parentId: diningId,
      );
    }
    await pumpPage(
      tester,
      controller,
      const EntryDetailPage(initialAmount: 30),
    );

    final children = controller.childCategories(diningId);
    expect(children, hasLength(5));
    final firstRect = tester.getRect(
      find.byKey(Key('entry_subcategory_${children.first.id}')),
    );
    final fifthRect = tester.getRect(
      find.byKey(Key('entry_subcategory_${children[4].id}')),
    );
    final addRect = tester.getRect(
      find.byKey(const Key('entry_subcategory_add')),
    );
    expect(fifthRect.top, closeTo(firstRect.top, 0.1));
    expect(addRect.top, greaterThan(firstRect.top));
  });

  testWidgets('新增子分类时可选择图标', (tester) async {
    final controller = await controllerWithSubcategories();
    final diningId = idOfLabel(controller, '餐饮');
    await pumpPage(
      tester,
      controller,
      const EntryDetailPage(initialAmount: 30),
    );

    await tester.tap(find.byKey(const Key('entry_subcategory_add')));
    await tester.pumpAndSettle();
    final dialog = find.byType(AlertDialog);
    await tester.enterText(
      find.descendant(of: dialog, matching: find.byType(TextField)),
      '晚餐',
    );
    await tester.tap(find.descendant(of: dialog, matching: find.text('确认')));
    await tester.pumpAndSettle();

    final emoji = categoryEmojiChoices.first;
    await tester.ensureVisible(find.text(emoji));
    await tester.tap(find.text(emoji));
    await tester.pumpAndSettle();

    final created = controller.categories.singleWhere(
      (category) => category.parentId == diningId && category.label == '晚餐',
    );
    expect(created.iconCode, emojiIconCode(emoji));
    expect(
      tester
          .widget<EntrySubcategoryPanel>(find.byType(EntrySubcategoryPanel))
          .selectedId,
      created.id,
    );
  });
}
