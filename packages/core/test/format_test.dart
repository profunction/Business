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

  group('parseRmToSen', () {
    test('切字串，不经过 double', () {
      expect(parseRmToSen('12.50'), 1250);
      expect(parseRmToSen('12.5'), 1250);
      expect(parseRmToSen('12'), 1200);
      expect(parseRmToSen('12.'), 1200);
      expect(parseRmToSen('.5'), 50);
      expect(parseRmToSen('0.05'), 5);
      expect(parseRmToSen(' RM 8.60 '), 860);
      expect(parseRmToSen('rm4.20'), 420);
      expect(parseRmToSen('1,250.00'), 125000);
      expect(parseRmToSen('999999.99'), 99999999);
      // double 会算错的几个：0.29 * 100 = 28.999999999999996、4.35 * 100 = 434.99999999999994
      expect(parseRmToSen('0.29'), 29);
      expect(parseRmToSen('4.35'), 435);
      expect(parseRmToSen('1.15'), 115);
      for (var sen = 1; sen <= 100000; sen += 7) {
        expect(parseRmToSen(senToInput(sen)), sen);
      }
    });

    test('看不懂、0、太多小数位 → null', () {
      for (final bad in ['', ' ', '.', 'RM', 'abc', '12.345', '12,50', '1.2.3', '-5', '0', '0.00', '1e3', '1000000']) {
        expect(parseRmToSen(bad), isNull, reason: bad);
      }
    });

    test('senToInput', () {
      expect(senToInput(1250), '12.50');
      expect(senToInput(5), '0.05');
      expect(senToInput(100000), '1000.00');
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
