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
      'patient_phone': '03001234567',
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
    expect(entry.displayPatientName, 'Ali Khan');
    expect(entry.patientPhone, '03001234567');
    expect(entry.serialNo, 12);
    expect(entry.subTreatment, 'RCT');
    expect(displaySubTreatment(subTreatment: entry.subTreatment, details: entry.details, catalogName: entry.catalogName), 'RCT');
    expect(entry.details['tooth_number'], '26');
    expect(kindOf(entry.catalogName), TreatmentKind.rct);
    expect(toothNameFor('26'), 'Upper Left First Molar');
    expect(
      clinicalSummary(entry.details, subTreatment: 'RCT'),
      contains('3 canals'),
    );
  });

  test('shows Walk-in when a treatment has no patient name', () {
    final entry = MoneyEntry.fromJson({
      'id': 'tx2',
      'treatment_id': 'rct1',
      'treatment_name': 'RCT',
      'transaction_date': '2026-11-10',
      'amount': '1000.00',
    });
    expect(entry.patientName, isNull);
    expect(entry.displayPatientName, 'Walk-in');
    expect(entry.catalogName, 'RCT');
  });

  test('keeps the registered patient name from the API payload', () {
    final patient = PatientRecord.fromJson({
      'id': '05834fef-7589-4893-b064-44aa4afa2ce2',
      'name': 'faiz khan',
      'phone': '03189253385',
      'created_at': '2026-11-10T05:58:41.365692+00:00',
      'version': 1,
    });
    expect(patient.name, 'faiz khan');
    expect(patient.phone, '03189253385');
    expect(patient.createdAt, isNotNull);
  });
}
