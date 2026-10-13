import 'package:flutter_test/flutter_test.dart';
import 'package:verifin/app/models.dart';
import 'package:verifin/app/report_analysis.dart';

void main() {
  const categories = [
    Category(
      id: 'dining',
      bookId: 'book',
      label: '餐饮',
      type: EntryType.expense,
      iconCode: 'category',
    ),
    Category(
      id: 'lunch',
      bookId: 'book',
      label: '午餐',
      type: EntryType.expense,
      iconCode: 'category',
      parentId: 'dining',
    ),
    Category(
      id: 'deep',
      bookId: 'book',
      label: '工作餐',
      type: EntryType.expense,
      iconCode: 'category',
      parentId: 'lunch',
    ),
    Category(
      id: 'traffic',
      bookId: 'book',
      label: '交通',
      type: EntryType.expense,
      iconCode: 'category',
    ),
  ];
  LedgerEntry entry(
    String id,
    String categoryId,
    double base, {
    String bookId = 'book',
    EntryType type = EntryType.expense,
    double refunded = 0,
    bool excluded = false,
    String currency = 'CNY',
  }) => LedgerEntry(
    id: id,
    bookId: bookId,
    type: type,
    amount: currency == 'CNY' ? base : 10,
    baseAmount: base,
    currencyCode: currency,
    categoryId: categoryId,
    accountId: '',
    refundedBaseAmount: refunded,
    excludedFromBudget: excluded,
    note: '',
    occurredAt: DateTime(2026, 10, 13),
  );

  test('一级上卷、二级归并深层、顶级直接金额不重复且净额使用本位币', () {
    final entries = [
      entry('direct', 'dining', 25),
      entry('lunch', 'lunch', 50, refunded: 10),
      entry('deep', 'deep', 20, currency: 'USD', excluded: true),
      entry('traffic', 'traffic', 15),
      entry('foreign', 'traffic', 999, bookId: 'foreign'),
      entry('transfer', 'traffic', 999, type: EntryType.transfer),
      entry('refund', 'traffic', 999, type: EntryType.refund),
    ];
    List<ReportCategoryStat> stats(bool sub) => reportCategoryShareStats(
      entries: entries,
      categories: categories,
      bookId: 'book',
      type: EntryType.expense,
      showSubcategories: sub,
    );
    expect(stats(false).map((s) => s.amount), [85, 15]);
    expect(stats(false).first.percent, .85);
    expect(stats(true).map((s) => s.amount), [60, 25, 15]);
    expect(stats(true).first.categoryId, 'lunch');
    expect(stats(true).first.percent, .6);
    expect(
      stats(true).fold<double>(0, (sum, stat) => sum + stat.percent),
      closeTo(1, .0001),
    );
    expect(stats(true).first.count, 2);
  });

  test('全额退款、空集和非法类型不产生无效百分比', () {
    final stats = reportCategoryShareStats(
      entries: [entry('zero', 'dining', 50, refunded: 50)],
      categories: categories,
      bookId: 'book',
      type: EntryType.expense,
      showSubcategories: true,
    );
    expect(stats.single.amount, 0);
    expect(stats.single.percent, 0);
    expect(
      reportCategoryShareStats(
        entries: [],
        categories: categories,
        bookId: 'book',
        type: EntryType.income,
        showSubcategories: false,
      ),
      isEmpty,
    );
    expect(
      reportCategoryShareStats(
        entries: [entry('x', 'dining', 5)],
        categories: categories,
        bookId: 'book',
        type: EntryType.transfer,
        showSubcategories: false,
      ),
      isEmpty,
    );
  });
}
