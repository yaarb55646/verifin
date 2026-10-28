import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../../l10n/app_localizations.dart';
import 'ai_agent_engine.dart';
import 'ai_agent_event.dart';
import 'ai_agent_message.dart';
import 'ai_agent_step.dart';
import 'ai_answer_provenance.dart';
import 'ai_capabilities.dart';
import 'ai_error.dart';
import 'ai_ledger_snapshot.dart';
import 'ai_query_tool.dart';
import 'ai_settings.dart';
import 'ai_streaming_text_buffer.dart';
import 'ai_tool_presentation.dart';
import '../models.dart';

enum AiChatRole { user, assistant }

enum AiChatMessageStatus { streaming, done, error }

class AiChatMessage {
  AiChatMessage({
    required this.role,
    required this.bookId,
    required this.bookName,
    required this.baseCurrencyCode,
    required this.moneyCodeDisplay,
    this.text = '',
    this.status = AiChatMessageStatus.done,
    Iterable<AiResultDisplay> displays = const <AiResultDisplay>[],
    Iterable<AiAgentStep> steps = const <AiAgentStep>[],
    this.sourceUserInput = '',
    this.successfulToolCalls = 0,
    this.provenance,
    this.errorText,
  }) : displays = List<AiResultDisplay>.unmodifiable(displays),
       steps = List<AiAgentStep>.unmodifiable(steps);

  final AiChatRole role;
  final String bookId;
  final String bookName;
  final String baseCurrencyCode;
  final MoneyCodeDisplay moneyCodeDisplay;
  final String text;
  final AiChatMessageStatus status;
  final List<AiResultDisplay> displays;
  final List<AiAgentStep> steps;
  final String sourceUserInput;
  final int successfulToolCalls;
  final AiAnswerProvenance? provenance;
  final String? errorText;

  AiChatMessage copyWith({
    String? text,
    AiChatMessageStatus? status,
    Iterable<AiResultDisplay>? displays,
    Iterable<AiAgentStep>? steps,
    int? successfulToolCalls,
    AiAnswerProvenance? provenance,
    String? errorText,
  }) {
    return AiChatMessage(
      role: role,
      bookId: bookId,
      bookName: bookName,
      baseCurrencyCode: baseCurrencyCode,
      moneyCodeDisplay: moneyCodeDisplay,
      text: text ?? this.text,
      status: status ?? this.status,
      displays: displays ?? this.displays,
      steps: steps ?? this.steps,
      sourceUserInput: sourceUserInput,
      successfulToolCalls: successfulToolCalls ?? this.successfulToolCalls,
      provenance: provenance ?? this.provenance,
      errorText: errorText ?? this.errorText,
    );
  }
}

class AiChatRequest {
  const AiChatRequest({
    required this.text,
    required this.ledger,
    required this.l10n,
    required this.moneyCodeDisplay,
    required this.settings,
    required this.capability,
    required this.mode,
    required this.streamTransport,
    required this.completeTransport,
  });

  final String text;
  final AiLedgerSnapshot ledger;
  final AppLocalizations l10n;
  final MoneyCodeDisplay moneyCodeDisplay;
  final AiSettings settings;
  final AiCapabilityProfile? capability;
  final AiToolCallMode mode;
  final AiAgentStreamTransport streamTransport;
  final AiAgentCompleteTransport completeTransport;
}

typedef AiSessionCapabilityCallback =
    void Function(AiCapabilityProfile profile);
typedef AiSessionErrorCallback =
    void Function(String message, Object error, StackTrace? stackTrace);

/// 页面内存内的 AI 会话状态机。
///
/// 负责消息、流式生命周期、取消、重试和能力更新；不访问 BuildContext，
/// 也不持久化聊天内容。
class AiChatSessionController extends ChangeNotifier {
  AiChatSessionController({
    required this.engine,
    required this.onCapabilityDetected,
    required this.onError,
  });

  final AiAgentEngine engine;
  final AiSessionCapabilityCallback onCapabilityDetected;
  final AiSessionErrorCallback onError;

  final List<AiChatMessage> _messages = <AiChatMessage>[];
  String? _selectedBookId;
  int _requestSerial = 0;
  bool _streaming = false;
  int? _activeAssistantIndex;
  AiAgentCancellation? _activeCancellation;
  AiStreamingTextBuffer? _activeStreamBuffer;

  List<AiChatMessage> get messages =>
      UnmodifiableListView<AiChatMessage>(_messages);

  String? get selectedBookId => _selectedBookId;

  bool get isStreaming => _streaming;

  void ensureSelectedBook(String bookId) {
    _selectedBookId ??= bookId;
  }

  void selectBook(String bookId) {
    if (_streaming || bookId == _selectedBookId) return;
    _selectedBookId = bookId;
    notifyListeners();
  }

  void clear() {
    if (_streaming || _messages.isEmpty) return;
    _messages.clear();
    notifyListeners();
  }

  void send(AiChatRequest request) {
    final text = request.text.trim();
    if (text.isEmpty || _streaming) return;
    final priorMessages = _priorMessages();
    final assistant = AiChatMessage(
      role: AiChatRole.assistant,
      bookId: request.ledger.bookId,
      bookName: request.ledger.bookName,
      baseCurrencyCode: request.ledger.baseCurrencyCode,
      moneyCodeDisplay: request.moneyCodeDisplay,
      status: AiChatMessageStatus.streaming,
      sourceUserInput: text,
    );
    final requestId = ++_requestSerial;
    final cancellation = AiAgentCancellation();
    final buffer = AiStreamingTextBuffer(
      onFlush: (chunk) {
        if (requestId != _requestSerial) return;
        _updateActiveAssistant(
          (message) => message.copyWith(text: message.text + chunk),
        );
        notifyListeners();
      },
    );
    _activeCancellation = cancellation;
    _activeStreamBuffer = buffer;
    _selectedBookId = request.ledger.bookId;
    _messages.add(
      AiChatMessage(
        role: AiChatRole.user,
        bookId: request.ledger.bookId,
        bookName: request.ledger.bookName,
        baseCurrencyCode: request.ledger.baseCurrencyCode,
        moneyCodeDisplay: request.moneyCodeDisplay,
        text: text,
      ),
    );
    _messages.add(assistant);
    _activeAssistantIndex = _messages.length - 1;
    _streaming = true;
    notifyListeners();

    engine
        .run(
          mode: request.mode,
          streamTransport: request.streamTransport,
          completeTransport: request.completeTransport,
          context: AiToolContext(
            ledger: request.ledger,
            now: request.ledger.capturedAt,
            l10n: request.l10n,
            currencyDisplay: request.moneyCodeDisplay,
          ),
          priorMessages: priorMessages,
          userInput: text,
          cancellation: cancellation,
        )
        .listen(
          (event) => _handleEvent(requestId, request, event),
          onError: (Object error, StackTrace stackTrace) {
            _handleStreamError(requestId, request, error, stackTrace);
          },
          onDone: () => _handleDone(requestId, request),
          cancelOnError: true,
        );
  }

  void stop() {
    if (!_streaming) return;
    _activeStreamBuffer?.flush();
    _activeStreamBuffer?.dispose();
    _activeStreamBuffer = null;
    _requestSerial += 1;
    _activeCancellation?.cancel();
    _activeCancellation = null;
    final index = _activeAssistantIndex;
    _activeAssistantIndex = null;
    _streaming = false;
    if (index != null && index < _messages.length) {
      final message = _messages[index];
      final steps = message.steps
          .where(
            (step) =>
                step.status != AiAgentStepStatus.running &&
                step.status != AiAgentStepStatus.retrying,
          )
          .toList(growable: false);
      final status = message.status == AiChatMessageStatus.streaming
          ? AiChatMessageStatus.done
          : message.status;
      _messages[index] = message.copyWith(
        status: status,
        steps: steps,
        provenance: classifyAiAnswerProvenance(
          userInput: message.sourceUserInput,
          answer: message.text,
          successfulToolCalls: message.successfulToolCalls,
        ),
      );
    }
    notifyListeners();
  }

  void _handleEvent(int requestId, AiChatRequest request, AiAgentEvent event) {
    if (requestId != _requestSerial) return;
    if (event is AiAgentAnswerDelta) {
      _activeStreamBuffer?.add(event.text);
      return;
    }
    _activeStreamBuffer?.flush();
    if (event is AiAgentFailed) {
      _finishRetrySteps(succeeded: false);
    } else if (event is! AiAgentRetrying) {
      _finishRetrySteps(succeeded: true);
    }
    switch (event) {
      case final AiAgentToolStarted e:
        if (request.mode != AiToolCallMode.prompt &&
            request.capability?.matches(request.settings) != true) {
          onCapabilityDetected(
            AiCapabilityProfile.forSettings(
              settings: request.settings,
              nativeToolCalls: AiNativeToolCapability.supported,
            ),
          );
        }
        _updateActiveAssistant(
          (message) => message.copyWith(
            steps: <AiAgentStep>[
              ...message.steps,
              AiAgentStep(
                id: e.stepId,
                toolName: e.toolName,
                status: AiAgentStepStatus.running,
                arguments: e.arguments,
              ),
            ],
          ),
        );
      case final AiAgentToolCompleted e:
        _updateStep(
          e.stepId,
          status: AiAgentStepStatus.succeeded,
          summary: presentAiToolResultSummary(request.l10n, e.result),
          incrementSuccessfulToolCalls: true,
        );
        if (e.result.display != null) {
          _updateActiveAssistant(
            (message) => message.copyWith(
              displays: <AiResultDisplay>[
                ...message.displays,
                e.result.display!,
              ],
            ),
          );
        }
      case final AiAgentToolFailed e:
        _updateStep(
          e.stepId,
          status: AiAgentStepStatus.failed,
          summary: request.l10n.aiStepFailed,
        );
      case final AiAgentRetrying e:
        if (e.reason == AiAgentRetryReason.protocolFallback) {
          onCapabilityDetected(
            AiCapabilityProfile.forSettings(
              settings: request.settings,
              nativeToolCalls: AiNativeToolCapability.unsupported,
            ),
          );
        }
        _updateActiveAssistant(
          (message) => message.copyWith(
            steps: <AiAgentStep>[
              ...message.steps,
              AiAgentStep(
                id: 'retry-${message.steps.length}',
                toolName: 'agentRetry',
                status: AiAgentStepStatus.retrying,
                retryReason: e.reason,
              ),
            ],
          ),
        );
      case AiAgentAnswerDelta():
        break;
      case final AiAgentCompleted e:
        _updateActiveAssistant((message) {
          final answer = message.text.trim().isEmpty ? e.answer : message.text;
          return message.copyWith(
            text: answer,
            status: AiChatMessageStatus.done,
            successfulToolCalls: e.successfulToolCalls,
            provenance: classifyAiAnswerProvenance(
              userInput: message.sourceUserInput,
              answer: answer,
              successfulToolCalls: e.successfulToolCalls,
            ),
          );
        });
        _finishTurn();
      case final AiAgentFailed e:
        _updateActiveAssistant(
          (message) => message.copyWith(
            status: AiChatMessageStatus.error,
            errorText: e.error is AiException
                ? aiErrorMessage(request.l10n, e.error as AiException)
                : request.l10n.aiErrUnknown,
            provenance: classifyAiAnswerProvenance(
              userInput: message.sourceUserInput,
              answer: message.text,
              successfulToolCalls: message.successfulToolCalls,
            ),
          ),
        );
        onError('AI Agent 回答失败', e.error, null);
        _finishTurn();
    }
    notifyListeners();
  }

  void _handleStreamError(
    int requestId,
    AiChatRequest request,
    Object error,
    StackTrace stackTrace,
  ) {
    if (requestId != _requestSerial) return;
    _activeStreamBuffer?.flush();
    _activeStreamBuffer?.dispose();
    _activeStreamBuffer = null;
    _finishRetrySteps(succeeded: false);
    _updateActiveAssistant(
      (message) => message.copyWith(
        status: AiChatMessageStatus.error,
        errorText: error is AiException
            ? aiErrorMessage(request.l10n, error)
            : request.l10n.aiErrUnknown,
        provenance: classifyAiAnswerProvenance(
          userInput: message.sourceUserInput,
          answer: message.text,
          successfulToolCalls: message.successfulToolCalls,
        ),
      ),
    );
    onError('AI Agent 回答失败', error, stackTrace);
    _finishTurn();
    notifyListeners();
  }

  void _handleDone(int requestId, AiChatRequest request) {
    if (requestId != _requestSerial) return;
    _activeStreamBuffer?.flush();
    _activeStreamBuffer?.dispose();
    _activeStreamBuffer = null;
    final index = _activeAssistantIndex;
    if (index != null && index < _messages.length) {
      final message = _messages[index];
      if (message.status == AiChatMessageStatus.streaming) {
        _messages[index] = message.copyWith(
          status: AiChatMessageStatus.done,
          provenance: classifyAiAnswerProvenance(
            userInput: message.sourceUserInput,
            answer: message.text,
            successfulToolCalls: message.successfulToolCalls,
          ),
        );
      }
    }
    _finishTurn();
    notifyListeners();
  }

  void _finishTurn() {
    _activeStreamBuffer?.dispose();
    _streaming = false;
    _activeAssistantIndex = null;
    _activeCancellation = null;
    _activeStreamBuffer = null;
  }

  List<AiTextMessage> _priorMessages() {
    return <AiTextMessage>[
      for (final message in _messages)
        if (message.status == AiChatMessageStatus.done &&
            message.text.trim().isNotEmpty)
          AiTextMessage(
            role: message.role == AiChatRole.user
                ? AiMessageRole.user
                : AiMessageRole.assistant,
            content:
                '${message.bookName.trim().isEmpty ? '' : '[book: ${message.bookName.trim()}] '}'
                '${message.text.trim()}',
          ),
    ];
  }

  void _updateStep(
    String stepId, {
    required AiAgentStepStatus status,
    required String summary,
    bool incrementSuccessfulToolCalls = false,
  }) {
    _updateActiveAssistant((message) {
      final index = message.steps.indexWhere((step) => step.id == stepId);
      if (index < 0) return message;
      final steps = List<AiAgentStep>.of(message.steps);
      steps[index] = steps[index].copyWith(status: status, summary: summary);
      return message.copyWith(
        steps: steps,
        successfulToolCalls:
            message.successfulToolCalls +
            (incrementSuccessfulToolCalls ? 1 : 0),
      );
    });
  }

  void _finishRetrySteps({required bool succeeded}) {
    _updateActiveAssistant((message) {
      final steps = <AiAgentStep>[];
      for (final step in message.steps) {
        steps.add(
          step.status == AiAgentStepStatus.retrying
              ? step.copyWith(
                  status: succeeded
                      ? AiAgentStepStatus.succeeded
                      : AiAgentStepStatus.failed,
                )
              : step,
        );
      }
      return message.copyWith(steps: steps);
    });
  }

  void _updateActiveAssistant(
    AiChatMessage Function(AiChatMessage message) update,
  ) {
    final index = _activeAssistantIndex;
    if (index == null || index < 0 || index >= _messages.length) return;
    _messages[index] = update(_messages[index]);
  }

  @override
  void dispose() {
    _requestSerial += 1;
    _activeCancellation?.cancel();
    _activeStreamBuffer?.dispose();
    super.dispose();
  }
}
