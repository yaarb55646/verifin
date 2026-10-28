part of 'platform_bridge.dart';

/// 桌面小组件与原生之间的通道：应用内预览渲染、桌面实例计数、点击路由。
/// 数据与刷新排程交给维护中的 home_widget 插件，不另立第二套协议。
class AppWidgetBridge {
  AppWidgetBridge._();

  static Future<void> Function(Map<String, Object?> args)? _routeHandler;

  static void setRouteHandler(
    Future<void> Function(Map<String, Object?> args) handler,
  ) {
    _routeHandler = handler;
    _ensureInboundDispatcher();
  }

  static void clearRouteHandler() {
    _routeHandler = null;
    _ensureInboundDispatcher();
  }

  static bool get hasRouteHandler => _routeHandler != null;

  static Future<void> handleRoute(Map<String, Object?> args) async {
    await _routeHandler?.call(args);
  }

  /// 请求原生用同一套 Glance 组合渲染一张预览图（应用内展示，不读桌面实例配置）。
  ///
  /// [bookId] 为空表示样例态（不读任何账本数据）；[appearance] 传草稿外观，
  /// 因此预览与保存后的桌面渲染完全同源。
  static Future<Uint8List?> renderPreview({
    required String template,
    required int widthDp,
    required int heightDp,
    String bookId = '',
    String appearance = 'system',
    bool sample = false,
  }) async {
    try {
      return await _channel.invokeMethod<Uint8List>('renderWidgetPreview', {
        'template': template,
        'widthDp': widthDp,
        'heightDp': heightDp,
        'bookId': bookId,
        'appearance': appearance,
        'sample': sample,
      });
    } on MissingPluginException {
      return null;
    }
  }

  /// 桌面上各模板的实例数（模板 key → 数量）。空表示没有实例，投影刷新可整体跳过。
  static Future<Map<String, int>> widgetInstanceCounts() async {
    try {
      return await _channel.invokeMapMethod<String, int>(
            'widgetInstanceCounts',
          ) ??
          const <String, int>{};
    } on MissingPluginException {
      return const <String, int>{};
    }
  }

  /// 从配置页打开主应用（全新安装还没推送过账本时，用户需要先打开一次应用）。
  static Future<void> openApp() async {
    try {
      await _channel.invokeMethod<void>('openApp');
    } on MissingPluginException {
      // 非 Android / 测试宿主：忽略。
    }
  }

  static Future<Map<String, Object?>?> consumeInitialRoute() async {
    try {
      return await _channel.invokeMapMethod<String, Object?>(
        'consumeWidgetRoute',
      );
    } on MissingPluginException {
      return null;
    }
  }
}
