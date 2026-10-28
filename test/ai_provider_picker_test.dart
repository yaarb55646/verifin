import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verifin/app/veri_fin_scope.dart';
import 'package:verifin/pages/sheets.dart';

import 'support/test_harness.dart';

void main() {
  useTestDatabases();

  testWidgets('渠道宫格支持分组、搜索与选择', (tester) async {
    final controller = await makeController();
    addTearDown(controller.dispose);
    String? selected;
    await tester.pumpWidget(
      VeriFinScope(
        controller: controller,
        child: zhMaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  selected = await showAiProviderSelectionSheet(
                    context: context,
                    selected: 'deepseek',
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('选择 AI 渠道'), findsOneWidget);
    expect(find.text('DeepSeek'), findsOneWidget);

    await tester.tap(find.byKey(const Key('ai_provider_group_local')));
    await tester.pumpAndSettle();
    expect(find.text('Ollama'), findsOneWidget);
    expect(find.text('DeepSeek'), findsNothing);

    await tester.tap(find.byKey(const Key('ai_provider_group_all')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('ai_provider_search_field')),
      '火山',
    );
    await tester.pumpAndSettle();
    expect(find.text('火山方舟'), findsOneWidget);
    expect(find.text('DeepSeek'), findsNothing);

    await tester.tap(
      find.byKey(const Key('ai_provider_search_result_volcengine-ark')),
    );
    await tester.pumpAndSettle();
    expect(selected, 'volcengine-ark');
  });

  testWidgets('渠道选择器在 360dp 和大字号下不溢出', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.4;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final controller = await makeController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      VeriFinScope(
        controller: controller,
        child: zhMaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showAiProviderSelectionSheet(
                  context: context,
                  selected: 'custom',
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
