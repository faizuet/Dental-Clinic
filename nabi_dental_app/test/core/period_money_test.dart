import 'package:flutter_test/flutter_test.dart';
import 'package:nabi_dental_app/core/utils/money.dart';
import 'package:nabi_dental_app/core/utils/period.dart';

void main() {
  test('formats PKR with two decimals', () {
    expect(formatMoney('2500.5'), 'PKR 2,500.50');
    expect(isValidMoney('10.25'), isTrue);
    expect(isValidMoney('-1'), isFalse);
    expect(isValidMoney('1.234'), isFalse);
    expect(isValidQuantity('10.5'), isTrue);
    expect(isValidQuantity('10.555'), isTrue);
    expect(isValidQuantity('10.5555'), isFalse);
    expect(formatQuantity('10.500'), '10.5');
  });

  test('daily period is a single inclusive day', () {
    final range = DateRange.forPeriod(FinancePeriod.daily, now: DateTime(2026, 9, 19));
    expect(range.fromIso, '2026-09-19');
    expect(range.toIso, '2026-09-19');
    expect(range.containsIso('2026-09-19'), isTrue);
    expect(range.containsIso('2026-09-18'), isFalse);
  });
}
