import 'dart:async';
import 'dart:convert';

import 'ai_agent_event.dart';
import 'ai_agent_message.dart';
import 'ai_completion_event.dart';
import 'ai_error.dart';
import 'ai_native_tool_protocol.dart';
import 'ai_prompt_tool_protocol.dart';
import 'ai_query_tool.dart';
import 'ai_settings.dart';

typedef AiAgentStreamTransport =
    Stream<AiCompletionEvent> Function(
      List<AiAgentMessage> messages,
      List<Map<String, Object?>> tools,
    );

typedef AiAgentCompleteTransport =
    Future<AiCompletionResult> Function(
      List<AiAgentMessage> messages,
      List<Map<String, Object?>> tools,
    );

class AiAgentCancellation {
  final Completer<void> _completer = Completer<void>();

  bool get isCancelled => _completer.isCompleted;

  Future<void> get whenCancelled => _completer.future;

  void cancel() {
    if (!_completer.isCompleted) {
      _completer.complete();
    }
  }
}

/// 只读财务 Agent。协议差异只负责编解码，工具执行、轮次、边界和 UI 事件共用此状态机。
class AiAgentEngine {
  const AiAgentEngine({
    required this.tools,
    this.maxToolRounds = 5,
    this.maxToolCalls = 10,
    this.maxPriorMessages = 12,
    this.maxPriorCharacters = 12000,
    this.maxToolSummaryCharacters = 4000,
    this.maxAnswerCharacters = 50000,
    this.maxUserInputCharacters = 8000,
    this.maxToolArgumentsCharacters = 32000,
    this.maxToolArgumentsTotalCharacters = 64000,
    this.maxReasoningCharacters = 64000,
    this.maxTurnRequestCharacters = 256000,
  });

  final List<AiQueryTool> tools;
  final int maxToolRounds;
  final int maxToolCalls;
  final int maxPriorMessages;
  final int maxPriorCharacters;
  final int maxToolSummaryCharacters;
  final int maxAnswerCharacters;
  final int maxUserInputCharacters;
  final int maxToolArgumentsCharacters;
  final int maxToolArgumentsTotalCharacters;
  final int maxReasoningCharacters;
  final int maxTurnRequestCharacters;

  Stream<AiAgentEvent> run({
    required AiToolCallMode mode,
    required AiAgentStreamTransport streamTransport,
    AiAgentCompleteTransport? completeTransport,
    required AiToolContext context,
    required List<AiTextMessage> priorMessages,
    required String userInput,
    AiAgentCancellation? cancellation,
  }) async* {
    if (userInput.length > maxUserInputCharacters) {
      yield AiAgentFailed(
        AiException(AiErrorCode.requestTooLarge, detail: 'user input too long'),
      );
      return;
    }
    final initialProtocol = mode == AiToolCallMode.prompt
        ? _AgentProtocol.prompt
        : _AgentProtocol.native;
    try {
      await for (final event in _runProtocol(
        protocol: initialProtocol,
        streamTransport: streamTransport,
        completeTransport: completeTransport,
        context: context,
        priorMessages: priorMessages,
        userInput: userInput,
        cancellation: cancellation,
      )) {
        yield event;
      }
      return;
    } catch (error) {
      final canDowngrade =
          mode == AiToolCallMode.auto &&
          initialProtocol == _AgentProtocol.native &&
          error is AiException &&
          error.code == AiErrorCode.protocolUnsupported;
      if (!canDowngrade) {
        yield AiAgentFailed(error);
        return;
      }
    }

    yield const AiAgentRetrying(
      attempt: 1,
      reason: AiAgentRetryReason.protocolFallback,
    );
    try {
      await for (final event in _runProtocol(
        protocol: _AgentProtocol.prompt,
        streamTransport: streamTransport,
        completeTransport: completeTransport,
        context: context,
        priorMessages: priorMessages,
        userInput: userInput,
        cancellation: cancellation,
      )) {
        yield event;
      }
    } catch (error) {
      yield AiAgentFailed(error);
    }
  }

  Stream<AiAgentEvent> _runProtocol({
    required _AgentProtocol protocol,
    required AiAgentStreamTransport streamTransport,
    required AiAgentCompleteTransport? completeTransport,
    required AiToolContext context,
    required List<AiTextMessage> priorMessages,
    required String userInput,
    AiAgentCancellation? cancellation,
  }) async* {
    final nativeDefinitions = protocol == _AgentProtocol.native
        ? tools.map((tool) => tool.toNativeDefinition()).toList(growable: false)
        : const <Map<String, Object?>>[];
    final systemPrompt = protocol == _AgentProtocol.native
        ? buildAgentSystemPrompt(context)
        : buildPromptAgentSystemPrompt(context, tools);
    final messages = <AiAgentMessage>[
      AiTextMessage.system(systemPrompt),
      ..._boundedPrior(priorMessages),
      AiTextMessage.user(userInput),
    ];
    var toolCallCount = 0;
    var successfulToolCallCount = 0;
    var retryUsed = false;
    var answerCharacters = 0;
    var toolArgumentCharacters = 0;
    var reasoningCharacters = 0;
    var anyToolExecuted = false;

    for (var round = 0; round <= maxToolRounds; round += 1) {
      if (cancellation?.isCancelled == true) return;
      _ensureRequestFits(messages, nativeDefinitions);
      final accumulator = AiNativeCompletionAccumulator();
      var visibleAnswerWritten = false;
      late AiCompletionResult response;
      try {
        final iterator = StreamIterator(
          streamTransport(messages, nativeDefinitions),
        );
        try {
          while (true) {
            final hasNext = cancellation == null
                ? await iterator.moveNext()
                : await Future.any(<Future<bool>>[
                    iterator.moveNext(),
                    cancellation.whenCancelled.then((_) => false),
                  ]);
            if (cancellation?.isCancelled == true) return;
            if (!hasNext) break;
            final event = iterator.current;
            if (protocol == _AgentProtocol.native &&
                event is AiContentDelta &&
                event.text.isNotEmpty) {
              answerCharacters += event.text.length;
              _checkAnswerLength(answerCharacters);
              visibleAnswerWritten = true;
              yield AiAgentAnswerDelta(event.text);
            }
            accumulator.add(event);
          }
          response = accumulator.build();
        } finally {
          await iterator.cancel();
        }
      } catch (error) {
        final canRetry =
            !visibleAnswerWritten &&
            !anyToolExecuted &&
            completeTransport != null &&
            !retryUsed &&
            _isTransient(error);
        if (!canRetry) {
          if (protocol == _AgentProtocol.native &&
              error is AiException &&
              error.code == AiErrorCode.protocolUnsupported &&
              (visibleAnswerWritten || anyToolExecuted)) {
            throw AiException(
              AiErrorCode.badResponse,
              detail: 'native protocol failed after output',
            );
          }
          rethrow;
        }
        retryUsed = true;
        yield const AiAgentRetrying(
          attempt: 1,
          reason: AiAgentRetryReason.network,
        );
        response = await completeTransport(messages, nativeDefinitions);
        if (cancellation?.isCancelled == true) return;
      }

      if (response.finishReason == AiFinishReason.insufficientSystemResource &&
          completeTransport != null &&
          !retryUsed &&
          !visibleAnswerWritten &&
          !anyToolExecuted) {
        retryUsed = true;
        yield const AiAgentRetrying(
          attempt: 1,
          reason: AiAgentRetryReason.upstreamResource,
        );
        response = await completeTransport(messages, nativeDefinitions);
        if (cancellation?.isCancelled == true) return;
      }

      if (protocol == _AgentProtocol.native &&
          !visibleAnswerWritten &&
          response.content.isNotEmpty) {
        answerCharacters += response.content.length;
        _checkAnswerLength(answerCharacters);
        visibleAnswerWritten = true;
        yield AiAgentAnswerDelta(response.content);
      }
      reasoningCharacters += response.reasoningContent.length;
      if (reasoningCharacters > maxReasoningCharacters) {
        throw AiException(
          AiErrorCode.responseTooLarge,
          detail: 'reasoning too large',
        );
      }

      if (protocol == _AgentProtocol.native && response.toolCalls.isNotEmpty) {
        if (response.finishReason == AiFinishReason.length) {
          throw AiException(
            AiErrorCode.badResponse,
            detail: 'truncated tool call',
          );
        }
        if (round >= maxToolRounds) {
          throw AiException(
            AiErrorCode.badResponse,
            detail: 'tool round limit exceeded',
          );
        }
        messages.add(
          AiAssistantToolMessage(
            content: response.content.isEmpty ? null : response.content,
            reasoningContent: response.reasoningContent.isEmpty
                ? null
                : response.reasoningContent,
            toolCalls: response.toolCalls,
          ),
        );
        for (
          var callIndex = 0;
          callIndex < response.toolCalls.length;
          callIndex += 1
        ) {
          final call = response.toolCalls[callIndex];
          if (cancellation?.isCancelled == true) return;
          toolCallCount += 1;
          if (toolCallCount > maxToolCalls) {
            throw AiException(
              AiErrorCode.badResponse,
              detail: 'tool call limit exceeded',
            );
          }
          toolArgumentCharacters += call.arguments.length;
          _checkToolArgumentSize(
            call.arguments.length,
            cumulative: toolArgumentCharacters,
          );
          final decodedArguments = call.decodeArguments();
          final arguments = decodedArguments ?? <String, Object?>{};
          final stepId = 'native-$round-${callIndex + 1}';
          yield AiAgentToolStarted(
            stepId: stepId,
            toolName: call.name,
            arguments: arguments,
          );
          final execution = decodedArguments == null
              ? const _ToolExecution.failed(
                  reason: 'invalidArguments',
                  modelMessage: '工具参数不是有效的 JSON 对象，请修正参数后重试。',
                )
              : _execute(call.name, arguments, context);
          anyToolExecuted = true;
          if (execution.result == null) {
            yield AiAgentToolFailed(
              stepId: stepId,
              toolName: call.name,
              arguments: arguments,
              reason: execution.failureReason!,
            );
            messages.add(
              AiToolResultMessage(
                toolCallId: call.id,
                content: execution.modelMessage,
              ),
            );
          } else {
            successfulToolCallCount += 1;
            yield AiAgentToolCompleted(
              stepId: stepId,
              toolName: call.name,
              arguments: arguments,
              result: execution.result!,
              duration: execution.duration,
            );
            messages.add(
              AiToolResultMessage(
                toolCallId: call.id,
                content: _truncateSummary(execution.result!.summary),
              ),
            );
          }
        }
        continue;
      }

      if (protocol == _AgentProtocol.prompt) {
        if (response.content.length > maxAnswerCharacters) {
          throw AiException(
            AiErrorCode.responseTooLarge,
            detail: 'prompt response too large',
          );
        }
        final parsed = parsePromptResponse(
          response.content,
          knownTools: tools.map((tool) => tool.name).toSet(),
        );
        if (parsed is AiPromptToolCall) {
          if (cancellation?.isCancelled == true) return;
          if (round >= maxToolRounds || ++toolCallCount > maxToolCalls) {
            throw AiException(
              AiErrorCode.badResponse,
              detail: 'tool limit exceeded',
            );
          }
          final stepId = 'prompt-$round-$toolCallCount';
          final argumentText = jsonEncode(parsed.arguments);
          toolArgumentCharacters += argumentText.length;
          _checkToolArgumentSize(
            argumentText.length,
            cumulative: toolArgumentCharacters,
          );
          yield AiAgentToolStarted(
            stepId: stepId,
            toolName: parsed.name,
            arguments: parsed.arguments,
          );
          final execution = _execute(parsed.name, parsed.arguments, context);
          anyToolExecuted = true;
          messages.add(AiTextMessage.assistant(response.content));
          if (execution.result == null) {
            yield AiAgentToolFailed(
              stepId: stepId,
              toolName: parsed.name,
              arguments: parsed.arguments,
              reason: execution.failureReason!,
            );
            messages.add(
              AiTextMessage.user(
                'VERIFIN_TOOL_RESULT\n${execution.modelMessage}',
              ),
            );
          } else {
            successfulToolCallCount += 1;
            yield AiAgentToolCompleted(
              stepId: stepId,
              toolName: parsed.name,
              arguments: parsed.arguments,
              result: execution.result!,
              duration: execution.duration,
            );
            messages.add(
              AiTextMessage.user(
                'VERIFIN_TOOL_RESULT\n'
                '${_truncateSummary(execution.result!.summary)}',
              ),
            );
          }
          continue;
        }
        if (parsed is AiPromptAnswer) {
          if (cancellation?.isCancelled == true) return;
          yield* _answerEvents(
            parsed.text,
            response.finishReason,
            attemptedToolCalls: toolCallCount,
            successfulToolCalls: successfulToolCallCount,
          );
          return;
        }
      } else {
        if (cancellation?.isCancelled == true) return;
        final answer = response.content.trim();
        if (answer.isEmpty) {
          throw AiException(AiErrorCode.badResponse, detail: 'empty answer');
        }
        if (response.finishReason == AiFinishReason.length) {
          yield AiAgentFailed(
            AiException(AiErrorCode.badResponse, detail: 'response truncated'),
            partialAnswer: answer,
          );
          return;
        }
        if (response.finishReason == AiFinishReason.contentFilter) {
          yield AiAgentFailed(
            AiException(AiErrorCode.upstream, detail: 'content filtered'),
            partialAnswer: answer,
          );
          return;
        }
        yield AiAgentCompleted(
          answer,
          attemptedToolCalls: toolCallCount,
          successfulToolCalls: successfulToolCallCount,
        );
        return;
      }
    }
  }

  void _checkAnswerLength(int characters) {
    if (characters > maxAnswerCharacters) {
      throw AiException(
        AiErrorCode.responseTooLarge,
        detail: 'answer too large',
      );
    }
  }

  void _checkToolArgumentSize(int characters, {required int cumulative}) {
    if (characters > maxToolArgumentsCharacters ||
        cumulative > maxToolArgumentsTotalCharacters) {
      throw AiException(
        AiErrorCode.requestTooLarge,
        detail: 'tool arguments too large',
      );
    }
  }

  void _ensureRequestFits(
    List<AiAgentMessage> messages,
    List<Map<String, Object?>> tools,
  ) {
    final messageCharacters = messages.fold<int>(
      0,
      (sum, message) => sum + jsonEncode(message.toJson()).length,
    );
    final toolCharacters = tools.isEmpty ? 0 : jsonEncode(tools).length;
    if (messageCharacters + toolCharacters > maxTurnRequestCharacters) {
      throw AiException(
        AiErrorCode.requestTooLarge,
        detail: 'agent request too large',
      );
    }
  }

  Stream<AiAgentEvent> _answerEvents(
    String rawAnswer,
    AiFinishReason finishReason, {
    required int attemptedToolCalls,
    required int successfulToolCalls,
  }) async* {
    final answer = rawAnswer.trim();
    if (answer.isEmpty) {
      throw AiException(AiErrorCode.badResponse, detail: 'empty answer');
    }
    _checkAnswerLength(answer.length);
    if (_containsToolProtocol(answer)) {
      throw AiException(AiErrorCode.badResponse, detail: 'tool protocol leak');
    }
    yield AiAgentAnswerDelta(answer);
    if (finishReason == AiFinishReason.length) {
      yield AiAgentFailed(
        AiException(AiErrorCode.badResponse, detail: 'response truncated'),
        partialAnswer: answer,
      );
      return;
    }
    if (finishReason == AiFinishReason.contentFilter) {
      yield AiAgentFailed(
        AiException(AiErrorCode.upstream, detail: 'content filtered'),
        partialAnswer: answer,
      );
      return;
    }
    yield AiAgentCompleted(
      answer,
      attemptedToolCalls: attemptedToolCalls,
      successfulToolCalls: successfulToolCalls,
    );
  }

  List<AiTextMessage> _boundedPrior(List<AiTextMessage> priorMessages) {
    final selected = <AiTextMessage>[];
    var characters = 0;
    for (final message in priorMessages.reversed) {
      if (selected.length >= maxPriorMessages) break;
      if (characters + message.content.length > maxPriorCharacters) break;
      selected.insert(0, message);
      characters += message.content.length;
    }
    while (selected.isNotEmpty &&
        selected.first.role == AiMessageRole.assistant) {
      selected.removeAt(0);
    }
    return selected;
  }

  _ToolExecution _execute(
    String toolName,
    Map<String, Object?> arguments,
    AiToolContext context,
  ) {
    final tool = _toolNamed(toolName);
    if (tool == null) {
      return const _ToolExecution.failed(
        reason: 'unknownTool',
        modelMessage: '工具不存在，请选择已提供的工具。',
      );
    }
    final validation = tool.schema.validateArguments(arguments);
    if (!validation.isValid) {
      return _ToolExecution.failed(
        reason: 'invalidArguments',
        modelMessage:
            '工具参数无效：${validation.issues.take(5).join('；')}。'
            '请修正参数后重试。',
      );
    }
    final stopwatch = Stopwatch()..start();
    try {
      final result = tool.run(context, validation.normalizedArguments);
      stopwatch.stop();
      return _ToolExecution.succeeded(result, stopwatch.elapsed);
    } catch (_) {
      stopwatch.stop();
      return _ToolExecution.failed(
        reason: 'executionFailed',
        modelMessage: '工具执行失败，请换一种查询方式。',
        duration: stopwatch.elapsed,
      );
    }
  }

  AiQueryTool? _toolNamed(String name) {
    for (final tool in tools) {
      if (tool.name == name) return tool;
    }
    return null;
  }

  String _truncateSummary(String summary) {
    if (summary.length <= maxToolSummaryCharacters) return summary;
    return '${summary.substring(0, maxToolSummaryCharacters)}\n[结果已截断]';
  }
}

enum _AgentProtocol { native, prompt }

class _ToolExecution {
  const _ToolExecution.succeeded(this.result, this.duration)
    : failureReason = null,
      modelMessage = '';

  const _ToolExecution.failed({
    required String reason,
    required this.modelMessage,
    this.duration = Duration.zero,
  }) : result = null,
       failureReason = reason;

  final AiToolResult? result;
  final String? failureReason;
  final String modelMessage;
  final Duration duration;
}

bool _isTransient(Object error) {
  if (error is! AiException) return false;
  return switch (error.code) {
    AiErrorCode.timeout ||
    AiErrorCode.network ||
    AiErrorCode.serverError ||
    AiErrorCode.incompleteStream => true,
    _ => false,
  };
}

bool _containsToolProtocol(String answer) {
  return answer.contains(aiPromptToolMarker) ||
      answer.contains('"tool"') ||
      answer.contains('tool_calls') ||
      answer.contains('reasoning_content');
}
