import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:verifin/app/models.dart';
import 'package:verifin/local_storage/local_storage.dart';

import 'support/test_harness.dart';

void main() {
  useTestDatabases();

  for (final restoreBackup in [false, true]) {
    for (final hasCurrent in [false, true]) {
      test('月度旧面板兼容：备份=$restoreBackup，新旧共存=$hasCurrent', () async {
        final stored = <Map<String, Object>>[
          {'id': 'ranking', 'enabled': true},
          {'id': 'category_share', 'enabled': false},
          {'id': 'summary', 'enabled': false},
          if (hasCurrent) {'id': 'category_stats', 'enabled': true},
          {'id': 'budget_execution', 'enabled': false},
          {'id': 'daily_trend', 'enabled': false},
        ];
        final store = LocalKeyValueStore();
        if (!restoreBackup) {
          store.write('verifin.report_panels.v1', jsonEncode(stored));
        }
        final controller = await makeController(store);
        addTearDown(controller.dispose);
        if (restoreBackup) {
          final backup =
              jsonDecode(controller.exportDataJson()) as Map<String, dynamic>;
          final data = backup['data'] as Map<String, dynamic>;
          data['reportPanels'] = stored;
          await controller.importDataJson(jsonEncode(backup));
        }
        final expectedIds = hasCurrent
            ? [
                'ranking',
                'summary',
                'category_stats',
                'budget_execution',
                'daily_trend',
              ]
            : [
                'ranking',
                'category_stats',
                'summary',
                'budget_execution',
                'daily_trend',
              ];
        void verify(List<PagePanelSetting> panels) {
          expect(panels.map((p) => p.id), expectedIds);
          expect(
            panels.singleWhere((p) => p.id == 'category_stats').enabled,
            hasCurrent,
          );
        }

        verify(controller.panelSettings(PanelPageKind.reportsMonthly));
        for (final kind in [
          PanelPageKind.reportsDaily,
          PanelPageKind.reportsYearly,
        ]) {
          expect(controller.enabledPanelIds(kind), contains('category_share'));
          expect(
            controller.enabledPanelIds(kind),
            isNot(contains('category_stats')),
          );
        }
        final exported = controller.exportDataJson();
        final exportedData =
            (jsonDecode(exported) as Map<String, dynamic>)['data']
                as Map<String, dynamic>;
        expect(
          (exportedData['reportPanels'] as List).map((p) => (p as Map)['id']),
          expectedIds,
        );
        final reloaded = await makeController(store);
        addTearDown(reloaded.dispose);
        verify(reloaded.panelSettings(PanelPageKind.reportsMonthly));
        final restored = await makeController();
        addTearDown(restored.dispose);
        await restored.importDataJson(exported);
        verify(restored.panelSettings(PanelPageKind.reportsMonthly));
      });
    }
  }
}
