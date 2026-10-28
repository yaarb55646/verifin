import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:verifin/app/attachments/attachment_store.dart';
import 'package:verifin/app/models.dart';
import 'package:verifin/data/ledger_repository.dart';
import 'package:verifin/local_storage/local_storage.dart';

import 'support/in_memory_ledger_repository.dart';
import 'support/test_harness.dart';

class _FailingReplaceRepository extends InMemoryLedgerRepository {
  bool failReplace = false;

  @override
  Future<void> replaceAllLedgerData(LedgerDataSnapshot snapshot) async {
    if (failReplace) {
      throw StateError('disk full');
    }
    await super.replaceAllLedgerData(snapshot);
  }
}

void main() {
  useTestDatabases();

  test(
    'reset keeps memory and disk unchanged when replacement fails',
    () async {
      final repository = _FailingReplaceRepository();
      final controller = await createTestController(
        LocalKeyValueStore(),
        repository: repository,
      );
      addTearDown(controller.dispose);
      controller.addEntry(
        LedgerEntry(
          id: 'keep-me',
          bookId: defaultLedgerBookId,
          type: EntryType.expense,
          amount: 8,
          categoryId: '',
          accountId: '',
          note: 'before reset',
          occurredAt: DateTime(2026, 10, 18),
        ),
      );
      await controller.waitForPendingWrites();
      controller.onPersistError = (_) {};
      repository.failReplace = true;

      expect(await controller.resetAllData(), isFalse);
      expect(controller.entries.single.id, 'keep-me');
      expect((await repository.loadEntries()).single.id, 'keep-me');
    },
  );

  test(
    'import keeps memory and disk unchanged when replacement fails',
    () async {
      final repository = _FailingReplaceRepository();
      final controller = await createTestController(
        LocalKeyValueStore(),
        repository: repository,
      );
      addTearDown(controller.dispose);
      final backup =
          jsonDecode(controller.exportDataJson()) as Map<String, Object?>;
      final data = Map<String, Object?>.from(
        backup['data']! as Map<dynamic, dynamic>,
      );
      data['entries'] = <Object?>[
        LedgerEntry(
          id: 'imported',
          bookId: defaultLedgerBookId,
          type: EntryType.expense,
          amount: 12,
          currencyCode: defaultCurrencyCode,
          accountAmount: null,
          baseAmount: 12,
          conversionSource: ConversionSource.identity,
          categoryId: '',
          accountId: '',
          note: 'imported',
          occurredAt: DateTime(2026, 10, 18),
        ).toJson(),
      ];
      backup['data'] = data;
      controller.onPersistError = (_) {};
      repository.failReplace = true;

      await expectLater(
        controller.importDataJson(jsonEncode(backup)),
        throwsA(isA<StateError>()),
      );
      expect(controller.entries, isEmpty);
      expect(await repository.loadEntries(), isEmpty);
    },
  );

  test('deleting a ledger keeps it when replacement fails', () async {
    final repository = _FailingReplaceRepository();
    final controller = await createTestController(
      LocalKeyValueStore(),
      repository: repository,
    );
    addTearDown(controller.dispose);
    controller.addLedgerBook('Travel');
    await controller.waitForPendingWrites();
    final bookId = controller.activeBook.id;
    controller.onPersistError = (_) {};
    repository.failReplace = true;

    expect(await controller.deleteLedgerBook(bookId), isFalse);
    expect(controller.ledgerBooks.any((book) => book.id == bookId), isTrue);
  });

  test(
    'confirmed bill import keeps memory unchanged when replacement fails',
    () async {
      final repository = _FailingReplaceRepository();
      final controller = await createTestController(
        LocalKeyValueStore(),
        repository: repository,
      );
      addTearDown(controller.dispose);
      controller.onPersistError = (_) {};
      repository.failReplace = true;

      expect(
        await controller.applyImportEntries(
          entries: <LedgerEntry>[
            LedgerEntry(
              id: 'import-fail',
              bookId: defaultLedgerBookId,
              type: EntryType.expense,
              amount: 3,
              currencyCode: defaultCurrencyCode,
              accountAmount: null,
              baseAmount: 3,
              conversionSource: ConversionSource.identity,
              categoryId: '',
              accountId: '',
              note: 'import',
              occurredAt: DateTime(2026, 10, 18),
            ),
          ],
          candidateAccounts: const <Account>[],
          candidateCategories: const <Category>[],
        ),
        isFalse,
      );
      expect(controller.entries, isEmpty);
    },
  );

  test('reset removes attachment files after clearing metadata', () async {
    final repository = _FailingReplaceRepository();
    final store = InMemoryAttachmentStore();
    final controller = await createTestController(
      LocalKeyValueStore(),
      repository: repository,
      attachmentStore: store,
    );
    addTearDown(controller.dispose);
    controller.addEntry(
      LedgerEntry(
        id: 'entry-with-attachment',
        bookId: defaultLedgerBookId,
        type: EntryType.expense,
        amount: 8,
        categoryId: '',
        accountId: '',
        note: 'attachment',
        occurredAt: DateTime(2026, 10, 18),
      ),
    );
    await controller.waitForPendingWrites();
    await controller.addAttachment(
      'entry-with-attachment',
      Uint8List.fromList(<int>[1, 2, 3]),
    );
    await controller.waitForPendingWrites();
    final attachmentId = controller
        .attachmentsForEntry('entry-with-attachment')
        .single
        .id;

    expect(await controller.resetAllData(), isTrue);
    expect(store.existsSync(attachmentId), isFalse);
  });

  test('failed import does not overwrite an existing attachment id', () async {
    final repository = _FailingReplaceRepository();
    final store = InMemoryAttachmentStore();
    final controller = await createTestController(
      LocalKeyValueStore(),
      repository: repository,
      attachmentStore: store,
    );
    addTearDown(controller.dispose);
    controller.addEntry(
      LedgerEntry(
        id: 'existing-entry',
        bookId: defaultLedgerBookId,
        type: EntryType.expense,
        amount: 8,
        categoryId: '',
        accountId: '',
        note: 'existing',
        occurredAt: DateTime(2026, 10, 18),
      ),
    );
    await controller.waitForPendingWrites();
    final originalBytes = Uint8List.fromList(<int>[1, 2, 3]);
    await controller.addAttachment('existing-entry', originalBytes);
    await controller.waitForPendingWrites();
    final attachmentId = controller
        .attachmentsForEntry('existing-entry')
        .single
        .id;
    final backup =
        jsonDecode(controller.exportDataJson()) as Map<String, Object?>;
    controller.onPersistError = (_) {};
    repository.failReplace = true;

    await expectLater(
      controller.importDataJson(
        jsonEncode(backup),
        readStagedAttachment: (_) async =>
            Uint8List.fromList(<int>[9, 8, 7, 6]),
      ),
      throwsA(isA<StateError>()),
    );
    expect(await store.readBytes(attachmentId), originalBytes);
  });

  test('partial attachment materialization is cleaned up', () async {
    final repository = _FailingReplaceRepository();
    final store = InMemoryAttachmentStore();
    final controller = await createTestController(
      LocalKeyValueStore(),
      repository: repository,
      attachmentStore: store,
    );
    addTearDown(controller.dispose);
    final backup = <String, Object?>{
      'app': 'verifin',
      'version': 4,
      'data': <String, Object?>{
        'entries': <Object?>[
          LedgerEntry(
            id: 'entry',
            bookId: defaultLedgerBookId,
            type: EntryType.expense,
            amount: 8,
            currencyCode: defaultCurrencyCode,
            accountAmount: null,
            baseAmount: 8,
            conversionSource: ConversionSource.identity,
            categoryId: '',
            accountId: '',
            note: 'import',
            occurredAt: DateTime(2026, 10, 18),
          ).toJson(),
        ],
        'attachments': <Object?>[
          const Attachment(id: 'first', entryId: 'entry', byteSize: 1).toJson(),
          const Attachment(
            id: 'second',
            entryId: 'entry',
            byteSize: 1,
          ).toJson(),
        ],
      },
    };

    await expectLater(
      controller.importDataJson(
        jsonEncode(backup),
        readStagedAttachment: (id) async {
          if (id == 'first') {
            return Uint8List.fromList(<int>[1]);
          }
          throw const FormatException('missing');
        },
      ),
      throwsA(isA<FormatException>()),
    );
    expect(store.existsSync('first'), isFalse);
    expect(store.existsSync('second'), isFalse);
  });
}
