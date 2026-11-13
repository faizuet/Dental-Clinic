import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nabi_dental_app/core/api/api_client.dart';
import 'package:nabi_dental_app/core/database/app_database.dart';
import 'package:nabi_dental_app/core/errors/app_exception.dart';
import 'package:nabi_dental_app/core/finance/finance_repository.dart';
import 'package:nabi_dental_app/core/models/finance_models.dart';
import 'package:nabi_dental_app/core/security/device_id.dart';

class _Api extends Mock implements ApiClient {}

class _Db extends Mock implements AppDatabase {}

class _Device extends Mock implements DeviceIdentity {}

void main() {
  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
  });

  late _Api api;
  late _Db db;
  late FinanceRepository repo;

  setUp(() {
    api = _Api();
    db = _Db();
    repo = FinanceRepository(api: api, database: db, device: _Device());
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

  test('recent patients list latest treated first', () async {
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
    expect(recent.map((item) => item.patient.id).toList(), ['p-old', 'p-new']);
    expect(recent.first.lastVisitDate, '2026-11-12');
    expect(recent.first.lastTreatment, 'RCT');
    expect(recent.last.lastVisitDate, isNull);
  });
}
