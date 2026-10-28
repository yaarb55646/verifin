import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('正式 Manifest 明确禁用 Android 系统备份', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(manifest, contains('android:allowBackup="false"'));
  });

  test('桌面只注册固定模板 Provider，并统一接入 home_widget 配置 Activity', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(manifest, contains('android:name=".WidgetConfigurationActivity"'));
    expect(manifest, contains('HomeWidgetScheduledUpdateReceiver'));
    expect(manifest, contains('android:name=".QuickEntryWidgetProvider"'));
    expect(manifest, contains('android:name=".BudgetWidgetProvider"'));
    expect(manifest, contains('android:name=".NetWorthWidgetProvider"'));
    expect(manifest, contains('android:name=".TrendWidgetProvider"'));
  });

  test('桌面与分享入口关闭 Flutter 自动深链，避免 URI 被当作命名路由', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    final deeplinkOptOut = RegExp(
      r'<meta-data\s+android:name="flutter_deeplinking_enabled"\s+'
      r'android:value="false"\s*/>',
    );
    for (final activity in <String>[
      'MainActivity',
      'WidgetConfigurationActivity',
    ]) {
      final match = RegExp(
        '<activity\\s+android:name="\\.$activity"[\\s\\S]*?</activity>',
      ).firstMatch(manifest);
      expect(match, isNotNull, reason: 'Manifest 缺少 $activity');
      expect(
        deeplinkOptOut.hasMatch(match!.group(0)!),
        isTrue,
        reason: '$activity 必须由应用自行解析 URI，不能让 Flutter 推入命名路由',
      );
    }
  });
}
