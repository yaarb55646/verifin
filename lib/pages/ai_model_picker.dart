import 'package:flutter/material.dart';

import '../app/ai/ai_model_catalog.dart';
import '../app/common_widgets.dart';
import '../l10n/app_localizations.dart';
import 'sheets.dart';

Future<String?> showAiModelPickerSheet({
  required BuildContext context,
  required List<AiModelInfo> models,
  required String selectedModel,
}) {
  return showVeriModalSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (context) =>
        _AiModelPickerBody(models: models, selectedModel: selectedModel),
  );
}

class _AiModelPickerBody extends StatefulWidget {
  const _AiModelPickerBody({required this.models, required this.selectedModel});

  final List<AiModelInfo> models;
  final String selectedModel;

  @override
  State<_AiModelPickerBody> createState() => _AiModelPickerBodyState();
}

class _AiModelPickerBodyState extends State<_AiModelPickerBody> {
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final query = _query.trim().toLowerCase();
    final filtered = widget.models
        .where(
          (model) =>
              query.isEmpty ||
              model.id.toLowerCase().contains(query) ||
              (model.ownedBy?.toLowerCase().contains(query) ?? false),
        )
        .toList(growable: false);
    final grouped = <String, List<AiModelInfo>>{};
    for (final model in filtered) {
      grouped
          .putIfAbsent(model.ownedBy ?? '', () => <AiModelInfo>[])
          .add(model);
    }
    final groups = grouped.keys.where((group) => group.isNotEmpty).toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final other = grouped[''];
    if (other != null && other.isNotEmpty) {
      groups.add('');
    }

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          14,
          10,
          14,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.76,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                l10n.aiProviderModelPickerTitle,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('ai_model_search_field'),
                controller: _search,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: l10n.aiProviderModelSearchHint,
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
                onChanged: (value) => setState(() => _query = value),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: filtered.isEmpty
                    ? EmptyState(
                        icon: Icons.search_off,
                        title: l10n.aiProviderModelEmpty,
                        description: l10n.aiProviderModelEmptyDesc,
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 4),
                        itemCount: _rowCount(groups, grouped),
                        itemBuilder: (context, index) =>
                            _buildRow(context, l10n, groups, grouped, index),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  int _rowCount(List<String> groups, Map<String, List<AiModelInfo>> grouped) {
    return groups.fold<int>(
      0,
      (count, group) => count + 1 + grouped[group]!.length,
    );
  }

  Widget _buildRow(
    BuildContext context,
    AppLocalizations l10n,
    List<String> groups,
    Map<String, List<AiModelInfo>> grouped,
    int index,
  ) {
    var cursor = index;
    for (final group in groups) {
      if (cursor == 0) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 5),
          child: Text(
            group.isEmpty ? l10n.aiProviderModelOtherGroup : group,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.58),
              fontWeight: FontWeight.w800,
            ),
          ),
        );
      }
      cursor -= 1;
      final models = grouped[group]!;
      if (cursor < models.length) {
        final model = models[cursor];
        final selected = model.id == widget.selectedModel;
        return ListTile(
          key: Key('ai_model_option_${model.id}'),
          minTileHeight: 48,
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          title: Text(
            model.id,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
          subtitle: model.ownedBy == null
              ? null
              : Text(
                  model.ownedBy!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
          trailing: selected
              ? Icon(
                  Icons.check_circle,
                  color: Theme.of(context).colorScheme.primary,
                  size: 18,
                )
              : null,
          onTap: () => Navigator.of(context).pop(model.id),
        );
      }
      cursor -= models.length;
    }
    return const SizedBox.shrink();
  }
}
