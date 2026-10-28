import 'package:flutter_test/flutter_test.dart';
import 'package:verifin/app/models.dart';
import 'package:verifin/app/veri_fin_controller.dart';
import 'package:verifin/local_storage/local_storage.dart';

import 'support/test_harness.dart';
import 'support/in_memory_ledger_repository.dart';

/// 分类与标签是**账本内数据**：这里覆盖跨账本的隔离语义（改名/换图标/删除/笔数/
/// 标签引用），以及「新账本自带默认分类」「删账本连带删分类标签」。
///
/// 分类 id 随机生成，测试一律按语义键（[Category.key]）或标签取，不写死 id。
LedgerEntry _expense(
  String id,
  String bookId,
  String categoryId, {
  String accountId = 'cash',
  List<String> tagIds = const <String>[],
  EntryType type = EntryType.expense,
  double amount = 10,
}) => LedgerEntry(
  id: id,
  bookId: bookId,
  type: type,
  amount: amount,
  categoryId: categoryId,
  accountId: accountId,
  note: '',
  occurredAt: DateTime(2026, 7, 4),
  tagIds: tagIds,
);

/// 按账本 + 语义键取分类。`categoryById` 只在当前账本内查找（这正是隔离的体现），
/// 跨账本断言一律走这个助手。
Category _categoryIn(VeriFinController controller, String bookId, String key) =>
    controller
        .categoriesForBook(bookId)
        .firstWhere((category) => category.key == key);

/// 用给定的库内容构造控制器（默认账本 + 旅行账本），用于验证载入期自愈；
/// 返回仓储以便断言落库结果。
Future<(VeriFinController, InMemoryLedgerRepository)> _controllerWithData({
  required List<Category> categories,
  required List<Tag> tags,
  required List<LedgerEntry> entries,
}) async {
  final store = LocalKeyValueStore();
  store.write('verifin.privacy_consent.v1', 'true');
  store.write('verifin.onboarding.v1', 'true');
  store.write('verifin.locale.v1', 'zh');
  final repo = InMemoryLedgerRepository();
  await repo.saveBooks(<LedgerBook>[
    LedgerBook(
      id: defaultLedgerBookId,
      name: '日常账本',
      createdAt: DateTime(2026, 1, 1),
      isDefault: true,
    ),
    LedgerBook(
      id: 'book_travel',
      name: '旅行',
      createdAt: DateTime(2026, 1, 2),
      isDefault: false,
    ),
  ]);
  await repo.saveCategories(categories);
  await repo.saveTags(tags);
  await repo.saveEntries(entries);
  final controller = await createTestController(store, repository: repo);
  return (controller, repo);
}

void main() {
  useTestDatabases();

  test('新建账本自带一份默认分类，且与已有账本互不影响', () async {
    final controller = await makeController();
    final defaultBookId = controller.activeBook.id;
    final diningInDefault = controller.categoryByKey(defaultBookId, 'dining')!;

    controller.addLedgerBook('旅行');
    final travelBookId = controller.activeBook.id;
    expect(travelBookId, isNot(defaultBookId));

    // 新账本拿到同名的默认分类，但**是另一条记录**（不同 id）。
    final diningInTravel = controller.categoryByKey(travelBookId, 'dining')!;
    expect(diningInTravel.label, '餐饮');
    expect(diningInTravel.id, isNot(diningInDefault.id));
    expect(
      controller.categories.length,
      controller.categoriesForBook(defaultBookId).length,
    );

    // 在旅行账本改名/换图标，不影响日常账本。
    await controller.renameCategory(diningInTravel.id, '美食');
    controller.updateCategoryIcon(diningInTravel.id, 'coffee');
    expect(_categoryIn(controller, travelBookId, 'dining').label, '美食');
    expect(_categoryIn(controller, defaultBookId, 'dining').label, '餐饮');
    expect(_categoryIn(controller, defaultBookId, 'dining').iconCode, 'dining');

    // 切回日常账本，看到的仍是原名。
    controller.switchLedgerBook(defaultBookId);
    expect(controller.categoryById(diningInDefault.id).label, '餐饮');
    expect(
      controller.categories.any((category) => category.label == '美食'),
      isFalse,
    );
    controller.dispose();
  });

  test('另一个账本用过某分类，不再阻塞本账本的删除', () async {
    final controller = await makeController();
    final defaultBookId = controller.activeBook.id;
    final diningInDefault = controller.categoryByKey(defaultBookId, 'dining')!;

    controller.addLedgerBook('旅行');
    final travelBookId = controller.activeBook.id;
    final diningInTravel = controller.categoryByKey(travelBookId, 'dining')!;
    // 旅行账本里有交易引用它自己的「餐饮」。
    controller.addEntry(_expense('e_travel', travelBookId, diningInTravel.id));
    expect(controller.categoryUsageCount(diningInTravel.id), 1);

    // 日常账本的「餐饮」没有任何引用：可以删除（旧实现会被另一个账本锁死）。
    controller.switchLedgerBook(defaultBookId);
    expect(controller.categoryUsageCount(diningInDefault.id), 0);
    expect(await controller.deleteCategory(diningInDefault.id), isTrue);
    expect(
      controller.categories.any(
        (category) => category.id == diningInDefault.id,
      ),
      isFalse,
    );
    // 旅行账本的那条完全不受影响（跨账本只能用各自账本的列表查找）。
    expect(_categoryIn(controller, travelBookId, 'dining').label, '餐饮');
    // 笔数是账本内口径：切回旅行账本才看得到它自己的那 1 笔。
    controller.switchLedgerBook(travelBookId);
    expect(controller.categoryUsageCount(diningInTravel.id), 1);
    expect(controller.categoryUsageCount(diningInDefault.id), 0);
    controller.dispose();
  });

  test('分类笔数只算当前账本', () async {
    final controller = await makeController();
    final defaultBookId = controller.activeBook.id;
    final dining = controller.categoryByKey(defaultBookId, 'dining')!;

    controller
      ..addEntry(_expense('e1', defaultBookId, dining.id))
      ..addEntry(_expense('e2', defaultBookId, dining.id));
    expect(controller.categoryUsageCount(dining.id), 2);
    expect(controller.categoryUsageCountInTree(dining.id), 2);

    controller.addLedgerBook('旅行');
    final travelBookId = controller.activeBook.id;
    expect(controller.categoryUsageCount(dining.id), 0);

    final travelDining = controller.categoryByKey(travelBookId, 'dining')!;
    controller.addEntry(_expense('e3', travelBookId, travelDining.id));
    expect(controller.categoryUsageCount(travelDining.id), 1);
    controller.switchLedgerBook(defaultBookId);
    expect(controller.categoryUsageCount(dining.id), 2);
    controller.dispose();
  });

  test('同级分类重排只影响当前账本', () async {
    final controller = await makeController();
    final defaultBookId = controller.activeBook.id;
    final defaultOrder = controller
        .categoriesForBook(defaultBookId)
        .where(
          (category) =>
              category.type == EntryType.expense && category.parentId == null,
        )
        .map((category) => category.id)
        .toList();

    controller.addLedgerBook('旅行');
    final travelBookId = controller.activeBook.id;
    final travelOrder = controller
        .categoriesForBook(travelBookId)
        .where(
          (category) =>
              category.type == EntryType.expense && category.parentId == null,
        )
        .map((category) => category.id)
        .toList();
    controller.switchLedgerBook(defaultBookId);

    controller.reorderCategories(EntryType.expense, null, 0, 1);

    final reorderedDefault = controller
        .categoriesForBook(defaultBookId)
        .where(
          (category) =>
              category.type == EntryType.expense && category.parentId == null,
        )
        .map((category) => category.id)
        .toList();
    expect(reorderedDefault.take(2), <String>[
      defaultOrder[1],
      defaultOrder[0],
    ]);
    expect(
      controller
          .categoriesForBook(travelBookId)
          .where(
            (category) =>
                category.type == EntryType.expense && category.parentId == null,
          )
          .map((category) => category.id)
          .toList(),
      travelOrder,
    );
    controller.dispose();
  });

  test('删除标签只摘掉本账本交易上的引用', () async {
    final controller = await makeController();
    final defaultBookId = controller.activeBook.id;
    final dining = controller.categoryByKey(defaultBookId, 'dining')!;
    final tagInDefault = controller.addTag('报销')!;
    controller.addEntry(
      _expense('e1', defaultBookId, dining.id, tagIds: <String>[tagInDefault]),
    );
    expect(controller.tagUsageCount(tagInDefault), 1);

    controller.addLedgerBook('旅行');
    final travelBookId = controller.activeBook.id;
    final travelDining = controller.categoryByKey(travelBookId, 'dining')!;
    // 旅行账本另建一个同名标签 + 一条带标签的交易。
    final tagInTravel = controller.addTag('报销')!;
    expect(tagInTravel, isNot(tagInDefault));
    controller.addEntry(
      _expense(
        'e2',
        travelBookId,
        travelDining.id,
        tagIds: <String>[tagInTravel],
      ),
    );
    expect(controller.tagUsageCount(tagInTravel), 1);

    // 在旅行账本删标签：只影响旅行账本的交易。
    expect(await controller.deleteTag(tagInTravel), isTrue);
    expect(controller.entriesForBook(travelBookId).single.tagIds, isEmpty);
    final defaultEntry = controller.entriesForBook(defaultBookId).single;
    expect(defaultEntry.tagIds, <String>[tagInDefault]);
    expect(
      controller.tagsForBook(defaultBookId).map((tag) => tag.label),
      contains('报销'),
    );
    controller.dispose();
  });

  test('删除账本连带删除该账本的分类与标签', () async {
    final controller = await makeController();
    final defaultBookId = controller.activeBook.id;
    controller.addLedgerBook('旅行');
    final travelBookId = controller.activeBook.id;
    controller.addTag('旅行专用');
    controller.addCategory(
      type: EntryType.expense,
      label: '门票',
      iconCode: 'travel',
    );
    expect(controller.categoriesForBook(travelBookId), isNotEmpty);
    expect(controller.tagsForBook(travelBookId), isNotEmpty);

    expect(await controller.deleteLedgerBook(travelBookId), isTrue);
    expect(controller.categoriesForBook(travelBookId), isEmpty);
    expect(controller.tagsForBook(travelBookId), isEmpty);
    // 默认账本的分类与标签保持原样。
    expect(controller.categoriesForBook(defaultBookId), isNotEmpty);
    controller.dispose();
  });

  test('交易不能引用别的账本的分类（写入守卫）', () async {
    final controller = await makeController();
    final defaultBookId = controller.activeBook.id;
    controller.addLedgerBook('旅行');
    final travelBookId = controller.activeBook.id;
    final travelDining = controller.categoryByKey(travelBookId, 'dining')!;

    // 把旅行账本的分类挂到日常账本的交易上：必须被拒。
    final result = await controller.saveEntryAggregateDraftResult(
      entry: _expense('e_bad', defaultBookId, travelDining.id),
      isNew: true,
    );
    expect(result, isA<EntrySaveValidationFailure>());
    expect(
      (result as EntrySaveValidationFailure).code,
      EntryValidationCode.categoryOutOfScope,
    );
    expect(controller.entriesForBook(defaultBookId), isEmpty);
    controller.dispose();
  });

  test('批量改分类不会把交易串到别的账本', () async {
    final controller = await makeController();
    final defaultBookId = controller.activeBook.id;
    final dining = controller.categoryByKey(defaultBookId, 'dining')!;
    controller.addEntry(_expense('e1', defaultBookId, dining.id));

    controller.addLedgerBook('旅行');
    final travelBookId = controller.activeBook.id;
    final travelDining = controller.categoryByKey(travelBookId, 'dining')!;
    controller.addEntry(_expense('e2', travelBookId, travelDining.id));

    // 旅行账本里把 e2 改成「日常账本的餐饮」：类型相同也不允许（跨账本）。
    final changed = controller.setEntriesCategory(<String>{'e2'}, dining.id);
    expect(changed, 0);
    expect(
      controller.entriesForBook(travelBookId).single.categoryId,
      travelDining.id,
    );
    controller.dispose();
  });

  test('同账本内同名分类仍被唯一约束拒绝，跨账本则可同名', () async {
    final controller = await makeController();
    final before = controller.categories.length;
    controller.addCategory(
      type: EntryType.expense,
      label: '餐饮', // 已存在（同名同类型顶级）
      iconCode: 'category',
    );
    expect(controller.categories.length, before);

    controller.addLedgerBook('旅行');
    final travelBookId = controller.activeBook.id;
    expect(controller.categoryByKey(travelBookId, 'dining')!.label, '餐饮');
    controller.dispose();
  });

  test('默认分类的语义键与种子定义一一对应', () async {
    final controller = await makeController();
    final keys = controller.categories
        .where((category) => category.bookId == controller.activeBook.id)
        .map((category) => category.key)
        .whereType<String>()
        .toSet();
    expect(keys, defaultCategoryKeys.toSet());
    controller.dispose();
  });

  test('系统分类（余额调整）按账本各一条，且不可删除', () async {
    final controller = await makeController();
    final defaultBookId = controller.activeBook.id;
    final expenseAdjust = controller.categoryByKey(
      defaultBookId,
      balanceAdjustExpenseKey,
    )!;
    expect(expenseAdjust.isBalanceAdjust, isTrue);
    expect(await controller.deleteCategory(expenseAdjust.id), isFalse);
    expect(controller.moveCategory(expenseAdjust.id, null), isFalse);

    controller.addLedgerBook('旅行');
    final travelBookId = controller.activeBook.id;
    final travelAdjust = controller.categoryByKey(
      travelBookId,
      balanceAdjustExpenseKey,
    )!;
    expect(travelAdjust.id, isNot(expenseAdjust.id));
    controller.dispose();
  });

  test('导入的 v4 备份保持每个账本各自的分类集合', () async {
    final source = await makeController();
    final defaultBookId = source.activeBook.id;
    final dining = source.categoryByKey(defaultBookId, 'dining')!;
    source.addLedgerBook('旅行');
    final travelBookId = source.activeBook.id;
    final travelDining = source.categoryByKey(travelBookId, 'dining')!;
    await source.renameCategory(travelDining.id, '美食');
    final backup = source.exportDataJson();

    final target = await createTestController(
      LocalKeyValueStore(),
      repository: InMemoryLedgerRepository(),
    );
    await target.importDataJson(backup);
    // v4 备份按账本存分类，导入后两个账本各自的集合与 id 都不变。
    expect(
      target.categoriesForBook(defaultBookId).map((c) => c.id),
      contains(dining.id),
    );
    expect(_categoryIn(target, defaultBookId, 'dining').label, '餐饮');
    expect(_categoryIn(target, travelBookId, 'dining').label, '美食');
    target.dispose();
    source.dispose();
  });

  test('交易不能引用别的账本的标签（写入守卫）', () async {
    final controller = await makeController();
    final defaultBookId = controller.activeBook.id;
    final dining = controller.categoryByKey(defaultBookId, 'dining')!;
    final ownTag = controller.addTag('报销')!;
    controller.addAccount(
      const Account(
        id: 'cash',
        bookId: defaultLedgerBookId,
        name: '现金',
        type: AccountType.cash,
        groupId: null,
        initialBalance: 0,
        iconCode: 'wallet',
        note: '',
        includeInAssets: true,
        hidden: false,
      ),
    );

    controller.addLedgerBook('旅行');
    final travelTag = controller.addTag('报销')!; // 旅行账本的同名标签
    expect(travelTag, isNot(ownTag));

    // 切回默认账本，把旅行账本的标签挂到默认账本的交易上：必须被拒。
    controller.switchLedgerBook(defaultBookId);
    final rejected = await controller.saveEntryAggregateDraftResult(
      entry: _expense(
        'e_bad',
        defaultBookId,
        dining.id,
        tagIds: <String>[travelTag],
      ),
      isNew: true,
    );
    expect(rejected, isA<EntrySaveValidationFailure>());
    expect(
      (rejected as EntrySaveValidationFailure).code,
      EntryValidationCode.tagOutOfScope,
    );
    expect(controller.entriesForBook(defaultBookId), isEmpty);

    // 同账本的标签照常保存（守卫只拦跨账本引用）。
    final saved = await controller.saveEntryAggregateDraftResult(
      entry: _expense(
        'e_ok',
        defaultBookId,
        dining.id,
        tagIds: <String>[ownTag],
      ),
      isNew: true,
    );
    expect(saved.isSuccess, isTrue);
    expect(controller.entriesForBook(defaultBookId).single.tagIds, <String>[
      ownTag,
    ]);
    controller.dispose();
  });

  test('tagById 只解析当前账本的标签', () async {
    final controller = await makeController();
    final defaultBookId = controller.activeBook.id;
    final ownTag = controller.addTag('报销')!;
    controller.addLedgerBook('旅行');
    final travelBookId = controller.activeBook.id;
    final travelTag = controller.addTag('报销')!;

    // 当前是旅行账本：解析得到自己的标签，解析不到别的账本的。
    expect(controller.tagById(travelTag)?.label, '报销');
    expect(controller.tagById(ownTag), isNull);

    controller.switchLedgerBook(defaultBookId);
    expect(controller.tagById(ownTag)?.label, '报销');
    expect(controller.tagById(travelTag), isNull);
    // 跨账本读取走 tagsForBook。
    expect(controller.tagsForBook(travelBookId).single.id, travelTag);
    controller.dispose();
  });

  test('载入自愈摘掉悬空与跨账本的标签引用并落库，重开幂等', () async {
    const defaultCategory = Category(
      id: 'cat_default',
      bookId: defaultLedgerBookId,
      label: '餐饮',
      type: EntryType.expense,
      iconCode: 'dining',
      key: 'dining',
    );
    const travelCategory = Category(
      id: 'cat_travel',
      bookId: 'book_travel',
      label: '餐饮',
      type: EntryType.expense,
      iconCode: 'dining',
      key: 'dining',
    );
    const ownTag = Tag(id: 'tag_own', bookId: defaultLedgerBookId, label: '报销');
    const otherTag = Tag(id: 'tag_other', bookId: 'book_travel', label: '旅行');
    const duplicateTag = Tag(
      id: 'tag_dup',
      bookId: defaultLedgerBookId,
      label: '工作',
    );

    final (controller, repo) = await _controllerWithData(
      categories: <Category>[defaultCategory, travelCategory],
      tags: <Tag>[ownTag, otherTag, duplicateTag],
      entries: <LedgerEntry>[
        // 悬空 id + 别的账本的 id + 重复引用 + 合法 id。
        _expense(
          'e_mixed',
          defaultLedgerBookId,
          defaultCategory.id,
          tagIds: <String>['tag_ghost', otherTag.id, ownTag.id, ownTag.id],
        ),
        // 全部解析不到 → 摘空。
        _expense(
          'e_foreign',
          defaultLedgerBookId,
          defaultCategory.id,
          tagIds: <String>[otherTag.id],
        ),
        // 合法的原样保留。
        _expense(
          'e_clean',
          defaultLedgerBookId,
          defaultCategory.id,
          tagIds: <String>[duplicateTag.id],
        ),
      ],
    );

    List<String> tagsOf(String entryId) => controller
        .entriesForBook(defaultLedgerBookId)
        .firstWhere((entry) => entry.id == entryId)
        .tagIds;

    expect(tagsOf('e_mixed'), <String>[ownTag.id]);
    expect(tagsOf('e_foreign'), isEmpty);
    expect(tagsOf('e_clean'), <String>[duplicateTag.id]);
    // 跨账本引用的标签本身不被删除。
    expect(controller.tagsForBook('book_travel').single.id, otherTag.id);

    // 自愈结果落库。
    await controller.waitForPendingWrites();
    final persisted = <String, List<String>>{
      for (final entry in await repo.loadEntries()) entry.id: entry.tagIds,
    };
    expect(persisted['e_mixed'], <String>[ownTag.id]);
    expect(persisted['e_foreign'], isEmpty);
    expect(persisted['e_clean'], <String>[duplicateTag.id]);

    // 重开一次：数据已干净，不再有改动（幂等）。
    final reloaded = await createTestController(
      LocalKeyValueStore(),
      repository: repo,
    );
    await reloaded.waitForPendingWrites();
    expect(<String, List<String>>{
      for (final entry in await repo.loadEntries()) entry.id: entry.tagIds,
    }, persisted);
    controller.dispose();
    reloaded.dispose();
  });
}
