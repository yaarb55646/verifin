import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verifin/app/platform_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('verifin/app');
  const codec = StandardMethodCodec();
  final consumed = <String>[];

  setUp(() {
    consumed.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          consumed.add(call.method);
          switch (call.method) {
            case 'consumeQuickEntryIntent':
              return true;
            case 'consumeWidgetRoute':
              return <String, Object?>{
                'route': 'entry',
                'bookId': 'book-1',
                'widgetId': '7',
              };
          }
          return null;
        });
    AppCaptureBridge.clearQuickEntryHandler();
    AppWidgetBridge.clearRouteHandler();
  });

  tearDown(() {
    AppCaptureBridge.clearQuickEntryHandler();
    AppWidgetBridge.clearRouteHandler();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<void> deliver(String method, [Object? arguments]) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          channel.name,
          codec.encodeMethodCall(MethodCall(method, arguments)),
          null,
        );
  }

  test('壳层未就绪时不消费磁贴入口，处理器就绪后消费一次', () async {
    await deliver('openQuickEntry');
    expect(consumed, isEmpty, reason: '没有 Shell 处理器时必须保留原生 pending');

    var opened = 0;
    AppCaptureBridge.setQuickEntryHandler(() async {
      opened += 1;
    });

    await deliver('openQuickEntry');

    expect(consumed, <String>['consumeQuickEntryIntent']);
    expect(opened, 1);
  });

  test('壳层未就绪时保留组件路由，就绪后使用原生存储值导航一次', () async {
    await deliver('openWidgetRoute', <String, Object?>{'route': 'app'});
    expect(consumed, isEmpty, reason: '没有 Shell 处理器时必须保留原生 pending');

    final handled = <Map<String, Object?>>[];
    AppWidgetBridge.setRouteHandler((args) async {
      handled.add(args);
    });

    await deliver('openWidgetRoute', <String, Object?>{'route': 'app'});

    expect(consumed, <String>['consumeWidgetRoute']);
    expect(handled, <Map<String, Object?>>[
      <String, Object?>{'route': 'entry', 'bookId': 'book-1', 'widgetId': '7'},
    ]);
  });
}
