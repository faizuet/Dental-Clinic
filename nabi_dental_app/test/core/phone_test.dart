import 'package:flutter_test/flutter_test.dart';
import 'package:nabi_dental_app/core/utils/phone.dart';

void main() {
  test('accepts Pakistani 11-digit mobiles starting with 03', () {
    expect(isPakistaniMobile('03001234567'), isTrue);
    expect(isPakistaniMobile('03123456789'), isTrue);
    expect(validateOptionalPakistaniMobile('03001234567'), isNull);
    expect(validateOptionalPakistaniMobile('  '), isNull);
    expect(validateOptionalPakistaniMobile(null), isNull);
  });

  test('rejects short, long, foreign, and non-numeric numbers', () {
    const invalid = [
      '0300123456',
      '030012345678',
      '923001234567',
      '0300ABC4567',
      '0300 1234567',
      '0300-1234567',
      '+923001234567',
      '12345678901',
    ];
    for (final value in invalid) {
      expect(isPakistaniMobile(value), isFalse, reason: value);
      expect(validateOptionalPakistaniMobile(value), pakistaniMobileMessage, reason: value);
    }
  });
}
