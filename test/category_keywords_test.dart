import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:verifin/app/category_suggest.dart';
import 'package:verifin/app/models.dart';
import 'package:verifin/local_storage/local_storage.dart';

import 'support/in_memory_ledger_repository.dart';
import 'support/test_harness.dart';

class _FailingCategoryRepository extends InMemoryLedgerRepository {
  bool fail = false;

  @override
  Future<void> saveCategories(List<Category> categories) async {
    if (fail) throw StateError('category write failed');
    await super.saveCategories(categories);
  }
}

void main() {
  useTestDatabases();

  const dining = Category(
    id: 'dining',
    bookId: 'book',
    label: '餐饮',
    type: EntryType.expense,
    iconCode: 'category',
    keywords: ['包子', '面', 'car'],
  );
  const lunch = Category(
    id: 'lunch',
    bookId: 'book',
    label: '午餐',
    type: EntryType.expense,
    iconCode: 'category',
    parentId: 'dining',
    keywords: ['牛肉面'],
  );
  Category? match(
    String note,
    List<Category> categories, {
    EntryType? forcedType,
  }) => suggestCategoryFromText(
    categories: categories,
    bookId: 'book',
    note: note,
    forcedType: forcedType,
  );

  test('自定义词无历史匹配，最长词优先，分类名和路径优先', () {
    expect(match('买包子', [dining, lunch])?.id, 'dining');
    expect(match('牛肉面', [dining, lunch])?.id, 'lunch');
    expect(match('午餐 包子', [dining, lunch])?.id, 'lunch');
    expect(match('餐饮/午餐 包子', [dining, lunch])?.id, 'lunch');
    expect(match('CARD', [dining]), isNull);
    expect(match('ＣＡＲ parking', [dining])?.id, 'dining');
  });

  test('跨账本、强制类型、系统分类与同等候选不误选', () {
    expect(match('包子', [dining.copyWith(bookId: 'other')]), isNull);
    expect(match('包子', [dining], forcedType: EntryType.income), isNull);
    expect(
      match('包子', [dining.copyWith(key: balanceAdjustExpenseKey)]),
      isNull,
    );
    expect(
      match('包子', [
        dining,
        lunch.copyWith(keywords: ['包子']),
      ]),
      isNull,
    );
    expect(
      match('豆浆 包子', [
        dining,
        lunch.copyWith(keywords: ['豆浆']),
      ]),
      isNull,
    );
  });

  test('关键词去重、冲突阻止保存，清空后可以重新绑定', () async {
    final controller = await makeController();
    expect(
      await controller.saveCategoryKeywords('dining', [
        ' 包子 ',
        '包子',
        'ＡＢＣ',
        'abc',
        '',
      ]),
      isTrue,
    );
    expect(controller.categoryById('dining').keywords, ['包子', 'ＡＢＣ']);
    expect(await controller.saveCategoryKeywords('transport', ['包子']), isFalse);
    expect(controller.categoryById('transport').keywords, isEmpty);
    expect(await controller.saveCategoryKeywords('dining', []), isTrue);
    expect(await controller.saveCategoryKeywords('transport', ['包子']), isTrue);
    expect(await controller.saveCategoryKeywords('missing', ['词']), isFalse);
    final system = controller.categories.firstWhere(
      (category) => category.isBalanceAdjust,
    );
    expect(await controller.saveCategoryKeywords(system.id, ['词']), isFalse);
    controller.dispose();
  });

  test('关键词重启与备份恢复、改名保留，旧备份缺字段默认空', () async {
    final store = LocalKeyValueStore();
    final controller = await makeController(store);
    await controller.saveCategoryKeywords('dining', ['包子']);
    await controller.renameCategory('dining', '吃饭');
    await controller.waitForPendingWrites();
    final reloaded = await makeController(store);
    expect(reloaded.categoryById('dining').keywords, ['包子']);
    final restored = await makeController();
    await restored.importDataJson(controller.exportDataJson());
    expect(restored.categories.firstWhere((c) => c.label == '吃饭').keywords, [
      '包子',
    ]);
    final oldJson = dining.toJson()..remove('keywords');
    expect(Category.fromJson(oldJson).keywords, isEmpty);
    controller.dispose();
    reloaded.dispose();
    restored.dispose();
  });

  test('新账本默认无规则，同词允许在不同账本绑定且整表保存不丢其它账本', () async {
    final controller = await makeController();
    final firstBook = controller.activeBook.id;
    await controller.saveCategoryKeywords('dining', ['包子']);
    controller.addLedgerBook('旅行');
    final secondBook = controller.activeBook.id;
    expect(
      controller.categories.every((category) => category.keywords.isEmpty),
      isTrue,
    );
    expect(await controller.saveCategoryKeywords('dining', ['豆浆']), isFalse);
    final otherDining = controller.categories.firstWhere(
      (c) => c.key == 'dining',
    );
    expect(
      await controller.saveCategoryKeywords(otherDining.id, ['包子']),
      isTrue,
    );
    controller.switchLedgerBook(firstBook);
    expect(controller.categoryById('dining').keywords, ['包子']);
    expect(
      controller
          .categoriesForBook(secondBook)
          .firstWhere((c) => c.key == 'dining')
          .keywords,
      ['包子'],
    );
    controller.dispose();
  });

  test('合并保留关键词、删除清除规则、重置回默认', () async {
    final controller = await makeController();
    await controller.saveCategoryKeywords('dining', ['包子']);
    await controller.saveCategoryKeywords('shopping', ['衣服']);
    expect(await controller.mergeCategoryInto('shopping', 'dining'), 0);
    expect(controller.categoryById('dining').keywords, ['包子', '衣服']);
    controller.addCategory(
      type: EntryType.expense,
      label: '临时',
      iconCode: 'category',
    );
    final temp = controller.categories.firstWhere((c) => c.label == '临时');
    await controller.saveCategoryKeywords(temp.id, ['临时词']);
    expect(await controller.deleteCategory(temp.id), isTrue);
    expect(await controller.saveCategoryKeywords('dining', ['临时词']), isTrue);
    await controller.resetAllData();
    expect(
      controller.categories.every((category) => category.keywords.isEmpty),
      isTrue,
    );
    controller.dispose();
  });

  test('保存失败不提交内存规则，错误回调可见且后续保存可重试', () async {
    final repository = _FailingCategoryRepository();
    final controller = await createTestController(
      LocalKeyValueStore(),
      repository: repository,
    );
    await controller.waitForPendingWrites();
    Object? reported;
    controller.onPersistError = (error) => reported = error;
    repository.fail = true;
    expect(await controller.saveCategoryKeywords('dining', ['包子']), isFalse);
    expect(reported, isA<StateError>());
    expect(controller.categoryById('dining').keywords, isEmpty);
    expect(
      (await repository.loadCategories())
          .firstWhere((c) => c.id == 'dining')
          .keywords,
      isEmpty,
    );
    repository.fail = false;
    expect(await controller.saveCategoryKeywords('dining', ['包子']), isTrue);
    controller.dispose();
  });

  test('导入重复分类自愈合并时保留各自关键词', () async {
    final controller = await makeController();
    final duplicate = controller
        .categoryById('dining')
        .copyWith(id: 'duplicate-dining', keywords: ['包子']);
    final payload =
        jsonDecode(controller.exportDataJson()) as Map<String, Object?>;
    final data = payload['data']! as Map<String, Object?>;
    final categories = data['categories']! as List<Object?>;
    categories.add(duplicate.toJson());
    await controller.importDataJson(jsonEncode(payload));
    expect(controller.categories.where((c) => c.label == '餐饮'), hasLength(1));
    expect(controller.categories.firstWhere((c) => c.label == '餐饮').keywords, [
      '包子',
    ]);
    controller.dispose();
  });
}
