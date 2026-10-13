import 'package:flutter_test/flutter_test.dart';
import 'package:verifin/app/quick_entry_text.dart';

void main() {
  group('parseQuickEntryText 金额识别', () {
    test('中文单位词：元 / 块 / 块钱 / 元钱 / 圆', () {
      expect(parseQuickEntryText('早餐5元').amount, 5);
      expect(parseQuickEntryText('早餐5元').note, '早餐');
      expect(parseQuickEntryText('打车32块').amount, 32);
      expect(parseQuickEntryText('打车32块').note, '打车');
      expect(parseQuickEntryText('奶茶18块钱').amount, 18);
      expect(parseQuickEntryText('奶茶18块钱').note, '奶茶');
      expect(parseQuickEntryText('买菜50元钱').amount, 50);
      expect(parseQuickEntryText('买菜50元钱').note, '买菜');
      expect(parseQuickEntryText('书20圆').amount, 20);
    });

    test('金额在词前也能识别', () {
      expect(parseQuickEntryText('5元早餐').amount, 5);
      expect(parseQuickEntryText('5元早餐').note, '早餐');
    });

    test('货币符号', () {
      expect(parseQuickEntryText('¥32').amount, 32);
      expect(parseQuickEntryText('￥32 打车').amount, 32);
      expect(parseQuickEntryText('￥32 打车').note, '打车');
      expect(parseQuickEntryText(r'$5.5').amount, 5.5);
      expect(parseQuickEntryText('€20 午餐').amount, 20);
      expect(parseQuickEntryText('€20 午餐').note, '午餐');
    });

    test('小数与全角数字', () {
      expect(parseQuickEntryText('早餐 5.5 元').amount, 5.5);
      expect(parseQuickEntryText('早餐５元').amount, 5);
      expect(parseQuickEntryText('早餐5．5元').amount, 5.5);
      expect(parseQuickEntryText('0.5元 停车').amount, 0.5);
    });

    test('千分位逗号', () {
      expect(parseQuickEntryText('房租1,200元').amount, 1200);
      expect(parseQuickEntryText('房租1,200元').note, '房租');
      expect(parseQuickEntryText('工资 12,345.67 元').amount, 12345.67);
    });

    test('多个数字时取最后一个（金额常在末尾）', () {
      expect(parseQuickEntryText('买3斤苹果12').amount, 12);
      expect(parseQuickEntryText('买3斤苹果12').note, '买3斤苹果');
      expect(parseQuickEntryText('早餐两个包子5元').amount, 5);
      expect(parseQuickEntryText('早餐两个包子5元').note, '早餐两个包子');
    });

    test('单位词优先于裸数字', () {
      // 「2个」是数量，「5元」才是金额：单位词优先级更高。
      final parsed = parseQuickEntryText('买了2个 5元');
      expect(parsed.amount, 5);
      expect(parsed.note, '买了2个');
    });

    test('纯算式', () {
      expect(parseQuickEntryText('500+800').amount, 1300);
      expect(parseQuickEntryText('500+800').note, '');
      expect(parseQuickEntryText('100*3').amount, 300);
      expect(parseQuickEntryText('1000÷4').amount, 250);
      expect(parseQuickEntryText('500-200').amount, 300);
    });

    test('算式混文字时不按算式求值，按裸数字取尾', () {
      // 「打车 12-5」含义不明，不应算成 7；取最后一个数字 5，
      // 残留的悬空减号在备注清理阶段被去掉。
      final parsed = parseQuickEntryText('打车 12-5');
      expect(parsed.amount, 5);
      expect(parsed.note, '打车 12');
    });
  });

  group('parseQuickEntryText 无金额场景', () {
    test('纯文字 → amount 为 null，整段留作备注', () {
      final parsed = parseQuickEntryText('早餐');
      expect(parsed.amount, isNull);
      expect(parsed.note, '早餐');
      expect(parsed.hasAmount, isFalse);
    });

    test('空输入', () {
      final parsed = parseQuickEntryText('');
      expect(parsed.amount, isNull);
      expect(parsed.note, '');
      expect(parseQuickEntryText('   ').amount, isNull);
    });

    test('金额为 0 不算识别成功', () {
      expect(parseQuickEntryText('0元 免费').amount, isNull);
      expect(parseQuickEntryText('0').amount, isNull);
    });

    test('只有标点或符号', () {
      expect(parseQuickEntryText('---').amount, isNull);
      expect(parseQuickEntryText('¥').amount, isNull);
    });

    test('除以零的算式不识别', () {
      expect(parseQuickEntryText('100÷0').amount, isNull);
    });
  });

  group('parseQuickEntryText 备注清理', () {
    test('剥掉金额后不留首尾标点与多余空格', () {
      expect(parseQuickEntryText('早餐，5元').note, '早餐');
      expect(parseQuickEntryText('早餐 5元 好贵').note, '早餐 好贵');
      expect(parseQuickEntryText('打车：32元').note, '打车');
    });

    test('金额在中间时两侧都保留', () {
      final parsed = parseQuickEntryText('麦当劳 32元 午饭');
      expect(parsed.amount, 32);
      expect(parsed.note, '麦当劳 午饭');
    });

    test('英文单位词', () {
      expect(parseQuickEntryText('coffee 32 RMB').amount, 32);
      expect(parseQuickEntryText('coffee 32 RMB').note, 'coffee');
      expect(parseQuickEntryText('coffee 32 cny').amount, 32);
    });
  });

  group('parseQuickEntryText 健壮性', () {
    test('超长数字不抛异常', () {
      expect(
        () => parseQuickEntryText(List.filled(200, '9').join()),
        returnsNormally,
      );
    });

    test('大量特殊字符不抛异常', () {
      expect(
        () => parseQuickEntryText(r'!@#$%^&*()_+=[]{}|;:"<>?,./~\/*-+'),
        returnsNormally,
      );
    });

    test('多个单位词取最后一个', () {
      final parsed = parseQuickEntryText('3元 停车 5元');
      expect(parsed.amount, 5);
    });

    test('负数表达式按正数金额处理', () {
      // 记账金额恒为正；「-5元」应识别为 5（类型由用户/识别决定）。
      expect(parseQuickEntryText('-5元 退款').amount, 5);
    });
  });
}
