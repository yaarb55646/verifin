// AI 对话查询结果的渲染层：把工具产出的 [AiResultDisplay] 规格映射成图表 / 列表 /
// 统计卡 / 表格。与工具逻辑解耦——新增展示类型只需在 switch 里加一支。
import 'package:flutter/material.dart';

import '../app/ai/ai_query_tool.dart';
import '../app/app_theme.dart';
import '../app/chart_painters.dart';
import '../app/common_widgets.dart';
import '../app/currency_math.dart';
import '../app/ledger_math.dart';
import '../app/models.dart' show MoneyCodeDisplay;
import '../l10n/app_localizations.dart';

/// 把一条 [AiResultDisplay] 渲染成卡片。
class AiResultView extends StatelessWidget {
  const AiResultView({
    super.key,
    required this.display,
    required this.baseCurrencyCode,
    required this.moneyCodeDisplay,
  });

  final AiResultDisplay display;
  final String baseCurrencyCode;
  final MoneyCodeDisplay moneyCodeDisplay;

  @override
  Widget build(BuildContext context) {
    return switch (display) {
      final AiStatDisplay d => _StatCard(d, baseCurrencyCode, moneyCodeDisplay),
      final AiRankingDisplay d => _RankingCard(
        d,
        baseCurrencyCode,
        moneyCodeDisplay,
      ),
      final AiTrendDisplay d => _TrendCard(
        d,
        baseCurrencyCode,
        moneyCodeDisplay,
      ),
      final AiTransactionsDisplay d => _TransactionsCard(
        d,
        baseCurrencyCode: baseCurrencyCode,
        moneyCodeDisplay: moneyCodeDisplay,
      ),
      final AiTableDisplay d => _TableCard(d),
    };
  }
}

Widget _cardTitle(
  BuildContext context,
  String title, {
  String? currencyCode,
  MoneyCodeDisplay? moneyCodeDisplay,
}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      children: <Widget>[
        Expanded(
          child: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        if (currencyCode != null)
          MoneyUnitLabel(currencyCode: currencyCode, display: moneyCodeDisplay),
      ],
    ),
  );
}

Widget _emptyHint(BuildContext context, String text) {
  return Text(
    text,
    style: Theme.of(context).textTheme.bodySmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
    ),
  );
}

/// 图表纵轴 3 档标签，自下而上：0 / max·½ / max（紧凑格式）。
List<String> _yLabels(BuildContext context, Iterable<double> values) {
  final max = values.fold<double>(0, (m, v) => v.abs() > m ? v.abs() : m);
  if (max <= 0) {
    return const <String>[];
  }
  final l10n = AppLocalizations.of(context);
  return <String>[
    '0',
    formatCompactAmount(l10n, max / 2),
    formatCompactAmount(l10n, max),
  ];
}

class _StatCard extends StatelessWidget {
  const _StatCard(this.display, this.baseCurrencyCode, this.moneyCodeDisplay);
  final AiStatDisplay display;
  final String baseCurrencyCode;
  final MoneyCodeDisplay moneyCodeDisplay;

  @override
  Widget build(BuildContext context) {
    return VeriCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _cardTitle(
            context,
            display.title,
            currencyCode: baseCurrencyCode,
            moneyCodeDisplay: moneyCodeDisplay,
          ),
          for (final item in display.items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: <Widget>[
                  Text(
                    item.label,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const Spacer(),
                  Text(
                    formatMoney(
                      item.value,
                      baseCurrencyCode,
                      display: moneyCodeDisplay,
                    ),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: item.emphasize
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: item.emphasize
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _RankingCard extends StatelessWidget {
  const _RankingCard(
    this.display,
    this.baseCurrencyCode,
    this.moneyCodeDisplay,
  );
  final AiRankingDisplay display;
  final String baseCurrencyCode;
  final MoneyCodeDisplay moneyCodeDisplay;

  @override
  Widget build(BuildContext context) {
    final rows = display.rows;
    if (rows.isEmpty) {
      return VeriCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _cardTitle(
              context,
              display.title,
              currencyCode: baseCurrencyCode,
              moneyCodeDisplay: moneyCodeDisplay,
            ),
            _emptyHint(context, AppLocalizations.of(context).aiChatNoData),
          ],
        ),
      );
    }
    // 柱状图只画前若干名，避免横轴标签拥挤；完整明细在下方列表。
    final chartRows = rows.take(7).toList();
    final values = chartRows.map((r) => r.amount).toList();
    final labels = chartRows.map((r) => r.label).toList();
    return VeriCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _cardTitle(
            context,
            display.title,
            currencyCode: baseCurrencyCode,
            moneyCodeDisplay: moneyCodeDisplay,
          ),
          SizedBox(
            height: 172,
            child: InteractiveBarChart(
              values: values,
              xLabels: labels,
              yLabels: _yLabels(context, values),
              color: veriSemantic(
                context,
                display.isExpense ? veriExpense : veriIncome,
              ),
              tooltipOf: (index) => ChartTooltip(
                title: labels[index],
                lines: <ChartTooltipLine>[
                  ChartTooltipLine(
                    text: formatMoney(
                      values[index],
                      baseCurrencyCode,
                      display: moneyCodeDisplay,
                    ),
                  ),
                  ChartTooltipLine(
                    text:
                        '${(chartRows[index].percent * 100).toStringAsFixed(1)}% · ${AppLocalizations.of(context).entriesCount(chartRows[index].count)}',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          for (final row in rows.take(8))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      row.label,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  Text(
                    '${(row.percent * 100).toStringAsFixed(1)}%',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    formatMoney(
                      row.amount,
                      baseCurrencyCode,
                      display: moneyCodeDisplay,
                    ),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _TrendCard extends StatelessWidget {
  const _TrendCard(this.display, this.baseCurrencyCode, this.moneyCodeDisplay);
  final AiTrendDisplay display;
  final String baseCurrencyCode;
  final MoneyCodeDisplay moneyCodeDisplay;

  @override
  Widget build(BuildContext context) {
    if (display.values.isEmpty) {
      return VeriCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _cardTitle(
              context,
              display.title,
              currencyCode: baseCurrencyCode,
              moneyCodeDisplay: moneyCodeDisplay,
            ),
            _emptyHint(context, AppLocalizations.of(context).aiChatNoData),
          ],
        ),
      );
    }
    return VeriCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _cardTitle(
            context,
            display.title,
            currencyCode: baseCurrencyCode,
            moneyCodeDisplay: moneyCodeDisplay,
          ),
          SizedBox(
            height: 172,
            child: InteractiveTrendChart(
              color: display.isExpense
                  ? veriSemantic(context, veriExpense)
                  : veriSemantic(context, veriIncome),
              values: display.values,
              xLabels: display.labels,
              yLabels: _yLabels(context, display.values),
              tooltipOf: (index) => ChartTooltip(
                title: index < display.labels.length
                    ? display.labels[index]
                    : '',
                lines: <ChartTooltipLine>[
                  ChartTooltipLine(
                    text: formatMoney(
                      display.values[index],
                      baseCurrencyCode,
                      display: moneyCodeDisplay,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TransactionsCard extends StatelessWidget {
  const _TransactionsCard(
    this.display, {
    required this.baseCurrencyCode,
    required this.moneyCodeDisplay,
  });
  final AiTransactionsDisplay display;
  final String baseCurrencyCode;
  final MoneyCodeDisplay moneyCodeDisplay;

  @override
  Widget build(BuildContext context) {
    final entries = display.entries;
    if (entries.isEmpty) {
      return VeriCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _cardTitle(
              context,
              display.title,
              currencyCode: baseCurrencyCode,
              moneyCodeDisplay: moneyCodeDisplay,
            ),
            _emptyHint(
              context,
              AppLocalizations.of(context).aiChatNoMatchingTx,
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(left: 4, right: 4),
          child: _cardTitle(
            context,
            display.title,
            currencyCode: baseCurrencyCode,
            moneyCodeDisplay: moneyCodeDisplay,
          ),
        ),
        TransactionListCard(
          entries: entries,
          accounts: display.accounts,
          categories: display.categories,
          tags: display.tags,
          baseCurrencyCode: baseCurrencyCode,
          moneyDisplay: moneyCodeDisplay,
        ),
      ],
    );
  }
}

class _TableCard extends StatelessWidget {
  const _TableCard(this.display);
  final AiTableDisplay display;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final headerBg = isDark ? veriSurfaceAltDark : veriSurfaceAltLight;
    final divider = theme.colorScheme.onSurface.withValues(alpha: 0.07);
    final headerStyle = theme.textTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.w700,
      fontSize: 13.5,
    );
    final cellStyle = theme.textTheme.bodyMedium?.copyWith(
      fontSize: 13.5,
      height: 1.4,
    );

    // 无竖线、仅头部底色 + 行间细分隔线的精致表格；首列左对齐、其余右对齐。
    TableRow rowFor(List<String> cells, {required bool header}) {
      return TableRow(
        children: <Widget>[
          for (var i = 0; i < display.headers.length; i += 1)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Text(
                i < cells.length ? cells[i] : '',
                textAlign: i == 0 ? TextAlign.left : TextAlign.right,
                style: header ? headerStyle : cellStyle,
              ),
            ),
        ],
      );
    }

    return VeriCard(
      padding: const EdgeInsets.fromLTRB(13, 13, 13, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _cardTitle(context, display.title),
          ClipRRect(
            borderRadius: BorderRadius.circular(veriRadiusMd),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: divider),
                borderRadius: BorderRadius.circular(veriRadiusMd),
              ),
              // 列宽按内容取，整表在卡片内横向滚动：列多或文字长时不再撑破卡片。
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: constraints.maxWidth),
                    child: Table(
                      border: TableBorder(
                        horizontalInside: BorderSide(color: divider),
                      ),
                      defaultColumnWidth: const IntrinsicColumnWidth(),
                      defaultVerticalAlignment:
                          TableCellVerticalAlignment.middle,
                      children: <TableRow>[
                        TableRow(
                          decoration: BoxDecoration(color: headerBg),
                          children: <Widget>[
                            for (var i = 0; i < display.headers.length; i += 1)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                child: Text(
                                  display.headers[i],
                                  textAlign: i == 0
                                      ? TextAlign.left
                                      : TextAlign.right,
                                  style: headerStyle,
                                ),
                              ),
                          ],
                        ),
                        for (final row in display.rows)
                          rowFor(row, header: false),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 7),
        ],
      ),
    );
  }
}
