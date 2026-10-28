import 'package:flutter_test/flutter_test.dart';
import 'package:verifin/app/ai/ai_ledger_snapshot.dart';
import 'package:verifin/app/models.dart';

import 'support/test_harness.dart';

void main() {
  useTestDatabases();

  test(
    'AI ledger snapshot stays unchanged after controller mutations',
    () async {
      final controller = await makeController();
      addTearDown(controller.dispose);
      final book = controller.activeBook;
      final category = controller.categories.firstWhere(
        (item) => item.type == EntryType.expense,
      );
      final account = Account(
        id: 'snapshot-account',
        bookId: book.id,
        name: '现金',
        type: AccountType.cash,
        groupId: null,
        initialBalance: 500,
        iconCode: 'cash',
        note: '',
        includeInAssets: true,
        hidden: false,
      );
      controller.addAccount(account);
      controller.addEntry(
        LedgerEntry(
          id: 'snapshot-entry',
          bookId: book.id,
          type: EntryType.expense,
          amount: 100,
          categoryId: category.id,
          accountId: account.id,
          note: 'snapshot',
          occurredAt: DateTime(2026, 6, 10),
        ),
      );
      controller.setMonthlyBudget(DateTime(2026, 6), 1000);

      final snapshot = controller.aiLedgerSnapshotForBook(
        book.id,
        now: DateTime(2026, 6, 20),
      );
      final frozenBalance = snapshot.balanceOf(account);

      controller.addEntry(
        LedgerEntry(
          id: 'after-snapshot',
          bookId: book.id,
          type: EntryType.expense,
          amount: 50,
          categoryId: category.id,
          accountId: account.id,
          note: 'after',
          occurredAt: DateTime(2026, 6, 11),
        ),
      );
      controller.setMonthlyBudget(DateTime(2026, 6), 2000);

      expect(snapshot.entries.map((entry) => entry.id), <String>[
        'snapshot-entry',
      ]);
      expect(snapshot.balanceOf(account), frozenBalance);
      expect(snapshot.budget?.monthlyBudgetOf(DateTime(2026, 6)), 1000);
      expect(snapshot.capturedAt, DateTime(2026, 6, 20));
    },
  );

  test('snapshot rejects data from another book', () {
    expect(
      () => AiLedgerSnapshot.forTesting(
        bookId: 'book-a',
        entries: <LedgerEntry>[
          LedgerEntry(
            id: 'foreign',
            bookId: 'book-b',
            type: EntryType.expense,
            amount: 1,
            categoryId: 'c',
            accountId: '',
            note: '',
            occurredAt: DateTime(2026, 6, 1),
          ),
        ],
        balanceOf: (_) => 0,
      ),
      throwsStateError,
    );
  });

  test('snapshot data is exposed through unmodifiable collections', () {
    final snapshot = AiLedgerSnapshot.forTesting(
      bookId: 'b',
      balanceOf: (_) => 0,
    );
    expect(() => snapshot.entries.add(_entry()), throwsUnsupportedError);
    expect(() => snapshot.balanceByAccountId['x'] = 1, throwsUnsupportedError);
  });

  test('snapshot sorts entries and exposes account index', () {
    final account = Account(
      id: 'a',
      bookId: 'b',
      name: '现金',
      type: AccountType.cash,
      groupId: null,
      initialBalance: 0,
      iconCode: 'cash',
      note: '',
      includeInAssets: true,
      hidden: false,
    );
    final snapshot = AiLedgerSnapshot.forTesting(
      bookId: 'b',
      accounts: <Account>[account],
      entries: <LedgerEntry>[
        _entry(id: 'old', at: DateTime(2026, 6, 1)),
        _entry(id: 'new', at: DateTime(2026, 6, 3)),
      ],
      balanceOf: (_) => 0,
    );

    expect(snapshot.entries.map((entry) => entry.id), <String>['new', 'old']);
    expect(snapshot.accountById('a')?.name, '现金');
    expect(snapshot.accountById('missing'), isNull);
  });
}

LedgerEntry _entry({String id = 'e', DateTime? at}) => LedgerEntry(
  id: id,
  bookId: 'b',
  type: EntryType.expense,
  amount: 1,
  categoryId: 'c',
  accountId: '',
  note: '',
  occurredAt: at ?? DateTime(2026, 6, 1),
);
