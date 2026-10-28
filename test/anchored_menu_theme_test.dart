import 'package:anchored_menu/anchored_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verifin/app/app_theme.dart';

void main() {
  for (final brightness in Brightness.values) {
    test('主题将设计令牌桥接给 anchored_menu：$brightness', () {
      final theme = buildVeriFinTheme(brightness);
      final menuTheme = theme.extension<AnchoredMenuThemeData>();

      expect(menuTheme, isNotNull);
      expect(menuTheme!.surfaceColor, veriElevatedSurfaceColor(brightness));
      expect(
        menuTheme.borderColor,
        brightness == Brightness.dark
            ? Colors.white.withValues(alpha: 0.12)
            : veriLine,
      );
      expect(menuTheme.foregroundColor, theme.colorScheme.onSurface);
      expect(menuTheme.selectedColor, theme.colorScheme.primary);
      expect(menuTheme.panelBorderRadius, BorderRadius.circular(veriRadiusXl));
      expect(menuTheme.itemBorderRadius, BorderRadius.circular(veriRadiusLg));
      expect(menuTheme.minWidth, 168);
    });
  }
}
