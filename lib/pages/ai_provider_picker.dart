import 'package:flutter/material.dart';

import '../app/ai/ai_provider_presentation.dart';
import '../app/ai/ai_provider_presets.dart';
import '../app/app_theme.dart';
import '../app/common_widgets.dart';
import '../l10n/app_localizations.dart';
import 'ai_provider_logo.dart';
import 'sheets.dart';

Future<String?> showAiProviderPickerSheet({
  required BuildContext context,
  required String selectedProviderId,
}) {
  return showVeriModalSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (context) =>
        _AiProviderPickerBody(selectedProviderId: selectedProviderId),
  );
}

class _AiProviderPickerBody extends StatefulWidget {
  const _AiProviderPickerBody({required this.selectedProviderId});

  final String selectedProviderId;

  @override
  State<_AiProviderPickerBody> createState() => _AiProviderPickerBodyState();
}

class _AiProviderPickerBodyState extends State<_AiProviderPickerBody> {
  final TextEditingController _search = TextEditingController();
  String _query = '';
  AiProviderGroup? _group;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Widget _filters(AppLocalizations l10n) {
    final entries = <(String, AiProviderGroup?, String)>[
      ('all', null, l10n.aiProviderGroupAll),
      for (final group in aiProviderGroupOrder)
        (group.name, group, aiProviderGroupLabel(l10n, group)),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          for (final (key, group, label) in entries) ...<Widget>[
            ChoiceChip(
              key: Key('ai_provider_group_$key'),
              label: Text(label),
              selected: _group == group,
              showCheckmark: false,
              materialTapTargetSize: MaterialTapTargetSize.padded,
              selectedColor: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.14),
              onSelected: (_) => setState(() {
                _group = group;
                _query = '';
                _search.clear();
              }),
            ),
            if (key != entries.last.$1) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  List<AiProviderPreset> _visibleChoices(AppLocalizations l10n) {
    return aiProviderChoices
        .where((provider) => _group == null || provider.group == _group)
        .where(
          (provider) => aiProviderMatchesSearch(
            l10n: l10n,
            provider: provider,
            query: _query,
          ),
        )
        .toList(growable: false);
  }

  Widget _gridTile(
    BuildContext context,
    AppLocalizations l10n,
    AiProviderPreset provider,
  ) {
    final selected = provider.id == widget.selectedProviderId;
    final description = aiProviderDescription(l10n, provider);
    return Semantics(
      button: true,
      selected: selected,
      label: '${provider.brandName}，$description',
      child: Material(
        color: selected
            ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.10)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(veriRadiusMd),
        child: InkWell(
          key: Key('ai_provider_option_${provider.id}'),
          borderRadius: BorderRadius.circular(veriRadiusMd),
          onTap: () => Navigator.of(context).pop(provider.id),
          child: Container(
            padding: const EdgeInsets.fromLTRB(6, 8, 6, 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(veriRadiusMd),
              border: Border.all(
                color: selected
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.10),
                width: selected ? 2 : 1,
              ),
            ),
            child: Stack(
              children: <Widget>[
                Align(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      AiProviderLogo(provider: provider, size: 36),
                      const SizedBox(height: 5),
                      Text(
                        provider.brandName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontWeight: selected
                              ? FontWeight.w800
                              : FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontSize: 9.5,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.55),
                        ),
                      ),
                    ],
                  ),
                ),
                if (selected)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Icon(
                      Icons.check_circle,
                      size: 15,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _browse(AppLocalizations l10n) {
    final groups = _group == null
        ? <AiProviderGroup?>[null, ...aiProviderGroupOrder]
        : <AiProviderGroup?>[_group];
    final children = <Widget>[];
    for (final group in groups) {
      if (group == null) {
        continue;
      }
      final providers = aiProviderChoices
          .where((provider) => provider.group == group)
          .toList(growable: false);
      if (providers.isEmpty) {
        continue;
      }
      children.add(
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 8),
          child: Text(
            aiProviderGroupLabel(l10n, group),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.58),
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      );
      children.add(
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 120,
            mainAxisExtent: 112,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
          ),
          itemCount: providers.length,
          itemBuilder: (context, index) =>
              _gridTile(context, l10n, providers[index]),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 4),
      children: children,
    );
  }

  Widget _searchResults(AppLocalizations l10n) {
    final providers = _visibleChoices(l10n);
    if (providers.isEmpty) {
      return EmptyState(
        icon: Icons.search_off,
        title: l10n.aiProviderSearchEmpty,
        description: l10n.aiProviderSearchEmptyDesc,
      );
    }
    return ListView.separated(
      itemCount: providers.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final provider = providers[index];
        final selected = provider.id == widget.selectedProviderId;
        return ListTile(
          key: Key('ai_provider_search_result_${provider.id}'),
          minTileHeight: 64,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 4,
          ),
          leading: AiProviderLogo(provider: provider, size: 38),
          title: Text(
            provider.brandName,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
            ),
          ),
          subtitle: Text(
            '${aiProviderDescription(l10n, provider)} · '
            '${aiProviderGroupLabel(l10n, provider.group)}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: selected
              ? Icon(
                  Icons.check_circle,
                  color: Theme.of(context).colorScheme.primary,
                  size: 18,
                )
              : null,
          onTap: () => Navigator.of(context).pop(provider.id),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final searchActive = _query.trim().isNotEmpty;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          14,
          10,
          14,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.82,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                l10n.aiProviderPickerTitle,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 2),
              Text(
                l10n.aiProviderPickerSubtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.58),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('ai_provider_search_field'),
                controller: _search,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: l10n.aiProviderSearchHint,
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: l10n.commonClear,
                          onPressed: () {
                            _search.clear();
                            setState(() => _query = '');
                          },
                          icon: const Icon(Icons.close),
                        ),
                ),
                onChanged: (value) => setState(() {
                  _query = value;
                  if (value.trim().isNotEmpty) {
                    _group = null;
                  }
                }),
              ),
              const SizedBox(height: 10),
              _filters(l10n),
              const SizedBox(height: 2),
              Expanded(
                child: searchActive ? _searchResults(l10n) : _browse(l10n),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
