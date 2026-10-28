import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:verifin/local_storage/local_storage.dart';

import 'support/test_harness.dart';

void main() {
  useTestDatabases();

  test('旧版 AI 聊天 KV 只清理，不迁移也不恢复', () async {
    final store = LocalKeyValueStore();
    store.write(
      'verifin.ai_chat.v1',
      jsonEncode(<Map<String, Object?>>[
        <String, Object?>{'role': 'user', 'content': '旧版聊天'},
      ]),
    );

    final controller = await makeController(store);

    expect(store.read('verifin.ai_chat.v1'), isNull);
    controller.dispose();
  });
}
