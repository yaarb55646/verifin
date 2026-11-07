import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:verifin/app/backup/payment_import.dart';
import 'package:verifin/app/models.dart';
import 'package:verifin/local_storage/local_storage.dart';

import 'support/test_harness.dart';

void main() {
  useTestDatabases();

  test('随手记预览不写分类，确认导入复用分类并保留关键词', () async {
    final store = LocalKeyValueStore();
    final controller = await makeController(store);
    addTearDown(controller.dispose);
    final dining = controller.categories.firstWhere((c) => c.label == '餐饮');
    controller.addCategory(
      type: EntryType.expense,
      label: '午餐',
      iconCode: 'category',
      parentId: dining.id,
    );
    final lunch = controller.categories.firstWhere((c) => c.label == '午餐');
    expect(await controller.saveCategoryKeywords(lunch.id, ['工作餐']), isTrue);
    // 备份信封含生成时间，只比较权威数据载荷。
    Object? snapshot() =>
        (jsonDecode(controller.exportDataJson())
            as Map<String, dynamic>)['data'];
    final before = snapshot();
    final plan = controller.parsePlatformImport(
      ImportPlatform.suishouji,
      File('test/fixtures/suishouji_sample.xlsx').readAsBytesSync(),
    );
    expect(plan.errorCount, 0);
    expect(plan.entries.any((e) => e.categoryId == lunch.id), isTrue);
    expect(plan.newCategories.any((c) => c.id == lunch.id), isFalse);
    expect(plan.newCategories.every((c) => c.keywords.isEmpty), isTrue);
    // 预览后取消即丢弃计划；仅解析不能修改现有账目或关键词。
    expect(snapshot(), before);
    expect(
      await controller.applyImportEntries(
        entries: plan.entries,
        candidateAccounts: plan.newAccounts,
        candidateCategories: plan.newCategories,
      ),
      isTrue,
    );
    expect(controller.categoryById(lunch.id).keywords, ['工作餐']);
    final reloaded = await makeController(store);
    addTearDown(reloaded.dispose);
    expect(reloaded.categoryById(lunch.id).keywords, ['工作餐']);
    expect(reloaded.entries, hasLength(plan.entries.length));
  });
}
