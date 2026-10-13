import 'package:flutter_test/flutter_test.dart';
import 'package:verifin/app/category_suggest.dart';
import 'package:verifin/app/models.dart';
import 'package:verifin/app/quick_entry_text.dart';

Category _category(
  String id,
  String label, {
  String bookId = 'book',
  String? parentId,
  EntryType type = EntryType.expense,
  String? key,
}) => Category(
  id: id,
  bookId: bookId,
  label: label,
  type: type,
  iconCode: 'category',
  parentId: parentId,
  key: key,
);

void main() {
  final dining = _category('root', '餐饮');
  final lunch = _category('opaque-child', '午餐', parentId: dining.id);
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

  test('午餐10.25元 matches a newly created subcategory without history', () {
    final parsed = parseQuickEntryText('午餐10.25元');
    expect(parsed.amount, 10.25);
    expect(parsed.note, '午餐');
    expect(match(parsed.note, [dining, lunch])?.id, lunch.id);
  });

  test('matches arbitrary levels and normalized names', () {
    final deep = _category('deep', 'Ｃｏｆｆｅｅ', parentId: lunch.id);
    expect(match('coffee', [dining, lunch, deep])?.id, deep.id);
    expect(match('餐饮 / 午餐 / coffee', [dining, lunch, deep])?.id, deep.id);
    expect(match('今天午餐很好吃', [dining, lunch])?.id, lunch.id);
  });

  test('longest complete name wins and English uses word boundaries', () {
    final short = _category('short', '餐');
    expect(match('今天午餐', [short, lunch])?.id, lunch.id);
    final car = _category('car', 'car');
    expect(match('card payment', [car]), isNull);
    expect(match('car parking', [car])?.id, car.id);
  });

  test('same name is ambiguous unless its ancestor path is specified', () {
    final travel = _category('travel', '旅行');
    final otherLunch = _category('other-lunch', '午餐', parentId: travel.id);
    final categories = [dining, lunch, travel, otherLunch];
    expect(match('午餐', categories), isNull);
    expect(match('今天午餐', categories), isNull);
    expect(match('餐饮/午餐', categories)?.id, lunch.id);
    expect(match('旅行 → 午餐', categories)?.id, otherLunch.id);
  });

  test('scope, forced type and excluded system types are respected', () {
    final foreign = lunch.copyWith(id: 'foreign', bookId: 'foreign-book');
    final income = _category('income', '午餐', type: EntryType.income);
    expect(match('午餐', [foreign]), isNull);
    expect(match('午餐', [lunch, foreign])?.id, lunch.id);
    expect(match('午餐', [lunch, income]), isNull);
    expect(
      match('午餐', [lunch, income], forcedType: EntryType.income)?.id,
      income.id,
    );
    expect(match('午餐', [lunch], forcedType: EntryType.transfer), isNull);
    expect(
      match('午餐', [_category('transfer', '午餐', type: EntryType.transfer)]),
      isNull,
    );
    expect(
      match('午餐', [_category('refund', '午餐', type: EntryType.refund)]),
      isNull,
    );
    expect(
      match('调整', [_category('system', '调整', key: balanceAdjustExpenseKey)]),
      isNull,
    );
  });

  test(
    'rename and deletion immediately use the current category collection',
    () {
      expect(match('午餐', [dining, lunch])?.id, lunch.id);
      final renamed = lunch.copyWith(label: '工作午餐');
      expect(match('午餐', [dining, renamed]), isNull);
      expect(match('工作午餐', [dining, renamed])?.id, lunch.id);
      expect(match('午餐', [dining]), isNull);
      expect(match('', [dining, lunch]), isNull);
      expect(match('无匹配', [dining, lunch]), isNull);
    },
  );
}
