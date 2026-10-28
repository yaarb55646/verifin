import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:verifin/app/models.dart';
import 'package:verifin/data/app_database.dart';
import 'package:verifin/data/ledger_repository.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('incremental save aborts on a secondary unique conflict', () async {
    final database = await AppDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    addTearDown(database.close);
    final repository = SqliteLedgerRepository(database);
    final book = LedgerBook(
      id: 'book',
      name: 'Book',
      createdAt: DateTime(2026, 10, 18),
      isDefault: true,
    );
    const categoryA = Category(
      id: 'cat-a',
      bookId: 'book',
      label: 'A',
      type: EntryType.expense,
      iconCode: 'wallet',
    );
    const categoryB = Category(
      id: 'cat-b',
      bookId: 'book',
      label: 'B',
      type: EntryType.expense,
      iconCode: 'wallet',
    );

    await repository.saveBooks(<LedgerBook>[book]);
    await repository.saveCategories(<Category>[categoryA, categoryB]);
    await repository.loadCategories();

    await expectLater(
      repository.saveCategories(<Category>[
        categoryA,
        categoryB.copyWith(label: 'A'),
      ]),
      throwsA(isA<DatabaseException>()),
    );

    final rows = await database.db.query(
      'categories',
      columns: const <String>['id', 'label'],
      orderBy: 'id ASC',
    );
    expect(rows, hasLength(2));
    expect(rows.map((row) => row['label']), containsAll(<String>['A', 'B']));
  });
}
