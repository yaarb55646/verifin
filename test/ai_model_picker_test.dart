import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verifin/app/ai/ai_model_catalog.dart';
import 'package:verifin/app/veri_fin_scope.dart';
import 'package:verifin/pages/sheets.dart';

import 'support/test_harness.dart';

void main() {
  useTestDatabases();

  testWidgets('模型弹层按厂商分组、支持搜索与选择', (tester) async {
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
                  selected = await showAiModelSelectionSheet(
                    context: context,
                    selectedModel: 'model-a',
                    models: const <AiModelInfo>[
                      AiModelInfo(id: 'model-a', ownedBy: 'Vendor A'),
                      AiModelInfo(id: 'model-b', ownedBy: 'Vendor B'),
                      AiModelInfo(id: 'other-model'),
                    ],
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
    expect(find.text('选择模型'), findsOneWidget);
    expect(find.text('Vendor A'), findsWidgets);
    expect(find.text('Vendor B'), findsWidgets);
    expect(find.text('其他'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('ai_model_search_field')),
      'model-b',
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ai_model_option_model-b')), findsOneWidget);
    expect(find.text('model-a'), findsNothing);

    await tester.tap(find.byKey(const Key('ai_model_option_model-b')));
    await tester.pumpAndSettle();
    expect(selected, 'model-b');
  });
}
