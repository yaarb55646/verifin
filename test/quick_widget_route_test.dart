import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verifin/app/platform_bridge.dart';
import 'package:verifin/app/veri_fin_scope.dart';
import 'package:verifin/pages/shell.dart';
import 'support/test_harness.dart';

void main() {
  useTestDatabases();
  testWidgets('数字区域打开首页；加号打开键盘；再次点数字关闭旧键盘', (tester) async {
    final controller = await makeController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      VeriFinScope(
        controller: controller,
        child: zhMaterialApp(home: const VeriFinShell()),
      ),
    );
    await tester.pumpAndSettle();
    await AppWidgetBridge.handleRoute({'route': 'app'});
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('number_pad_ok')), findsNothing);
    // entry 路由会依次弹「一句话记账」输入层与数字键盘；两者都关闭后该路由才完成。
    final entry = AppWidgetBridge.handleRoute({'route': 'entry'});
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('quick_text_entry_number_pad')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('quick_text_entry_number_pad')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('number_pad_ok')), findsOneWidget);
    await AppWidgetBridge.handleRoute({'route': 'app'});
    await tester.pumpAndSettle();
    await entry;
    expect(find.byKey(const Key('number_pad_ok')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
