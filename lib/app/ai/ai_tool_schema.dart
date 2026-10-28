/// OpenAI-compatible 工具参数支持的基础类型。
enum AiToolParameterType {
  string('string'),
  number('number'),
  integer('integer'),
  boolean('boolean');

  const AiToolParameterType(this.jsonName);

  final String jsonName;
}

/// 单个工具参数的声明。
///
/// 这是原生 JSON Schema、兼容协议提示词和本地参数检查的共同数据源。
class AiToolParameter {
  const AiToolParameter({
    required this.type,
    required this.description,
    this.enumValues = const <Object>[],
    this.minimum,
    this.maximum,
  });

  final AiToolParameterType type;
  final String description;
  final List<Object> enumValues;
  final num? minimum;
  final num? maximum;

  Map<String, Object?> toJsonSchema() => <String, Object?>{
    'type': type.jsonName,
    'description': description,
    if (enumValues.isNotEmpty) 'enum': enumValues,
    if (minimum != null) 'minimum': minimum,
    if (maximum != null) 'maximum': maximum,
  };

  String get promptConstraint {
    final parts = <String>[type.jsonName];
    if (enumValues.isNotEmpty) {
      parts.add('可选值：${enumValues.join('/')}');
    }
    if (minimum != null) parts.add('最小 $minimum');
    if (maximum != null) parts.add('最大 $maximum');
    return parts.join('，');
  }
}

class AiToolArgumentIssue {
  const AiToolArgumentIssue({required this.field, required this.message});

  final String field;
  final String message;

  @override
  String toString() => '$field: $message';
}

class AiToolValidation {
  const AiToolValidation({
    required this.normalizedArguments,
    required this.issues,
  });

  final Map<String, Object?> normalizedArguments;
  final List<AiToolArgumentIssue> issues;

  bool get isValid => issues.isEmpty;
}

/// 一个工具的参数对象 Schema。
class AiToolSchema {
  const AiToolSchema({
    this.properties = const <String, AiToolParameter>{},
    this.required = const <String>{},
  });

  final Map<String, AiToolParameter> properties;
  final Set<String> required;

  Map<String, Object?> toJsonSchema() => <String, Object?>{
    'type': 'object',
    'properties': <String, Object?>{
      for (final entry in properties.entries)
        entry.key: entry.value.toJsonSchema(),
    },
    if (required.isNotEmpty) 'required': required.toList(growable: false),
    'additionalProperties': false,
  };

  /// 生成兼容提示词协议使用的紧凑参数说明。
  ///
  /// 必须保留类型、枚举、范围和必填约束，避免提示词协议与原生 JSON Schema
  /// 的实际契约发生漂移。
  String get promptDescription {
    final parameters = properties.entries
        .map(
          (entry) =>
              '${entry.key}（${entry.value.promptConstraint}）：'
              '${entry.value.description}',
        )
        .join('；');
    final requiredText = required.isEmpty
        ? ''
        : '；必填：${required.toList(growable: false).join('/')}';
    return '$parameters$requiredText';
  }

  /// 归一化并校验模型参数。
  ///
  /// 数字/整数字符串和布尔字符串在进入工具前被安全转换；额外字段、类型错误、
  /// 非法枚举及范围错误会返回具体字段问题。
  AiToolValidation validateArguments(Map<String, Object?> arguments) {
    final normalized = <String, Object?>{};
    final issues = <AiToolArgumentIssue>[];
    for (final name in required) {
      if (!arguments.containsKey(name)) {
        issues.add(AiToolArgumentIssue(field: name, message: 'is required'));
      }
    }
    for (final entry in arguments.entries) {
      final name = entry.key;
      final parameter = properties[name];
      if (parameter == null) {
        issues.add(AiToolArgumentIssue(field: name, message: 'is not allowed'));
        continue;
      }
      final (value, typeError) = _normalizeValue(entry.value, parameter.type);
      if (typeError != null) {
        issues.add(AiToolArgumentIssue(field: name, message: typeError));
        continue;
      }
      if (parameter.enumValues.isNotEmpty &&
          !parameter.enumValues.contains(value)) {
        issues.add(
          AiToolArgumentIssue(
            field: name,
            message: 'expected one of ${parameter.enumValues.join('/')}',
          ),
        );
        continue;
      }
      if (value is num) {
        if (parameter.minimum != null && value < parameter.minimum!) {
          issues.add(
            AiToolArgumentIssue(
              field: name,
              message: 'must be at least ${parameter.minimum}',
            ),
          );
          continue;
        }
        if (parameter.maximum != null && value > parameter.maximum!) {
          issues.add(
            AiToolArgumentIssue(
              field: name,
              message: 'must be at most ${parameter.maximum}',
            ),
          );
          continue;
        }
      }
      normalized[name] = value;
    }
    return AiToolValidation(normalizedArguments: normalized, issues: issues);
  }
}

(Object?, String?) _normalizeValue(Object? value, AiToolParameterType type) {
  if (value == null) return (null, 'must not be null');
  return switch (type) {
    AiToolParameterType.string =>
      value is String ? (value, null) : (null, 'expected string'),
    AiToolParameterType.number => _normalizeNumber(value),
    AiToolParameterType.integer => _normalizeInteger(value),
    AiToolParameterType.boolean => switch (value) {
      bool() => (value, null),
      String() when value.trim().toLowerCase() == 'true' => (true, null),
      String() when value.trim().toLowerCase() == 'false' => (false, null),
      _ => (null, 'expected boolean'),
    },
  };
}

(Object?, String?) _normalizeNumber(Object? value) {
  final number = value is num
      ? value.toDouble()
      : value is String
      ? double.tryParse(value.trim())
      : null;
  if (number == null || !number.isFinite) {
    return (null, 'expected number');
  }
  return (number, null);
}

(Object?, String?) _normalizeInteger(Object? value) {
  final number = value is num
      ? value.toDouble()
      : value is String
      ? double.tryParse(value.trim())
      : null;
  if (number == null || !number.isFinite || number != number.roundToDouble()) {
    return (null, 'expected integer');
  }
  return (number.toInt(), null);
}
