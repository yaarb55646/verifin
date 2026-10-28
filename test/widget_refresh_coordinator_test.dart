import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:verifin/app/widgets/widget_refresh_coordinator.dart';

void main() {
  testWidgets('防抖只推一次，切后台会取消防抖并先刷盘再推送', (tester) async {
    final calls = <String>[];
    final coordinator = WidgetRefreshCoordinator(
      () async {
        calls.add('flush');
      },
      ({required bool force}) async {
        calls.add('push:${force ? 'force' : 'normal'}');
      },
    );
    addTearDown(coordinator.dispose);

    coordinator.schedule();
    await tester.pump(const Duration(milliseconds: 249));
    expect(calls, isEmpty);

    await tester.pump(const Duration(milliseconds: 1));
    expect(calls, <String>['push:normal']);

    calls.clear();
    coordinator.schedule();
    await tester.pump(const Duration(milliseconds: 100));
    await coordinator.flush();
    await tester.pump(const Duration(milliseconds: 300));

    expect(calls, <String>['flush', 'push:force']);
  });

  testWidgets('立即推送会取消待执行防抖并转发 force', (tester) async {
    final calls = <String>[];
    final coordinator = WidgetRefreshCoordinator(() async {}, ({
      required bool force,
    }) async {
      calls.add(force ? 'force' : 'normal');
    });
    addTearDown(coordinator.dispose);

    coordinator.schedule();
    await tester.pump(const Duration(milliseconds: 100));
    await coordinator.pushNow(force: true);
    await tester.pump(const Duration(milliseconds: 300));

    expect(calls, <String>['force']);
  });

  testWidgets('flush 等待写入完成后才推送', (tester) async {
    final writes = Completer<void>();
    final calls = <String>[];
    final coordinator = WidgetRefreshCoordinator(
      () async {
        calls.add('flush-start');
        await writes.future;
        calls.add('flush-end');
      },
      ({required bool force}) async {
        calls.add('push');
      },
    );
    addTearDown(coordinator.dispose);

    final flushing = coordinator.flush();
    await tester.pump();
    expect(calls, <String>['flush-start']);

    writes.complete();
    await flushing;
    await tester.pump();
    expect(calls, <String>['flush-start', 'flush-end', 'push']);
  });

  testWidgets('hidden 与 paused 连续触发时复用同一次冲刷', (tester) async {
    final writes = Completer<void>();
    var flushes = 0;
    var pushes = 0;
    final coordinator = WidgetRefreshCoordinator(
      () async {
        flushes += 1;
        await writes.future;
      },
      ({required bool force}) async {
        pushes += 1;
      },
    );
    addTearDown(coordinator.dispose);

    final hiddenFlush = coordinator.flush();
    final pausedFlush = coordinator.flush();
    expect(identical(hiddenFlush, pausedFlush), isTrue);

    writes.complete();
    await Future.wait(<Future<void>>[hiddenFlush, pausedFlush]);
    await tester.pump();

    expect(flushes, 1);
    expect(pushes, 1);
  });
}
