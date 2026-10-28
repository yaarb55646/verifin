import 'package:flutter_test/flutter_test.dart';
import 'package:verifin/app/ai/ledger_query.dart';
import 'package:verifin/app/ledger_math.dart';
import 'package:verifin/app/models.dart';

LedgerEntry _entry({
  required String id,
  EntryType type = EntryType.expense,
  double amount = 100,
  String categoryId = 'cat',
  String accountId = 'acc',
  String? toAccountId,
  String note = '',
  List<String> tagIds = const <String>[],
  double refunded = 0,
  DateTime? at,
}) {
  return LedgerEntry(
    id: id,
    bookId: 'b',
    type: type,
    amount: amount,
    categoryId: categoryId,
    accountId: accountId,
    toAccountId: toAccountId,
    note: note,
    occurredAt: at ?? DateTime(2026, 6, 15),
    tagIds: tagIds,
    refundedAmount: refunded,
  );
}

void main() {
  group('queryLedgerEntries', () {
    test('空条件返回全部、默认按时间降序', () {
      final entries = <LedgerEntry>[
        _entry(id: 'a', at: DateTime(2026, 6, 1)),
        _entry(id: 'b', at: DateTime(2026, 6, 20)),
        _entry(id: 'c', at: DateTime(2026, 6, 10)),
      ];
      final result = queryLedgerEntries(entries, const LedgerQuery());
      expect(result.map((e) => e.id), <String>['b', 'c', 'a']);
    });

    test('不改动入参列表', () {
      final entries = <LedgerEntry>[
        _entry(id: 'a', at: DateTime(2026, 6, 1)),
        _entry(id: 'b', at: DateTime(2026, 6, 20)),
      ];
      queryLedgerEntries(
        entries,
        const LedgerQuery(sortBy: LedgerSortField.amount),
      );
      expect(entries.map((e) => e.id), <String>['a', 'b']);
    });

    test('按类型过滤', () {
      final entries = <LedgerEntry>[
        _entry(id: 'e', type: EntryType.expense),
        _entry(id: 'i', type: EntryType.income),
        _entry(id: 't', type: EntryType.transfer),
      ];
      final result = queryLedgerEntries(
        entries,
        const LedgerQuery(types: <EntryType>{EntryType.income}),
      );
      expect(result.map((e) => e.id), <String>['i']);
    });

    test('金额区间按净额（支出扣退款）', () {
      final entries = <LedgerEntry>[
        _entry(id: 'small', amount: 30),
        _entry(id: 'mid', amount: 100),
        _entry(id: 'big', amount: 500),
        _entry(id: 'netdown', amount: 500, refunded: 480), // 净 20
      ];
      final result = queryLedgerEntries(
        entries,
        const LedgerQuery(minAmount: 50, maxAmount: 200),
      );
      expect(result.map((e) => e.id).toSet(), <String>{'mid'});
    });

    test('时间窗过滤（闭区间、按自然日）', () {
      final entries = <LedgerEntry>[
        _entry(id: 'before', at: DateTime(2026, 5, 31)),
        _entry(id: 'in1', at: DateTime(2026, 6, 1)),
        _entry(id: 'in2', at: DateTime(2026, 6, 30, 23, 59)),
        _entry(id: 'after', at: DateTime(2026, 7, 1)),
      ];
      final result = queryLedgerEntries(
        entries,
        LedgerQuery(window: monthWindowFor(DateTime(2026, 6, 10))),
      );
      expect(result.map((e) => e.id).toSet(), <String>{'in1', 'in2'});
    });

    test('账户匹配 accountId 或转账 toAccountId', () {
      final entries = <LedgerEntry>[
        _entry(id: 'from', accountId: 'wallet'),
        _entry(
          id: 'to',
          type: EntryType.transfer,
          accountId: 'bank',
          toAccountId: 'wallet',
        ),
        _entry(id: 'other', accountId: 'bank'),
      ];
      final result = queryLedgerEntries(
        entries,
        const LedgerQuery(accountIds: <String>{'wallet'}),
      );
      expect(result.map((e) => e.id).toSet(), <String>{'from', 'to'});
    });

    test('标签命中任一即匹配', () {
      final entries = <LedgerEntry>[
        _entry(id: 'x', tagIds: <String>['t1', 't2']),
        _entry(id: 'y', tagIds: <String>['t3']),
        _entry(id: 'z', tagIds: <String>[]),
      ];
      final result = queryLedgerEntries(
        entries,
        const LedgerQuery(tagIds: <String>{'t2', 't9'}),
      );
      expect(result.map((e) => e.id).toSet(), <String>{'x'});
    });

    test('关键词大小写不敏感子串匹配备注', () {
      final entries = <LedgerEntry>[
        _entry(id: 'a', note: '星巴克 Coffee'),
        _entry(id: 'b', note: '午餐'),
      ];
      final result = queryLedgerEntries(
        entries,
        const LedgerQuery(keyword: 'coffee'),
      );
      expect(result.map((e) => e.id), <String>['a']);
    });

    test('按金额降序 + Top N', () {
      final entries = <LedgerEntry>[
        _entry(id: 'a', amount: 100),
        _entry(id: 'b', amount: 500),
        _entry(id: 'c', amount: 300),
        _entry(id: 'd', amount: 50),
      ];
      final result = queryLedgerEntries(
        entries,
        const LedgerQuery(sortBy: LedgerSortField.amount, limit: 2),
      );
      expect(result.map((e) => e.id), <String>['b', 'c']);
    });

    test('升序排序', () {
      final entries = <LedgerEntry>[
        _entry(id: 'a', amount: 100),
        _entry(id: 'b', amount: 500),
        _entry(id: 'c', amount: 300),
      ];
      final result = queryLedgerEntries(
        entries,
        const LedgerQuery(sortBy: LedgerSortField.amount, descending: false),
      );
      expect(result.map((e) => e.id), <String>['a', 'c', 'b']);
    });

    test('多条件叠加为「与」关系', () {
      final entries = <LedgerEntry>[
        _entry(
          id: 'hit',
          type: EntryType.expense,
          amount: 200,
          categoryId: 'food',
          at: DateTime(2026, 6, 5),
        ),
        _entry(
          id: 'wrongcat',
          type: EntryType.expense,
          amount: 200,
          categoryId: 'travel',
          at: DateTime(2026, 6, 5),
        ),
        _entry(
          id: 'wrongmonth',
          type: EntryType.expense,
          amount: 200,
          categoryId: 'food',
          at: DateTime(2026, 5, 5),
        ),
      ];
      final result = queryLedgerEntries(
        entries,
        LedgerQuery(
          types: const <EntryType>{EntryType.expense},
          categoryIds: const <String>{'food'},
          minAmount: 50,
          window: monthWindowFor(DateTime(2026, 6, 1)),
        ),
      );
      expect(result.map((e) => e.id), <String>['hit']);
    });

    test('bounded top-k matches full sorting for date and amount', () {
      final entries = List<LedgerEntry>.generate(
        200,
        (index) => _entry(
          id: 'e$index',
          amount: (index * 37 % 211).toDouble(),
          at: DateTime(2026, 1, 1).add(Duration(days: index % 30)),
        ),
      );
      for (final sortBy in LedgerSortField.values) {
        for (final descending in <bool>[true, false]) {
          final full = queryLedgerEntries(
            entries,
            LedgerQuery(sortBy: sortBy, descending: descending),
          );
          final bounded = queryLedgerEntries(
            entries,
            LedgerQuery(sortBy: sortBy, descending: descending, limit: 7),
          );
          expect(
            bounded.map((entry) => entry.id),
            full.take(7).map((entry) => entry.id),
          );
        }
      }
    });
  });
}
