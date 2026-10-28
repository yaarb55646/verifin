import 'package:flutter_test/flutter_test.dart';
import 'package:verifin/app/ai/ai_provider_presets.dart';

void main() {
  test('核心渠道固定为八个，自定义不计入其中', () {
    expect(aiProviderPresets, hasLength(8));
    expect(aiProviderChoices, hasLength(9));
    expect(
      aiProviderPresets.map((preset) => preset.id),
      isNot(contains('custom')),
    );
    expect(customAiProviderPreset.group, AiProviderGroup.custom);
  });

  test('渠道 ID 唯一且预设地址有效', () {
    final ids = aiProviderChoices.map((preset) => preset.id).toList();
    expect(ids.toSet(), hasLength(ids.length));
    for (final preset in aiProviderPresets) {
      expect(preset.id.trim(), isNotEmpty);
      expect(Uri.tryParse(preset.baseUrl), isNotNull, reason: preset.id);
      expect(preset.baseUrl, isNot(endsWith('/chat/completions')));
      expect(preset.iconAsset, isNotNull, reason: preset.id);
    }
  });

  test('未知渠道安全回退到自定义', () {
    expect(aiProviderPresetFor('missing').id, customAiProviderId);
    expect(aiProviderPresetFor(null).id, customAiProviderId);
    expect(aiProviderPresetFor('deepseek').brandName, 'DeepSeek');
  });

  test('模型列表地址按版本段推导并支持显式覆盖', () {
    expect(
      aiModelListUrlFor(
        provider: aiProviderPresetFor('deepseek'),
        baseUrl: 'https://api.deepseek.com/v1/',
      ),
      'https://api.deepseek.com/v1/models',
    );
    expect(
      aiModelListUrlFor(
        provider: aiProviderPresetFor('zhipu-glm'),
        baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
      ),
      'https://open.bigmodel.cn/api/paas/v4/models',
    );
    expect(
      aiModelListUrlFor(
        provider: customAiProviderPreset,
        baseUrl: 'https://example.com',
      ),
      'https://example.com/v1/models',
    );
    expect(
      aiModelListUrlFor(
        provider: customAiProviderPreset,
        baseUrl: 'https://example.com',
        modelListUrl: 'https://example.com/custom/models',
      ),
      'https://example.com/custom/models',
    );
  });
}
