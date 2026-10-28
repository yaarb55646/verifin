import 'package:flutter/foundation.dart' show visibleForTesting;

import '../budget_cycle.dart';
import '../ledger_math.dart';
import '../models.dart';

/// AI 只读预算快照。构造后不再读取 Controller 或 KV。
class AiBudgetSnapshot {
  AiBudgetSnapshot({
    required this.cycleStartDay,
    required Map<String, double> monthlyBudgetByMonth,
    required this.defaultMonthlyBudget,
    required Map<String, double> categoryBudgetByMonthAndCategory,
    required Map<String, double> defaultCategoryBudgetByCategory,
  }) : monthlyBudgetByMonth = Map<String, double>.unmodifiable(
         monthlyBudgetByMonth,
       ),
       categoryBudgetByMonthAndCategory = Map<String, double>.unmodifiable(
         categoryBudgetByMonthAndCategory,
       ),
       defaultCategoryBudgetByCategory = Map<String, double>.unmodifiable(
         defaultCategoryBudgetByCategory,
       );

  final int cycleStartDay;
  final Map<String, double> monthlyBudgetByMonth;
  final double defaultMonthlyBudget;
  final Map<String, double> categoryBudgetByMonthAndCategory;
  final Map<String, double> defaultCategoryBudgetByCategory;

  DateTime keyMonthOf(DateTime date) =>
      budgetCycleKeyMonthFor(date, cycleStartDay);

  DateWindow windowOf(DateTime keyMonth) =>
      budgetCycleOfKeyMonth(keyMonth, cycleStartDay);

  double monthlyBudgetOf(DateTime keyMonth) =>
      monthlyBudgetByMonth[_monthKey(keyMonth)] ?? defaultMonthlyBudget;

  double categoryBudgetOf(DateTime keyMonth, String categoryId) =>
      categoryBudgetByMonthAndCategory['${_monthKey(keyMonth)}:$categoryId'] ??
      defaultCategoryBudgetByCategory[categoryId] ??
      0;
}

/// Agent 一次 turn 使用的不可变账本快照。
///
/// 交易、账户、分类、标签、汇率、余额和预算都在发送时冻结。工具与展示层不得
/// 通过该快照访问 Controller、Repository 或任何可写端口。
class AiLedgerSnapshot {
  AiLedgerSnapshot({
    required this.bookId,
    required this.bookName,
    required this.baseCurrencyCode,
    required this.capturedAt,
    required Iterable<LedgerEntry> entries,
    required Iterable<Account> accounts,
    required Iterable<Category> categories,
    required Iterable<Tag> tags,
    required Iterable<ExchangeRate> exchangeRates,
    required Map<String, double> balanceByAccountId,
    this.budget,
  }) : entries = List<LedgerEntry>.unmodifiable(
         entries.toList(growable: false)..sort((a, b) {
           final byDate = b.occurredAt.compareTo(a.occurredAt);
           return byDate != 0 ? byDate : b.id.compareTo(a.id);
         }),
       ),
       accounts = List<Account>.unmodifiable(accounts),
       categories = List<Category>.unmodifiable(categories),
       tags = List<Tag>.unmodifiable(tags),
       exchangeRates = List<ExchangeRate>.unmodifiable(exchangeRates),
       balanceByAccountId = Map<String, double>.unmodifiable(
         balanceByAccountId,
       ),
       _accountsById = Map<String, Account>.unmodifiable({
         for (final account in accounts) account.id: account,
       }),
       _categoriesById = Map<String, Category>.unmodifiable({
         for (final category in categories) category.id: category,
       }),
       _tagsById = Map<String, Tag>.unmodifiable({
         for (final tag in tags) tag.id: tag,
       }) {
    _assertBookScope();
  }

  final String bookId;
  final String bookName;
  final String baseCurrencyCode;
  final DateTime capturedAt;
  final List<LedgerEntry> entries;
  final List<Account> accounts;
  final List<Category> categories;
  final List<Tag> tags;
  final List<ExchangeRate> exchangeRates;
  final Map<String, double> balanceByAccountId;
  final AiBudgetSnapshot? budget;
  final Map<String, Account> _accountsById;
  final Map<String, Category> _categoriesById;
  final Map<String, Tag> _tagsById;

  Account? accountById(String id) => _accountsById[id];

  Category? categoryById(String id) => _categoriesById[id];

  Tag? tagById(String id) => _tagsById[id];

  double balanceOf(Account account) {
    final balance = balanceByAccountId[account.id];
    if (balance == null) {
      throw StateError(
        'AI snapshot $bookId has no balance for account ${account.id}',
      );
    }
    return balance;
  }

  /// 测试专用：把调用方提供的余额函数一次求值成冻结 Map。
  @visibleForTesting
  factory AiLedgerSnapshot.forTesting({
    required String bookId,
    String bookName = '',
    String baseCurrencyCode = 'CNY',
    DateTime? capturedAt,
    Iterable<LedgerEntry> entries = const <LedgerEntry>[],
    Iterable<Account> accounts = const <Account>[],
    Iterable<Category> categories = const <Category>[],
    Iterable<Tag> tags = const <Tag>[],
    Iterable<ExchangeRate> exchangeRates = const <ExchangeRate>[],
    required double Function(Account account) balanceOf,
    AiBudgetSnapshot? budget,
  }) {
    final accountList = List<Account>.of(accounts);
    return AiLedgerSnapshot(
      bookId: bookId,
      bookName: bookName,
      baseCurrencyCode: baseCurrencyCode,
      capturedAt: capturedAt ?? DateTime.now(),
      entries: entries,
      accounts: accountList,
      categories: categories,
      tags: tags,
      exchangeRates: exchangeRates,
      balanceByAccountId: <String, double>{
        for (final account in accountList) account.id: balanceOf(account),
      },
      budget: budget,
    );
  }

  void _assertBookScope() {
    for (final entry in entries) {
      if (entry.bookId != bookId) {
        throw StateError('Entry ${entry.id} is outside AI snapshot book');
      }
    }
    for (final account in accounts) {
      if (account.bookId != bookId) {
        throw StateError('Account ${account.id} is outside AI snapshot book');
      }
    }
    for (final category in categories) {
      if (category.bookId != bookId) {
        throw StateError('Category ${category.id} is outside AI snapshot book');
      }
    }
    for (final tag in tags) {
      if (tag.bookId != bookId) {
        throw StateError('Tag ${tag.id} is outside AI snapshot book');
      }
    }
    for (final rate in exchangeRates) {
      if (rate.bookId != bookId) {
        throw StateError('Exchange rate $rate.id is outside AI snapshot book');
      }
    }
  }
}

String _monthKey(DateTime month) =>
    '${month.year}-${month.month.toString().padLeft(2, '0')}';
