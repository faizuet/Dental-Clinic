import 'package:flutter_test/flutter_test.dart';
import 'package:nabi_dental_app/core/dental/tooth_catalog.dart';
import 'package:nabi_dental_app/core/models/finance_models.dart';

void main() {
  test('parses a treatment visit with patient and clinical details', () {
    final entry = MoneyEntry.fromJson({
      'id': 'tx1',
      'treatment_id': 'rct1',
      'treatment_name': 'RCT',
      'transaction_date': '2026-09-20',
      'amount': '8000.00',
      'serial_no': 12,
      'patient_name': 'Ali Khan',
      'sub_treatment': 'RCT',
      'details': {
        'kind': 'rct',
        'tooth_number': '26',
        'canals': 3,
        'length_mm': '21',
      },
      'details_text': 'Tooth #26, 3 canals, 21 mm',
    });
    expect(entry.patientName, 'Ali Khan');
    expect(entry.serialNo, 12);
    expect(entry.details['tooth_number'], '26');
    expect(kindOf(entry.catalogName), TreatmentKind.rct);
    expect(toothNameFor('26'), 'Upper Left First Molar');
    expect(
      clinicalSummary(entry.details, subTreatment: 'RCT'),
      contains('3 canals'),
    );
  });
}
