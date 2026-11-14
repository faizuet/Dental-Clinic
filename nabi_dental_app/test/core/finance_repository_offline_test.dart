import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nabi_dental_app/core/api/api_client.dart';
import 'package:nabi_dental_app/core/database/app_database.dart';
import 'package:nabi_dental_app/core/errors/app_exception.dart';
import 'package:nabi_dental_app/core/finance/finance_repository.dart';
import 'package:nabi_dental_app/core/models/finance_models.dart';
import 'package:nabi_dental_app/core/security/device_id.dart';
import 'package:nabi_dental_app/core/utils/period.dart';

class _Api extends Mock implements ApiClient {}

class _Db extends Mock implements AppDatabase {}

class _Device extends Mock implements DeviceIdentity {}

void main() {
  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
  });

  late _Api api;
  late _Db db;
  late _Device device;
  late FinanceRepository repo;

  setUp(() {
    api = _Api();
    db = _Db();
    device = _Device();
    repo = FinanceRepository(api: api, database: db, device: device);
    when(() => db.list('patients')).thenAnswer((_) async => const <Map<String, dynamic>>[]);
    when(() => db.list('treatments')).thenAnswer(
      (_) async => [
        {'id': 't1', 'name': 'Check Up / Consultation', 'is_active': true},
      ],
    );
    when(() => db.upsert(any(), any())).thenAnswer((_) async {});
    when(
      () => db.enqueueChange(
        clientChangeId: any(named: 'clientChangeId'),
        entityType: any(named: 'entityType'),
        entityId: any(named: 'entityId'),
        operation: any(named: 'operation'),
        payload: any(named: 'payload'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => db.enqueueChange(
        clientChangeId: any(named: 'clientChangeId'),
        entityType: any(named: 'entityType'),
        entityId: any(named: 'entityId'),
        operation: any(named: 'operation'),
        payload: any(named: 'payload'),
        baseVersion: any(named: 'baseVersion'),
      ),
    ).thenAnswer((_) async {});
    when(() => api.get(any())).thenThrow(const OfflineException());
    when(() => api.post(any(), data: any(named: 'data'))).thenThrow(const OfflineException());
    when(() => api.patch(any(), data: any(named: 'data'))).thenThrow(const OfflineException());
  });

  test('does not queue a patient with a live duplicate mobile', () async {
    when(() => db.list('patients')).thenAnswer(
      (_) async => [
        {'id': 'p1', 'name': 'Sara Ahmed', 'phone': '03001234567'},
      ],
    );

    await expectLater(
      repo.savePatient(name: 'Ali Khan', phone: '03001234567'),
      throwsA(isA<AppException>().having((error) => error.code, 'code', 'CONFLICT')),
    );
    verifyNever(() => db.enqueueChange(
          clientChangeId: any(named: 'clientChangeId'),
          entityType: any(named: 'entityType'),
          entityId: any(named: 'entityId'),
          operation: any(named: 'operation'),
          payload: any(named: 'payload'),
        ));
  });

  test('queues a new patient when the API is offline', () async {
    final patient = await repo.savePatient(name: 'Ali Khan', phone: '03001234567');

    expect(patient.name, 'Ali Khan');
    expect(patient.phone, '03001234567');
    verify(() => db.upsert('patients', any())).called(1);
    verify(
      () => db.enqueueChange(
        clientChangeId: any(named: 'clientChangeId'),
        entityType: 'patient',
        entityId: patient.id,
        operation: 'create',
        payload: any(named: 'payload'),
      ),
    ).called(1);
  });

  test('queues a patient edit when the API is offline', () async {
    const existing = PatientRecord(id: 'patient-a', name: 'Ali Khan', phone: '03001234567', version: 3);

    final updated = await repo.updatePatient(existing, name: 'Ali Raza', phone: '03001234567');

    expect(updated.name, 'Ali Raza');
    expect(updated.version, 4);
    verify(() => db.upsert('patients', any())).called(1);
    verify(
      () => db.enqueueChange(
        clientChangeId: any(named: 'clientChangeId'),
        entityType: 'patient',
        entityId: 'patient-a',
        operation: 'update',
        payload: any(named: 'payload'),
        baseVersion: 3,
      ),
    ).called(1);
  });

  test('queues a visit without X-rays when the API is offline', () async {
    final message = await repo.saveTreatmentVisit(
      date: '2026-11-13',
      treatmentId: 't1',
      amount: '1000.00',
      patientId: 'patient-a',
      patientName: 'Ali Khan',
    );

    expect(message, 'Saved on this device and waiting to sync.');
    verify(() => db.upsert('treatment_transactions', any())).called(1);
    verify(
      () => db.enqueueChange(
        clientChangeId: any(named: 'clientChangeId'),
        entityType: 'treatment_transaction',
        entityId: any(named: 'entityId'),
        operation: 'create',
        payload: any(named: 'payload'),
      ),
    ).called(1);
  });

  test('does not save a visit with X-rays while offline', () async {
    await expectLater(
      repo.saveTreatmentVisit(
        date: '2026-11-13',
        treatmentId: 't1',
        amount: '1000.00',
        patientId: 'patient-a',
        patientName: 'Ali Khan',
        xrays: [
          (bytes: <int>[1, 2, 3], filename: 'xray.jpg', label: 'before', lineId: 'line-1'),
        ],
      ),
      throwsA(
        isA<AppException>().having((error) => error.code, 'code', 'XRAY_OFFLINE'),
      ),
    );

    verifyNever(() => db.upsert('treatment_transactions', any()));
    verifyNever(
      () => db.enqueueChange(
        clientChangeId: any(named: 'clientChangeId'),
        entityType: 'treatment_transaction',
        entityId: any(named: 'entityId'),
        operation: any(named: 'operation'),
        payload: any(named: 'payload'),
      ),
    );
  });

  test('does not update a visit with X-ray changes while offline', () async {
    const entry = MoneyEntry(
      id: 'visit-1',
      catalogId: 't1',
      catalogName: 'Check Up / Consultation',
      date: '2026-11-13',
      amount: '1000.00',
      patientId: 'patient-a',
      version: 2,
    );

    await expectLater(
      repo.updateTreatmentVisit(
        entry: entry,
        date: '2026-11-13',
        treatmentId: 't1',
        amount: '1200.00',
        patientId: 'patient-a',
        removeAttachmentIds: const ['att-1'],
      ),
      throwsA(
        isA<AppException>().having((error) => error.code, 'code', 'XRAY_OFFLINE'),
      ),
    );

    verifyNever(() => db.upsert('treatment_transactions', any()));
  });

  test('queues a lab charge when the API is offline', () async {
    final message = await repo.saveLabCharge(
      date: '2026-11-13',
      amount: '1500.00',
      patientId: 'patient-a',
      transactionId: 'visit-1',
      labName: 'Smile Ceramics',
    );

    expect(message, 'Saved on this device and waiting to sync.');
    verify(() => db.upsert('lab_charges', any())).called(1);
    verify(
      () => db.enqueueChange(
        clientChangeId: any(named: 'clientChangeId'),
        entityType: 'lab_charge',
        entityId: any(named: 'entityId'),
        operation: 'create',
        payload: any(named: 'payload'),
      ),
    ).called(1);
  });

  test('clinic totals keep lab charges apart from clinic expenses', () async {
    final range = DateRange(from: DateTime(2026, 11, 1), to: DateTime(2026, 11, 30), period: FinancePeriod.custom);
    when(() => db.list('treatment_transactions')).thenAnswer(
      (_) async => [
        {'id': 'v1', 'transaction_date': '2026-11-12', 'amount': '10000.00'},
      ],
    );
    when(() => db.list('clinic_expenses')).thenAnswer(
      (_) async => [
        {'id': 'e1', 'expense_date': '2026-11-12', 'amount': '2000.00'},
      ],
    );
    when(() => db.list('lab_charges')).thenAnswer(
      (_) async => [
        {'id': 'l1', 'charge_date': '2026-11-12', 'amount': '1500.00'},
        {'id': 'l2', 'charge_date': '2026-10-31', 'amount': '900.00'},
      ],
    );

    final totals = await repo.clinicTotals(range);

    expect(totals.income, '10000.00');
    expect(totals.expenses, '2000.00');
    expect(totals.labCharges, '1500.00');
    expect(totals.profit, '6500.00');
  });

  test('legacy offline lab expenses sync as lab charges', () async {
    when(() => db.pendingChanges()).thenAnswer(
      (_) async => [
        {
          'client_change_id': 'c1',
          'entity_type': 'clinic_expense',
          'entity_id': 'e1',
          'operation': 'create',
          'payload': {'id': 'e1', 'category_id': 'cat-lab', 'expense_date': '2026-11-12', 'amount': '1500.00'},
        },
      ],
    );
    when(() => db.get('clinic_expense_categories', 'cat-lab')).thenAnswer(
      (_) async => {'id': 'cat-lab', 'name': 'Lab Charges'},
    );
    when(() => db.get('clinic_expenses', 'e1')).thenAnswer(
      (_) async => {'id': 'e1', 'expense_date': '2026-11-12', 'amount': '1500.00'},
    );
    when(() => db.removePending(any())).thenAnswer((_) async {});
    when(() => db.markDeleted(any(), any())).thenAnswer((_) async {});
    when(() => device.id()).thenAnswer((_) async => 'device-1');
    Map<String, dynamic>? sent;
    when(() => api.post('/api/v1/sync/push', data: any(named: 'data'))).thenAnswer((invocation) async {
      sent = invocation.namedArguments[#data] as Map<String, dynamic>;
      throw const OfflineException();
    });

    await expectLater(repo.pushPending(), throwsA(isA<OfflineException>()));

    final change = (sent!['changes'] as List).single as Map;
    expect(change['entity'], 'lab_charge');
    expect(change['entity_id'], 'e1');
    expect((change['data'] as Map)['charge_date'], '2026-11-12');
    verify(() => db.markDeleted('clinic_expenses', 'e1')).called(1);
    verify(() => db.upsert('lab_charges', any())).called(1);
  });

  test('recent patients lists the newest registration first', () async {
    when(() => db.list('patients')).thenAnswer(
      (_) async => [
        {'id': 'p-new', 'name': 'New Patient', 'created_at': '2026-11-13T10:00:00Z'},
        {
          'id': 'p-old',
          'name': 'Old Patient',
          'phone': '03001234567',
          'created_at': '2026-01-01T10:00:00Z',
        },
      ],
    );
    when(() => db.list('treatment_transactions')).thenAnswer(
      (_) async => [
        {
          'id': 'v1',
          'treatment_id': 't1',
          'catalog_name': 'RCT',
          'transaction_date': '2026-11-12',
          'amount': '8000.00',
          'patient_id': 'p-old',
          'patient_name': 'Old Patient',
        },
      ],
    );

    final recent = await repo.recentClinicPatients(limit: 6);
    expect(recent.map((item) => item.patient.id).toList(), ['p-new', 'p-old']);
    expect(recent.first.lastVisitDate, isNull);
    expect(recent.last.lastVisitDate, '2026-11-12');
    expect(recent.last.lastTreatment, 'RCT');
  });

  test('patients and treatment history use creation time, newest first', () async {
    when(() => db.list('patients')).thenAnswer(
      (_) async => [
        {'id': 'morning', 'name': 'Morning Patient', 'created_at': '2026-11-14T09:00:00Z'},
        {'id': 'later', 'name': 'Later Patient', 'created_at': '2026-11-14T10:00:00.000000+00:00'},
      ],
    );
    when(() => db.list('treatment_transactions')).thenAnswer(
      (_) async => [
        {
          'id': 'older-entry',
          'treatment_id': 't1',
          'catalog_name': 'Check Up / Consultation',
          'transaction_date': '2026-11-14',
          'amount': '1500.00',
          'patient_id': 'later',
          'patient_name': 'Later Patient',
          'created_at': '2026-11-14T09:00:00Z',
        },
        {
          'id': 'newer-entry',
          'treatment_id': 't1',
          'catalog_name': 'Check Up / Consultation',
          'transaction_date': '2026-11-10',
          'amount': '2000.00',
          'patient_id': 'later',
          'patient_name': 'Later Patient',
          'created_at': '2026-11-14T10:00:00.000000+00:00',
        },
      ],
    );

    final patients = await repo.patients();
    expect(patients.map((item) => item.id).toList(), ['later', 'morning']);

    final history = await repo.incomeHistory();
    expect(history.map((item) => item.id).toList(), ['newer-entry', 'older-entry']);

    final visits = await repo.patientTreatments('later');
    expect(visits.map((item) => item.id).toList(), ['newer-entry', 'older-entry']);
    expect(visits.first.date, '2026-11-10');
    expect(visits.last.amount, '1500.00');
  });

  test('a patient can be saved without a phone and updated later', () async {
    final created = await repo.savePatient(name: 'No Phone Yet');
    expect(created.name, 'No Phone Yet');
    expect(created.phone, isNull);

    final withPhone = await repo.updatePatient(created, name: 'No Phone Yet', phone: '03123456789');
    expect(withPhone.phone, '03123456789');

    final renamed = await repo.updatePatient(withPhone, name: 'Amina Noor', phone: null);
    expect(renamed.name, 'Amina Noor');
    expect(renamed.phone, isNull);
  });

  test('recent activity uses the current patient name after an edit', () async {
    when(() => db.list('patients')).thenAnswer(
      (_) async => [
        {'id': 'p1', 'name': 'Amina Noor', 'phone': '03123456789'},
      ],
    );
    when(() => db.list('treatment_transactions')).thenAnswer(
      (_) async => [
        {
          'id': 'v1',
          'treatment_id': 't1',
          'catalog_name': 'RCT',
          'transaction_date': '2026-11-12',
          'amount': '8000.00',
          'patient_id': 'p1',
          'patient_name': 'Ali Khan',
          'patient_phone': '03001234567',
        },
      ],
    );
    when(() => db.list('clinic_expenses')).thenAnswer((_) async => const <Map<String, dynamic>>[]);
    when(() => db.list('lab_charges')).thenAnswer((_) async => const <Map<String, dynamic>>[]);

    final activity = await repo.recentClinicActivity();

    expect(activity, hasLength(1));
    expect(activity.single.title, 'RCT for Amina Noor');
    expect(activity.single.amount, '8000.00');
  });

  test('clinic expense history keeps Materials instead of the Item placeholder', () async {
    when(() => db.list('clinic_expenses')).thenAnswer(
      (_) async => [
        {
          'id': 'e1',
          'category_id': 'cat-materials',
          'expense_date': '2026-11-14',
          'amount': '2000.00',
          'notes': 'Dental Materials',
          'catalog_name': 'Item',
        },
      ],
    );
    when(() => db.list('clinic_expense_categories', includeDeleted: true)).thenAnswer(
      (_) async => [
        {'id': 'cat-materials', 'name': 'Materials'},
      ],
    );

    final items = await repo.clinicExpenseHistory();

    expect(items, hasLength(1));
    expect(items.single.catalogName, 'Materials');
    expect(items.single.notes, 'Dental Materials');
    expect(items.single.amount, '2000.00');
  });
}
