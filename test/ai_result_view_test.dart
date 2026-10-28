import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verifin/app/ai/ai_query_tool.dart';
import 'package:verifin/app/chart_painters.dart';
import 'package:verifin/app/models.dart';
import 'package:verifin/app/veri_fin_scope.dart';
import 'package:verifin/pages/ai_result_view.dart';

import 'support/test_harness.dart';

void main() {
  useTestDatabases();

  testWidgets('排行图纵轴 0 在底部、最大值在顶部', (tester) async {
    final controller = await makeController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      VeriFinScope(
        controller: controller,
        child: zhMaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AiResultView(
                display: const AiRankingDisplay(
                  title: '分类排行',
                  isExpense: true,
                  rows: <AiRankingRow>[
                    AiRankingRow(
                      label: '餐饮',
                      amount: 100,
                      percent: 1,
                      count: 2,
                    ),
                  ],
                ),
                baseCurrencyCode: controller.activeBook.baseCurrencyCode,
                moneyCodeDisplay: MoneyCodeDisplay.none,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final chart = find.byType(InteractiveBarChart);
    final zero = tester.getCenter(
      find.descendant(of: chart, matching: find.text('0')),
    );
    final mid = tester.getCenter(
      find.descendant(of: chart, matching: find.text('50')),
    );
    final max = tester.getCenter(
      find.descendant(of: chart, matching: find.text('100')),
    );
    expect(zero.dy, greaterThan(mid.dy));
    expect(mid.dy, greaterThan(max.dy));
  });
}
