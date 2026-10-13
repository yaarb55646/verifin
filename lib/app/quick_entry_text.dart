/// 「一句话记账」的本地文字解析：把用户敲的一行文字拆成金额与备注，不联网、
/// 不调用 AI、不依赖 Flutter。纯函数，便于单测。
///
/// 设计取向是**宁可少认，不可认错**：拆不出确定的金额时返回 `amount == null`，
/// 由调用方把整段文字当备注处理，绝不猜一个金额出来。
///
/// 金额识别按优先级依次尝试：
/// 1. 带货币符号或单位词的（`¥32`、`32元`、`32块`、`32块钱`、`$5.5`）；
/// 2. 纯四则算式（`500+800`，复用 `calc_expression.dart` 的求值）；
/// 3. 裸数字（`打车 32`），多个数字时取**最后一个**——中文口语习惯把金额放在末尾
///    （「早餐两个包子 5 元」「买3斤苹果 12」）。
library;

import 'calc_expression.dart';

/// 解析结果。[amount] 为 null 表示没能确定金额；[note] 是剥掉金额后的剩余文字。
class QuickEntryParse {
  const QuickEntryParse({required this.amount, required this.note});

  /// 识别出的金额（正数）；无法确定时为 null。
  final double? amount;

  /// 剥掉金额片段后的备注，已去除首尾空白与残留的分隔标点。
  final String note;

  /// 是否识别出了金额。
  bool get hasAmount => amount != null && amount! > 0;
}

/// 货币符号 → 无实义，只用于把符号连同其后的数字一起吃掉。
/// 只列常见符号；识别出符号不改变币种（币种仍由账户/账本决定），符号仅帮助定位金额。
const String _currencySymbols = r'¥￥$€£₩₽₹';

/// 数字字符（含全角）与小数点、千分位逗号。
final RegExp _numberPattern = RegExp(r'[0-9０-９]+(?:[.．][0-9０-９]+)?');

/// 形如「数字 + 可选单位词」的金额片段。单位词按**长优先**排列（`块钱` 先于 `块`），
/// 否则 `18块钱` 只会吃掉 `块`、留下 `钱`。
final RegExp _amountWithUnitPattern = RegExp(
  r'([0-9０-９]+(?:[.．][0-9０-９]+)?)\s*(?:'
  '块钱|元钱|块|元|圆|rmb|cny'
  ')',
  caseSensitive: false,
);

/// 货币符号 + 数字。
final RegExp _symbolAmountPattern = RegExp(
  '[$_currencySymbols]\\s*([0-9０-９]+(?:[.．][0-9０-９]+)?)',
);

/// 数字之间的千分位逗号（`1,234.5`）：仅当逗号两侧都是三位一组的数字时才吞掉，
/// 避免把「买2,3斤」这类内容误连成一个数。
final RegExp _thousandsSeparator = RegExp(r'(?<=\d),(?=\d{3}(?!\d))');

/// 把全角数字与全角小数点归一成 ASCII，便于后续解析。
String _normalizeDigits(String raw) {
  final buffer = StringBuffer();
  for (final rune in raw.runes) {
    // 全角 ０-９ 位于 U+FF10–U+FF19，与 ASCII 相差 0xFEE0。
    if (rune >= 0xFF10 && rune <= 0xFF19) {
      buffer.writeCharCode(rune - 0xFEE0);
    } else if (rune == 0xFF0E) {
      buffer.write('.');
    } else {
      buffer.writeCharCode(rune);
    }
  }
  return buffer.toString();
}

/// 解析一行文字。永不抛异常。
QuickEntryParse parseQuickEntryText(String raw) {
  // 先归一全角数字，再吞掉数字间的千分位逗号（`1,200` → `1200`）。后续所有匹配都在
  // 这个规范串上进行——否则 `1,200元` 会被裸数字规则拆成 `200`。
  final normalized = _thousandsSeparator.replaceAll(
    _normalizeDigits(raw.trim()),
    '',
  );
  if (normalized.isEmpty) {
    return const QuickEntryParse(amount: null, note: '');
  }

  // 优先级 1：带单位词的金额。命中最靠后的一处（口语金额常出现在末尾）。
  final withUnit = _amountWithUnitPattern.allMatches(normalized).toList();
  if (withUnit.isNotEmpty) {
    final match = withUnit.last;
    final value = _toDouble(match.group(1));
    if (value != null && value > 0) {
      return QuickEntryParse(
        amount: value,
        note: _stripSpan(normalized, match.start, match.end),
      );
    }
  }

  // 优先级 2：货币符号 + 数字。
  final withSymbol = _symbolAmountPattern.allMatches(normalized).toList();
  if (withSymbol.isNotEmpty) {
    final match = withSymbol.last;
    final value = _toDouble(match.group(1));
    if (value != null && value > 0) {
      return QuickEntryParse(
        amount: value,
        note: _stripSpan(normalized, match.start, match.end),
      );
    }
  }

  // 优先级 3：整段就是一个算式（如「500+800」）。只在文字里没有其它汉字时尝试，
  // 避免把「打车 12-5」这类备注里的连字符误当算式。
  if (!_containsLetterOrIdeograph(normalized)) {
    final evaluated = evaluateAmountExpression(normalized);
    if (evaluated != null && evaluated > 0) {
      return QuickEntryParse(amount: evaluated, note: '');
    }
  }

  // 优先级 4：裸数字，取最后一个。
  final numbers = _numberPattern.allMatches(normalized).toList();
  if (numbers.isEmpty) {
    return QuickEntryParse(amount: null, note: normalized);
  }
  final last = numbers.last;
  final value = _toDouble(last.group(0));
  if (value == null || value <= 0) {
    // 金额为 0 或解析失败：不当作金额，整段留作备注（用户可能只是写了个门牌号）。
    return QuickEntryParse(amount: null, note: normalized);
  }
  return QuickEntryParse(
    amount: value,
    note: _stripSpan(normalized, last.start, last.end),
  );
}

/// 去掉 [start, end) 这段文字，并清理留下的多余空白与孤零零的分隔标点。
String _stripSpan(String text, int start, int end) {
  final rest = (text.substring(0, start) + ' ' + text.substring(end));
  return rest
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'^[\s,，、。;；:：\-—+*×÷/]+'), '')
      .replaceAll(RegExp(r'[\s,，、。;；:：\-—+*×÷/]+$'), '')
      .trim();
}

/// 是否含字母或汉字——用于判断「整段是否纯算式」。
bool _containsLetterOrIdeograph(String text) {
  for (final rune in text.runes) {
    if (rune >= 0x4E00 && rune <= 0x9FFF) return true; // CJK 统一汉字
    if (rune >= 0x3040 && rune <= 0x30FF) return true; // 日文假名
    if (rune >= 0x41 && rune <= 0x5A) return true; // A-Z
    if (rune >= 0x61 && rune <= 0x7A) return true; // a-z
  }
  return false;
}

double? _toDouble(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  return double.tryParse(raw);
}
