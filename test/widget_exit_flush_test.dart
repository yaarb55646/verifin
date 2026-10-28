import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verifin/app/veri_fin_controller.dart';
import 'package:verifin/app/veri_fin_scope.dart';
import 'package:verifin/app/widgets/widget_refresh_coordinator.dart';
import 'package:verifin/app/widgets/widget_refresh_scope.dart';
import 'package:verifin/pages/shell.dart';

import 'support/test_harness.dart';

/// 退出路径：`SystemNavigator.pop()` 会 finish Activity，Flutter 引擎随之下线，
/// 挂在 `hidden` / `paused` 上的异步冲刷会被直接掐断。用户「记完账立刻按返回退出」
/// 时快照就停在上一笔，且不会自愈。所以退出前必须**先等这一轮发布完成**。
void main() {
  useTestDatabases();

  const app = MethodChannel('verifin/app');
  final pops = <String>[];

  void mockPlatform() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(app, (call) async => null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'SystemNavigator.pop') {
            pops.add(call.method);
          }
          return null;
        });
  }

  tearDown(() {
    pops.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(app, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<
    ({
      VeriFinController controller,
      int Function() flushes,
      int Function() pushes,
    })
  >
  pumpShell(WidgetTester tester, {required Completer<void> gate}) async {
    final controller = await makeController();
    addTearDown(controller.dispose);
    var flushes = 0;
    var pushes = 0;
    final coordinator = WidgetRefreshCoordinator(
      () async {
        flushes += 1;
        await gate.future;
      },
      ({required bool force}) async {
        pushes += 1;
      },
    );
    addTearDown(coordinator.dispose);

    await tester.pumpWidget(
      VeriFinScope(
        controller: controller,
        child: WidgetRefreshScope(
          coordinator: coordinator,
          child: zhMaterialApp(home: const VeriFinShell()),
        ),
      ),
    );
    await tester.pump();
    return (
      controller: controller,
      flushes: () => flushes,
      pushes: () => pushes,
    );
  }

  /// 连按两次返回：第一次只提示「再按一次退出」，第二次进入退出流程。
  Future<void> pressBackTwice(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pump();
  }

  testWidgets('退出前先等冲刷完成，再关闭 Activity', (tester) async {
    mockPlatform();
    final gate = Completer<void>();
    final shell = await pumpShell(tester, gate: gate);

    await pressBackTwice(tester);

    expect(shell.flushes(), 1, reason: '第二次返回必须触发一次冲刷');
    expect(pops, isEmpty, reason: '冲刷没完成之前不能关闭 Activity');

    gate.complete();
    await tester.pump();
    await tester.pump();

    expect(pops, <String>['SystemNavigator.pop']);
  });

  testWidgets('冲刷卡住时按超时退出，不把用户卡在应用里', (tester) async {
    mockPlatform();
    final gate = Completer<void>(); // 故意不 complete：模拟平台通道不返回
    await pumpShell(tester, gate: gate);

    await pressBackTwice(tester);
    expect(pops, isEmpty);

    await tester.pump(const Duration(milliseconds: 700));

    expect(pops, <String>[
      'SystemNavigator.pop',
    ], reason: '超时后仍要退出，未完成的发布由下次冷启动补推');
  });

  testWidgets('没有挂冲刷 scope 时也能正常退出', (tester) async {
    mockPlatform();
    final controller = await makeController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      VeriFinScope(
        controller: controller,
        child: zhMaterialApp(home: const VeriFinShell()),
      ),
    );
    await tester.pump();

    await pressBackTwice(tester);
    await tester.pump();

    expect(pops, <String>['SystemNavigator.pop']);
  });
}
