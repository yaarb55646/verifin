import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../app/ai/ai_provider_presets.dart';
import '../app/app_theme.dart';

/// 渠道 Logo 的统一实底托盘；品牌素材保持原色与比例。
class AiProviderLogo extends StatelessWidget {
  const AiProviderLogo({super.key, required this.provider, this.size = 36});

  final AiProviderPreset provider;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final asset = provider.iconAsset;
    final child = asset == null
        ? Icon(
            Icons.hub_outlined,
            size: size * 0.55,
            color: theme.colorScheme.primary,
          )
        : asset.endsWith('.svg')
        ? SvgPicture.asset(asset, fit: BoxFit.contain)
        : Image.asset(
            asset,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
          );
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        padding: EdgeInsets.all(size * 0.12),
        decoration: BoxDecoration(
          color: asset == null
              ? theme.colorScheme.surfaceContainerHighest
              : Colors.white,
          borderRadius: BorderRadius.circular(veriRadiusSm),
          border: Border.all(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.12),
          ),
        ),
        child: child,
      ),
    );
  }
}
