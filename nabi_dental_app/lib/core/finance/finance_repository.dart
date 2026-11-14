import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http_parser/http_parser.dart';
import 'package:uuid/uuid.dart';

import '../api/api_client.dart';
import '../auth/session_controller.dart';
import '../backup/backup_status.dart';
import '../database/app_database.dart';
import '../errors/app_exception.dart';
import '../errors/friendly_error.dart';
import '../media/clinic_image_picker.dart';
import '../models/finance_models.dart';
import '../security/device_id.dart';
import '../utils/dates.dart';
import '../utils/money.dart';
import '../utils/period.dart';
import '../utils/phone.dart';

DateTime? _recordInstant(String? createdAt, String? date) {
  final created = DateTime.tryParse((createdAt ?? '').trim());
  if (created != null) {
    return created.toUtc();
  }
  final raw = (date ?? '').trim();
  if (raw.length >= 10) {
    final day = DateTime.tryParse(raw.substring(0, 10));
    if (day != null) {
      return DateTime.utc(day.year, day.month, day.day);
    }
  }
  return null;
}

int _newestFirst(DateTime? a, DateTime? b, String aId, String bId) {
  if (a != null && b != null) {
    final byTime = b.compareTo(a);
    if (byTime != 0) {
      return byTime;
    }
  } else if (a != null || b != null) {
    return a == null ? 1 : -1;
  }
  return bId.compareTo(aId);
}

int _compareEntries(MoneyEntry a, MoneyEntry b) {
  return _newestFirst(_recordInstant(a.createdAt, a.date), _recordInstant(b.createdAt, b.date), a.id, b.id);
}

const _collections = {
  'treatment_category': 'treatment_categories',
  'treatment': 'treatments',
  'treatment_transaction': 'treatment_transactions',
  'patient': 'patients',
  'clinic_expense_category': 'clinic_expense_categories',
  'clinic_expense': 'clinic_expenses',
  'lab_charge': 'lab_charges',
  'home_expense_category': 'home_expense_categories',
  'home_expense': 'home_expenses',
  'home_budget': 'home_budgets',
};

const _retiredSyncEntities = {
  'construction_material_category',
  'construction_material',
  'construction_purchase',
};

class ClinicTotals {
  const ClinicTotals({
    required this.income,
    required this.expenses,
    required this.labCharges,
    required this.profit,
    required this.range,
    this.online = true,
  });

  final String income;
  final String expenses;
  final String labCharges;
  final String profit;
  final DateRange range;
  final bool online;
}

class HomeTotals {
  const HomeTotals({
    required this.spent,
    required this.budget,
    required this.remaining,
    required this.percentageUsed,
    required this.budgetSource,
    required this.range,
    this.online = true,
  });

  final String spent;
  final String budget;
  final String remaining;
  final String? percentageUsed;
  final String budgetSource;
  final DateRange range;
  final bool online;
}

class SyncStatus {
  const SyncStatus({
    required this.pending,
    required this.conflicts,
    this.lastSync,
    this.state = 'idle',
  });

  final int pending;
  final int conflicts;
  final String? lastSync;
  final String state;
}

class SyncConflict {
  const SyncConflict({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.local,
    required this.server,
  });

  final String id;
  final String entityType;
  final String entityId;
  final Map<String, dynamic> local;
  final Map<String, dynamic> server;

  factory SyncConflict.fromJson(Map<String, dynamic> json) {
    return SyncConflict(
      id: json['id'].toString(),
      entityType: json['entity_type'].toString(),
      entityId: json['entity_id'].toString(),
      local: Map<String, dynamic>.from(json['local'] as Map),
      server: Map<String, dynamic>.from(json['server'] as Map),
    );
  }
}

class FinanceRepository {
  FinanceRepository({
    required ApiClient api,
    required AppDatabase database,
    required DeviceIdentity device,
    this.onChanged,
  })  : _api = api,
        _db = database,
        _device = device;

  final ApiClient _api;
  final AppDatabase _db;
  final DeviceIdentity _device;
  final void Function()? onChanged;

  void _publish() => onChanged?.call();
  static const _uuid = Uuid();
  final _serverCatalogIds = <String>{};
  final _attachmentBytes = <String, List<int>>{};
  Future<bool>? _refreshing;
  static const _freshSync = Duration(seconds: 60);
  static const _fullHydrateEvery = Duration(minutes: 15);

  Future<bool> refresh({bool force = false}) {
    if (!force && _refreshing != null) {
      return _refreshing!;
    }
    final future = _refreshNow(force: force);
    _refreshing = future;
    return future.whenComplete(() {
      if (identical(_refreshing, future)) {
        _refreshing = null;
      }
    });
  }

  Future<bool> _refreshNow({required bool force}) async {
    try {
      await pushPending();
      if (!force && await _syncedRecently(_freshSync)) {
        return true;
      }
      final cursor = await _db.meta('sync_cursor');
      var needsHydrate = force || cursor == null || await _clinicCacheEmpty();
      if (cursor == null) {
        await _bootstrap();
        needsHydrate = true;
      } else {
        await _pull(cursor);
        needsHydrate = needsHydrate || await _hydrateIsStale();
      }
      if (needsHydrate) {
        await _hydrateRest();
      }
      await _hydrateLabCharges();
      await _hydrateHome();
      await _pruneDuplicateFinanceCatalogs();
      await _pruneDuplicateMonthBudgets();
      await _db.setMeta('last_sync', DateTime.now().toUtc().toIso8601String());
      await _db.setMeta('sync_state', 'synced');
      return true;
    } on OfflineException {
      await _db.setMeta('sync_state', 'offline');
      await _pruneDuplicateFinanceCatalogs();
      return false;
    } on AppException {
      try {
        if (force || await _clinicCacheEmpty()) {
          await _hydrateRest();
        }
        await _hydrateLabCharges();
        await _hydrateHome();
        await _pruneDuplicateFinanceCatalogs();
        await _db.setMeta('last_sync', DateTime.now().toUtc().toIso8601String());
        return true;
      } on OfflineException {
        await _db.setMeta('sync_state', 'offline');
        await _pruneDuplicateFinanceCatalogs();
        return false;
      } on AppException {
        await _db.setMeta('sync_state', 'failed');
        await _pruneDuplicateFinanceCatalogs();
        return false;
      }
    }
  }

  Future<bool> _syncedRecently(Duration maxAge) async {
    final last = DateTime.tryParse(await _db.meta('last_sync') ?? '');
    if (last == null) {
      return false;
    }
    return DateTime.now().toUtc().difference(last.toUtc()) < maxAge;
  }

  Future<bool> _hydrateIsStale() async {
    return !await _syncedRecently(_fullHydrateEvery);
  }

  Future<bool> _clinicCacheEmpty() async {
    final treatments = await _db.list('treatments');
    final patients = await _db.list('patients');
    return treatments.isEmpty || patients.isEmpty;
  }

  Future<SyncStatus> syncStatus() async {
    return SyncStatus(
      pending: await _db.pendingCount(),
      conflicts: await _db.conflictCount(),
      lastSync: await _db.meta('last_sync'),
      state: await _db.meta('sync_state') ?? 'idle',
    );
  }

  Future<BackupStatus> backupStatus() async {
    final raw = await _db.meta('last_backup_at');
    return BackupStatus(lastBackupAt: DateTime.tryParse(raw ?? ''));
  }

  Future<void> markBackupSaved() {
    return _db.setMeta('last_backup_at', DateTime.now().toUtc().toIso8601String());
  }

  Future<ResponseBytes> exportBackup() async {
    final response = await _api.getBytes(
      '/api/v1/settings/backup/export',
      timeout: const Duration(minutes: 5),
    );
    final stamp = DateTime.now();
    final name =
        'nabi-dental-backup-${stamp.year}-${stamp.month.toString().padLeft(2, '0')}-${stamp.day.toString().padLeft(2, '0')}-'
        '${stamp.hour.toString().padLeft(2, '0')}${stamp.minute.toString().padLeft(2, '0')}.zip';
    return ResponseBytes(
      bytes: response.data ?? <int>[],
      filename: name,
      mime: 'application/zip',
    );
  }

  Future<void> restoreBackup({required String path, required String filename}) async {
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(path, filename: filename),
    });
    await _api.postMultipart(
      '/api/v1/settings/backup/restore',
      data: form,
      query: {'confirm': true},
      timeout: const Duration(minutes: 5),
    );
    for (final collection in _collections.values) {
      await _db.clearCollection(collection);
    }
    await _db.clearCollection('conflicts');
    await _db.clearPending();
    await _db.setMeta('sync_cursor', '');
    await _db.setMeta('last_sync', '');
    await refresh(force: true);
  }

  Future<List<SyncConflict>> conflicts() async {
    final rows = await _db.list('conflicts');
    return rows.map(SyncConflict.fromJson).toList();
  }

  Future<void> resolveConflict({required SyncConflict conflict, required bool keepLocal}) async {
    final collection = _collections[conflict.entityType] ?? conflict.entityType;
    if (keepLocal) {
      await _db.upsert(collection, conflict.local);
      await _db.enqueueChange(
        clientChangeId: _uuid.v4(),
        entityType: conflict.entityType,
        entityId: conflict.entityId,
        operation: 'update',
        payload: conflict.local,
        baseVersion: _asInt(conflict.server['version']),
      );
    } else {
      await _db.upsert(collection, conflict.server);
    }
    await _db.markDeleted('conflicts', conflict.id);
    await refresh(force: true);
    _publish();
  }

  Future<List<CatalogItem>> treatments() async {
    final rows = await _db.list('treatments');
    final items = rows
        .map((row) => CatalogItem.fromJson(row, categoryName: row['category_name']?.toString()))
        .where((item) => item.isActive);
    return _uniqueCatalogItems(items);
  }

  Future<List<CatalogItem>> clinicExpenseCategories() async {
    final items = await _categories('clinic_expense_categories');
    return items.where((item) => !isLabChargeCategoryName(item.name)).toList();
  }

  Future<List<CatalogItem>> homeExpenseCategories() async {
    final items = await _categories('home_expense_categories');
    items.sort((a, b) {
      final byOrder = a.displayOrder.compareTo(b.displayOrder);
      return byOrder != 0 ? byOrder : a.name.compareTo(b.name);
    });
    return items;
  }

  Future<List<CatalogItem>> treatmentCategories() => _categories('treatment_categories');

  Future<List<CatalogItem>> _categories(String collection) async {
    final rows = await _db.list(collection);
    return _uniqueCatalogItems(rows.map(CatalogItem.fromJson).where((item) => item.isActive));
  }

  List<CatalogItem> _uniqueCatalogItems(Iterable<CatalogItem> items, {bool includeCategory = false}) {
    final unique = <String, CatalogItem>{};
    for (final item in items) {
      final key = includeCategory
          ? '${item.name.trim().toLowerCase()}|${(item.categoryName ?? item.categoryId ?? '').trim().toLowerCase()}'
          : item.name.trim().toLowerCase();
      final existing = unique[key];
      if (existing == null) {
        unique[key] = item;
        continue;
      }
      if (!_serverCatalogIds.contains(existing.id) && _serverCatalogIds.contains(item.id)) {
        unique[key] = item;
      }
    }
    return unique.values.toList()..sort((a, b) => a.name.compareTo(b.name));
  }

  Future<void> _pruneDuplicateFinanceCatalogs() async {
    await _pruneDuplicateNamed('treatment_categories', remapCollection: 'treatments', remapField: 'category_id');
    await _pruneDuplicateNamed('treatments', extraKey: 'category_name', remapCollection: 'treatment_transactions', remapField: 'treatment_id');
    await _pruneDuplicateNamed('clinic_expense_categories', remapCollection: 'clinic_expenses', remapField: 'category_id');
    await _pruneDuplicateNamed('home_expense_categories', remapCollection: 'home_expenses', remapField: 'category_id');
  }

  Future<void> _pruneDuplicateNamed(
    String collection, {
    String? extraKey,
    String? remapCollection,
    String? remapField,
  }) async {
    final rows = await _db.list(collection);
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final row in rows) {
      final name = (row['name']?.toString() ?? '').trim().toLowerCase();
      if (name.isEmpty) {
        continue;
      }
      final extra = extraKey == null ? '' : (row[extraKey]?.toString() ?? '').trim().toLowerCase();
      groups.putIfAbsent('$name|$extra', () => []).add(row);
    }
    final idMap = <String, String>{};
    for (final group in groups.values) {
      if (group.length < 2) {
        continue;
      }
      group.sort((a, b) {
        final aServer = _serverCatalogIds.contains(a['id'].toString()) ? 0 : 1;
        final bServer = _serverCatalogIds.contains(b['id'].toString()) ? 0 : 1;
        if (aServer != bServer) {
          return aServer.compareTo(bServer);
        }
        final seedRank = (a['local_seed'] == true ? 1 : 0).compareTo(b['local_seed'] == true ? 1 : 0);
        if (seedRank != 0) {
          return seedRank;
        }
        return a['id'].toString().compareTo(b['id'].toString());
      });
      final keepId = group.first['id'].toString();
      for (final extra in group.skip(1)) {
        idMap[extra['id'].toString()] = keepId;
        await _db.markDeleted(collection, extra['id'].toString());
      }
    }
    if (idMap.isEmpty || remapCollection == null || remapField == null) {
      return;
    }
    for (final row in await _db.list(remapCollection)) {
      var changed = false;
      final mapped = idMap[row[remapField]?.toString()];
      if (mapped != null) {
        row[remapField] = mapped;
        changed = true;
      }
      if (remapCollection == 'treatment_transactions') {
        final details = row['details'];
        if (details is Map && details['items'] is List) {
          for (final item in details['items']) {
            if (item is Map) {
              final nested = idMap[item['treatment_id']?.toString()];
              if (nested != null) {
                item['treatment_id'] = nested;
                changed = true;
              }
            }
          }
          row['details'] = details;
        }
      }
      if (changed) {
        await _db.upsert(remapCollection, row);
      }
    }
  }

  Future<ClinicTotals> clinicTotals(DateRange range) async {
    final income = _sumRows(await _db.list('treatment_transactions'), range);
    final expenses = _sumRows(await _db.list('clinic_expenses'), range);
    final labCharges = _sumRows(await _db.list('lab_charges'), range);
    return ClinicTotals(
      income: moneyFromDouble(income),
      expenses: moneyFromDouble(expenses),
      labCharges: moneyFromDouble(labCharges),
      profit: moneyFromDouble(income - expenses - labCharges),
      range: range,
    );
  }

  Future<HomeTotals> homeTotals(DateRange range, {required String defaultBudget}) async {
    final spent = _sum(await homeExpenseHistory(range: range));
    final month = DateTime.now();
    final override = (await _db.list('home_budgets')).where((row) {
      return _asInt(row['year']) == month.year && _asInt(row['month']) == month.month;
    }).toList();
    final budget = override.isEmpty ? defaultBudget : override.first['amount'].toString();
    final remaining = moneyToDouble(budget) - spent;
    final pct = moneyToDouble(budget) == 0 ? null : (spent / moneyToDouble(budget) * 100);
    return HomeTotals(
      spent: moneyFromDouble(spent),
      budget: budget,
      remaining: moneyFromDouble(remaining),
      percentageUsed: pct?.toStringAsFixed(2),
      budgetSource: override.isEmpty ? 'default' : 'override',
      range: range,
    );
  }

  Future<List<MoneyEntry>> recentHomeExpenses({int limit = 6}) async {
    final items = await homeExpenseHistory();
    return items.take(limit).toList();
  }

  Future<List<RecentClinicPatient>> recentClinicPatients({int limit = 6}) async {
    final registered = await _localPatients();
    final byId = {for (final item in registered) item.id: item};
    final grouped = <String, List<MoneyEntry>>{};
    for (final visit in await incomeHistory()) {
      final id = visit.patientId;
      if (id == null || id.isEmpty) {
        continue;
      }
      grouped.putIfAbsent(id, () => []).add(visit);
    }
    final records = [...registered];
    for (final entry in grouped.entries) {
      if (byId.containsKey(entry.key)) {
        continue;
      }
      final visit = entry.value.first;
      records.add(
        PatientRecord(
          id: entry.key,
          name: visit.displayPatientName,
          phone: visit.patientPhone,
          createdAt: visit.createdAt,
        ),
      );
    }
    _sortPatients(records);
    final recent = <RecentClinicPatient>[];
    for (final patient in records) {
      final last = _latestVisit(grouped[patient.id]);
      final treatment = last?.subTreatment?.trim();
      recent.add(
        RecentClinicPatient(
          patient: patient,
          lastVisitDate: last?.date,
          lastTreatment: last == null
              ? null
              : (treatment != null && treatment.isNotEmpty ? treatment : last.catalogName),
        ),
      );
      if (recent.length >= limit) {
        break;
      }
    }
    return recent;
  }

  MoneyEntry? _latestVisit(List<MoneyEntry>? visits) {
    MoneyEntry? last;
    for (final visit in visits ?? const <MoneyEntry>[]) {
      if (last == null || visit.date.compareTo(last.date) > 0 || (visit.date == last.date && _compareEntries(visit, last) < 0)) {
        last = visit;
      }
    }
    return last;
  }

  Future<List<ClinicActivity>> recentClinicActivity({int limit = 6}) async {
    final items = [
      for (final visit in await incomeHistory())
        (
          activity: ClinicActivity(
            kind: ClinicActivityKind.treatment,
            title: '${visit.subTreatment?.trim().isNotEmpty == true ? visit.subTreatment : visit.catalogName} for ${visit.displayPatientName}',
            date: visit.date,
            amount: visit.amount,
          ),
          createdAt: visit.createdAt,
          id: visit.id,
        ),
      for (final expense in await clinicExpenseHistory())
        (
          activity: ClinicActivity(
            kind: ClinicActivityKind.expense,
            title: '${expense.catalogName} expense',
            date: expense.date,
            amount: expense.amount,
          ),
          createdAt: expense.createdAt,
          id: expense.id,
        ),
      for (final charge in await labCharges())
        (
          activity: ClinicActivity(
            kind: ClinicActivityKind.labCharge,
            title: charge.patientName == null ? '${charge.displayLab} lab charge' : '${charge.displayLab} for ${charge.patientName}',
            date: charge.date,
            amount: charge.amount,
          ),
          createdAt: charge.createdAt,
          id: charge.id,
        ),
    ]..sort(
        (a, b) => _newestFirst(
          _recordInstant(a.createdAt, a.activity.date),
          _recordInstant(b.createdAt, b.activity.date),
          a.id,
          b.id,
        ),
      );
    return [for (final item in items.take(limit)) item.activity];
  }

  Future<List<PatientRecord>> patients({String? search, bool remote = false}) async {
    final needle = search?.trim();
    if (!remote) {
      return _localPatients(search: needle);
    }
    try {
      final extra = {
        'page_size': 100,
        'sort': '-created_at',
        if (needle != null && needle.isNotEmpty) 'search': needle,
      };
      final remoteRows = await _allPages('/api/v1/patients', extra: extra);
      await _replacePatients(remoteRows);
      final items = remoteRows.map(PatientRecord.fromJson).toList();
      _sortPatients(items);
      return items;
    } on OfflineException {
      return _localPatients(search: needle);
    } on AppException {
      return _localPatients(search: needle);
    }
  }

  Future<PatientRecord> savePatient({required String name, String? phone}) async {
    final trimmed = name.trim();
    if (trimmed.length < 2) {
      throw const AppException('Enter the patient name.', code: 'VALIDATION_ERROR', statusCode: 400);
    }
    final phoneValue = phone?.trim();
    final phoneError = validateOptionalPakistaniMobile(phoneValue);
    if (phoneError != null) {
      throw AppException(phoneError, code: 'VALIDATION_ERROR', statusCode: 400);
    }
    final existing = await patients();
    for (final item in existing) {
      final sameName = item.name.toLowerCase() == trimmed.toLowerCase();
      final samePhone = (item.phone ?? '') == (phoneValue ?? '');
      if (sameName && samePhone) {
        return item;
      }
    }
    final duplicate = duplicatePatientPhoneWarning(patients: existing, phone: phoneValue);
    if (duplicate != null) {
      throw AppException(duplicate, code: 'CONFLICT', statusCode: 409);
    }
    final payload = {
      'id': _uuid.v4(),
      'name': trimmed,
      if (phoneValue != null && phoneValue.isNotEmpty) 'phone': phoneValue,
    };
    try {
      final response = await _api.post('/api/v1/patients', data: payload);
      final saved = _asMap(response.data);
      if (saved == null || (saved['name']?.toString().trim().isEmpty ?? true)) {
        throw const AppException('The patient could not be saved. Please try again.', code: 'SERVER', statusCode: 500);
      }
      await _db.upsert('patients', saved);
      _serverCatalogIds.add(saved['id'].toString());
      _publish();
      return PatientRecord.fromJson(saved);
    } on OfflineException {
      final local = {
        ...payload,
        'version': 1,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      };
      await _db.upsert('patients', local);
      await _db.enqueueChange(
        clientChangeId: _uuid.v4(),
        entityType: 'patient',
        entityId: payload['id'].toString(),
        operation: 'create',
        payload: payload,
      );
      _publish();
      return PatientRecord.fromJson(local);
    }
  }

  Future<PatientRecord> updatePatient(PatientRecord patient, {String? name, String? phone}) async {
    final phoneValue = phone?.trim();
    final phoneError = validateOptionalPakistaniMobile(phoneValue);
    if (phoneError != null) {
      throw AppException(phoneError, code: 'VALIDATION_ERROR', statusCode: 400);
    }
    final patch = {
      if (name != null) 'name': name.trim(),
      'phone': phoneValue == null || phoneValue.isEmpty ? null : phoneValue,
    };
    final duplicate = duplicatePatientPhoneWarning(
      patients: await patients(),
      phone: phoneValue,
      excludeId: patient.id,
    );
    if (duplicate != null) {
      throw AppException(duplicate, code: 'CONFLICT', statusCode: 409);
    }
    try {
      final response = await _api.patch(
        '/api/v1/patients/${patient.id}',
        data: {'version': patient.version, ...patch},
      );
      final saved = _asMap(response.data) ?? {...patient.toJson(), ...patch, 'version': patient.version + 1};
      if ((saved['name']?.toString().trim().isEmpty ?? true)) {
        throw const AppException('The patient could not be updated. Please try again.', code: 'SERVER', statusCode: 500);
      }
      await _db.upsert('patients', saved);
      _publish();
      return PatientRecord.fromJson(saved);
    } on OfflineException {
      final local = {...patient.toJson(), ...patch, 'version': patient.version + 1};
      if ((local['name']?.toString().trim().isEmpty ?? true)) {
        throw const AppException('The patient could not be updated. Please try again.', code: 'SERVER', statusCode: 500);
      }
      await _db.upsert('patients', local);
      await _db.enqueueChange(
        clientChangeId: _uuid.v4(),
        entityType: 'patient',
        entityId: patient.id,
        operation: 'update',
        payload: patch,
        baseVersion: patient.version,
      );
      _publish();
      return PatientRecord.fromJson(local);
    }
  }

  Future<void> deletePatient(PatientRecord patient) async {
    await deleteCatalog(
      path: '/api/v1/patients/${patient.id}',
      collection: 'patients',
      entityType: 'patient',
      id: patient.id,
      version: patient.version,
    );
    await _snapshotDeletedPatient(patient);
    _publish();
  }

  Future<void> _snapshotDeletedPatient(PatientRecord patient) async {
    final rows = await _db.list('treatment_transactions');
    for (final row in rows) {
      if (row['patient_id']?.toString() != patient.id) {
        continue;
      }
      row['patient_name'] = patient.name;
      row['patient_phone'] = patient.phone;
      await _db.upsert('treatment_transactions', row);
    }
  }

  Future<List<MoneyEntry>> incomeHistory({DateRange? range, String? search}) async {
    final rows = await _namedTransactions(await _db.list('treatment_transactions'));
    return _filterEntries(rows, range: range, search: search);
  }

  Future<MoneyEntry?> treatmentById(String id, {bool remote = false}) async {
    if (remote) {
      try {
        final response = await _api.get('/api/v1/treatment-transactions/$id');
        final row = _asMap(response.data);
        if (row != null) {
          final named = (await _namedTransactions([row])).first;
          await _db.upsert('treatment_transactions', named);
          return MoneyEntry.fromJson(named);
        }
      } catch (_) {}
    }
    final local = await _db.get('treatment_transactions', id);
    return local == null ? null : MoneyEntry.fromJson(local);
  }

  Future<PatientRecord?> patientById(String id, {bool remote = false}) async {
    if (remote) {
      try {
        final response = await _api.get('/api/v1/patients/$id');
        final row = _asMap(response.data);
        if (row != null) {
          await _db.upsert('patients', row);
          return PatientRecord.fromJson(row);
        }
      } catch (_) {}
    }
    final local = await _db.get('patients', id);
    return local == null ? null : PatientRecord.fromJson(local);
  }

  Future<List<MoneyEntry>> patientTreatments(String patientId, {bool remote = false}) async {
    if (!remote) {
      return _localPatientTreatments(patientId);
    }
    try {
      final rows = await _allPages(
        '/api/v1/patients/$patientId/treatments',
        extra: {'page_size': 100, 'sort': '-created_at'},
      );
      final named = await _namedTransactions(rows);
      await _db.upsertAll('treatment_transactions', named);
      return _sortEntries([for (final row in named) MoneyEntry.fromJson(row)]);
    } on OfflineException {
      return _localPatientTreatments(patientId);
    } on AppException {
      return _localPatientTreatments(patientId);
    }
  }

  Future<List<MoneyEntry>> _localPatientTreatments(String patientId) async {
    final rows = await _namedTransactions(await _db.list('treatment_transactions'));
    return _sortEntries([
      for (final row in rows)
        if (row['patient_id']?.toString() == patientId) MoneyEntry.fromJson(row),
    ]);
  }

  Future<List<int>> treatmentAttachmentBytes(String transactionId, String attachmentId) async {
    final key = '$transactionId:$attachmentId';
    final cached = _attachmentBytes[key];
    if (cached != null) {
      return cached;
    }
    final response = await _api.getBytes('/api/v1/treatment-transactions/$transactionId/attachments/$attachmentId/file');
    final bytes = response.data ?? <int>[];
    if (bytes.isNotEmpty) {
      _attachmentBytes[key] = bytes;
    }
    return bytes;
  }

  Future<ResponseBytes> exportTreatment(String id) async {
    final response = await _api.getBytes('/api/v1/treatment-transactions/$id/export');
    return ResponseBytes(
      bytes: response.data ?? <int>[],
      filename: 'treatment-record.pdf',
      mime: 'application/pdf',
    );
  }

  Future<Map<String, dynamic>> _mergeLineAttachments({
    required String transactionId,
    required int version,
    required Map<String, dynamic> details,
    required Map<String, List<String>> uploadedByLine,
  }) async {
    if (uploadedByLine.isEmpty) {
      return {'details': details, 'version': version};
    }
    final items = jsonMapList(details['items']);
    if (items.isEmpty) {
      return {'details': details, 'version': version};
    }
    var changed = false;
    for (final item in items) {
      final extra = uploadedByLine[item['id']?.toString()];
      if (extra == null || extra.isEmpty) {
        continue;
      }
      final current = [
        for (final value in item['attachment_ids'] is List ? item['attachment_ids'] as List : const []) value.toString(),
      ];
      current.addAll(extra);
      item['attachment_ids'] = current;
      changed = true;
    }
    if (!changed) {
      return {'details': details, 'version': version};
    }
    final next = {...details, 'items': items};
    try {
      final response = await _api.patch(
        '/api/v1/treatment-transactions/$transactionId',
        data: {'version': version, 'details': next},
      );
      final saved = _asMap(response.data);
      return {
        'details': saved != null && saved['details'] is Map ? Map<String, dynamic>.from(saved['details'] as Map) : next,
        'version': saved == null ? version + 1 : jsonInt(saved['version'], fallback: version + 1),
      };
    } catch (_) {
      return {'details': next, 'version': version};
    }
  }

  Future<String> saveTreatmentVisit({
    required String date,
    required String treatmentId,
    required String amount,
    String? patientId,
    String? patientName,
    String? patientPhone,
    String? subTreatment,
    Map<String, dynamic>? details,
    String? notes,
    List<({List<int> bytes, String filename, String label, String? lineId})> xrays = const [],
  }) async {
    final resolvedTreatmentId = await _resolveCatalogId(
      collection: 'treatments',
      listPath: '/api/v1/treatments',
      id: treatmentId,
      extraKey: 'category_name',
    );
    final resolvedPatientId = await _resolvePatientId(patientId, name: patientName, phone: patientPhone);
    final payload = {
      'id': _uuid.v4(),
      'treatment_id': resolvedTreatmentId,
      'transaction_date': date,
      'quantity': 1,
      'amount': amount,
      'notes': notes,
      'patient_id': resolvedPatientId,
      'sub_treatment': subTreatment,
      'details': details ?? {},
    };
    final names = {for (final item in await treatments()) item.id: item.name};
    try {
      final response = await _api.post('/api/v1/treatment-transactions', data: payload);
      final saved = _asMap(response.data) ?? payload;
      saved['catalog_name'] = names[resolvedTreatmentId] ?? names[treatmentId] ?? saved['treatment_name'] ?? 'Treatment';
      saved['sub_treatment'] = saved['sub_treatment'] ?? subTreatment;
      saved['patient_name'] = saved['patient_name'] ?? patientName;
      saved['patient_phone'] = saved['patient_phone'] ?? patientPhone;
      var failedImages = 0;
      Object? lastImageError;
      final uploadedByLine = <String, List<String>>{};
      for (final xray in xrays) {
        final filename = clinicUploadFilename(xray.filename);
        try {
          final form = FormData.fromMap({
            'label': xray.label,
            'file': MultipartFile.fromBytes(
              xray.bytes,
              filename: filename,
              contentType: MediaType.parse(sniffImageContentType(xray.bytes, filename)),
            ),
          });
          final uploaded = await _api.postMultipart(
            '/api/v1/treatment-transactions/${saved['id']}/attachments',
            data: form,
          );
          final attachment = _asMap(uploaded.data);
          if (attachment != null) {
            final current = jsonMapList(saved['attachments']);
            current.add(attachment);
            saved['attachments'] = current;
            final lineId = xray.lineId;
            final attachmentId = attachment['id']?.toString();
            if (lineId != null && attachmentId != null) {
              uploadedByLine.putIfAbsent(lineId, () => []).add(attachmentId);
            }
          }
        } catch (error) {
          failedImages += 1;
          lastImageError = error;
        }
      }
      final merged = await _mergeLineAttachments(
        transactionId: saved['id'].toString(),
        version: jsonInt(saved['version'], fallback: 1),
        details: saved['details'] is Map ? Map<String, dynamic>.from(saved['details'] as Map) : Map<String, dynamic>.from(details ?? {}),
        uploadedByLine: uploadedByLine,
      );
      saved['details'] = merged['details'];
      saved['version'] = merged['version'];
      await _db.upsert('treatment_transactions', saved);
      _publish();
      if (failedImages > 0) {
        final detail = lastImageError == null ? '' : ' ${friendlyError(lastImageError, feature: 'upload')}';
        throw AppException(
          failedImages == 1
              ? 'Treatment saved, but the image could not be uploaded.$detail Open the visit to add it again.'
              : 'Treatment saved, but $failedImages images could not be uploaded.$detail Open the visit to add them again.',
          code: 'IMAGE_UPLOAD_PARTIAL',
        );
      }
      return 'Treatment saved.';
    } on OfflineException {
      if (xrays.isNotEmpty) {
        _throwXrayOffline();
      }
      payload['catalog_name'] = names[resolvedTreatmentId] ?? names[treatmentId] ?? 'Treatment';
      payload['sub_treatment'] = subTreatment;
      payload['patient_name'] = patientName;
      payload['patient_phone'] = patientPhone;
      payload['version'] = 1;
      await _db.upsert('treatment_transactions', {
        ...payload,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
      await _db.enqueueChange(
        clientChangeId: _uuid.v4(),
        entityType: 'treatment_transaction',
        entityId: payload['id'].toString(),
        operation: 'create',
        payload: payload,
      );
      _publish();
      return 'Saved on this device and waiting to sync.';
    }
  }

  Future<String> updateTreatmentVisit({
    required MoneyEntry entry,
    required String date,
    required String treatmentId,
    required String amount,
    String? patientId,
    String? patientName,
    String? patientPhone,
    String? subTreatment,
    Map<String, dynamic>? details,
    String? notes,
    List<String> removeAttachmentIds = const [],
    List<({List<int> bytes, String filename, String label, String? lineId})> xrays = const [],
  }) async {
    final resolvedTreatmentId = await _resolveCatalogId(
      collection: 'treatments',
      listPath: '/api/v1/treatments',
      id: treatmentId,
      extraKey: 'category_name',
    );
    final resolvedPatientId = await _resolvePatientId(patientId, name: patientName, phone: patientPhone);
    final payload = {
      'version': entry.version,
      'treatment_id': resolvedTreatmentId,
      'transaction_date': date,
      'quantity': entry.quantity,
      'amount': amount,
      'notes': notes,
      'patient_id': resolvedPatientId,
      'sub_treatment': subTreatment,
      'details': details ?? {},
    };
    final names = {for (final item in await treatments()) item.id: item.name};
    try {
      final response = await _api.patch('/api/v1/treatment-transactions/${entry.id}', data: payload);
      final saved = _asMap(response.data) ?? {...entry.toJson(), ...payload, 'version': entry.version + 1};
      saved['id'] = entry.id;
      saved['serial_no'] = saved['serial_no'] ?? entry.serialNo;
      saved['catalog_name'] = names[resolvedTreatmentId] ?? names[treatmentId] ?? saved['treatment_name'] ?? entry.catalogName;
      saved['sub_treatment'] = saved['sub_treatment'] ?? subTreatment;
      saved['patient_name'] = saved['patient_name'] ?? patientName;
      saved['patient_phone'] = saved['patient_phone'] ?? patientPhone;
      final attachments = jsonMapList(saved['attachments']);
      var failedImages = 0;
      Object? lastImageError;
      final uploadedByLine = <String, List<String>>{};
      for (final attachmentId in removeAttachmentIds) {
        try {
          await _api.delete('/api/v1/treatment-transactions/${entry.id}/attachments/$attachmentId');
          attachments.removeWhere((item) => item['id']?.toString() == attachmentId);
        } catch (error) {
          failedImages += 1;
          lastImageError = error;
        }
      }
      for (final xray in xrays) {
        final filename = clinicUploadFilename(xray.filename);
        try {
          final form = FormData.fromMap({
            'label': xray.label,
            'file': MultipartFile.fromBytes(
              xray.bytes,
              filename: filename,
              contentType: MediaType.parse(sniffImageContentType(xray.bytes, filename)),
            ),
          });
          final uploaded = await _api.postMultipart(
            '/api/v1/treatment-transactions/${entry.id}/attachments',
            data: form,
          );
          final attachment = _asMap(uploaded.data);
          if (attachment != null) {
            attachments.add(attachment);
            final lineId = xray.lineId;
            final attachmentId = attachment['id']?.toString();
            if (lineId != null && attachmentId != null) {
              uploadedByLine.putIfAbsent(lineId, () => []).add(attachmentId);
            }
          }
        } catch (error) {
          failedImages += 1;
          lastImageError = error;
        }
      }
      saved['attachments'] = attachments;
      final merged = await _mergeLineAttachments(
        transactionId: entry.id,
        version: jsonInt(saved['version'], fallback: entry.version + 1),
        details: saved['details'] is Map ? Map<String, dynamic>.from(saved['details'] as Map) : Map<String, dynamic>.from(details ?? {}),
        uploadedByLine: uploadedByLine,
      );
      saved['details'] = merged['details'];
      saved['version'] = merged['version'];
      await _db.upsert('treatment_transactions', saved);
      _publish();
      if (failedImages > 0) {
        final detail = lastImageError == null ? '' : ' ${friendlyError(lastImageError, feature: 'upload')}';
        throw AppException(
          failedImages == 1
              ? 'Treatment updated, but one image change could not be saved.$detail'
              : 'Treatment updated, but $failedImages image changes could not be saved.$detail',
          code: 'IMAGE_UPLOAD_PARTIAL',
        );
      }
      return 'Treatment updated.';
    } on OfflineException {
      if (xrays.isNotEmpty || removeAttachmentIds.isNotEmpty) {
        _throwXrayOffline();
      }
      final local = {
        ...entry.toJson(),
        ...payload,
        'id': entry.id,
        'catalog_name': names[resolvedTreatmentId] ?? names[treatmentId] ?? entry.catalogName,
        'sub_treatment': subTreatment,
        'patient_name': patientName,
        'patient_phone': patientPhone,
        'version': entry.version + 1,
      };
      await _db.upsert('treatment_transactions', local);
      await _db.enqueueChange(
        clientChangeId: _uuid.v4(),
        entityType: 'treatment_transaction',
        entityId: entry.id,
        operation: 'update',
        payload: payload,
        baseVersion: entry.version,
      );
      _publish();
      return 'Saved on this device and waiting to sync.';
    }
  }

  Future<List<MoneyEntry>> clinicExpenseHistory({DateRange? range, String? search}) async {
    final rows = await _namedExpenses(await _db.list('clinic_expenses'), 'clinic_expense_categories');
    return _filterEntries(rows, range: range, search: search);
  }

  Future<List<LabCharge>> labCharges({DateRange? range, String? search}) async {
    final rows = await _namedLabCharges(await _db.list('lab_charges'));
    var items = rows.map(LabCharge.fromJson).toList();
    if (range != null) {
      items = items.where((item) => range.containsIso(item.date)).toList();
    }
    final needle = search?.trim().toLowerCase();
    if (needle != null && needle.isNotEmpty) {
      items = items.where((item) {
        return item.displayLab.toLowerCase().contains(needle) ||
            (item.notes ?? '').toLowerCase().contains(needle) ||
            (item.patientName ?? '').toLowerCase().contains(needle) ||
            (item.patientPhone ?? '').toLowerCase().contains(needle) ||
            (item.visitLabel ?? '').toLowerCase().contains(needle);
      }).toList();
    }
    items.sort(
      (a, b) => _newestFirst(_recordInstant(a.createdAt, a.date), _recordInstant(b.createdAt, b.date), a.id, b.id),
    );
    return items;
  }

  Future<List<MoneyEntry>> labChargeHistory({DateRange? range, String? search}) async {
    return [for (final item in await labCharges(range: range, search: search)) item.toEntry()];
  }

  Future<LabCharge?> labChargeById(String id) async {
    final row = await _db.get('lab_charges', id);
    if (row == null || row['deleted_at'] != null) {
      return null;
    }
    return LabCharge.fromJson((await _namedLabCharges([row])).first);
  }

  Future<String> saveLabCharge({
    required String date,
    required String amount,
    String? patientId,
    String? transactionId,
    String? labName,
    String? notes,
  }) async {
    final payload = {
      'id': _uuid.v4(),
      'charge_date': date,
      'amount': amount,
      'patient_id': patientId,
      'transaction_id': transactionId,
      'lab_name': labName,
      'notes': notes,
    };
    try {
      final response = await _api.post('/api/v1/lab-charges', data: payload);
      await _db.upsert('lab_charges', _asMap(response.data) ?? {...payload, 'version': 1});
      _publish();
      return 'Lab charge saved.';
    } on OfflineException {
      await _db.upsert('lab_charges', {...payload, 'version': 1});
      await _db.enqueueChange(
        clientChangeId: _uuid.v4(),
        entityType: 'lab_charge',
        entityId: payload['id'].toString(),
        operation: 'create',
        payload: payload,
      );
      _publish();
      return 'Saved on this device and waiting to sync.';
    }
  }

  Future<String> updateLabCharge(
    LabCharge charge, {
    required String date,
    required String amount,
    String? patientId,
    String? transactionId,
    String? labName,
    String? notes,
  }) async {
    final patch = {
      'charge_date': date,
      'amount': amount,
      'patient_id': patientId,
      'transaction_id': transactionId,
      'lab_name': labName,
      'notes': notes,
    };
    try {
      final response = await _api.patch('/api/v1/lab-charges/${charge.id}', data: {'version': charge.version, ...patch});
      await _db.upsert(
        'lab_charges',
        _asMap(response.data) ?? {...charge.toJson(), ...patch, 'version': charge.version + 1},
      );
      _publish();
      return 'Lab charge updated.';
    } on OfflineException {
      await _db.upsert('lab_charges', {...charge.toJson(), ...patch, 'version': charge.version + 1});
      await _db.enqueueChange(
        clientChangeId: _uuid.v4(),
        entityType: 'lab_charge',
        entityId: charge.id,
        operation: 'update',
        payload: patch,
        baseVersion: charge.version,
      );
      _publish();
      return 'Saved on this device and waiting to sync.';
    }
  }

  Future<List<Map<String, dynamic>>> _namedLabCharges(List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) {
      return rows;
    }
    final patients = {
      for (final row in await _db.list('patients', includeDeleted: true)) row['id'].toString(): row,
    };
    final visits = {
      for (final row in await _db.list('treatment_transactions', includeDeleted: true)) row['id'].toString(): row,
    };
    return [
      for (final row in rows)
        {
          ...row,
          'patient_name': patients[row['patient_id']?.toString()]?['name'],
          'patient_phone': patients[row['patient_id']?.toString()]?['phone'],
          'visit_label': _visitLabel(visits[row['transaction_id']?.toString()]),
        },
    ];
  }

  String? _visitLabel(Map<String, dynamic>? visit) {
    if (visit == null) {
      return null;
    }
    final serial = visit['serial_no'];
    final treatment = jsonText(visit['sub_treatment']) ?? jsonText(visit['catalog_name']);
    final date = jsonText(visit['transaction_date']);
    return [
      if (serial != null) '#$serial',
      if (treatment != null) treatment,
      if (date != null) formatDisplayDate(date),
    ].join(' · ');
  }

  Future<void> _hydrateLabCharges() async {
    try {
      final rows = await _allPages('/api/v1/lab-charges', extra: {'page_size': 100, 'sort': '-charge_date'});
      await _db.upsertAll('lab_charges', rows);
    } catch (_) {}
  }

  Future<List<MoneyEntry>> homeExpenseHistory({DateRange? range, String? search}) async {
    final rows = await _namedExpenses(await _db.list('home_expenses'), 'home_expense_categories');
    return _filterEntries(rows, range: range, search: search);
  }

  Future<String> saveIncomeBatch({
    required String date,
    required List<({String treatmentId, String amount, int quantity, String? notes})> rows,
  }) async {
    final items = [
      for (final row in rows)
        {
          'id': _uuid.v4(),
          'treatment_id': await _resolveCatalogId(
            collection: 'treatments',
            listPath: '/api/v1/treatments',
            id: row.treatmentId,
            extraKey: 'category_name',
          ),
          'transaction_date': date,
          'quantity': row.quantity,
          'amount': row.amount,
          'notes': row.notes,
        },
    ];
    return _saveBatch(
      path: '/api/v1/treatment-transactions/batch',
      collection: 'treatment_transactions',
      entityType: 'treatment_transaction',
      items: items,
      names: {for (final item in await treatments()) item.id: item.name},
    );
  }

  Future<String> saveClinicExpenses({
    required String date,
    required List<({String categoryId, String amount, String? notes})> rows,
  }) {
    return _saveExpenseBatch(
      path: '/api/v1/clinic-expenses/batch',
      collection: 'clinic_expenses',
      entityType: 'clinic_expense',
      categories: clinicExpenseCategories,
      catalogCollection: 'clinic_expense_categories',
      catalogPath: '/api/v1/clinic-expense-categories',
      date: date,
      rows: rows,
    );
  }

  Future<String> saveHomeExpenses({
    required String date,
    required List<({String categoryId, String amount, String? notes})> rows,
  }) {
    return _saveExpenseBatch(
      path: '/api/v1/home-expenses/batch',
      collection: 'home_expenses',
      entityType: 'home_expense',
      categories: homeExpenseCategories,
      catalogCollection: 'home_expense_categories',
      catalogPath: '/api/v1/home-expense-categories',
      date: date,
      rows: rows,
    );
  }

  Future<String> updateEntry({
    required String collection,
    required String path,
    required String entityType,
    required MoneyEntry entry,
    required Map<String, dynamic> patch,
  }) async {
    final body = {'version': entry.version, ...patch};
    try {
      final response = await _api.patch(path, data: body);
      final saved = _asMap(response.data) ?? {...entry.toJson(), ...patch, 'version': entry.version + 1};
      saved['catalog_name'] = entry.catalogName;
      await _db.upsert(collection, saved);
      _publish();
      return 'Updated.';
    } on OfflineException {
      final local = {...entry.toJson(), ...patch, 'version': entry.version + 1};
      await _db.upsert(collection, local);
      await _db.enqueueChange(
        clientChangeId: _uuid.v4(),
        entityType: entityType,
        entityId: entry.id,
        operation: 'update',
        payload: patch,
        baseVersion: entry.version,
      );
      _publish();
      return 'Saved on this device and waiting to sync.';
    }
  }

  Future<void> deleteEntry({
    required String collection,
    required String path,
    required String entityType,
    required MoneyEntry entry,
  }) async {
    try {
      await _api.delete(path, query: {'version': entry.version});
      await _db.markDeleted(collection, entry.id);
    } on OfflineException {
      await _db.markDeleted(collection, entry.id);
      await _db.enqueueChange(
        clientChangeId: _uuid.v4(),
        entityType: entityType,
        entityId: entry.id,
        operation: 'delete',
        payload: {'version': entry.version},
        baseVersion: entry.version,
      );
    }
    _publish();
  }

  Future<HomeBudget?> budgetFor(int year, int month) async {
    final rows = await _db.list('home_budgets');
    for (final row in rows) {
      if (_asInt(row['year']) == year && _asInt(row['month']) == month) {
        return HomeBudget.fromJson(row);
      }
    }
    return null;
  }

  Future<void> saveBudget({required int year, required int month, required String amount}) async {
    final existing = await budgetFor(year, month);
    try {
      try {
        final response = await _api.put('/api/v1/home-budgets/current', data: {
          'year': year,
          'month': month,
          'amount': amount,
        });
        await _storeMonthBudget(year, month, _asMap(response.data));
        _publish();
        return;
      } on AppException catch (error) {
        if (!_isMissingRoute(error)) {
          rethrow;
        }
      }
      await _saveBudgetByPeriod(year: year, month: month, amount: amount);
      _publish();
    } on OfflineException {
      final local = {
        'id': existing?.id ?? _uuid.v4(),
        'year': year,
        'month': month,
        'amount': amount,
        'version': (existing?.version ?? 0) + 1,
      };
      await _storeMonthBudget(year, month, local);
      await _db.enqueueChange(
        clientChangeId: _uuid.v4(),
        entityType: 'home_budget',
        entityId: local['id'].toString(),
        operation: existing == null ? 'create' : 'update',
        payload: existing == null ? local : {'amount': amount},
        baseVersion: existing?.version,
      );
      _publish();
    }
  }

  Future<void> _saveBudgetByPeriod({required int year, required int month, required String amount}) async {
    final current = await _api.get('/api/v1/home-budgets/current', query: {'year': year, 'month': month});
    final body = _asMap(current.data) ?? {};
    final override = body['override'];
    if (override is Map && override['id'] != null) {
      try {
        final response = await _api.patch('/api/v1/home-budgets/${override['id']}', data: {
          'version': override['version'] ?? 1,
          'amount': amount,
        });
        await _storeMonthBudget(year, month, _asMap(response.data));
        return;
      } on AppException catch (error) {
        if (!_isNotFound(error)) {
          rethrow;
        }
      }
    }
    try {
      final response = await _api.post('/api/v1/home-budgets', data: {
        'id': _uuid.v4(),
        'year': year,
        'month': month,
        'amount': amount,
      });
      await _storeMonthBudget(year, month, _asMap(response.data));
    } on AppException catch (error) {
      if (error.code != 'CONFLICT' && error.statusCode != 409) {
        rethrow;
      }
      final retry = await _api.get('/api/v1/home-budgets/current', query: {'year': year, 'month': month});
      final retryOverride = (_asMap(retry.data) ?? {})['override'];
      if (retryOverride is! Map || retryOverride['id'] == null) {
        rethrow;
      }
      final response = await _api.patch('/api/v1/home-budgets/${retryOverride['id']}', data: {
        'version': retryOverride['version'] ?? 1,
        'amount': amount,
      });
      await _storeMonthBudget(year, month, _asMap(response.data));
    }
  }

  Future<void> _storeMonthBudget(int year, int month, Map<String, dynamic>? saved) async {
    if (saved == null) {
      return;
    }
    for (final row in await _db.list('home_budgets')) {
      if (_asInt(row['year']) == year && _asInt(row['month']) == month && row['id'].toString() != saved['id'].toString()) {
        await _db.markDeleted('home_budgets', row['id'].toString());
      }
    }
    await _db.upsert('home_budgets', saved);
  }

  bool _isMissingRoute(AppException error) {
    return error.statusCode == 404 || error.statusCode == 405 || error.code == 'NOT_FOUND';
  }

  Future<void> _pruneDuplicateMonthBudgets() async {
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final row in await _db.list('home_budgets')) {
      groups.putIfAbsent('${_asInt(row['year'])}-${_asInt(row['month'])}', () => []).add(row);
    }
    for (final group in groups.values) {
      if (group.length < 2) {
        continue;
      }
      group.sort((a, b) {
        final aServer = _serverCatalogIds.contains(a['id'].toString()) ? 0 : 1;
        final bServer = _serverCatalogIds.contains(b['id'].toString()) ? 0 : 1;
        return aServer.compareTo(bServer);
      });
      for (final extra in group.skip(1)) {
        await _db.markDeleted('home_budgets', extra['id'].toString());
      }
    }
  }

  Future<String> createCatalog({
    required String path,
    required String collection,
    required String entityType,
    required Map<String, dynamic> body,
  }) async {
    final payload = {'id': _uuid.v4(), ...body};
    try {
      final response = await _api.post(path, data: payload);
      final saved = _asMap(response.data) ?? payload;
      await _db.upsert(collection, saved);
      final id = saved['id']?.toString() ?? payload['id'].toString();
      _serverCatalogIds.add(id);
      return id;
    } on OfflineException {
      await _db.upsert(collection, payload);
      await _db.enqueueChange(
        clientChangeId: _uuid.v4(),
        entityType: entityType,
        entityId: payload['id'].toString(),
        operation: 'create',
        payload: payload,
      );
    }
    return payload['id'].toString();
  }

  Future<void> updateCatalog({
    required String path,
    required String collection,
    required String entityType,
    required String id,
    required int version,
    required Map<String, dynamic> patch,
  }) async {
    final body = {'version': version, ...patch};
    try {
      final response = await _api.patch(path, data: body);
      await _db.upsert(collection, _asMap(response.data) ?? {'id': id, ...patch, 'version': version + 1});
    } on OfflineException {
      final existing = await _db.get(collection, id) ?? {'id': id, 'version': version};
      await _db.upsert(collection, {...existing, ...patch, 'version': version + 1});
      await _db.enqueueChange(
        clientChangeId: _uuid.v4(),
        entityType: entityType,
        entityId: id,
        operation: 'update',
        payload: patch,
        baseVersion: version,
      );
    }
  }

  Future<void> deleteCatalog({
    required String path,
    required String collection,
    required String entityType,
    required String id,
    required int version,
  }) async {
    try {
      await _api.delete(path, query: {'version': version});
      await _db.markDeleted(collection, id);
    } on OfflineException {
      await _db.markDeleted(collection, id);
      await _db.enqueueChange(
        clientChangeId: _uuid.v4(),
        entityType: entityType,
        entityId: id,
        operation: 'delete',
        payload: {'version': version},
        baseVersion: version,
      );
    }
  }

  Future<List<NamedAmount>> breakdown(List<MoneyEntry> entries) {
    final totals = <String, double>{};
    for (final entry in entries) {
      totals[entry.catalogName] = (totals[entry.catalogName] ?? 0) + moneyToDouble(entry.amount);
    }
    final items = totals.entries.map((entry) => NamedAmount(name: entry.key, amount: moneyFromDouble(entry.value))).toList()
      ..sort((a, b) => moneyToDouble(b.amount).compareTo(moneyToDouble(a.amount)));
    return Future.value(items);
  }

  Future<List<NamedAmount>> timeline(List<MoneyEntry> entries) {
    final totals = <String, double>{};
    for (final entry in entries) {
      totals[entry.date] = (totals[entry.date] ?? 0) + moneyToDouble(entry.amount);
    }
    final items = totals.entries.map((entry) => NamedAmount(name: entry.key, amount: moneyFromDouble(entry.value))).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return Future.value(items);
  }

  Future<ResponseBytes> exportClinic({required DateRange range, required String format}) {
    return _export('/api/v1/reports/clinic/export', range, format);
  }

  Future<ResponseBytes> exportHome({required DateRange range, required String format}) {
    return _export('/api/v1/reports/home/export', range, format);
  }

  Future<void> pushPending() async {
    final pending = <Map<String, dynamic>>[];
    final labIds = <String>{};
    for (final row in await _db.pendingChanges()) {
      final entity = row['entity_type']?.toString() ?? '';
      if (_retiredSyncEntities.contains(entity)) {
        await _db.removePending(row['client_change_id'].toString());
        continue;
      }
      if (entity == 'clinic_expense' && row['operation'] == 'create' && await _isLegacyLabExpense(row)) {
        labIds.add(row['entity_id'].toString());
        pending.add(await _requeueAsLabCharge(row));
        continue;
      }
      if (entity == 'clinic_expense' && labIds.contains(row['entity_id'].toString())) {
        pending.add(await _requeueAsLabCharge(row));
        continue;
      }
      pending.add(row);
    }
    if (pending.isEmpty) {
      return;
    }
    final changes = [
      for (final row in pending)
        {
          'client_change_id': row['client_change_id'],
          'entity': row['entity_type'],
          'operation': row['operation'],
          'entity_id': row['entity_id'],
          if (row['base_version'] != null) 'base_version': row['base_version'],
          'data': _syncPayload(row['payload']),
        },
    ];
    final response = await _api.post(
      '/api/v1/sync/push',
      data: {
        'device_id': await _device.id(),
        'changes': changes,
      },
    );
    final results = (((response.data as Map?)?['results'] as List?) ?? []);
    for (var i = 0; i < results.length; i++) {
      final result = Map<String, dynamic>.from(results[i] as Map);
      final change = pending[i];
      final status = result['status']?.toString();
      if (status == 'applied') {
        final record = result['record'];
        if (record is Map) {
          final collection = _collections[change['entity_type']] ?? change['entity_type'].toString();
          await _db.upsert(collection, Map<String, dynamic>.from(record));
        }
        await _db.removePending(change['client_change_id'].toString());
      } else if (status == 'conflict') {
        await _db.upsert('conflicts', {
          'id': change['client_change_id'],
          'entity_type': change['entity_type'],
          'entity_id': change['entity_id'],
          'local': change['payload'],
          'server': result['record'] ?? {},
        });
        await _db.removePending(change['client_change_id'].toString());
      } else {
        await _db.setPendingStatus(change['client_change_id'].toString(), 'failed');
      }
    }
  }

  Future<bool> _isLegacyLabExpense(Map<String, dynamic> change) async {
    final payload = change['payload'];
    final categoryId = payload is Map ? payload['category_id']?.toString() : null;
    if (categoryId == null) {
      return false;
    }
    final category = await _db.get('clinic_expense_categories', categoryId);
    return isLabChargeCategoryName(category?['name']?.toString());
  }

  // Offline entries made under the old "Lab Charges" expense category are sent as lab charges
  // so they are not rejected by the server or counted as clinic expenses.
  Future<Map<String, dynamic>> _requeueAsLabCharge(Map<String, dynamic> change) async {
    final payload = Map<String, dynamic>.from((change['payload'] as Map?) ?? {});
    final id = change['entity_id'].toString();
    final operation = change['operation'].toString();
    final data = <String, dynamic>{
      if (operation == 'create') 'id': id,
      if (payload.containsKey('expense_date')) 'charge_date': payload['expense_date'],
      if (payload.containsKey('amount')) 'amount': payload['amount'],
      if (payload.containsKey('notes')) 'notes': payload['notes'],
    };
    final baseVersion = change['base_version'] as int?;
    final clientChangeId = _uuid.v4();
    await _db.removePending(change['client_change_id'].toString());
    await _db.enqueueChange(
      clientChangeId: clientChangeId,
      entityType: 'lab_charge',
      entityId: id,
      operation: operation,
      payload: data,
      baseVersion: baseVersion,
    );
    if (operation == 'create') {
      final local = await _db.get('clinic_expenses', id);
      await _db.markDeleted('clinic_expenses', id);
      if (local != null && local['deleted_at'] == null) {
        await _db.upsert('lab_charges', {
          'id': id,
          'charge_date': local['expense_date'] ?? data['charge_date'],
          'amount': local['amount'] ?? data['amount'],
          'notes': local['notes'],
          'version': local['version'] ?? 1,
        });
      }
    }
    return {
      'client_change_id': clientChangeId,
      'entity_type': 'lab_charge',
      'entity_id': id,
      'operation': operation,
      if (baseVersion != null) 'base_version': baseVersion,
      'payload': data,
    };
  }

  Future<ResponseBytes> _export(String path, DateRange range, String format) async {
    final response = await _api.getBytes(path, query: {
      'from_date': range.fromIso,
      'to_date': range.toIso,
      'format': format,
    });
    final stamp = DateTime.now();
    final tag =
        '${stamp.year}${stamp.month.toString().padLeft(2, '0')}${stamp.day.toString().padLeft(2, '0')}-'
        '${stamp.hour.toString().padLeft(2, '0')}${stamp.minute.toString().padLeft(2, '0')}';
    final name = format == 'xlsx' ? 'nabi-report-$tag.xlsx' : 'nabi-report-$tag.pdf';
    return ResponseBytes(
      bytes: response.data ?? <int>[],
      filename: name,
      mime: format == 'xlsx'
          ? 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
          : 'application/pdf',
    );
  }

  Future<void> _bootstrap() async {
    final response = await _api.post('/api/v1/sync/bootstrap');
    final body = _asMap(response.data) ?? {};
    final data = Map<String, dynamic>.from(body['data'] as Map? ?? {});
    for (final entry in data.entries) {
      final rows = (entry.value as List? ?? []).map((item) => Map<String, dynamic>.from(item as Map)).toList();
      await _db.upsertAll(entry.key, rows);
    }
    final cursor = body['cursor']?.toString();
    if (cursor != null) {
      await _db.setMeta('sync_cursor', cursor);
    }
  }

  Future<void> _pull(String cursor) async {
    final response = await _api.get('/api/v1/sync/pull', query: {'cursor': cursor, 'limit': 500});
    final body = _asMap(response.data) ?? {};
    final changes = Map<String, dynamic>.from(body['changes'] as Map? ?? {});
    for (final entry in changes.entries) {
      final rows = (entry.value as List? ?? []).map((item) => Map<String, dynamic>.from(item as Map)).toList();
      await _db.upsertAll(entry.key, rows);
    }
    final next = body['next_cursor']?.toString();
    if (next != null) {
      await _db.setMeta('sync_cursor', next);
    }
  }

  bool _isNotFound(Object error) {
    return error is AppException &&
        (error.code == 'NOT_FOUND' || error.message.toLowerCase().contains('not found'));
  }

  Future<String> _resolveCatalogId({
    required String collection,
    required String listPath,
    required String id,
    String? extraKey,
  }) async {
    try {
      await _api.get('$listPath/$id');
      _serverCatalogIds.add(id);
      return id;
    } on OfflineException {
      return id;
    } on AppException catch (error) {
      if (!_isNotFound(error)) {
        rethrow;
      }
    }
    final local = await _db.get(collection, id);
    final name = (local?['name']?.toString() ?? '').trim().toLowerCase();
    final extra = extraKey == null ? '' : (local?[extraKey]?.toString() ?? '').trim().toLowerCase();
    if (name.isEmpty) {
      return id;
    }

    bool matches(Map<String, dynamic> row) {
      if ((row['name']?.toString() ?? '').trim().toLowerCase() != name) {
        return false;
      }
      if (extraKey == null || extra.isEmpty) {
        return true;
      }
      final rowExtra = (row[extraKey]?.toString() ?? row['category_name']?.toString() ?? '').trim().toLowerCase();
      return rowExtra.isEmpty || rowExtra == extra;
    }

    for (final row in await _db.list(collection)) {
      final candidate = row['id'].toString();
      if (candidate == id || !matches(row)) {
        continue;
      }
      try {
        await _api.get('$listPath/$candidate');
        _serverCatalogIds.add(candidate);
        return candidate;
      } on OfflineException {
        return candidate;
      } on AppException catch (error) {
        if (!_isNotFound(error)) {
          rethrow;
        }
      }
    }

    try {
      final remote = await _allPages(listPath, extra: {'page_size': 100});
      for (final row in remote) {
        if (!matches(row)) {
          continue;
        }
        final resolved = row['id'].toString();
        await _db.upsert(collection, {
          ...row,
          if (local != null) 'category_name': local['category_name'] ?? row['category_name'],
        });
        _serverCatalogIds.add(resolved);
        return resolved;
      }
    } on OfflineException {
      return id;
    } on AppException {
      return id;
    }
    return id;
  }

  Future<String?> _resolvePatientId(String? patientId, {String? name, String? phone}) async {
    if (patientId == null || patientId.isEmpty) {
      return null;
    }
    try {
      await _api.get('/api/v1/patients/$patientId');
      return patientId;
    } on OfflineException {
      return patientId;
    } on AppException catch (error) {
      if (!_isNotFound(error)) {
        rethrow;
      }
    }
    final needleName = (name ?? '').trim().toLowerCase();
    final needlePhone = (phone ?? '').trim();
    try {
      final remote = await _allPages('/api/v1/patients', extra: {'page_size': 100, 'sort': 'name'});
      for (final row in remote) {
        final rowName = (row['name']?.toString() ?? '').trim().toLowerCase();
        final rowPhone = (row['phone']?.toString() ?? '').trim();
        final sameName = needleName.isNotEmpty && rowName == needleName;
        final samePhone = needlePhone.isEmpty || rowPhone.isEmpty || rowPhone == needlePhone;
        if (sameName && samePhone) {
          await _db.upsert('patients', row);
          return row['id'].toString();
        }
      }
      if (needleName.length >= 2) {
        return await createCatalog(
          path: '/api/v1/patients',
          collection: 'patients',
          entityType: 'patient',
          body: {
            'name': name!.trim(),
            if (needlePhone.isNotEmpty) 'phone': needlePhone,
          },
        );
      }
    } catch (_) {}
    return patientId;
  }

  Future<void> _hydrateRest() async {
    final pages = await Future.wait([
      _allPages('/api/v1/treatments', extra: {'page_size': 100}),
      _allPages('/api/v1/treatment-categories', extra: {'page_size': 100}),
      _allPages('/api/v1/clinic-expense-categories', extra: {'page_size': 100}),
      _allPages('/api/v1/patients', extra: {'page_size': 100, 'sort': '-created_at'}),
      _allPages('/api/v1/treatment-transactions', extra: {'page_size': 100, 'sort': '-created_at'}),
      _allPages('/api/v1/clinic-expenses', extra: {'page_size': 100, 'sort': '-expense_date'}),
    ]);
    final treatments = pages[0];
    final treatmentCats = pages[1];
    final clinicCats = pages[2];
    final patients = pages[3];
    final transactions = pages[4];
    final clinicExpenses = pages[5];
    final catNames = {
      for (final item in treatmentCats) item['id'].toString(): item['name'].toString(),
    };
    await _db.upsertAll(
      'treatments',
      treatments
          .map((item) => {
                ...item,
                'category_name': catNames[item['category_id'].toString()] ?? '',
              })
          .toList(),
    );
    await _db.upsertAll('treatment_categories', treatmentCats);
    await _db.upsertAll('clinic_expense_categories', clinicCats);
    await _replacePatients(patients);
    await _db.upsertAll('treatment_transactions', await _namedTransactions(transactions));
    await _db.upsertAll(
      'clinic_expenses',
      await _namedExpenses(clinicExpenses, 'clinic_expense_categories'),
    );
    _serverCatalogIds
      ..addAll(treatments.map((item) => item['id'].toString()))
      ..addAll(treatmentCats.map((item) => item['id'].toString()))
      ..addAll(clinicCats.map((item) => item['id'].toString()))
      ..addAll(patients.map((item) => item['id'].toString()));
  }

  Future<void> _hydrateHome() async {
    try {
      final pages = await Future.wait([
        _allPages('/api/v1/home-expense-categories', extra: {'page_size': 100, 'sort': 'display_order'}),
        _allPages('/api/v1/home-expenses', extra: {'page_size': 100, 'sort': '-expense_date'}),
        _allPages('/api/v1/home-budgets', extra: {'page_size': 100}),
      ]);
      final categories = pages[0];
      final expenses = pages[1];
      final budgets = pages[2];
      await _db.upsertAll('home_expense_categories', categories);
      await _db.upsertAll(
        'home_expenses',
        await _namedExpenses(expenses, 'home_expense_categories'),
      );
      await _db.upsertAll('home_budgets', budgets);
      _serverCatalogIds.addAll(categories.map((item) => item['id'].toString()));
    } catch (_) {}
  }

  // Kept for one-off repairs if local catalog names are missing after a partial sync.
  // ignore: unused_element
  Future<void> _decorateNames() async {
    final treatmentNames = {for (final item in await treatments()) item.id: item.name};
    final clinicNames = {for (final item in await clinicExpenseCategories()) item.id: item.name};
    final homeNames = {for (final item in await homeExpenseCategories()) item.id: item.name};
    final catNames = {for (final item in await treatmentCategories()) item.id: item.name};
    for (final row in await _db.list('treatments')) {
      row['category_name'] = catNames[row['category_id']?.toString()] ?? row['category_name'];
      await _db.upsert('treatments', row);
    }
    for (final row in await _db.list('treatment_transactions')) {
      row['catalog_name'] = treatmentNames[row['treatment_id']?.toString()] ?? row['catalog_name'] ?? 'Treatment';
      await _db.upsert('treatment_transactions', row);
    }
    for (final row in await _db.list('clinic_expenses')) {
      row['catalog_name'] = clinicNames[row['category_id']?.toString()] ?? row['catalog_name'] ?? 'Category';
      await _db.upsert('clinic_expenses', row);
    }
    for (final row in await _db.list('home_expenses')) {
      row['catalog_name'] = homeNames[row['category_id']?.toString()] ?? row['catalog_name'] ?? 'Category';
      await _db.upsert('home_expenses', row);
    }
  }

  Future<List<Map<String, dynamic>>> _allPages(String path, {Map<String, dynamic>? extra}) async {
    final items = <Map<String, dynamic>>[];
    var page = 1;
    while (true) {
      final response = await _api.get(path, query: {'page': page, ...?extra});
      final body = _asMap(response.data) ?? {};
      final chunk = ((body['items'] as List?) ?? []).map((item) => Map<String, dynamic>.from(item as Map)).toList();
      items.addAll(chunk);
      final parsedPages = _asInt(body['total_pages']);
      final totalPages = parsedPages < 1 ? 1 : parsedPages;
      if (page >= totalPages || chunk.isEmpty) {
        break;
      }
      page += 1;
    }
    return items;
  }

  Future<List<Map<String, dynamic>>> _namedTransactions(List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) {
      return rows;
    }
    final needsCatalog = rows.any((row) => (row['catalog_name']?.toString() ?? '').isEmpty);
    final hasPatient = rows.any((row) {
      final id = row['patient_id']?.toString() ?? '';
      return id.isNotEmpty;
    });
    if (!needsCatalog && !hasPatient) {
      return rows;
    }
    final names = <String, String>{};
    final categories = <String, String?>{};
    if (needsCatalog) {
      for (final item in await treatments()) {
        names[item.id] = item.name;
        categories[item.id] = item.categoryName;
      }
    }
    final patients = hasPatient
        ? {for (final item in await _db.list('patients')) item['id'].toString(): item}
        : const <String, Map<String, dynamic>>{};
    return [
      for (final row in rows) _overlayPatientIdentity(row, patients, names, categories, fillCatalog: needsCatalog),
    ];
  }

  Map<String, dynamic> _overlayPatientIdentity(
    Map<String, dynamic> row,
    Map<String, Map<String, dynamic>> patients,
    Map<String, String> names,
    Map<String, String?> categories, {
    required bool fillCatalog,
  }) {
    final live = patients[row['patient_id']?.toString()];
    final liveName = live?['name']?.toString().trim();
    return {
      ...row,
      if (fillCatalog) ...{
        'catalog_name': names[row['treatment_id'].toString()] ?? row['catalog_name'] ?? 'Treatment',
        'category_name': categories[row['treatment_id'].toString()] ?? row['category_name'],
        'sub_treatment': row['sub_treatment'] ?? (row['details'] is Map ? row['details']['sub_treatment'] : null),
      },
      'patient_name': liveName != null && liveName.isNotEmpty ? liveName : row['patient_name'],
      'patient_phone': live != null ? live['phone'] : row['patient_phone'],
    };
  }

  Future<Set<String>> _pendingEntityIds(String entityType) async {
    final pending = await _db.pendingChanges();
    return {
      for (final row in pending)
        if (row['entity_type']?.toString() == entityType) row['entity_id'].toString(),
    };
  }

  Future<void> _replacePatients(List<Map<String, dynamic>> remote) async {
    final remoteIds = {for (final row in remote) row['id'].toString()};
    final pendingIds = await _pendingEntityIds('patient');
    for (final row in await _db.list('patients')) {
      final id = row['id'].toString();
      if (!remoteIds.contains(id) && !pendingIds.contains(id)) {
        await _db.markDeleted('patients', id);
      }
    }
    final incoming = [
      for (final row in remote)
        if (!pendingIds.contains(row['id'].toString())) row,
    ];
    await _db.upsertAll('patients', incoming);
  }

  Never _throwXrayOffline() {
    throw const AppException(
      'X-ray images can only be saved while the clinic is online. Remove the images, or start Docker and save again.',
      code: 'XRAY_OFFLINE',
    );
  }

  Future<List<PatientRecord>> _localPatients({String? search}) async {
    var items = [for (final row in await _db.list('patients')) PatientRecord.fromJson(row)];
    _sortPatients(items);
    final needle = search?.trim().toLowerCase();
    if (needle != null && needle.isNotEmpty) {
      items = items
          .where(
            (item) =>
                item.name.toLowerCase().contains(needle) || (item.phone ?? '').toLowerCase().contains(needle),
          )
          .toList();
    }
    return items;
  }

  void _sortPatients(List<PatientRecord> items) {
    items.sort((a, b) {
      final byTime = _newestFirst(_recordInstant(a.createdAt, null), _recordInstant(b.createdAt, null), '', '');
      final aCreated = a.createdAt?.trim().isNotEmpty == true;
      final bCreated = b.createdAt?.trim().isNotEmpty == true;
      if (byTime != 0 && (aCreated || bCreated)) {
        return byTime;
      }
      final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      if (byName != 0) {
        return byName;
      }
      return b.id.compareTo(a.id);
    });
  }

  List<MoneyEntry> _sortEntries(List<MoneyEntry> entries) {
    entries.sort(_compareEntries);
    return entries;
  }

  String? _usefulCatalogName(Object? value) => usefulCatalogName(value);

  void _assignCatalogName(Map<String, dynamic> row, Map<String, String> lookup) {
    final categoryId = row['category_id']?.toString();
    final treatmentId = row['treatment_id']?.toString();
    final resolved = (categoryId != null && categoryId.isNotEmpty ? lookup[categoryId] : null) ??
        (treatmentId != null && treatmentId.isNotEmpty ? lookup[treatmentId] : null);
    final label = _usefulCatalogName(resolved) ??
        _usefulCatalogName(row['catalog_name']) ??
        _usefulCatalogName(row['category_name']);
    if (label != null) {
      row['catalog_name'] = label;
      return;
    }
    if (categoryId != null && categoryId.isNotEmpty) {
      row.remove('catalog_name');
      return;
    }
    row['catalog_name'] = 'Item';
  }

  Future<List<Map<String, dynamic>>> _namedExpenses(List<Map<String, dynamic>> rows, String collection) async {
    if (rows.isEmpty) {
      return rows;
    }
    final names = <String, String>{};
    for (final row in await _db.list(collection, includeDeleted: true)) {
      final name = _usefulCatalogName(row['name']);
      if (name != null) {
        names[row['id'].toString()] = name;
      }
    }
    return [
      for (final row in rows)
        {
          ...row,
          'catalog_name': names[row['category_id']?.toString()] ??
              _usefulCatalogName(row['catalog_name']) ??
              _usefulCatalogName(row['category_name']) ??
              'Category',
        },
    ];
  }

  List<MoneyEntry> _filterEntries(List<Map<String, dynamic>> rows, {DateRange? range, String? search}) {
    var entries = rows.map(MoneyEntry.fromJson).toList();
    if (range != null) {
      entries = entries.where((entry) => range.containsIso(entry.date)).toList();
    }
    final needle = search?.trim().toLowerCase();
    if (needle != null && needle.isNotEmpty) {
      entries = entries.where((entry) {
        return entry.catalogName.toLowerCase().contains(needle) ||
            (entry.notes ?? '').toLowerCase().contains(needle) ||
            (entry.patientName ?? '').toLowerCase().contains(needle) ||
            (entry.patientPhone ?? '').toLowerCase().contains(needle) ||
            (entry.subTreatment ?? '').toLowerCase().contains(needle) ||
            (entry.detailsText ?? '').toLowerCase().contains(needle);
      }).toList();
    }
    entries.sort(_compareEntries);
    return entries;
  }

  double _sum(List<MoneyEntry> entries) => entries.fold(0, (sum, entry) => sum + moneyToDouble(entry.amount));

  double _sumRows(List<Map<String, dynamic>> rows, DateRange range) {
    var total = 0.0;
    for (final row in rows) {
      final raw = (row['transaction_date'] ?? row['expense_date'] ?? row['charge_date'] ?? row['date'] ?? '').toString();
      final date = raw.length >= 10 ? raw.substring(0, 10) : raw;
      if (!range.containsIso(date)) {
        continue;
      }
      total += moneyToDouble(row['amount']?.toString() ?? '0');
    }
    return total;
  }

  Future<String> _saveExpenseBatch({
    required String path,
    required String collection,
    required String entityType,
    required Future<List<CatalogItem>> Function() categories,
    required String catalogCollection,
    required String catalogPath,
    required String date,
    required List<({String categoryId, String amount, String? notes})> rows,
  }) async {
    final items = [
      for (final row in rows)
        {
          'id': _uuid.v4(),
          'category_id': await _resolveCatalogId(
            collection: catalogCollection,
            listPath: catalogPath,
            id: row.categoryId,
          ),
          'expense_date': date,
          'amount': row.amount,
          'notes': row.notes,
        },
    ];
    final names = <String, String>{};
    for (final row in await _db.list(catalogCollection, includeDeleted: true)) {
      final name = _usefulCatalogName(row['name']);
      if (name != null) {
        names[row['id'].toString()] = name;
      }
    }
    return _saveBatch(
      path: path,
      collection: collection,
      entityType: entityType,
      items: items,
      names: names,
      loadNames: categories,
    );
  }

  Future<String> _saveBatch({
    required String path,
    required String collection,
    required String entityType,
    required List<Map<String, dynamic>> items,
    required Map<String, String> names,
    Future<List<CatalogItem>> Function()? loadNames,
  }) async {
    final lookup = {...names};
    if (loadNames != null) {
      lookup.addAll({for (final item in await loadNames()) item.id: item.name});
    }
    try {
      final response = await _api.post(path, data: {'items': items});
      final saved = _asMaps(response.data, items);
      for (final row in saved) {
        _assignCatalogName(row, lookup);
        await _db.upsert(collection, row);
      }
      _publish();
      return 'Saved and synced.';
    } on OfflineException {
      for (final row in items) {
        _assignCatalogName(row, lookup);
        row['version'] = 1;
        await _db.upsert(collection, row);
        await _db.enqueueChange(
          clientChangeId: _uuid.v4(),
          entityType: entityType,
          entityId: row['id'].toString(),
          operation: 'create',
          payload: row,
        );
      }
      _publish();
      return 'Saved on this device and waiting to sync.';
    }
  }

  Map<String, dynamic> _syncPayload(dynamic raw) {
    final data = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    data.remove('catalog_name');
    data.remove('_deleted');
    data.remove('category_name');
    data.remove('material_name');
    return data;
  }

  Map<String, dynamic>? _asMap(dynamic raw) {
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    return null;
  }

  List<Map<String, dynamic>> _asMaps(dynamic raw, List<Map<String, dynamic>> fallback) {
    if (raw is List) {
      return raw.map((item) => Map<String, dynamic>.from(item as Map)).toList();
    }
    final map = _asMap(raw);
    if (map != null && map['items'] is List) {
      return (map['items'] as List).map((item) => Map<String, dynamic>.from(item as Map)).toList();
    }
    return fallback;
  }

  int _asInt(dynamic value) {
    if (value is int) {
      return value;
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

class ResponseBytes {
  const ResponseBytes({required this.bytes, required this.filename, required this.mime});
  final List<int> bytes;
  final String filename;
  final String mime;
}

final financeRepositoryProvider = Provider((ref) {
  return FinanceRepository(
    api: ref.watch(apiClientProvider),
    database: ref.watch(databaseProvider),
    device: ref.watch(deviceIdentityProvider),
    onChanged: () => ref.read(financeEpochProvider.notifier).state++,
  );
});

final financeEpochProvider = StateProvider<int>((ref) => 0);
