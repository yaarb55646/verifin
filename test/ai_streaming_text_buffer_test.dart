import 'package:flutter_test/flutter_test.dart';
import 'package:verifin/app/ai/ai_streaming_text_buffer.dart';

void main() {
  test('coalesces timer-driven deltas into one flush', () async {
    final flushed = <String>[];
    final buffer = AiStreamingTextBuffer(
      flushInterval: const Duration(milliseconds: 5),
      onFlush: flushed.add,
    );
    buffer
      ..add('你')
      ..add('好');
    expect(flushed, isEmpty);

    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(flushed, <String>['你好']);
    buffer.dispose();
  });

  test('large buffered content flushes immediately', () {
    final flushed = <String>[];
    final buffer = AiStreamingTextBuffer(
      maxBufferedCharacters: 4,
      onFlush: flushed.add,
    );
    buffer.add('abcd');
    expect(flushed, <String>['abcd']);
    buffer.dispose();
  });

  test('explicit flush and dispose are safe', () {
    final flushed = <String>[];
    final buffer = AiStreamingTextBuffer(onFlush: flushed.add);
    buffer.add('partial');
    buffer.flush();
    buffer.flush();
    buffer.dispose();
    buffer.add('ignored');
    expect(flushed, <String>['partial']);
  });
}
