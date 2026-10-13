/// 分类模型：**账本内**的邻接表多级树（parentId），树形纯函数在
/// lib/app/category_tree.dart。
library;

import 'category_keys.dart';
import 'ledger_book.dart';
import 'ledger_entry.dart';

class Category {
  const Category({
    required this.id,
    required this.bookId,
    required this.label,
    required this.type,
    required this.iconCode,
    this.parentId,
    this.key,
    this.keywords = const <String>[],
  });

  /// 纯标识，随机生成、不承载任何含义（[key] 才是语义）。
  final String id;

  /// 所属账本。分类跟随账本而不是跟随应用：切换账本会换成该账本自己的分类集合，
  /// 新建账本则播种一份默认分类。
  final String bookId;

  final String label;
  final EntryType type;
  final String iconCode;

  /// 父分类 id；`null` 表示顶级分类。子分类与父分类的 [type] 必须一致。
  /// 支持任意层级树形结构（多级分类）。
  final String? parentId;

  /// 语义键：默认分类/系统分类/「未分类」兜底为固定常量，用户自建分类为 `null`。
  /// 见 lib/app/models/category_keys.dart。
  final String? key;

  /// 一句话记账的自定义叫法，属于当前分类和账本，随分类备份。
  final List<String> keywords;

  /// 是否为顶级分类。
  bool get isRoot => parentId == null;

  static List<String> decodeKeywords(Object? raw) =>
      _decodeCategoryKeywords(raw);

  /// 是否为系统分类（余额调整）。系统分类可改名、换图标，但不能移动、合并、删除。
  bool get isBalanceAdjust =>
      key == balanceAdjustExpenseKey || key == balanceAdjustIncomeKey;

  /// 是否为「未分类」兜底分类（导入缺失分类与载入自愈共用同一 id 约定）。
  bool get isUncategorized {
    final value = key;
    return value != null && value.startsWith(uncategorizedKeyPrefix);
  }

  /// 规范化父分类 id：空串归一为 null（顶级）。JSON 与 SQLite 两条反序列化
  /// 路径共用，防止「parentId=''」被当成指向空串 id 的父分类而变成孤儿。
  static String? normalizeParentId(String? raw) =>
      (raw != null && raw.isEmpty) ? null : raw;

  Category copyWith({
    String? id,
    String? bookId,
    String? label,
    EntryType? type,
    String? iconCode,
    String? key,
    List<String>? keywords,
    // 使用哨兵区分「未传入」与「显式置空」，以便把子分类移动到顶级。
    Object? parentId = _copyWithSentinel,
  }) {
    return Category(
      id: id ?? this.id,
      bookId: bookId ?? this.bookId,
      label: label ?? this.label,
      type: type ?? this.type,
      iconCode: iconCode ?? this.iconCode,
      key: key ?? this.key,
      keywords: keywords == null
          ? this.keywords
          : List<String>.unmodifiable(keywords),
      parentId: identical(parentId, _copyWithSentinel)
          ? this.parentId
          : parentId as String?,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'bookId': bookId,
      'label': label,
      'type': type.storageValue,
      'iconCode': iconCode,
      if (key != null) 'key': key,
      if (parentId != null) 'parentId': parentId,
      if (keywords.isNotEmpty) 'keywords': keywords,
    };
  }

  static Category fromJson(Map<String, Object?> json) {
    return Category(
      id: json['id'] as String,
      // 旧版备份（v3 及更早）里的分类是全局的、没有 bookId；那条路径由导入侧
      // 显式展开到各账本，不依赖这里的回落。缺字段时与账户/交易同规则回落默认账本。
      bookId: json['bookId'] as String? ?? defaultLedgerBookId,
      label: json['label'] as String? ?? '未命名分类',
      type: EntryType.fromStorage(json['type'] as String? ?? 'expense'),
      iconCode: json['iconCode'] as String? ?? 'category',
      key: json['key'] as String?,
      parentId: normalizeParentId(json['parentId'] as String?),
      keywords: decodeKeywords(json['keywords']),
    );
  }
}

/// 旧备份没有关键词；异构备份中的非字符串项不能成为识别规则。
List<String> _decodeCategoryKeywords(Object? raw) => raw is List
    ? List<String>.unmodifiable(
        raw
            .whereType<String>()
            .map((word) => word.trim())
            .where((word) => word.isNotEmpty),
      )
    : const <String>[];

const Object _copyWithSentinel = Object();

/// 该类型的系统分类语义键（只有支出/收入有系统分类）。
String balanceAdjustCategoryKey(EntryType type) =>
    type == EntryType.income ? balanceAdjustIncomeKey : balanceAdjustExpenseKey;

/// 「未分类」兜底分类的语义键（按类型各一）。
String uncategorizedCategoryKey(EntryType type) =>
    uncategorizedKeyForStorageValue(type.storageValue);

/// 构造「未分类」分类。id 由调用方生成（随机、不承载语义），语义靠 [key]；
/// 「先按键查、没有再建」保证导入兜底与载入自愈幂等落到同一条分类上。
/// [english] 与种子数据同规则：按首启动语言取文案，播种后属用户数据、不随语言切换。
Category buildUncategorizedCategory(
  String id,
  String bookId,
  EntryType type, {
  required bool english,
}) => Category(
  id: id,
  bookId: bookId,
  key: uncategorizedCategoryKey(type),
  label: english ? 'Uncategorized' : '未分类',
  type: type,
  iconCode: 'category',
);

/// 构造系统分类（余额调整）。id 由调用方生成，语义靠 [key]。文案与种子数据同规则；
/// 用户改过名的账本不会走到这里（只有该账本缺这条系统分类时才补建）。
Category buildBalanceAdjustCategory(
  String id,
  String bookId,
  EntryType type, {
  required bool english,
}) => Category(
  id: id,
  bookId: bookId,
  key: balanceAdjustCategoryKey(type),
  label: english ? 'Balance adjustment' : '余额调整',
  type: type,
  iconCode: 'adjust',
);
