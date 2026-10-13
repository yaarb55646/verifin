import 'package:flutter/material.dart';

import '../app/quick_entry_text.dart';
import '../l10n/app_localizations.dart';
import 'sheets.dart';

/// 用户在弹层里选了「改用数字键盘」——与「直接取消」（返回 null）区分开：
/// 前者要接着弹数字键盘，后者直接结束。
const Object quickTextEntryUseNumberPad = Object();

/// 弹层返回的结果：解析出的金额 + 备注。
class QuickTextEntryResult {
  const QuickTextEntryResult({required this.amount, required this.note});

  /// 已确定的金额；为 null 表示文字里没有金额（此时 [note] 是整段原文）。
  final double? amount;

  /// 备注：有金额时是剥掉金额后的剩余文字（可能为空串），无金额时是整段原文。
  final String note;
}

/// 「一句话记账」入口：让用户敲一行文字（如「早餐 5 元」），在本机拆出金额与备注，
/// 再交给记账页确认。返回 [QuickTextEntryResult]；取消返回 null；
/// 选「改用数字键盘」返回 [quickTextEntryUseNumberPad]。
///
/// 与 AI 记账的区别：全程本地、不联网、不需要 API Key，因此只认「金额 + 备注」，
/// 不解析日期、账户、分类——那些仍由记账页的历史识别与用户自己确认。
Future<Object?> showQuickTextEntrySheet(BuildContext context) {
  return showVeriModalSheet<Object>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => const QuickTextEntrySheet(),
  );
}

/// 弹层组件体。**勿直接实例化**——统一走 [showQuickTextEntrySheet]。
class QuickTextEntrySheet extends StatefulWidget {
  const QuickTextEntrySheet({super.key});

  @override
  State<QuickTextEntrySheet> createState() => _QuickTextEntrySheetState();
}

class _QuickTextEntrySheetState extends State<QuickTextEntrySheet> {
  final TextEditingController _controller = TextEditingController();
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final raw = _controller.text.trim();
    if (raw.isEmpty) {
      setState(() => _errorText = AppLocalizations.of(context).quickTextEntryEmpty);
      return;
    }
    final parsed = parseQuickEntryText(raw);
    // 拆不出金额也照样往下走：按约定整段文字作为备注，用户在记账页补金额。
    Navigator.of(context).pop(
      QuickTextEntryResult(amount: parsed.amount, note: parsed.note),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.55);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.keyboard_alt_outlined,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                l10n.quickTextEntryTitle,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('quick_text_entry_field'),
            controller: _controller,
            autofocus: true,
            minLines: 1,
            maxLines: 3,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              hintText: l10n.quickTextEntryHint,
              border: const OutlineInputBorder(),
              errorText: _errorText,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(Icons.offline_bolt_outlined, size: 14, color: muted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  l10n.quickTextEntryDesc,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: muted,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const Key('quick_text_entry_submit'),
              onPressed: _submit,
              icon: const Icon(Icons.arrow_forward, size: 18),
              label: Text(l10n.quickTextEntrySubmit),
            ),
          ),
          const SizedBox(height: 6),
          // 出口：不想打字就走原来的数字键盘，避免把新入口变成唯一路径。
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              key: const Key('quick_text_entry_number_pad'),
              onPressed: () =>
                  Navigator.of(context).pop(quickTextEntryUseNumberPad),
              icon: const Icon(Icons.dialpad_outlined, size: 18),
              label: Text(l10n.quickTextEntryManual),
            ),
          ),
        ],
      ),
    );
  }
}
