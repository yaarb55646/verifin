/// 一条助手回答与本地账本数据之间的关系。
enum AiAnswerProvenance {
  /// 本 turn 至少成功执行过一次只读账本工具。
  ledgerQueried,

  /// 没有执行工具，但回答也不像账目事实。
  noLedgerQuery,

  /// 用户明显在问账目，回答含数字却没有成功查询账本。
  noLedgerQueryWithNumericContent,
}

final RegExp _financialQuestionPattern = RegExp(
  r'支出|收入|花费|消费|预算|账户|余额|转账|退款|报销|账单|工资|'
  r'大额|分类|标签|净资产|信用卡|还款|花|赚|'
  r'\b(?:spend|spending|spent|expense|expenses|income|budget|account|balance|transfer|'
  r'refund|bill|salary|cost|payment|net worth|credit card)\b',
  caseSensitive: false,
);

final RegExp _numericAnswerPattern = RegExp(
  r'[¥$€£₩₹]|\d[\d,.]*\s*(?:元|块|人民币|美元|欧元|日元|'
  r'CNY|USD|EUR|JPY|GBP)|'
  r'\b(?:CNY|USD|EUR|JPY|GBP)\s*\d',
  caseSensitive: false,
);

/// 根据用户问题、最终正文和真实工具执行结果判定回答来源。
///
/// 该函数只做本地展示判断，不修改回答。模型无法通过正文伪造
/// [successfulToolCalls]；工具失败也不会被算作成功查询。
AiAnswerProvenance classifyAiAnswerProvenance({
  required String userInput,
  required String answer,
  required int successfulToolCalls,
}) {
  if (successfulToolCalls > 0) {
    return AiAnswerProvenance.ledgerQueried;
  }
  if (_financialQuestionPattern.hasMatch(userInput) &&
      _numericAnswerPattern.hasMatch(answer)) {
    return AiAnswerProvenance.noLedgerQueryWithNumericContent;
  }
  return AiAnswerProvenance.noLedgerQuery;
}
