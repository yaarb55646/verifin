import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'common_widgets.dart';
import 'models.dart';
import '../l10n/app_localizations.dart';

/// 记账页「分类」区下方的子分类面板：常驻显示**当前选中父分类**的直接子分类，
/// 每行 5 个，末尾一个「新增」格子。
///
/// 设计意图：把子分类从「再点一次父分类才弹出」的二级弹窗里搬到主页面，选中
/// 子分类从 3 次点击降到 1 次。父分类胶囊网格本身不变，本面板只跟着选中项换内容。
///
/// 组件体，由记账页直接嵌入（不是弹层）。
class EntrySubcategoryPanel extends StatelessWidget {
  const EntrySubcategoryPanel({
    super.key,
    required this.children,
    required this.selectedId,
    required this.accent,
    required this.onSelected,
    required this.onCreate,
  });

  /// 当前选中父分类的直接子分类（仅一层），保持列表顺序。
  final List<Category> children;

  /// 当前选中的分类 id（可能是父分类本身，也可能是其中某个子分类）。
  final String selectedId;

  /// 语义色（支出红 / 收入青绿 / 转账蓝），与上方胶囊一致。
  final Color accent;

  final ValueChanged<Category> onSelected;

  /// 点「新增」：由调用方负责弹输入框、创建子分类。
  final VoidCallback onCreate;

  /// 每行格子数。
  static const int _columns = 5;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    // 子分类为空时仍显示面板：只留「新增」入口，让用户能就地建第一个子分类，
    // 而不是找不到入口。
    final cells = <Widget>[
      for (final child in children)
        _SubcategoryCell(
          key: ValueKey<String>('entry_subcategory_${child.id}'),
          label: child.label,
          iconCode: child.iconCode,
          accent: accent,
          selected: child.id == selectedId,
          onTap: () => onSelected(child),
        ),
      _SubcategoryAddCell(
        key: const Key('entry_subcategory_add'),
        label: l10n.entrySubcategoryAdd,
        onTap: onCreate,
      ),
    ];

    return Container(
      key: const Key('entry_subcategory_panel'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(veriRadiusMd),
      ),
      child: Wrap(
        spacing: 4,
        runSpacing: 10,
        children: <Widget>[
          for (final cell in cells)
            SizedBox(
              // 5 列：减去容器左右内边距（16）与 4 个 4px 间距（16）。
              width:
                  (MediaQuery.sizeOf(context).width -
                      14 * 2 -
                      16 -
                      4 * (_columns - 1)) /
                  _columns,
              child: cell,
            ),
        ],
      ),
    );
  }
}

/// 单个子分类格子：图标在上、名称在下，整格可点。
class _SubcategoryCell extends StatelessWidget {
  const _SubcategoryCell({
    super.key,
    required this.label,
    required this.iconCode,
    required this.accent,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String iconCode;
  final Color accent;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(veriRadiusSm),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // 选中态用一圈描边表达，不改变图标底色，避免与语义色打架。
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(veriRadiusSm),
                border: selected
                    ? Border.all(color: accent, width: 2)
                    : Border.all(color: Colors.transparent, width: 2),
              ),
              child: CategoryIconBox(iconCode: iconCode, size: 34),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: selected
                    ? accent
                    : scheme.onSurface.withValues(alpha: 0.72),
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 末尾的「新增」格子：虚框加号，视觉上弱于真实子分类。
class _SubcategoryAddCell extends StatelessWidget {
  const _SubcategoryAddCell({
    super.key,
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurface.withValues(alpha: 0.45);
    return InkWell(
      borderRadius: BorderRadius.circular(veriRadiusSm),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(veriRadiusSm),
                border: Border.all(color: muted, width: 1.2),
              ),
              child: Icon(Icons.add, size: 20, color: muted),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: muted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
