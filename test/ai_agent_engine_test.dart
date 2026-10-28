import 'dart:async';
import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:verifin/app/ai/ai_agent_engine.dart';
import 'package:verifin/app/ai/ai_agent_event.dart';
import 'package:verifin/app/ai/ai_agent_message.dart';
import 'package:verifin/app/ai/ai_completion_event.dart';
import 'package:verifin/app/ai/ai_error.dart';
import 'package:verifin/app/ai/ai_ledger_snapshot.dart';
import 'package:verifin/app/ai/ai_query_tool.dart';
import 'package:verifin/app/ai/ai_settings.dart';
import 'package:verifin/app/models.dart';
import 'package:verifin/l10n/app_localizations.dart';

AiToolContext _context() {
  final entries = <LedgerEntry>[
    LedgerEntry(
      id: 'e1',
      bookId: 'b',
      type: EntryType.expense,
      amount: 300,
      categoryId: 'food',
      accountId: 'acc',
      note: '午餐',
      occurredAt: DateTime(2026, 6, 10),
    ),
  ];
  return AiToolContext(
    ledger: AiLedgerSnapshot.forTesting(
      bookId: 'b',
      entries: entries,
      balanceOf: (_) => 0,
    ),
    now: DateTime(2026, 6, 20),
    l10n: lookupAppLocalizations(const Locale('zh')),
  );
}

class _ScriptedTransport {
  _ScriptedTransport(this.rounds);

  final List<Object> rounds;
  final List<List<AiAgentMessage>> messages = <List<AiAgentMessage>>[];
  final List<List<Map<String, Object?>>> toolDefinitions =
      <List<Map<String, Object?>>>[];
  var _index = 0;

  Stream<AiCompletionEvent> stream(
    List<AiAgentMessage> requestMessages,
    List<Map<String, Object?>> tools,
  ) async* {
    messages.add(List<AiAgentMessage>.from(requestMessages));
    toolDefinitions.add(List<Map<String, Object?>>.from(tools));
    final round = rounds[_index++];
    if (round is List<AiCompletionEvent>) {
      for (final event in round) {
        yield event;
      }
      return;
    }
    throw round;
  }
}

List<AiCompletionEvent> _answer(String text) => <AiCompletionEvent>[
  AiContentDelta(text),
  const AiCompletionFinished(AiFinishReason.stop),
  const AiStreamDone(),
];

Future<List<AiAgentEvent>> _run(
  AiAgentEngine engine,
  _ScriptedTransport transport, {
  AiToolCallMode mode = AiToolCallMode.native,
  AiAgentCompleteTransport? completeTransport,
  List<AiTextMessage> priorMessages = const <AiTextMessage>[],
  String userInput = '本月花了多少',
}) {
  return engine
      .run(
        mode: mode,
        streamTransport: transport.stream,
        completeTransport: completeTransport,
        context: _context(),
        priorMessages: priorMessages,
        userInput: userInput,
      )
      .toList();
}

void main() {
  final engine = AiAgentEngine(tools: buildAiQueryTools());

  test(
    'native protocol assembles fragmented calls and executes sequentially',
    () async {
      final transport = _ScriptedTransport(<Object>[
        <AiCompletionEvent>[
          const AiReasoningDelta('private reasoning'),
          const AiToolCallDelta(
            index: 0,
            id: 'call_1',
            name: 'sum',
            arguments: '{"range":',
          ),
          const AiToolCallDelta(
            index: 0,
            name: 'mary',
            arguments: '"thisMonth"}',
          ),
          const AiToolCallDelta(
            index: 1,
            id: 'call_2',
            name: 'largestTransactions',
            arguments: '{"range":"thisMonth","limit":1}',
          ),
          const AiCompletionFinished(AiFinishReason.toolCalls),
          const AiStreamDone(),
        ],
        _answer('本月支出 300 元，最大一笔也是 300 元。'),
      ]);

      final events = await _run(engine, transport);

      expect(events.whereType<AiAgentToolStarted>(), hasLength(2));
      expect(events.whereType<AiAgentToolCompleted>(), hasLength(2));
      expect(events.whereType<AiAgentToolFailed>(), isEmpty);
      final completed = events.whereType<AiAgentCompleted>().single;
      expect(completed.answer, '本月支出 300 元，最大一笔也是 300 元。');
      expect(completed.attemptedToolCalls, 2);
      expect(completed.successfulToolCalls, 2);
      expect(completed.usedLedgerData, isTrue);
      expect(
        events.whereType<AiAgentAnswerDelta>().single.text,
        isNot(contains('private reasoning')),
      );
      // 注册表里的每个工具都应作为一条原生 function definition 传给模型。
      expect(
        transport.toolDefinitions.first,
        hasLength(buildAiQueryTools().length),
      );
      final secondRound = transport.messages[1];
      expect(secondRound.whereType<AiAssistantToolMessage>(), hasLength(1));
      expect(secondRound.whereType<AiToolResultMessage>(), hasLength(2));
    },
  );

  test('prompt protocol consumes noisy tool JSON without leaking it', () async {
    const rawTool =
        '<think>需要查询</think>\n'
        '我先看一下。\n'
        '{"tool":"summary","args":{"range":"thisMonth"}}';
    final transport = _ScriptedTransport(<Object>[
      <AiCompletionEvent>[
        const AiContentDelta(rawTool),
        const AiCompletionFinished(AiFinishReason.stop),
        const AiStreamDone(),
      ],
      _answer('VERIFIN_ANSWER\n本月支出 300 元。'),
    ]);

    final events = await _run(engine, transport, mode: AiToolCallMode.prompt);

    expect(events.whereType<AiAgentToolCompleted>(), hasLength(1));
    final completed = events.whereType<AiAgentCompleted>().single;
    expect(completed.answer, '本月支出 300 元。');
    expect(completed.attemptedToolCalls, 1);
    expect(completed.successfulToolCalls, 1);
    final visible = events
        .whereType<AiAgentAnswerDelta>()
        .map((event) => event.text)
        .join();
    expect(visible, isNot(contains('{"tool"')));
    expect(visible, isNot(contains('<think>')));
    expect(transport.toolDefinitions.every((tools) => tools.isEmpty), isTrue);
  });

  test('native tool arguments are normalized before execution', () async {
    final transport = _ScriptedTransport(<Object>[
      <AiCompletionEvent>[
        const AiToolCallDelta(
          index: 0,
          id: 'call_normalized',
          name: 'largestTransactions',
          arguments: '{"range":"all","limit":"1"}',
        ),
        const AiCompletionFinished(AiFinishReason.toolCalls),
        const AiStreamDone(),
      ],
      _answer('已找到一笔。'),
    ]);

    final events = await _run(engine, transport);

    expect(events.whereType<AiAgentToolCompleted>(), hasLength(1));
    expect(events.whereType<AiAgentToolFailed>(), isEmpty);
    final completed = events.whereType<AiAgentCompleted>().single;
    expect(completed.successfulToolCalls, 1);
  });

  test('duplicate provider call ids keep distinct UI step ids', () async {
    final transport = _ScriptedTransport(<Object>[
      <AiCompletionEvent>[
        const AiToolCallDelta(
          index: 0,
          id: 'duplicate',
          name: 'summary',
          arguments: '{"range":"all"}',
        ),
        const AiToolCallDelta(
          index: 1,
          id: 'duplicate',
          name: 'largestTransactions',
          arguments: '{"range":"all","limit":1}',
        ),
        const AiCompletionFinished(AiFinishReason.toolCalls),
        const AiStreamDone(),
      ],
      _answer('完成。'),
    ]);

    final events = await _run(engine, transport);
    final ids = events
        .whereType<AiAgentToolStarted>()
        .map((event) => event.stepId)
        .toList();

    expect(ids, <String>['native-0-1', 'native-0-2']);
    expect(ids.toSet(), hasLength(2));
  });

  test(
    'auto mode falls back only after explicit native protocol rejection',
    () async {
      final transport = _ScriptedTransport(<Object>[
        AiException(AiErrorCode.protocolUnsupported),
        _answer('VERIFIN_ANSWER\n兼容模式回答。'),
      ]);

      final events = await _run(engine, transport, mode: AiToolCallMode.auto);

      expect(
        events.whereType<AiAgentRetrying>().single.reason,
        AiAgentRetryReason.protocolFallback,
      );
      expect(events.whereType<AiAgentCompleted>().single.answer, '兼容模式回答。');
      expect(transport.toolDefinitions[0], isNotEmpty);
      expect(transport.toolDefinitions[1], isEmpty);
    },
  );

  test('forced native mode does not silently downgrade', () async {
    final transport = _ScriptedTransport(<Object>[
      AiException(AiErrorCode.protocolUnsupported),
    ]);

    final events = await _run(engine, transport);

    expect(events.whereType<AiAgentRetrying>(), isEmpty);
    final error = events.whereType<AiAgentFailed>().single.error as AiException;
    expect(error.code, AiErrorCode.protocolUnsupported);
    expect(transport.messages, hasLength(1));
  });

  test(
    'transient stream failure retries once with non-stream transport',
    () async {
      final transport = _ScriptedTransport(<Object>[
        AiException(AiErrorCode.network),
      ]);
      var completeCalls = 0;

      final events = await _run(
        engine,
        transport,
        completeTransport: (messages, tools) async {
          completeCalls += 1;
          return const AiCompletionResult(
            content: '重试成功。',
            finishReason: AiFinishReason.stop,
          );
        },
      );

      expect(
        events.whereType<AiAgentRetrying>().single.reason,
        AiAgentRetryReason.network,
      );
      expect(events.whereType<AiAgentCompleted>().single.answer, '重试成功。');
      expect(completeCalls, 1);
    },
  );

  test('native answer deltas are delivered before the stream closes', () async {
    final stream = StreamController<AiCompletionEvent>();
    final events = <AiAgentEvent>[];
    final done = Completer<void>();
    final subscription = engine
        .run(
          mode: AiToolCallMode.native,
          streamTransport: (_, _) => stream.stream,
          context: _context(),
          priorMessages: const <AiTextMessage>[],
          userInput: '本月花了多少',
        )
        .listen(events.add, onDone: () => done.complete());

    stream.add(const AiContentDelta('第一段'));
    await Future<void>.delayed(const Duration(milliseconds: 1));

    expect(
      events.whereType<AiAgentAnswerDelta>().map((event) => event.text),
      <String>['第一段'],
    );
    expect(done.isCompleted, isFalse);

    stream.add(const AiCompletionFinished(AiFinishReason.stop));
    stream.add(const AiStreamDone());
    await stream.close();
    await done.future;
    await subscription.cancel();

    expect(events.whereType<AiAgentCompleted>(), hasLength(1));
  });

  test('partial answer survives a transport failure without retry', () async {
    final stream = StreamController<AiCompletionEvent>();
    var completeCalls = 0;
    final events = <AiAgentEvent>[];
    final done = Completer<void>();
    engine
        .run(
          mode: AiToolCallMode.native,
          streamTransport: (_, _) => stream.stream,
          completeTransport: (_, _) async {
            completeCalls += 1;
            return const AiCompletionResult(
              content: '不应重试',
              finishReason: AiFinishReason.stop,
            );
          },
          context: _context(),
          priorMessages: const <AiTextMessage>[],
          userInput: '本月花了多少',
        )
        .listen(events.add, onDone: () => done.complete());

    stream.add(const AiContentDelta('已经显示的正文'));
    await Future<void>.delayed(const Duration(milliseconds: 1));
    stream.addError(AiException(AiErrorCode.network));
    await stream.close();
    await done.future;

    expect(
      events.whereType<AiAgentAnswerDelta>().map((event) => event.text).join(),
      '已经显示的正文',
    );
    expect(events.whereType<AiAgentFailed>(), hasLength(1));
    expect(events.whereType<AiAgentRetrying>(), isEmpty);
    expect(completeCalls, 0);
  });

  test('cancellation stops the active transport', () async {
    final stream = StreamController<AiCompletionEvent>();
    var cancelled = false;
    stream.onCancel = () => cancelled = true;
    final cancellation = AiAgentCancellation();
    final done = Completer<void>();
    final events = <AiAgentEvent>[];
    engine
        .run(
          mode: AiToolCallMode.native,
          streamTransport: (_, _) => stream.stream,
          context: _context(),
          priorMessages: const <AiTextMessage>[],
          userInput: '本月花了多少',
          cancellation: cancellation,
        )
        .listen(events.add, onDone: () => done.complete());

    stream.add(const AiContentDelta('部分正文'));
    await Future<void>.delayed(const Duration(milliseconds: 1));
    cancellation.cancel();
    await done.future.timeout(const Duration(seconds: 1));

    expect(cancelled, isTrue);
    expect(
      events.whereType<AiAgentAnswerDelta>().map((event) => event.text).join(),
      '部分正文',
    );
    await stream.close();
  });

  test(
    'malformed compatibility control fails without visible raw JSON',
    () async {
      final transport = _ScriptedTransport(<Object>[
        _answer('VERIFIN_TOOL\n{"tool":"summary","args":{'),
      ]);

      final events = await _run(engine, transport, mode: AiToolCallMode.prompt);

      expect(events.whereType<AiAgentAnswerDelta>(), isEmpty);
      expect(events.whereType<AiAgentCompleted>(), isEmpty);
      expect(events.whereType<AiAgentFailed>(), hasLength(1));
    },
  );

  test('prior visible messages are bounded before transport', () async {
    final transport = _ScriptedTransport(<Object>[_answer('回答。')]);
    final prior = <AiTextMessage>[
      for (var index = 0; index < 20; index += 1)
        index.isEven
            ? AiTextMessage.user('user-$index')
            : AiTextMessage.assistant('assistant-$index'),
    ];

    await _run(engine, transport, priorMessages: prior);

    // system + at most 12 prior messages + current user question。
    expect(transport.messages.single.length, lessThanOrEqualTo(14));
    expect(transport.messages.single.first.role, AiMessageRole.system);
    expect(transport.messages.single.last.role, AiMessageRole.user);
  });

  test('answer character limit stops unbounded output', () async {
    final limited = AiAgentEngine(
      tools: buildAiQueryTools(),
      maxAnswerCharacters: 3,
    );
    final transport = _ScriptedTransport(<Object>[
      <AiCompletionEvent>[
        const AiContentDelta('too long'),
        const AiCompletionFinished(AiFinishReason.stop),
        const AiStreamDone(),
      ],
    ]);

    final events = await _run(limited, transport);

    final failure = events.whereType<AiAgentFailed>().single;
    expect((failure.error as AiException).code, AiErrorCode.responseTooLarge);
  });

  test('user input limit fails before contacting the transport', () async {
    final limited = AiAgentEngine(
      tools: buildAiQueryTools(),
      maxUserInputCharacters: 3,
    );
    var contacted = false;
    final events = await limited
        .run(
          mode: AiToolCallMode.native,
          streamTransport: (_, _) async* {
            contacted = true;
            yield const AiContentDelta('不应触达');
            yield const AiCompletionFinished(AiFinishReason.stop);
            yield const AiStreamDone();
          },
          context: _context(),
          priorMessages: const <AiTextMessage>[],
          userInput: 'too long',
        )
        .toList();

    expect(contacted, isFalse);
    final failure = events.whereType<AiAgentFailed>().single;
    expect((failure.error as AiException).code, AiErrorCode.requestTooLarge);
  });

  test('oversized tool arguments fail with a request limit error', () async {
    final limited = AiAgentEngine(
      tools: buildAiQueryTools(),
      maxToolArgumentsCharacters: 5,
    );
    final transport = _ScriptedTransport(<Object>[
      <AiCompletionEvent>[
        const AiToolCallDelta(
          index: 0,
          id: 'call',
          name: 'summary',
          arguments: '{"range":"thisMonth"}',
        ),
        const AiCompletionFinished(AiFinishReason.toolCalls),
        const AiStreamDone(),
      ],
    ]);

    final events = await _run(limited, transport);

    final failure = events.whereType<AiAgentFailed>().single;
    expect((failure.error as AiException).code, AiErrorCode.requestTooLarge);
    expect(events.whereType<AiAgentToolStarted>(), isEmpty);
  });

  test('turn request character limit fails before transport', () async {
    final limited = AiAgentEngine(
      tools: buildAiQueryTools(),
      maxTurnRequestCharacters: 1,
    );
    var contacted = false;
    final events = await limited
        .run(
          mode: AiToolCallMode.native,
          streamTransport: (_, _) async* {
            contacted = true;
            yield const AiCompletionFinished(AiFinishReason.stop);
          },
          context: _context(),
          priorMessages: const <AiTextMessage>[],
          userInput: 'q',
        )
        .toList();

    expect(contacted, isFalse);
    final failure = events.whereType<AiAgentFailed>().single;
    expect((failure.error as AiException).code, AiErrorCode.requestTooLarge);
  });
}
