import 'package:flutter_test/flutter_test.dart';
import 'package:verifin/app/ledger_math.dart';
import 'package:verifin/app/models.dart';

void main() {
  LedgerEntry expense({
    String id = 'e1',
    double amount = 250.89,
    String currencyCode = 'CNY',
  }) {
    return LedgerEntry(
      id: id,
      bookId: 'default',
      type: EntryType.expense,
      amount: amount,
      currencyCode: currencyCode,
      categoryId: 'dining',
      accountId: '',
      note: '',
      occurredAt: DateTime(2026, 9, 12),
    );
  }

  LedgerEntry refund(
    String id,
    double amount, {
    String expenseId = 'e1',
    String currencyCode = 'CNY',
    bool settled = true,
  }) {
    return LedgerEntry(
      id: id,
      bookId: 'default',
      type: EntryType.refund,
      amount: amount,
      currencyCode: currencyCode,
      categoryId: 'dining',
      accountId: '',
      note: '',
      occurredAt: DateTime(2026, 9, 12),
      refundOf: expenseId,
      settledAt: settled ? DateTime(2026, 9, 12) : null,
    );
  }

  test('剩余可退金额按原币 minor unit 归一化', () {
    final remaining = remainingRefundableAmount(expense(), <LedgerEntry>[
      refund('r1', 50),
      refund('r2', 50),
      refund('r3', 51),
      refund('r4', 51),
    ]);

    expect(remaining, 48.89);
  });

  test('待到账退款也占用可退额度', () {
    final remaining = remainingRefundableAmount(
      expense(amount: 200),
      <LedgerEntry>[refund('r1', 60), refund('r2', 40, settled: false)],
    );

    expect(remaining, 100);
  });

  test('编辑已有退款时排除自身', () {
    final remaining = remainingRefundableAmount(
      expense(amount: 100),
      <LedgerEntry>[refund('r1', 30), refund('r2', 40)],
      excludeRefundId: 'r1',
    );

    expect(remaining, 60);
  });

  test('超额退款钳到零，非支出返回零', () {
    expect(
      remainingRefundableAmount(expense(amount: 100), <LedgerEntry>[
        refund('r1', 60),
        refund('r2', 70),
      ]),
      0,
    );

    final income = expense(amount: 100);
    expect(
      remainingRefundableAmount(
        LedgerEntry(
          id: income.id,
          bookId: income.bookId,
          type: EntryType.income,
          amount: income.amount,
          categoryId: income.categoryId,
          accountId: income.accountId,
          note: income.note,
          occurredAt: income.occurredAt,
        ),
        <LedgerEntry>[refund('r1', 10)],
      ),
      0,
    );
  });

  test('零位与三位小数币种按各自 minor unit 归一化', () {
    expect(
      remainingRefundableAmount(
        expense(amount: 1000, currencyCode: 'JPY'),
        <LedgerEntry>[refund('r1', 333, currencyCode: 'JPY')],
      ),
      667,
    );
    expect(
      remainingRefundableAmount(
        expense(amount: 1.005, currencyCode: 'KWD'),
        <LedgerEntry>[refund('r1', 0.001, currencyCode: 'KWD')],
      ),
      1.004,
    );
  });
}
