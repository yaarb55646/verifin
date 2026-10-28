import 'dart:async';

/// 合并高频流式正文增量，避免每个 token 都触发一次页面重建。
class AiStreamingTextBuffer {
  AiStreamingTextBuffer({
    required this.onFlush,
    this.flushInterval = const Duration(milliseconds: 50),
    this.maxBufferedCharacters = 2000,
  });

  final void Function(String text) onFlush;
  final Duration flushInterval;
  final int maxBufferedCharacters;

  final StringBuffer _pending = StringBuffer();
  Timer? _timer;
  bool _disposed = false;

  int get bufferedCharacters => _pending.length;

  void add(String text) {
    if (_disposed || text.isEmpty) return;
    _pending.write(text);
    if (_pending.length >= maxBufferedCharacters) {
      flush();
      return;
    }
    _timer ??= Timer(flushInterval, flush);
  }

  void flush() {
    _timer?.cancel();
    _timer = null;
    if (_disposed || _pending.isEmpty) return;
    final text = _pending.toString();
    _pending.clear();
    onFlush(text);
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    _pending.clear();
  }
}
