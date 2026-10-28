import '../../l10n/app_localizations.dart';
import 'ai_provider_presets.dart';

const List<AiProviderGroup> aiProviderGroupOrder = <AiProviderGroup>[
  AiProviderGroup.chinaOfficial,
  AiProviderGroup.globalOfficial,
  AiProviderGroup.aggregator,
  AiProviderGroup.local,
  AiProviderGroup.custom,
];

String aiProviderGroupLabel(AppLocalizations l10n, AiProviderGroup group) =>
    switch (group) {
      AiProviderGroup.chinaOfficial => l10n.aiProviderGroupChinaOfficial,
      AiProviderGroup.globalOfficial => l10n.aiProviderGroupGlobalOfficial,
      AiProviderGroup.aggregator => l10n.aiProviderGroupAggregator,
      AiProviderGroup.local => l10n.aiProviderGroupLocal,
      AiProviderGroup.custom => l10n.aiProviderGroupCustom,
    };

String aiProviderDescription(
  AppLocalizations l10n,
  AiProviderPreset provider,
) => switch (provider.id) {
  'deepseek' => l10n.aiProviderDescDeepSeek,
  'volcengine-ark' => l10n.aiProviderDescVolcengine,
  'kimi' => l10n.aiProviderDescKimi,
  'zhipu-glm' => l10n.aiProviderDescZhipu,
  'dashscope' => l10n.aiProviderDescDashscope,
  'openai' => l10n.aiProviderDescOpenai,
  'openrouter' => l10n.aiProviderDescOpenrouter,
  'ollama' => l10n.aiProviderDescOllama,
  _ => l10n.aiProviderDescCustom,
};

bool aiProviderMatchesSearch({
  required AppLocalizations l10n,
  required AiProviderPreset provider,
  required String query,
}) {
  final normalized = _normalize(query);
  if (normalized.isEmpty) {
    return true;
  }
  final uri = Uri.tryParse(provider.baseUrl);
  return <String>[
    provider.brandName,
    provider.id,
    provider.baseUrl,
    if (uri != null) uri.host,
    aiProviderDescription(l10n, provider),
    aiProviderGroupLabel(l10n, provider.group),
    ...provider.searchTerms,
  ].any((term) => _normalize(term).contains(normalized));
}

String _normalize(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'\s+'), '');
