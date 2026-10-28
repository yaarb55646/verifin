/// AI 渠道预设的稳定性与展示分组。
///
/// `id` 一经发布不得复用；新增渠道时同步添加图标、文档与测试。
enum AiProviderGroup {
  chinaOfficial,
  globalOfficial,
  aggregator,
  local,
  custom,
}

/// 一个只读的 OpenAI-compatible 渠道预设。
///
/// 预设只负责提供固定 Base URL、模型列表入口与 UI 元数据；API Key 与具体模型
/// 仍由用户在设置页填写。
class AiProviderPreset {
  const AiProviderPreset({
    required this.id,
    required this.brandName,
    required this.group,
    required this.baseUrl,
    required this.iconAsset,
    this.modelListUrl,
    this.searchTerms = const <String>[],
  });

  final String id;
  final String brandName;
  final AiProviderGroup group;
  final String baseUrl;

  /// 精确模型列表地址；为空时由 [aiModelListUrlFor] 按 Base URL 推导。
  final String? modelListUrl;

  /// 随 APK 打包的品牌图标；自定义渠道为空。
  final String? iconAsset;

  final List<String> searchTerms;

  bool get isCustom => group == AiProviderGroup.custom;
}

const String customAiProviderId = 'custom';

/// 第一版只内置 8 个核心渠道；自定义渠道作为常驻兜底入口。
const List<AiProviderPreset> aiProviderPresets = <AiProviderPreset>[
  AiProviderPreset(
    id: 'deepseek',
    brandName: 'DeepSeek',
    group: AiProviderGroup.chinaOfficial,
    baseUrl: 'https://api.deepseek.com/v1',
    iconAsset: 'assets/ai_providers/deepseek.svg',
    searchTerms: <String>['深度求索', 'ds', 'deep seek'],
  ),
  AiProviderPreset(
    id: 'volcengine-ark',
    brandName: '火山方舟',
    group: AiProviderGroup.chinaOfficial,
    baseUrl: 'https://ark.cn-beijing.volces.com/api/v3',
    iconAsset: 'assets/ai_providers/huoshan.png',
    searchTerms: <String>['volcengine', 'volcano', 'ark', 'doubao', '豆包', '字节'],
  ),
  AiProviderPreset(
    id: 'kimi',
    brandName: 'Kimi',
    group: AiProviderGroup.chinaOfficial,
    baseUrl: 'https://api.moonshot.cn/v1',
    iconAsset: 'assets/ai_providers/kimi.svg',
    searchTerms: <String>['moonshot', '月之暗面'],
  ),
  AiProviderPreset(
    id: 'zhipu-glm',
    brandName: '智谱 GLM',
    group: AiProviderGroup.chinaOfficial,
    baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
    iconAsset: 'assets/ai_providers/zhipu.svg',
    searchTerms: <String>['zhipu', 'bigmodel', 'chatglm', 'glm', '智谱清言'],
  ),
  AiProviderPreset(
    id: 'dashscope',
    brandName: '阿里云百炼',
    group: AiProviderGroup.chinaOfficial,
    baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
    iconAsset: 'assets/ai_providers/qianwenai.svg',
    searchTerms: <String>[
      'dashscope',
      'bailian',
      'qwen',
      'tongyi',
      '通义',
      '千问',
      '阿里',
    ],
  ),
  AiProviderPreset(
    id: 'openai',
    brandName: 'OpenAI',
    group: AiProviderGroup.globalOfficial,
    baseUrl: 'https://api.openai.com/v1',
    iconAsset: 'assets/ai_providers/openai.svg',
    searchTerms: <String>['gpt', 'chatgpt'],
  ),
  AiProviderPreset(
    id: 'openrouter',
    brandName: 'OpenRouter',
    group: AiProviderGroup.aggregator,
    baseUrl: 'https://openrouter.ai/api/v1',
    iconAsset: 'assets/ai_providers/openrouter.svg',
    searchTerms: <String>['router', '聚合', '路由'],
  ),
  AiProviderPreset(
    id: 'ollama',
    brandName: 'Ollama',
    group: AiProviderGroup.local,
    baseUrl: 'http://localhost:11434/v1',
    iconAsset: 'assets/ai_providers/ollama.svg',
    searchTerms: <String>['local', '本地', 'llama'],
  ),
];

const AiProviderPreset customAiProviderPreset = AiProviderPreset(
  id: customAiProviderId,
  brandName: '自定义',
  group: AiProviderGroup.custom,
  baseUrl: '',
  iconAsset: null,
  searchTerms: <String>[
    'openai compatible',
    'custom',
    'gateway',
    '自定义',
    '兼容',
    '网关',
  ],
);

/// 设置页与选择器共用的完整渠道列表（8 个预设 + 自定义）。
const List<AiProviderPreset> aiProviderChoices = <AiProviderPreset>[
  ...aiProviderPresets,
  customAiProviderPreset,
];

AiProviderPreset aiProviderPresetFor(String? id) {
  final normalized = id?.trim() ?? '';
  for (final preset in aiProviderChoices) {
    if (preset.id == normalized) {
      return preset;
    }
  }
  return customAiProviderPreset;
}

/// 模型列表地址：显式覆盖优先，否则按 Base URL 的版本段推导。
String aiModelListUrlFor({
  required AiProviderPreset provider,
  required String baseUrl,
  String modelListUrl = '',
}) {
  final explicit = modelListUrl.trim();
  if (explicit.isNotEmpty) {
    return explicit;
  }
  final presetOverride = provider.modelListUrl?.trim();
  if (presetOverride != null && presetOverride.isNotEmpty) {
    return presetOverride;
  }

  final normalized = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
  if (normalized.isEmpty) {
    return '';
  }
  final lastSegment = normalized.split('/').last;
  if (RegExp(r'^v\d+$').hasMatch(lastSegment)) {
    return '$normalized/models';
  }
  return '$normalized/v1/models';
}
