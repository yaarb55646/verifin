/// 旧版备份（v3 及更早）里分类/标签是**全局**的、没有 `bookId`。分类/标签改为
/// 账本内数据之后，导入这类备份必须把它们展开成**每个账本各一份副本**，并把该账本
/// 交易、周期规则与分类预算里的引用改写到副本的新 id（每条副本随机生成，映射表见
/// 下方 `expandLegacyScopedRecords` 的返回值）。
///
/// 为什么是「全量复制到每个账本」而不是「只复制被引用到的」：旧模型下每个账本看到的
/// 本来就是同一张全局表，全量复制才能让导入前后的分类集合完全一致；按引用裁剪等于在
/// 导入时静默删掉用户「建好但还没用」或「只在别的账本用过」的分类。
library;

import '../models.dart';

/// 旧备份展开成账本内数据的结果。
class LegacyBookScopeExpansion {
  const LegacyBookScopeExpansion({
    required this.categories,
    required this.tags,
    required this.categoryIdsByBook,
    required this.tagIdsByBook,
  });

  /// 展开后的分类：每个账本一份。
  final List<Category> categories;

  /// 展开后的标签：每个账本一份。
  final List<Tag> tags;

  /// bookId → { 旧分类 id → 新分类 id }
  final Map<String, Map<String, String>> categoryIdsByBook;

  /// bookId → { 旧标签 id → 新标签 id }
  final Map<String, Map<String, String>> tagIdsByBook;

  /// 旧分类 id 在 [bookId] 里的新 id；该账本没有对应分类时返回 null。
  String? categoryIdFor(String bookId, String oldId) =>
      categoryIdsByBook[bookId]?[oldId];

  /// 旧标签 id 在 [bookId] 里的新 id；该账本没有对应标签时返回 null。
  String? tagIdFor(String bookId, String oldId) => tagIdsByBook[bookId]?[oldId];

  /// 把分类预算键 `<bookId>:<yyyy-MM|default>:<旧分类 id>` 的末段换成新 id。
  /// 解析不了或该账本没有对应分类的键原样保留。
  Map<String, double> rewriteCategoryBudgetKeys(Map<String, double> budgets) {
    final result = <String, double>{};
    budgets.forEach((key, value) {
      final parts = key.split(':');
      if (parts.length == 3) {
        final mapped = categoryIdFor(parts[0], parts[2]);
        if (mapped != null) {
          result['${parts[0]}:${parts[1]}:$mapped'] = value;
          return;
        }
      }
      result[key] = value;
    });
    return result;
  }
}

/// 把全局分类/标签展开成每个账本一份，并给出 id 映射表。
///
/// 每条副本都拿到**新生成的随机 id**（分类 id 不承载语义，旧 id 若是有约定的语义键
/// 就转成 `key` 保留下来）。[nextId] 由调用方提供，保证与其它实体同源生成。
/// 同一账本内的同名标签只保留第一条（旧表没有唯一约束，与迁移段同一口径）；
/// 被折叠掉的旧 id 会映射到保留者的新 id，因此引用不会丢。
LegacyBookScopeExpansion expandLegacyScopedRecords({
  required List<String> bookIds,
  required List<Category> categories,
  required List<Tag> tags,
  required String Function(String prefix) nextId,
}) {
  final expandedCategories = <Category>[];
  final categoryIdsByBook = <String, Map<String, String>>{};
  // 先为「每个账本 × 每条旧分类」生成随机 id（父级映射要用到），再据此建记录。
  final categoryNewIdByBook = <String, Map<String, String>>{};
  for (final bookId in bookIds) {
    categoryNewIdByBook[bookId] = <String, String>{
      for (final category in categories) category.id: nextId('category'),
    };
  }
  for (final bookId in bookIds) {
    final ids = categoryNewIdByBook[bookId]!;
    for (final category in categories) {
      expandedCategories.add(
        Category(
          id: ids[category.id]!,
          bookId: bookId,
          label: category.label,
          type: category.type,
          iconCode: category.iconCode,
          keywords: category.keywords,
          // 旧 id 若是有约定的语义键（默认分类/余额调整/未分类），转成 key 保留语义。
          key: isKnownCategoryKey(category.id) ? category.id : null,
          parentId: category.parentId == null ? null : ids[category.parentId],
        ),
      );
    }
    categoryIdsByBook[bookId] = ids;
  }

  final expandedTags = <Tag>[];
  final tagIdsByBook = <String, Map<String, String>>{};
  // 同一账本内的同名标签折叠到第一条（保留者）上，与迁移段同一口径。
  final labelByTagId = <String, String>{
    for (final tag in tags) tag.id: tag.label,
  };
  final keeperIdByLabel = <String, String>{};
  for (final tag in tags) {
    keeperIdByLabel.putIfAbsent(tag.label, () => tag.id);
  }
  final newIdByBookAndKeeperId = <String, Map<String, String>>{};
  for (final bookId in bookIds) {
    final newIds = <String, String>{};
    for (final tag in tags) {
      final keeperId = keeperIdByLabel[tag.label]!;
      newIds.putIfAbsent(keeperId, () => nextId('tag'));
    }
    newIdByBookAndKeeperId[bookId] = newIds;
  }
  for (final bookId in bookIds) {
    final newIds = newIdByBookAndKeeperId[bookId]!;
    for (final entry in newIds.entries) {
      expandedTags.add(
        Tag(id: entry.value, bookId: bookId, label: labelByTagId[entry.key]!),
      );
    }
    tagIdsByBook[bookId] = <String, String>{
      for (final tag in tags) tag.id: newIds[keeperIdByLabel[tag.label]!]!,
    };
  }

  return LegacyBookScopeExpansion(
    categories: expandedCategories,
    tags: expandedTags,
    categoryIdsByBook: categoryIdsByBook,
    tagIdsByBook: tagIdsByBook,
  );
}
