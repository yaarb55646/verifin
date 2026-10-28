import 'ai_agent_event.dart';

enum AiAgentStepStatus { running, succeeded, failed, retrying }

/// 用户可见、可持久化的 Agent 操作轨迹。不包含协议原文、思维链或底层异常。
class AiAgentStep {
  const AiAgentStep({
    required this.id,
    required this.toolName,
    required this.status,
    this.arguments = const <String, Object?>{},
    this.summary = '',
    this.retryReason,
  });

  final String id;
  final String toolName;
  final AiAgentStepStatus status;
  final Map<String, Object?> arguments;
  final String summary;
  final AiAgentRetryReason? retryReason;

  AiAgentStep copyWith({
    AiAgentStepStatus? status,
    String? summary,
    AiAgentRetryReason? retryReason,
  }) {
    return AiAgentStep(
      id: id,
      toolName: toolName,
      status: status ?? this.status,
      arguments: arguments,
      summary: summary ?? this.summary,
      retryReason: retryReason ?? this.retryReason,
    );
  }
}
