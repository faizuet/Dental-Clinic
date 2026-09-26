import 'package:flutter_test/flutter_test.dart';
import 'package:nabi_dental_app/core/dental/tooth_catalog.dart';
import 'package:nabi_dental_app/core/utils/dates.dart';

void main() {
  test('formats stored ISO dates as DD/MM/YY', () {
    expect(formatDisplayDate('2026-09-26'), '26/09/26');
    expect(formatDisplayDate(DateTime(2026, 9, 26)), '26/09/26');
    expect(formatDisplayDateRange('2026-09-01', '2026-09-26'), '01/09/26 to 26/09/26');
    expect(formatDisplayDateLabel('2026-09'), '09/26');
  });

  test('resolves a saved sub-treatment for display', () {
    expect(displayMainTreatment('RCT'), 'RCT');
    expect(displayMainTreatment('Crown'), 'Prosthetic');
    expect(
      displaySubTreatment(subTreatment: null, details: {'sub_treatment': 'RCT'}, catalogName: 'RCT'),
      'RCT',
    );
    expect(
      displaySubTreatment(subTreatment: null, details: const {}, catalogName: 'Crown'),
      'Crown',
    );
  });
}
