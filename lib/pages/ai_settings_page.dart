import 'dart:async';

import 'package:anchored_menu/anchored_menu.dart';
import 'package:flutter/material.dart';

import '../app/ai/ai_capabilities.dart';
import '../app/ai/ai_client.dart';
import '../app/ai/ai_model_catalog.dart';
import '../app/ai/ai_provider_presentation.dart';
import '../app/ai/ai_provider_presets.dart';
import '../app/ai/ai_settings.dart';
import '../app/app_theme.dart';
import '../app/common_widgets.dart';
import '../app/feedback.dart';
import '../app/veri_fin_scope.dart';
import '../l10n/app_localizations.dart';
import 'sheets.dart';
import 'ai_provider_logo.dart';

/// AI 记账设置页：配置 OpenAI 兼容服务的请求地址、API Key、模型，并测试连通性。
/// 配置为设备本地偏好（存 KV），不进 JSON 备份、初始化保留。
class AiSettingsPage extends StatefulWidget {
  const AiSettingsPage({super.key, this.debugFetchModels});

  final Future<List<AiModelInfo>> Function(
    AiSettings settings,
    AiProviderPreset provider,
  )?
  debugFetchModels;

  @override
  State<AiSettingsPage> createState() => _AiSettingsPageState();
}

class _AiSettingsPageState extends State<AiSettingsPage> {
  final EditorExitController _exitController = EditorExitController();
  final TextEditingController _baseUrlController = TextEditingController();
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _modelController = TextEditingController();
  final TextEditingController _modelListUrlController = TextEditingController();
  final TextEditingController _toolModeController = TextEditingController();
  bool _seeded = false;
  late AiSettings _initialSettings;
  bool _obscureKey = true;
  bool _testing = false;
  bool _fetchingModels = false;
  int _fetchToken = 0;
  String _providerId = customAiProviderId;
  AiToolCallMode _toolCallMode = AiToolCallMode.auto;
  AiCapabilityProfile? _detectedProfile;
  String? _statusText;
  bool _statusIsError = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_seeded) {
      final settings = VeriFinScope.of(context).aiSettings;
      _initialSettings = settings;
      _baseUrlController.text = settings.baseUrl;
      _apiKeyController.text = settings.apiKey;
      _modelController.text = settings.model;
      _modelListUrlController.text = settings.modelListUrl;
      _providerId = aiProviderPresetFor(settings.providerId).id;
      _toolCallMode = settings.toolCallMode;
      _toolModeController.text = _toolModeLabel(settings.toolCallMode);
      final cached = VeriFinScope.of(context).aiCapabilityProfile;
      if (cached?.matches(settings) == true) {
        _detectedProfile = cached;
        _statusText = _capabilityStatus(cached!, settings);
      }
      _seeded = true;
    }
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _modelController.dispose();
    _modelListUrlController.dispose();
    _toolModeController.dispose();
    super.dispose();
  }

  AiSettings _current() => AiSettings(
    providerId: _providerId,
    baseUrl: _baseUrlController.text.trim(),
    apiKey: _apiKeyController.text.trim(),
    model: _modelController.text.trim(),
    modelListUrl: _modelListUrlController.text.trim(),
    toolCallMode: _toolCallMode,
  );

  AiProviderPreset get _provider => aiProviderPresetFor(_providerId);

  bool get _isDirty => _seeded && _current() != _initialSettings;

  Future<void> _saveAndExit() async {
    if (await _save() && mounted) {
      setState(() => _initialSettings = _current());
      _exitController.exit();
    }
  }

  Future<bool> _save() async {
    final l10n = AppLocalizations.of(context);
    final settings = _current();
    if (!settings.isConfigured) {
      setState(() {
        _statusIsError = true;
        _statusText = l10n.aiFillAllFields;
      });
      return false;
    }
    // http 发往公网主机会明文暴露 API Key，保存前提醒确认。
    if (!await confirmCleartextIfRisky(context, settings.baseUrl)) return false;
    if (!mounted) return false;
    final detected = _detectedProfile;
    final saved = await VeriFinScope.of(
      context,
    ).saveAiSettingsDraft(settings, detectedProfile: detected);
    if (!mounted || !saved) {
      return false;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _statusIsError = false;
      _statusText = null;
    });
    return true;
  }

  Future<void> _clearConfig() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.aiClearConfig,
      message: l10n.aiClearConfigMessage,
      confirmLabel: l10n.aiClearConfig,
      destructive: true,
    );
    if (!confirmed || !mounted) {
      return;
    }
    final saved = await VeriFinScope.of(
      context,
    ).saveAiSettingsDraft(const AiSettings());
    if (!mounted || !saved) {
      return;
    }
    _baseUrlController.clear();
    _apiKeyController.clear();
    _modelController.clear();
    _modelListUrlController.clear();
    _providerId = customAiProviderId;
    _fetchToken += 1;
    _fetchingModels = false;
    _toolCallMode = AiToolCallMode.auto;
    _toolModeController.text = _toolModeLabel(AiToolCallMode.auto);
    _detectedProfile = null;
    _initialSettings = const AiSettings();
    FocusScope.of(context).unfocus();
    setState(() {
      _statusIsError = false;
      _statusText = null;
    });
    unawaited(
      VeriFeedbackHost.of(context).showMessage(
        message: l10n.aiConfigCleared,
        tone: VeriFeedbackTone.success,
      ),
    );
  }

  Future<void> _pickProvider() async {
    final selected = await showAiProviderSelectionSheet(
      context: context,
      selected: _providerId,
    );
    if (!mounted || selected == null || selected == _providerId) {
      return;
    }
    final provider = aiProviderPresetFor(selected);
    _fetchToken += 1;
    setState(() {
      _providerId = provider.id;
      _baseUrlController.text = provider.baseUrl;
      _apiKeyController.clear();
      _modelController.clear();
      _modelListUrlController.clear();
      _toolCallMode = AiToolCallMode.auto;
      _toolModeController.text = _toolModeLabel(AiToolCallMode.auto);
      _detectedProfile = null;
      _statusIsError = false;
      _statusText = null;
      _fetchingModels = false;
    });
  }

  Future<void> _fetchModels() async {
    if (_fetchingModels) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    final settings = _current();
    if (settings.baseUrl.trim().isEmpty) {
      unawaited(
        VeriFeedbackHost.of(context).showMessage(
          message: l10n.aiProviderMissingBaseUrl,
          tone: VeriFeedbackTone.warning,
        ),
      );
      return;
    }
    final provider = _provider;
    final modelListUrl = aiModelListUrlFor(
      provider: provider,
      baseUrl: settings.baseUrl,
      modelListUrl: settings.modelListUrl,
    );
    if (!await confirmCleartextIfRisky(context, modelListUrl)) {
      return;
    }
    if (!mounted) {
      return;
    }

    final token = ++_fetchToken;
    setState(() => _fetchingModels = true);
    try {
      final debugFetch = widget.debugFetchModels;
      final models = debugFetch == null
          ? await fetchAiModels(settings: settings, provider: provider)
          : await debugFetch(settings, provider);
      if (!mounted ||
          token != _fetchToken ||
          !_sameConnectionDraft(settings, provider)) {
        return;
      }
      if (models.isEmpty) {
        unawaited(
          VeriFeedbackHost.of(context).showMessage(
            message: l10n.aiProviderModelFetchEmpty,
            tone: VeriFeedbackTone.warning,
          ),
        );
        return;
      }
      setState(() => _fetchingModels = false);
      final selected = await showAiModelSelectionSheet(
        context: context,
        models: models,
        selectedModel: _modelController.text.trim(),
      );
      if (!mounted ||
          selected == null ||
          token != _fetchToken ||
          !_sameConnectionDraft(settings, provider)) {
        return;
      }
      setState(() {
        _modelController.text = selected;
        _detectedProfile = null;
        _statusIsError = false;
        _statusText = null;
      });
    } on AiException catch (error) {
      if (!mounted || token != _fetchToken) {
        return;
      }
      VeriFinScope.of(
        context,
      ).logger?.error('AI 模型列表获取失败', source: 'ai', error: error);
      unawaited(
        VeriFeedbackHost.of(context).showMessage(
          message: l10n.aiProviderModelFetchFailed(aiErrorMessage(l10n, error)),
          tone: VeriFeedbackTone.error,
          duration: VeriFeedbackDuration.long,
        ),
      );
    } catch (error) {
      if (!mounted || token != _fetchToken) {
        return;
      }
      VeriFinScope.of(
        context,
      ).logger?.error('AI 模型列表获取失败', source: 'ai', error: error);
      unawaited(
        VeriFeedbackHost.of(context).showMessage(
          message: l10n.aiProviderModelFetchFailed(l10n.aiErrUnknown),
          tone: VeriFeedbackTone.error,
          duration: VeriFeedbackDuration.long,
        ),
      );
    } finally {
      if (mounted && token == _fetchToken) {
        setState(() => _fetchingModels = false);
      }
    }
  }

  bool _sameConnectionDraft(AiSettings settings, AiProviderPreset provider) {
    final current = _current();
    return current.providerId == provider.id &&
        current.baseUrl == settings.baseUrl &&
        current.apiKey == settings.apiKey &&
        current.modelListUrl == settings.modelListUrl;
  }

  Future<void> _detectCapabilities() async {
    final l10n = AppLocalizations.of(context);
    final settings = _current();
    if (!settings.isConfigured) {
      setState(() {
        _statusIsError = true;
        _statusText = l10n.aiFillAllFields;
      });
      return;
    }
    if (!await confirmCleartextIfRisky(context, settings.baseUrl)) return;
    if (!mounted) return;
    setState(() {
      _testing = true;
      _statusIsError = false;
      _statusText = l10n.aiDetectingCapabilities;
    });
    try {
      final profile = await detectAiCapabilities(settings: settings);
      if (!mounted) {
        return;
      }
      final scope = VeriFinScope.of(context);
      if (profile.matches(scope.aiSettings)) {
        scope.setAiCapabilityProfile(profile);
      }
      setState(() {
        _detectedProfile = profile;
        _statusIsError = false;
        _statusText = _capabilityStatus(profile, settings);
      });
    } on AiException catch (error) {
      if (!mounted) {
        return;
      }
      VeriFinScope.of(
        context,
      ).logger?.error('AI 能力检测失败', source: 'ai', error: error);
      setState(() {
        _statusIsError = true;
        _statusText = l10n.connectionFailed(aiErrorMessage(l10n, error));
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      VeriFinScope.of(
        context,
      ).logger?.error('AI 能力检测失败', source: 'ai', error: error);
      setState(() {
        _statusIsError = true;
        _statusText = l10n.connectionFailed(l10n.aiErrUnknown);
      });
    } finally {
      if (mounted) {
        setState(() => _testing = false);
      }
    }
  }

  void _selectToolCallMode(AiToolCallMode selected) {
    setState(() {
      _toolCallMode = selected;
      _toolModeController.text = _toolModeLabel(selected);
      final profile = _detectedProfile;
      if (profile != null) {
        _statusText = _capabilityStatus(profile, _current());
      }
    });
  }

  String _toolModeLabel(AiToolCallMode mode) {
    final l10n = AppLocalizations.of(context);
    return switch (mode) {
      AiToolCallMode.auto => l10n.aiToolModeAuto,
      AiToolCallMode.native => l10n.aiToolModeNative,
      AiToolCallMode.prompt => l10n.aiToolModePrompt,
    };
  }

  String _toolModeHint(AiToolCallMode mode) {
    final l10n = AppLocalizations.of(context);
    return switch (mode) {
      AiToolCallMode.auto => l10n.aiToolModeAutoHint,
      AiToolCallMode.native => l10n.aiToolModeNativeHint,
      AiToolCallMode.prompt => l10n.aiToolModePromptHint,
    };
  }

  String _capabilityStatus(AiCapabilityProfile profile, AiSettings settings) {
    final l10n = AppLocalizations.of(context);
    final capability =
        profile.nativeToolCalls == AiNativeToolCapability.supported
        ? l10n.aiNativeToolsSupported
        : l10n.aiNativeToolsUnsupported;
    final effectiveMode = profile.effectiveMode(settings);
    final protocol = switch (effectiveMode) {
      AiToolCallMode.native => l10n.aiActualProtocolNative,
      AiToolCallMode.prompt => l10n.aiActualProtocolPrompt,
      AiToolCallMode.auto => l10n.aiActualProtocolAuto,
    };
    return '${l10n.aiConnectionReady}\n'
        '${l10n.aiStreamingReady}\n'
        '$capability\n'
        '$protocol';
  }

  void _onConfigChanged() {
    setState(() {
      _detectedProfile = null;
      _statusText = null;
      _statusIsError = false;
    });
  }

  InputDecoration _configInputDecoration({
    required String label,
    String? hint,
    String? helper,
    Widget? suffixIcon,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(veriRadiusMd),
      borderSide: BorderSide(color: isDark ? Colors.white24 : veriLine),
    );
    return InputDecoration(
      labelText: label,
      hintText: hint,
      helperText: helper,
      helperMaxLines: 2,
      filled: true,
      fillColor: isDark ? veriSurfaceAltDark : veriSurfaceAltLight,
      contentPadding: EdgeInsets.fromLTRB(
        14,
        14,
        suffixIcon == null ? 14 : 6,
        14,
      ),
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: BorderSide(color: theme.colorScheme.primary, width: 1.4),
      ),
      disabledBorder: border.copyWith(
        borderSide: BorderSide(
          color: (isDark ? Colors.white12 : veriLine).withValues(alpha: 0.7),
        ),
      ),
      suffixIcon: suffixIcon,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.55);

    return UnsavedChangesGuard(
      isDirty: _isDirty,
      onSave: _save,
      exitController: _exitController,
      child: Scaffold(
        body: SafeArea(
          child: VeriPage(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 28),
              children: <Widget>[
                VeriHeader(
                  title: l10n.aiSettingsTitle,
                  showBack: true,
                  actions: <Widget>[
                    HeaderAction(
                      icon: Icons.delete_outline,
                      tooltip: l10n.aiClearConfig,
                      destructive: true,
                      onPressed:
                          (_baseUrlController.text.isEmpty &&
                              _apiKeyController.text.isEmpty &&
                              _modelController.text.isEmpty &&
                              _modelListUrlController.text.isEmpty &&
                              _providerId == customAiProviderId)
                          ? null
                          : _clearConfig,
                    ),
                    SaveHeaderAction(
                      onPressed: _isDirty && _current().isConfigured
                          ? _saveAndExit
                          : null,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Semantics(
                  button: true,
                  label:
                      '${l10n.aiProviderCurrent}：${_provider.brandName}，'
                      '${aiProviderDescription(l10n, _provider)}',
                  child: VeriCard(
                    key: const Key('ai_provider_current_card'),
                    onTap: _pickProvider,
                    child: Row(
                      children: <Widget>[
                        AiProviderLogo(provider: _provider, size: 38),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                l10n.aiProviderCurrent,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: muted,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 1),
                              Text(
                                _provider.brandName,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                aiProviderDescription(l10n, _provider),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          l10n.aiProviderChange,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 2),
                        Icon(
                          Icons.chevron_right,
                          size: 18,
                          color: theme.colorScheme.primary,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                VeriCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      TextField(
                        controller: _baseUrlController,
                        readOnly: !_provider.isCustom,
                        onChanged: _provider.isCustom
                            ? (_) => _onConfigChanged()
                            : null,
                        keyboardType: TextInputType.url,
                        autocorrect: false,
                        decoration: _configInputDecoration(
                          label: l10n.aiBaseUrlLabel,
                          hint: _provider.isCustom ? l10n.aiBaseUrlHint : null,
                          helper: _provider.isCustom
                              ? l10n.aiProviderCustomBaseUrlHint
                              : null,
                          suffixIcon: _provider.isCustom
                              ? null
                              : const Icon(Icons.lock_outline),
                        ),
                      ),
                      if (_provider.isCustom) ...<Widget>[
                        const SizedBox(height: 10),
                        TextField(
                          controller: _modelListUrlController,
                          onChanged: (_) => _onConfigChanged(),
                          keyboardType: TextInputType.url,
                          autocorrect: false,
                          decoration: _configInputDecoration(
                            label: l10n.aiProviderModelListUrlLabel,
                            helper: l10n.aiProviderModelListUrlHint,
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      TextField(
                        controller: _apiKeyController,
                        onChanged: (_) => _onConfigChanged(),
                        obscureText: _obscureKey,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: _configInputDecoration(
                          label: l10n.aiProviderApiKeyLabel,
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureKey
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                            onPressed: () =>
                                setState(() => _obscureKey = !_obscureKey),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _modelController,
                        onChanged: (_) => _onConfigChanged(),
                        autocorrect: false,
                        decoration: _configInputDecoration(
                          label: l10n.aiProviderModelLabel,
                          hint: l10n.aiProviderModelHint,
                          suffixIcon: IconButton(
                            tooltip: _fetchingModels
                                ? l10n.aiProviderFetchingModels
                                : l10n.aiProviderFetchModels,
                            onPressed: _fetchingModels ? null : _fetchModels,
                            icon: _fetchingModels
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.expand_more),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      AnchoredMenuChoice<AiToolCallMode>(
                        values: AiToolCallMode.values,
                        selected: _toolCallMode,
                        idOf: (value) => 'ai_tool_mode_${value.name}',
                        labelOf: _toolModeLabel,
                        subtitleOf: _toolModeHint,
                        iconOf: (value) => switch (value) {
                          AiToolCallMode.auto => Icons.auto_awesome_outlined,
                          AiToolCallMode.native => Icons.extension_outlined,
                          AiToolCallMode.prompt => Icons.text_snippet_outlined,
                        },
                        onSelected: _selectToolCallMode,
                        semanticLabel: l10n.aiToolModeTitle,
                        builder: (context, openMenu, menuOpen) => TextField(
                          key: const Key('ai_tool_mode_field'),
                          controller: _toolModeController,
                          readOnly: true,
                          showCursor: false,
                          enableInteractiveSelection: false,
                          onTap: _testing ? null : openMenu,
                          decoration: _configInputDecoration(
                            label: l10n.aiToolModeTitle,
                            suffixIcon: const Icon(Icons.expand_more),
                          ),
                        ),
                      ),
                      if (_statusText != null) ...<Widget>[
                        const SizedBox(height: 12),
                        Text(
                          _statusText!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: _statusIsError
                                ? theme.colorScheme.error
                                : theme.colorScheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _testing ? null : _detectCapabilities,
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(44, 44),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(veriRadiusMd),
                            ),
                          ),
                          icon: _testing
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.wifi_tethering, size: 18),
                          label: Text(l10n.aiDetectCapabilities),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
