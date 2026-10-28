import 'package:flutter_test/flutter_test.dart';
import 'package:verifin/app/ai/ai_answer_provenance.dart';

void main() {
  test('successful tool calls always mark the answer as ledger-backed', () {
    expect(
      classifyAiAnswerProvenance(
        userInput: '本月花了多少',
        answer: '本月支出 1,200 元。',
        successfulToolCalls: 1,
      ),
      AiAnswerProvenance.ledgerQueried,
    );
  });

  test('financial numbers without a successful query are flagged', () {
    expect(
      classifyAiAnswerProvenance(
        userInput: '本月花了多少',
        answer: '本月支出 1,200 元。',
        successfulToolCalls: 0,
      ),
      AiAnswerProvenance.noLedgerQueryWithNumericContent,
    );
    expect(
      classifyAiAnswerProvenance(
        userInput: 'What did I spend this month?',
        answer: 'You spent CNY 1,200.',
        successfulToolCalls: 0,
      ),
      AiAnswerProvenance.noLedgerQueryWithNumericContent,
    );
    expect(
      classifyAiAnswerProvenance(
        userInput: 'direct answer monthly spending',
        answer: '本月支出 1234 元。',
        successfulToolCalls: 0,
      ),
      AiAnswerProvenance.noLedgerQueryWithNumericContent,
    );
  });

  test('non-financial direct answers remain a neutral no-query state', () {
    expect(
      classifyAiAnswerProvenance(
        userInput: '你好',
        answer: '你好，我可以帮你查询账目。',
        successfulToolCalls: 0,
      ),
      AiAnswerProvenance.noLedgerQuery,
    );
  });
}
