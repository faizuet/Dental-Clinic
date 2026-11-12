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

  test('summarizes multiple treatments in one visit without mixing details', () {
    final details = {
      'kind': 'visit',
      'items': [
        {
          'id': 'a',
          'kind': 'rct',
          'sub_treatment': 'RCT',
          'tooth_number': '16',
          'canals': 3,
          'length_mm': '21',
        },
        {
          'id': 'b',
          'kind': 'general',
          'sub_treatment': 'Tooth Extraction',
          'tooth_number': '18',
        },
        {
          'id': 'c',
          'kind': 'general',
          'sub_treatment': 'Dental Filling',
          'tooth_number': '24',
        },
      ],
    };
    expect(visitItems(details), hasLength(3));
    expect(visitMainLabel(catalogName: 'RCT', details: details), '3 treatments');
    expect(displaySubTreatment(details: details, catalogName: 'RCT'), 'RCT, Tooth Extraction, Dental Filling');
    final summary = clinicalSummary(details);
    expect(summary, contains('#16'));
    expect(summary, contains('#18'));
    expect(summary, contains('#24'));
    expect(summary, contains('3 canals'));
    expect(summary, isNot(contains('3 canals, #18')));
  });

  test('keeps attachments when a treatment visit is stored locally', () {
    final entry = MoneyEntry.fromJson({
      'id': 'tx3',
      'treatment_id': 'rct1',
      'treatment_name': 'RCT',
      'transaction_date': '2026-09-20',
      'amount': '8000.00',
      'attachments': [
        {
          'id': 'att1',
          'transaction_id': 'tx3',
          'label': 'before',
          'original_name': 'xray.jpg',
          'byte_size': 1200,
        },
      ],
    });
    expect(entry.attachments, hasLength(1));
    expect(entry.attachments.first.id, 'att1');
    expect(entry.toJson()['id'], 'tx3');
    expect(entry.toJson()['attachments'], isNotEmpty);
    expect(entry.toJson()['attachments'][0]['id'], 'att1');
  });

  test('filters the official treatment list without changing order', () {
    expect(clinicTreatmentNames, hasLength(15));
    expect(clinicTreatmentNames.first, 'Check Up / Consultation');
    expect(clinicTreatmentNames.last, 'Dental Gems');
    expect(
      filterClinicTreatments(clinicTreatmentNames, 'RCT').map((item) => item.name).toList(),
      ['Root Canal Treatment (RCT)', 'Obturation (RCT)'],
    );
    expect(
      filterClinicTreatments(clinicTreatmentNames, 'braces').map((item) => item.name).toList(),
      ['Braces Fresh', 'Braces Visits', 'Braces Retainer'],
    );
    expect(
      filterClinicTreatments(clinicTreatmentNames, 'Filling').map((item) => item.name).toList(),
      ['Temporary Filling', 'Permanent Filling', 'Composite Filling'],
    );
    expect(filterClinicTreatments(clinicTreatmentNames, 'xyz'), isEmpty);
    expect(kindOf('Root Canal Treatment (RCT)'), TreatmentKind.rct);
    expect(kindOf('Obturation (RCT)'), TreatmentKind.rct);
    expect(kindOf('Porcelain Bridge'), TreatmentKind.bridge);
    expect(kindOf('Zirconia Crown'), TreatmentKind.crown);
    expect(requiresToothSelection('Simple Extraction'), isTrue);
    expect(requiresToothSelection('Check Up / Consultation'), isFalse);
  });

  test('matches a saved treatment by name when the catalog id changed', () {
    const current = CatalogItem(id: 'new-filling', name: 'Dental Filling', categoryName: 'Basic');
    const implant = CatalogItem(id: 'implant', name: 'Dental Implant', categoryName: 'Prosthetics');
    final match = findCatalogMatch(
      [current, implant],
      id: 'old-filling',
      name: 'Dental Filling',
    );
    expect(match?.id, 'new-filling');
    expect(uniqueCatalogById([current, current], selected: implant).map((item) => item.id).toSet(), {'new-filling', 'implant'});
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
