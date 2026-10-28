import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verifin/app/attachments/attachment_store.dart';
import 'package:verifin/app/backup/backup_archive.dart';

void main() {
  test('attachment ids reject path separators and traversal', () {
    expect(isValidAttachmentId('att-1'), isTrue);
    expect(isValidAttachmentId('attachment_2026.10.18'), isTrue);
    expect(isValidAttachmentId('../escape'), isFalse);
    expect(isValidAttachmentId('a/b'), isFalse);
    expect(isValidAttachmentId(r'a\b'), isFalse);
    expect(isValidAttachmentId('..'), isFalse);
    expect(isValidAttachmentId(''), isFalse);
  });

  test('FileAttachmentStore never writes outside its root', () async {
    final temp = await Directory.systemTemp.createTemp('verifin_path_test');
    addTearDown(() => temp.delete(recursive: true));
    final store = FileAttachmentStore(
      root: Directory('${temp.path}${Platform.pathSeparator}attachments'),
    );

    await expectLater(
      store.writeBytes('../escaped.bin', <int>[1, 2, 3]),
      throwsA(isA<FormatException>()),
    );
    expect(
      File('${temp.path}${Platform.pathSeparator}escaped.bin').existsSync(),
      isFalse,
    );
  });

  test('ZIP path traversal is rejected before writing attachments', () async {
    final temp = await Directory.systemTemp.createTemp('verifin_zip_path');
    addTearDown(() => temp.delete(recursive: true));
    final archivePath = '${temp.path}${Platform.pathSeparator}backup.zip';
    final archive = Archive()
      ..addFile(ArchiveFile('attachments/../escaped.bin', 3, <int>[1, 2, 3]))
      ..addFile(
        ArchiveFile.string(
          backupJsonEntryName,
          jsonEncode(<String, Object?>{
            'app': 'verifin',
            'version': 4,
            'data': <String, Object?>{'attachments': <Object?>[]},
          }),
        ),
      );
    await File(archivePath).writeAsBytes(ZipEncoder().encode(archive));

    await expectLater(
      unpackBackupArchiveFile(
        archivePath: archivePath,
        sink: InMemoryAttachmentStore(),
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('oversized archive entries are rejected before decompression', () async {
    final temp = await Directory.systemTemp.createTemp('verifin_zip_size');
    addTearDown(() => temp.delete(recursive: true));
    final archivePath = '${temp.path}${Platform.pathSeparator}backup.zip';
    final archive = Archive()
      ..addFile(
        ArchiveFile(
          'attachments/too-large.bin',
          maxBackupAttachmentBytes + 1,
          <int>[1],
        ),
      )
      ..addFile(
        ArchiveFile.string(
          backupJsonEntryName,
          jsonEncode(<String, Object?>{
            'app': 'verifin',
            'version': 4,
            'data': <String, Object?>{'attachments': <Object?>[]},
          }),
        ),
      );
    await File(archivePath).writeAsBytes(ZipEncoder().encode(archive));

    await expectLater(
      unpackBackupArchiveFile(
        archivePath: archivePath,
        sink: InMemoryAttachmentStore(),
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('legacy attachment ids are validated before extraction', () async {
    final legacy = jsonEncode(<String, Object?>{
      'app': 'verifin',
      'version': 2,
      'data': <String, Object?>{
        'attachments': <Object?>[
          <String, Object?>{
            'id': '../escape',
            'dataUrl': 'data:image/jpeg;base64,${base64Encode(<int>[1, 2])}',
          },
        ],
      },
    });
    final sink = InMemoryAttachmentStore();

    await expectLater(
      extractLegacyAttachments(legacy, sink),
      throwsA(isA<FormatException>()),
    );
  });
}
