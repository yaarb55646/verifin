import 'package:flutter/material.dart';

import '../app/app_theme.dart';
import '../app/category_tree.dart';
import '../app/chart_painters.dart';
import '../app/common_widgets.dart';
import '../app/currency_math.dart';
import '../app/ledger_math.dart';
import '../app/models.dart';
import '../app/report_analysis.dart';
import '../app/veri_fin_scope.dart';
import '../l10n/app_localizations.dart';

/// 日常/月/年共用的分类占比卡。范围由外层明确提供，卡内切换只影响当前视图。
class CategorySharePanel extends StatefulWidget {
  const CategorySharePanel({
    super.key,
    required this.window,
    required this.rangeLabel,
  });

  final DateWindow window;
  final String rangeLabel;

  @override
  State<CategorySharePanel> createState() => _CategorySharePanelState();
}

class _CategorySharePanelState extends State<CategorySharePanel> {
  EntryType _type = EntryType.expense;
  bool _showSubcategories = false;
  bool _showAmounts = false;
  String? _selectedId;

  @override
  Widget build(BuildContext context) {
    final controller = VeriFinScope.of(context);
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final title = _type == EntryType.expense
        ? l10n.panelCategoryShareLabel
        : l10n.panelIncomeShareLabel;
    final stats = reportCategoryShareStats(
      entries: entriesInWindow(controller.entries, widget.window),
      categories: controller.categories,
      bookId: controller.activeBook.id,
      type: _type,
      showSubcategories: _showSubcategories,
    ).where((stat) => stat.amount > 0).toList(growable: false);
    final total = stats.fold<double>(0, (sum, stat) => sum + stat.amount);
    final palette = <Color>[
      theme.colorScheme.primary,
      veriSemantic(context, veriBlue),
      veriSemantic(context, veriIncome),
      veriSemantic(context, veriWarning),
      veriSemantic(context, veriExpense),
      theme.colorScheme.secondary,
      theme.colorScheme.tertiary,
    ];
    final selectedIndex = stats.indexWhere(
      (stat) => stat.categoryId == _selectedId,
    );
    final selected = selectedIndex < 0 ? null : stats[selectedIndex];
    final categories = controller.categories;
    String labelFor(ReportCategoryStat stat) => _showSubcategories
        ? pathLabel(categories, stat.categoryId).isEmpty
              ? stat.category.label
              : pathLabel(categories, stat.categoryId)
        : stat.category.label;
    final centerAmount = selected?.amount ?? total;

    void select(int? index) => setState(() {
      _selectedId = index == null ? null : stats[index].categoryId;
    });

    return VeriCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionTitle(
            title: title,
            trailingWidget: VeriEntryTypeToggle(
              compact: true,
              dimension: _type,
              onChanged: (type) => setState(() {
                _type = type;
                _selectedId = null;
              }),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            widget.rangeLabel,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          if (stats.isEmpty)
            EmptyState(
              icon: Icons.donut_small_outlined,
              title: l10n.noDimData(_type.label(l10n)),
              description: l10n.panelCategoryShareDesc,
            )
          else ...<Widget>[
            Center(
              child: SizedBox(
                width: 176,
                height: 176,
                child: VeriDonutChart(
                  key: const Key('category_share_chart'),
                  segments: <VeriDonutSegment>[
                    for (final (index, stat) in stats.indexed)
                      VeriDonutSegment(
                        label: labelFor(stat),
                        value: stat.amount,
                        color: palette[index % palette.length],
                      ),
                  ],
                  selectedIndex: selectedIndex < 0 ? null : selectedIndex,
                  onSelected: select,
                  ringWidth: 30,
                  showPercentTitles: true,
                  semanticsLabel: title,
                  center: SizedBox(
                    width: 100,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          selected == null
                              ? (_type == EntryType.expense
                                    ? l10n.totalExpenseLabel
                                    : l10n.totalIncomeLabel)
                              : labelFor(selected),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.labelSmall,
                        ),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            formatUserMoney(
                              centerAmount,
                              controller.activeBook.baseCurrencyCode,
                            ),
                            key: const Key('category_share_center_amount'),
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (selected != null)
                          Text(
                            '${(selected.percent * 100).toStringAsFixed(1)}%',
                            style: theme.textTheme.labelSmall,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            for (final (index, stat) in stats.indexed)
              InkWell(
                key: ValueKey('category_share_legend_${stat.categoryId}'),
                borderRadius: BorderRadius.circular(veriRadiusSm),
                onTap: () =>
                    select(_selectedId == stat.categoryId ? null : index),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: <Widget>[
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: palette[index % palette.length],
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          labelFor(stat),
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: _selectedId == stat.categoryId
                                ? FontWeight.w800
                                : null,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: <Widget>[
                          Text(
                            '${(stat.percent * 100).toStringAsFixed(1)}%',
                            style: theme.textTheme.labelMedium,
                          ),
                          if (_showAmounts)
                            Text(
                              formatUserMoney(
                                stat.amount,
                                controller.activeBook.baseCurrencyCode,
                              ),
                              style: theme.textTheme.labelSmall,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
          const SizedBox(height: 6),
          // Wrap 保证窄屏和大字号时两个选项仍可操作，不把触控区压到 48dp 以下。
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              alignment: WrapAlignment.end,
              children: <Widget>[
                _option(
                  key: const Key('category_share_subcategories'),
                  label: l10n.categoryShareSubcategories,
                  value: _showSubcategories,
                  onChanged: (value) => setState(() {
                    _showSubcategories = value;
                    _selectedId = null;
                  }),
                ),
                _option(
                  key: const Key('category_share_show_amounts'),
                  label: l10n.categoryShareShowAmounts,
                  value: _showAmounts,
                  onChanged: (value) => setState(() => _showAmounts = value),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _option({
    required Key key,
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return InkWell(
      key: key,
      borderRadius: BorderRadius.circular(veriRadiusSm),
      onTap: () => onChanged(!value),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Checkbox(
            value: value,
            onChanged: (value) => onChanged(value ?? false),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}
