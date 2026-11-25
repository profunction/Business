import 'package:test/test.dart';
import 'package:wholesale_core/wholesale_core.dart';

void main() {
  group('formatRm', () {
    test('仙转成 RM', () {
      expect(formatRm(1250), 'RM12.50');
      expect(formatRm(5), 'RM0.05');
      expect(formatRm(0), 'RM0.00');
      expect(formatRm(123456789), 'RM1,234,567.89');
      expect(formatRm(-800), '-RM8.00');
    });
  });

  group('formatSen', () {
    test('每个多少仙，去掉多余的 0', () {
      expect(formatSen(8.5), '8.5');
      expect(formatSen(9.6), '9.6');
      expect(formatSen(12), '12');
      expect(formatSen(0.42), '0.42');
    });
  });

  group('normalizeMalaysianMobile', () {
    test('各种写法都转成 +60', () {
      expect(normalizeMalaysianMobile('012-345 6789'), '+60123456789');
      expect(normalizeMalaysianMobile('0123456789'), '+60123456789');
      expect(normalizeMalaysianMobile('60123456789'), '+60123456789');
      expect(normalizeMalaysianMobile('+60 12-345 6789'), '+60123456789');
      expect(normalizeMalaysianMobile('123456789'), '+60123456789');
      expect(normalizeMalaysianMobile('011-1234 5678'), '+601112345678');
    });

    test('不像手机号就拒绝', () {
      expect(normalizeMalaysianMobile(''), isNull);
      expect(normalizeMalaysianMobile('07-123 4567'), isNull); // 新山的固线电话
      expect(normalizeMalaysianMobile('12345'), isNull);
    });

    test('显示格式', () {
      expect(formatMalaysianMobile('60123456789'), '012-345 6789');
      expect(formatMalaysianMobile('+601112345678'), '011-1234 5678');
    });
  });

  group('AppError', () {
    test('PRICE_CHANGED 带着新报价', () {
      const err = AppError('PRICE_CHANGED', detail: '{"can_place": true, "total_sen": 25700, "groups": []}');
      expect(err.quote?.totalSen, 25700);
    });

    test('没有报价时 quote 是 null', () {
      expect(const AppError('NOT_ALLOWED').quote, isNull);
    });
  });
}
