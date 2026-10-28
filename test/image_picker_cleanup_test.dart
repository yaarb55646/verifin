import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:verifin/app/image_picker_cleanup_io.dart';

void main() {
  test('image picker copy is deleted without touching other paths', () async {
    final directory = await Directory.systemTemp.createTemp(
      'verifin_picker_cleanup',
    );
    addTearDown(() => directory.delete(recursive: true));
    final picked = File('${directory.path}${Platform.pathSeparator}picked.jpg');
    final original = File(
      '${directory.path}${Platform.pathSeparator}original.jpg',
    );
    await picked.writeAsBytes(<int>[1, 2, 3]);
    await original.writeAsBytes(<int>[4, 5, 6]);

    await discardImagePickerPath(picked.path);

    expect(await picked.exists(), isFalse);
    expect(await original.exists(), isTrue);
  });

  test('missing or null picker paths are ignored', () async {
    await discardImagePickerPath(null);
    await discardImagePickerPath('');
    await discardImagePickerPath(
      '${Directory.systemTemp.path}${Platform.pathSeparator}missing.jpg',
    );
  });
}
