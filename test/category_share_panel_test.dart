import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verifin/app/app_theme.dart';
import 'package:verifin/app/chart_painters.dart';
import 'package:verifin/app/common_widgets.dart';
import 'package:verifin/app/ledger_math.dart';
import 'package:verifin/app/models.dart';
import 'package:verifin/app/veri_fin_controller.dart';
import 'package:verifin/app/veri_fin_scope.dart';
import 'package:verifin/pages/category_share_panel.dart';
import 'package:verifin/pages/reports_page.dart';

import 'support/test_harness.dart';

void main() {
  useTestDatabases();

  Future<VeriFinController> seeded() async {
    final controller = await makeController();
    controller.addCategory(
      type: EntryType.expense,
      label: '早餐',
      iconCode: 'category',
      parentId: 'dining',
    );
    controller.addCategory(
      type: EntryType.expense,
      label: '午餐',
      iconCode: 'category',
      parentId: 'dining',
    );
    final breakfast = controller.categories
        .firstWhere((c) => c.label == '早餐')
        .id;
    final lunch = controller.categories.firstWhere((c) => c.label == '午餐').id;
    for (final (id, categoryId, amount, type) in [
      ('breakfast', breakfast, 20.0, EntryType.expense),
      ('lunch', lunch, 40.0, EntryType.expense),
      ('direct', 'dining', 25.0, EntryType.expense),
      ('traffic', 'transport', 15.0, EntryType.expense),
      ('income', 'salary', 500.0, EntryType.income),
    ]) {
      controller.addEntry(
        LedgerEntry(
          id: id,
          bookId: controller.activeBook.id,
          type: type,
          amount: amount,
          categoryId: categoryId,
          accountId: '',
          note: '',
          occurredAt: DateTime.now(),
        ),
      );
    }
    return controller;
  }

  Widget app(
    VeriFinController controller,
    Widget child, {
    Brightness brightness = Brightness.light,
  }) => VeriFinScope(
    controller: controller,
    child: zhMaterialApp(
      theme: buildVeriFinTheme(brightness),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );

  CategorySharePanel panel() => CategorySharePanel(
    window: DateWindow(
      start: addCalendarDays(dateOnly(DateTime.now()), -6),
      end: dateOnly(DateTime.now()),
    ),
    rangeLabel: '最近 7 天',
  );

  testWidgets('分类占比可拆分二级分类、显示金额、选择分段与切换收入', (tester) async {
    final controller = await seeded();
    await tester.pumpWidget(app(controller, panel()));
    await tester.pumpAndSettle();
    VeriDonutChart chart() => tester.widget<VeriDonutChart>(
      find.byKey(const Key('category_share_chart')),
    );
    expect(chart().segments.map((s) => s.value), [85, 15]);
    expect(find.text('85.0%'), findsOneWidget);
    expect(find.text('100'), findsOneWidget);
    await tester.tap(find.byKey(const Key('category_share_subcategories')));
    await tester.pumpAndSettle();
    expect(chart().segments.map((s) => s.value), [40, 25, 20, 15]);
    expect(find.text('餐饮 / 午餐'), findsOneWidget);
    expect(find.text('40.0%'), findsOneWidget);
    expect(find.text('40'), findsNothing);
    await tester.tap(find.byKey(const Key('category_share_show_amounts')));
    await tester.pumpAndSettle();
    expect(find.text('40'), findsOneWidget);
    chart().onSelected!(0);
    await tester.pumpAndSettle();
    expect(chart().selectedIndex, 0);
    expect(
      tester
          .widget<Text>(find.byKey(const Key('category_share_center_amount')))
          .data,
      '40',
    );
    await tester.tap(
      find
          .descendant(
            of: find.byType(VeriEntryTypeToggle),
            matching: find.text('收入'),
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(find.text('收入占比'), findsOneWidget);
    expect(chart().segments.single.value, 500);
    expect(chart().selectedIndex, isNull);
    expect(controller.entries, hasLength(5));
  });

  testWidgets('日常近7日、月统计当月、年统计当年分别过滤，日常排行复用', (tester) async {
    final controller = await seeded();
    final today = dateOnly(DateTime.now());
    void add(String id, DateTime date, double amount) => controller.addEntry(
      LedgerEntry(
        id: id,
        bookId: controller.activeBook.id,
        type: EntryType.expense,
        amount: amount,
        categoryId: 'dining',
        accountId: '',
        note: '',
        occurredAt: date,
      ),
    );
    add('boundary', addCalendarDays(today, -6), 7);
    add('outside-week', addCalendarDays(today, -7), 9);
    // 月初/年初运行时，这两条也必须在近 7 日之外。
    add('previous-month', DateTime(today.year, today.month - 1, 1), 11);
    add('previous-year', DateTime(today.year - 1, 1, 1), 13);
    for (final kind in [
      PanelPageKind.reportsDaily,
      PanelPageKind.reportsMonthly,
      PanelPageKind.reportsYearly,
    ]) {
      for (final spec in kind.specs) {
        if (spec.id != 'category_share' && spec.id != 'ranking') {
          controller.setPanelEnabled(kind, spec.id, false);
        }
      }
    }
    await tester.pumpWidget(
      VeriFinScope(
        controller: controller,
        child: zhMaterialApp(home: const Scaffold(body: ReportsPage())),
      ),
    );
    await tester.pumpAndSettle();
    double chartTotal() => tester
        .widget<VeriDonutChart>(find.byKey(const Key('category_share_chart')))
        .segments
        .fold<double>(0, (s, e) => s + e.value);
    expect(chartTotal(), 107);
    expect(find.text('分类 · 标签排行'), findsOneWidget);
    expect(find.text('最近 7 天'), findsNWidgets(2));
    await tester.tap(find.text('月统计').first);
    await tester.pumpAndSettle();
    final monthTotal =
        entriesInWindow(controller.entries, monthWindowFor(today))
            .where((e) => e.type == EntryType.expense)
            .fold<double>(0, (s, e) => s + e.netBaseAmount);
    expect(chartTotal(), monthTotal);
    await tester.tap(find.text('年统计').first);
    await tester.pumpAndSettle();
    final yearTotal = controller.entries
        .where(
          (e) => e.type == EntryType.expense && e.occurredAt.year == today.year,
        )
        .fold<double>(0, (s, e) => s + e.netBaseAmount);
    expect(chartTotal(), yearTotal);
  });

  for (final brightness in Brightness.values) {
    testWidgets('393×852 ${brightness.name} 有数据的圆环和勾选项无溢出', (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = await seeded();
      await tester.pumpWidget(app(controller, panel(), brightness: brightness));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('category_share_subcategories')),
      );
      await tester.tap(find.byKey(const Key('category_share_subcategories')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('category_share_show_amounts')),
      );
      await tester.tap(find.byKey(const Key('category_share_show_amounts')));
      await tester.pumpAndSettle();
      expect(find.text('餐饮 / 午餐'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
    testWidgets('360dp ${brightness.name} 空态和大字号无溢出', (tester) async {
      tester.view.physicalSize = const Size(360, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = await makeController();
      await tester.pumpWidget(
        app(
          controller,
          MediaQuery(
            data: const MediaQueryData(
              size: Size(360, 852),
              textScaler: TextScaler.linear(1.5),
            ),
            child: panel(),
          ),
          brightness: brightness,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('category_share_subcategories')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('category_share_show_amounts')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('category_share_chart')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
