import 'ai_agent_message.dart';
import 'ai_completion_event.dart';
import 'ai_error.dart';

/// 把一个完整 SSE round 的结构化增量归并为补全结果。
AiCompletionResult collectNativeCompletion(Iterable<AiCompletionEvent> events) {
  final accumulator = AiNativeCompletionAccumulator();
  for (final event in events) {
    accumulator.add(event);
  }
  return accumulator.build();
}

/// 增量归并一轮原生 SSE。Agent 可在正文增量到达时立即下发，同时继续累积
/// Tool Call 分片与结束原因。
class AiNativeCompletionAccumulator {
  final StringBuffer _content = StringBuffer();
  final StringBuffer _reasoning = StringBuffer();
  final Map<int, _ToolCallBuilder> _calls = <int, _ToolCallBuilder>{};
  AiFinishReason _finishReason = AiFinishReason.other;

  void add(AiCompletionEvent event) {
    switch (event) {
      case AiContentDelta():
        _content.write(event.text);
      case AiReasoningDelta():
        _reasoning.write(event.text);
      case AiToolCallDelta():
        _calls.putIfAbsent(event.index, _ToolCallBuilder.new).append(event);
      case AiCompletionFinished():
        _finishReason = event.reason;
      case AiStreamDone():
        break;
    }
  }

  AiCompletionResult build() {
    final toolCalls = <AiNativeToolCall>[];
    for (final index in _calls.keys.toList()..sort()) {
      final call = _calls[index]!.build();
      if (call == null) {
        throw AiException(
          AiErrorCode.badResponse,
          detail: 'incomplete tool call',
        );
      }
      toolCalls.add(call);
    }
    if (_finishReason == AiFinishReason.toolCalls && toolCalls.isEmpty) {
      throw AiException(AiErrorCode.badResponse, detail: 'missing tool call');
    }
    return AiCompletionResult(
      content: _content.toString(),
      reasoningContent: _reasoning.toString(),
      toolCalls: toolCalls,
      finishReason: _finishReason,
    );
  }
}

class _ToolCallBuilder {
  final StringBuffer _name = StringBuffer();
  final StringBuffer _arguments = StringBuffer();
  String? _id;

  void append(AiToolCallDelta delta) {
    final id = delta.id;
    if (id != null && id.isNotEmpty) _id ??= id;
    final name = delta.name;
    if (name != null) _name.write(name);
    final arguments = delta.arguments;
    if (arguments != null) _arguments.write(arguments);
  }

  AiNativeToolCall? build() {
    final id = _id;
    final name = _name.toString().trim();
    if (id == null || id.isEmpty || name.isEmpty) return null;
    return AiNativeToolCall(
      id: id,
      name: name,
      arguments: _arguments.isEmpty ? '{}' : _arguments.toString(),
    );
  }
}
