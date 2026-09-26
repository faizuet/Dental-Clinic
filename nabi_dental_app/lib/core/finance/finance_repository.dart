import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../api/api_client.dart';
import '../auth/session_controller.dart';
import '../database/app_database.dart';
import '../errors/app_exception.dart';
import '../models/finance_models.dart';
import '../security/device_id.dart';
import '../utils/money.dart';
import '../utils/period.dart';
import 'construction_defaults.dart';

const _collections = {
  'treatment_category': 'treatment_categories',
  'treatment': 'treatments',
  'treatment_transaction': 'treatment_transactions',
  'patient': 'patients',
  'clinic_expense_category': 'clinic_expense_categories',
  'clinic_expense': 'clinic_expenses',
  'home_expense_category': 'home_expense_categories',
  'home_expense': 'home_expenses',
  'home_budget': 'home_budgets',
  'construction_material_category': 'construction_material_categories',
  'construction_material': 'construction_materials',
  'construction_purchase': 'construction_purchases',
};

class ClinicTotals {
  const ClinicTotals({
    required this.income,
    required this.expenses,
    required this.profit,
    required this.range,
    this.online = true,
  });

  final String income;
  final String expenses;
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

class ConstructionTotals {
  const ConstructionTotals({
    required this.spent,
    required this.purchaseCount,
    required this.byCategory,
    required this.byMaterial,
    required this.bySupplier,
    required this.recent,
    required this.monthly,
    required this.topMaterials,
    required this.range,
  });

  final String spent;
  final int purchaseCount;
  final List<NamedAmount> byCategory;
  final List<NamedAmount> byMaterial;
  final List<NamedAmount> bySupplier;
  final List<ConstructionPurchase> recent;
  final List<NamedAmount> monthly;
  final List<NamedAmount> topMaterials;
  final DateRange range;
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
  })  : _api = api,
        _db = database,
        _device = device;

  final ApiClient _api;
  final AppDatabase _db;
  final DeviceIdentity _device;
  static const _uuid = Uuid();
  final _serverCatalogIds = <String>{};

  Future<bool> refresh() async {
    try {
      await pushPending();
      final cursor = await _db.meta('sync_cursor');
      if (cursor == null) {
        await _bootstrap();
      } else {
        await _pull(cursor);
      }
      await _hydrateRest();
      await _decorateNames();
      await _pruneDuplicateFinanceCatalogs();
      await ensureConstructionCatalog();
      await _db.setMeta('last_sync', DateTime.now().toUtc().toIso8601String());
      await _db.setMeta('sync_state', 'synced');
      return true;
    } on OfflineException {
      await _db.setMeta('sync_state', 'offline');
      await _pruneDuplicateFinanceCatalogs();
      await ensureConstructionCatalog();
      return false;
    } on AppException {
      try {
        await _hydrateRest();
        await _decorateNames();
        await _pruneDuplicateFinanceCatalogs();
        await ensureConstructionCatalog();
        await _db.setMeta('last_sync', DateTime.now().toUtc().toIso8601String());
        return true;
      } on OfflineException {
        await _db.setMeta('sync_state', 'offline');
        await _pruneDuplicateFinanceCatalogs();
        await ensureConstructionCatalog();
        return false;
      } on AppException {
        await _db.setMeta('sync_state', 'failed');
        await _pruneDuplicateFinanceCatalogs();
        await ensureConstructionCatalog();
        return false;
      }
    }
  }

  Future<void> ensureConstructionCatalog() async {
    try {
      await _hydrateConstruction();
      await _decorateConstructionLocal();
      await _pruneLocalConstructionSeed();
    } catch (_) {}
    if ((await constructionMaterials()).isNotEmpty) {
      return;
    }
    try {
      await _bootstrap();
      await _hydrateConstruction();
      await _decorateConstructionLocal();
      await _pruneLocalConstructionSeed();
    } catch (_) {}
    if ((await constructionMaterials()).isEmpty) {
      await _installLocalConstructionSeed();
    }
  }

  Future<String> _resolveConstructionMaterialId(String materialId) async {
    final materials = await constructionMaterials();
    ConstructionMaterial? material;
    for (final item in materials) {
      if (item.id == materialId) {
        material = item;
        break;
      }
    }
    if (material == null || !material.localSeed) {
      return materialId;
    }
    try {
      await _hydrateConstruction();
      await _decorateConstructionLocal();
      final server = await constructionMaterials();
      for (final item in server) {
        if (!item.localSeed && item.name == material.name) {
          return item.id;
        }
      }
    } catch (_) {}
    final categories = await constructionMaterialCategories();
    CatalogItem? category;
    for (final item in categories) {
      if (item.id == material.categoryId) {
        category = item;
        break;
      }
    }
    try {
      if (category != null) {
        await createCatalog(
          path: '/api/v1/construction-material-categories',
          collection: 'construction_material_categories',
          entityType: 'construction_material_category',
          body: {'id': category.id, 'name': category.name},
        );
      }
      await createCatalog(
        path: '/api/v1/construction-materials',
        collection: 'construction_materials',
        entityType: 'construction_material',
        body: {
          'id': material.id,
          'category_id': material.categoryId,
          'name': material.name,
          'unit': material.unit,
        },
      );
      return material.id;
    } catch (_) {
      return material.id;
    }
  }

  Future<void> _pruneLocalConstructionSeed() async {
    final categories = await _db.list('construction_material_categories');
    final materials = await _db.list('construction_materials');
    String key(Object? value) => (value?.toString() ?? '').trim().toLowerCase();

    final serverCategoryIds = {
      for (final row in categories)
        if (row['local_seed'] != true) key(row['name']): row['id'].toString(),
    };
    final serverMaterialIds = <String, String>{};
    for (final row in materials) {
      if (row['local_seed'] == true) {
        continue;
      }
      serverMaterialIds['${key(row['name'])}|${key(row['category_name'])}'] = row['id'].toString();
      serverMaterialIds[key(row['name'])] = row['id'].toString();
    }

    final materialIdMap = <String, String>{};
    for (final row in materials) {
      if (row['local_seed'] != true) {
        continue;
      }
      final serverId = serverMaterialIds['${key(row['name'])}|${key(row['category_name'])}'] ?? serverMaterialIds[key(row['name'])];
      if (serverId == null) {
        continue;
      }
      materialIdMap[row['id'].toString()] = serverId;
      await _db.markDeleted('construction_materials', row['id'].toString());
    }
    for (final row in categories) {
      if (row['local_seed'] == true && serverCategoryIds.containsKey(key(row['name']))) {
        await _db.markDeleted('construction_material_categories', row['id'].toString());
      }
    }
    if (materialIdMap.isEmpty) {
      return;
    }
    for (final row in await _db.list('construction_purchases')) {
      final mapped = materialIdMap[row['material_id']?.toString()];
      if (mapped != null) {
        row['material_id'] = mapped;
        await _db.upsert('construction_purchases', row);
      }
    }
  }

  Future<void> _installLocalConstructionSeed() async {
    var categoryOrder = 0;
    for (final entry in defaultConstructionCatalog.entries) {
      final categoryId = _uuid.v4();
      await _db.upsert('construction_material_categories', {
        'id': categoryId,
        'name': entry.key,
        'display_order': categoryOrder,
        'is_active': true,
        'version': 1,
        'local_seed': true,
      });
      var materialOrder = 0;
      for (final material in entry.value) {
        await _db.upsert('construction_materials', {
          'id': _uuid.v4(),
          'category_id': categoryId,
          'name': material.$1,
          'unit': material.$2,
          'category_name': entry.key,
          'display_order': materialOrder,
          'is_active': true,
          'version': 1,
          'local_seed': true,
        });
        materialOrder += 1;
      }
      categoryOrder += 1;
    }
  }

  Future<SyncStatus> syncStatus() async {
    return SyncStatus(
      pending: await _db.pendingCount(),
      conflicts: await _db.conflictCount(),
      lastSync: await _db.meta('last_sync'),
      state: await _db.meta('sync_state') ?? 'idle',
    );
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
    await refresh();
  }

  Future<List<CatalogItem>> treatments() async {
    final rows = await _db.list('treatments');
    final items = rows
        .map((row) => CatalogItem.fromJson(row, categoryName: row['category_name']?.toString()))
        .where((item) => item.isActive);
    return _uniqueCatalogItems(items);
  }

  Future<List<CatalogItem>> clinicExpenseCategories() => _categories('clinic_expense_categories');

  Future<List<CatalogItem>> homeExpenseCategories() => _categories('home_expense_categories');

  Future<List<CatalogItem>> treatmentCategories() => _categories('treatment_categories');

  Future<List<CatalogItem>> constructionMaterialCategories() => _categories('construction_material_categories');

  Future<List<ConstructionMaterial>> constructionMaterials() async {
    final items = (await _db.list('construction_materials')).map(ConstructionMaterial.fromJson).where((item) => item.isActive);
    final unique = <String, ConstructionMaterial>{};
    for (final item in items) {
      final key = '${item.name.trim().toLowerCase()}|${(item.categoryName ?? '').trim().toLowerCase()}';
      final existing = unique[key];
      if (existing == null || (existing.localSeed && !item.localSeed)) {
        unique[key] = item;
      }
    }
    return unique.values.toList()
      ..sort((a, b) {
        final category = (a.categoryName ?? '').compareTo(b.categoryName ?? '');
        return category != 0 ? category : a.name.compareTo(b.name);
      });
  }

  Future<List<ConstructionPurchase>> constructionPurchases({DateRange? range, String? search}) async {
    var items = (await _db.list('construction_purchases')).map(ConstructionPurchase.fromJson).toList();
    if (range != null) {
      items = items.where((item) => range.containsIso(item.date)).toList();
    }
    final needle = search?.trim().toLowerCase();
    if (needle != null && needle.isNotEmpty) {
      items = items.where((item) {
        return (item.materialName ?? '').toLowerCase().contains(needle) ||
            (item.categoryName ?? '').toLowerCase().contains(needle) ||
            (item.supplier ?? '').toLowerCase().contains(needle) ||
            (item.notes ?? '').toLowerCase().contains(needle);
      }).toList();
    }
    items.sort((a, b) => b.date.compareTo(a.date));
    return items;
  }

  Future<ConstructionTotals> constructionTotals(DateRange range) async {
    final inRange = await constructionPurchases(range: range);
    final all = await constructionPurchases();
    return ConstructionTotals(
      spent: moneyFromDouble(inRange.fold(0, (sum, item) => sum + moneyToDouble(item.amount))),
      purchaseCount: inRange.length,
      byCategory: _namedTotals(inRange, (item) => item.categoryName ?? 'Other'),
      byMaterial: _materialSpend(inRange),
      bySupplier: _namedTotals(inRange, (item) {
        final supplier = item.supplier?.trim() ?? '';
        return supplier.isEmpty ? 'Unspecified' : supplier;
      }),
      recent: inRange.take(8).toList(),
      monthly: _monthlyTotals(inRange.isEmpty ? all : inRange),
      topMaterials: _namedTotals(inRange, (item) => item.materialName ?? 'Material').take(5).toList(),
      range: range,
    );
  }

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
      final mapped = idMap[row[remapField]?.toString()];
      if (mapped != null) {
        row[remapField] = mapped;
        await _db.upsert(remapCollection, row);
      }
    }
  }

  Future<ClinicTotals> clinicTotals(DateRange range) async {
    final income = _sum(await incomeHistory(range: range));
    final expenses = _sum(await clinicExpenseHistory(range: range));
    return ClinicTotals(
      income: moneyFromDouble(income),
      expenses: moneyFromDouble(expenses),
      profit: moneyFromDouble(income - expenses),
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

  Future<List<PatientRecord>> patients({String? search}) async {
    final rows = await _db.list('patients');
    var items = rows.map(PatientRecord.fromJson).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
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

  Future<PatientRecord> savePatient({required String name, String? phone}) async {
    final id = await createCatalog(
      path: '/api/v1/patients',
      collection: 'patients',
      entityType: 'patient',
      body: {
        'name': name,
        if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
      },
    );
    _serverCatalogIds.add(id);
    try {
      final response = await _api.get('/api/v1/patients/$id');
      final remote = _asMap(response.data);
      if (remote != null) {
        await _db.upsert('patients', remote);
        return PatientRecord.fromJson(remote);
      }
    } catch (_) {}
    final row = await _db.get('patients', id) ?? {'id': id, 'name': name, 'phone': phone};
    return PatientRecord.fromJson(row);
  }

  Future<PatientRecord> updatePatient(PatientRecord patient, {String? name, String? phone}) async {
    final patch = {
      if (name != null) 'name': name,
      'phone': phone,
    };
    await updateCatalog(
      path: '/api/v1/patients/${patient.id}',
      collection: 'patients',
      entityType: 'patient',
      id: patient.id,
      version: patient.version,
      patch: patch,
    );
    final row = await _db.get('patients', patient.id) ?? {...patient.toJson(), ...patch};
    return PatientRecord.fromJson(row);
  }

  Future<List<MoneyEntry>> incomeHistory({DateRange? range, String? search}) async {
    return _filterEntries(await _db.list('treatment_transactions'), range: range, search: search);
  }

  Future<MoneyEntry?> treatmentById(String id) async {
    try {
      final response = await _api.get('/api/v1/treatment-transactions/$id');
      final row = _asMap(response.data);
      if (row != null) {
        final named = (await _namedTransactions([row])).first;
        await _db.upsert('treatment_transactions', named);
        return MoneyEntry.fromJson(named);
      }
    } catch (_) {}
    final local = await _db.get('treatment_transactions', id);
    return local == null ? null : MoneyEntry.fromJson(local);
  }

  Future<List<int>> treatmentAttachmentBytes(String transactionId, String attachmentId) async {
    final response = await _api.getBytes('/api/v1/treatment-transactions/$transactionId/attachments/$attachmentId/file');
    return response.data ?? <int>[];
  }

  Future<ResponseBytes> exportTreatment(String id) async {
    final response = await _api.getBytes('/api/v1/treatment-transactions/$id/export');
    return ResponseBytes(
      bytes: response.data ?? <int>[],
      filename: 'treatment-record.pdf',
      mime: 'application/pdf',
    );
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
    List<({List<int> bytes, String filename, String label})> xrays = const [],
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
      saved['patient_name'] = saved['patient_name'] ?? patientName;
      saved['patient_phone'] = saved['patient_phone'] ?? patientPhone;
      for (final xray in xrays) {
        final form = FormData.fromMap({
          'label': xray.label,
          'file': MultipartFile.fromBytes(xray.bytes, filename: xray.filename),
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
        }
      }
      await _db.upsert('treatment_transactions', saved);
      return 'Treatment saved.';
    } on OfflineException {
      payload['catalog_name'] = names[resolvedTreatmentId] ?? names[treatmentId] ?? 'Treatment';
      payload['patient_name'] = patientName;
      payload['patient_phone'] = patientPhone;
      payload['version'] = 1;
      await _db.upsert('treatment_transactions', payload);
      await _db.enqueueChange(
        clientChangeId: _uuid.v4(),
        entityType: 'treatment_transaction',
        entityId: payload['id'].toString(),
        operation: 'create',
        payload: payload,
      );
      return xrays.isEmpty
          ? 'Saved on this device and waiting to sync.'
          : 'Treatment saved on this device. Add X-rays again when you are online.';
    }
  }

  Future<List<MoneyEntry>> clinicExpenseHistory({DateRange? range, String? search}) async {
    return _filterEntries(await _db.list('clinic_expenses'), range: range, search: search);
  }

  Future<List<MoneyEntry>> homeExpenseHistory({DateRange? range, String? search}) async {
    return _filterEntries(await _db.list('home_expenses'), range: range, search: search);
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
      return 'Saved on this device and waiting to sync.';
    }
  }

  Future<void> deleteEntry({
    required String collection,
    required String path,
    required String entityType,
    required MoneyEntry entry,
  }) async {
    await _db.markDeleted(collection, entry.id);
    try {
      await _api.delete(path, query: {'version': entry.version});
    } on OfflineException {
      await _db.enqueueChange(
        clientChangeId: _uuid.v4(),
        entityType: entityType,
        entityId: entry.id,
        operation: 'delete',
        payload: {'version': entry.version},
        baseVersion: entry.version,
      );
    }
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

  Future<String> saveConstructionPurchases({
    required String date,
    required List<
        ({
          String materialId,
          String quantity,
          String unit,
          String unitPrice,
          String? supplier,
          String? notes,
        })> rows,
  }) async {
    final resolved = <String, String>{};
    for (final row in rows) {
      resolved[row.materialId] = await _resolveConstructionMaterialId(row.materialId);
    }
    final materials = {for (final item in await constructionMaterials()) item.id: item};
    final items = [
      for (final row in rows)
        {
          'id': _uuid.v4(),
          'material_id': resolved[row.materialId] ?? row.materialId,
          'purchase_date': date,
          'quantity': row.quantity,
          'unit': row.unit,
          'unit_price': row.unitPrice,
          'supplier': row.supplier,
          'notes': row.notes,
          'amount': moneyFromDouble(moneyToDouble(row.quantity) * moneyToDouble(row.unitPrice)),
          'material_name': materials[resolved[row.materialId] ?? row.materialId]?.name ?? materials[row.materialId]?.name ?? 'Material',
          'category_name':
              materials[resolved[row.materialId] ?? row.materialId]?.categoryName ?? materials[row.materialId]?.categoryName,
        },
    ];
    try {
      final response = await _api.post(
        '/api/v1/construction-purchases/batch',
        data: {
          'items': [
            for (final row in items)
              {
                'id': row['id'],
                'material_id': row['material_id'],
                'purchase_date': row['purchase_date'],
                'quantity': row['quantity'],
                'unit': row['unit'],
                'unit_price': row['unit_price'],
                'supplier': row['supplier'],
                'notes': row['notes'],
              },
          ],
        },
      );
      final saved = await _decorateConstructionPurchases(_asMaps(response.data, items));
      for (final row in saved) {
        await _db.upsert('construction_purchases', row);
      }
      return 'Saved and synced.';
    } on OfflineException {
      for (final row in items) {
        await _db.upsert('construction_purchases', {...row, 'version': 1});
        await _db.enqueueChange(
          clientChangeId: _uuid.v4(),
          entityType: 'construction_purchase',
          entityId: row['id'].toString(),
          operation: 'create',
          payload: {
            'id': row['id'],
            'material_id': row['material_id'],
            'purchase_date': row['purchase_date'],
            'quantity': row['quantity'],
            'unit': row['unit'],
            'unit_price': row['unit_price'],
            'supplier': row['supplier'],
            'notes': row['notes'],
          },
        );
      }
      return 'Saved on this device and waiting to sync.';
    }
  }

  Future<String> updateConstructionPurchase({
    required ConstructionPurchase entry,
    required Map<String, dynamic> patch,
  }) async {
    final body = {'version': entry.version, ...patch};
    try {
      final response = await _api.patch('/api/v1/construction-purchases/${entry.id}', data: body);
      final saved = (await _decorateConstructionPurchases([_asMap(response.data) ?? {...entry.toJson(), ...patch}])).first;
      await _db.upsert('construction_purchases', saved);
      return 'Updated.';
    } on OfflineException {
      final quantity = moneyToDouble((patch['quantity'] ?? entry.quantity).toString());
      final unitPrice = moneyToDouble((patch['unit_price'] ?? entry.unitPrice).toString());
      final local = {
        ...entry.toJson(),
        ...patch,
        'amount': moneyFromDouble(quantity * unitPrice),
        'version': entry.version + 1,
      };
      await _db.upsert('construction_purchases', (await _decorateConstructionPurchases([local])).first);
      await _db.enqueueChange(
        clientChangeId: _uuid.v4(),
        entityType: 'construction_purchase',
        entityId: entry.id,
        operation: 'update',
        payload: patch,
        baseVersion: entry.version,
      );
      return 'Saved on this device and waiting to sync.';
    }
  }

  Future<void> deleteConstructionPurchase(ConstructionPurchase entry) async {
    await _db.markDeleted('construction_purchases', entry.id);
    try {
      await _api.delete('/api/v1/construction-purchases/${entry.id}', query: {'version': entry.version});
    } on OfflineException {
      await _db.enqueueChange(
        clientChangeId: _uuid.v4(),
        entityType: 'construction_purchase',
        entityId: entry.id,
        operation: 'delete',
        payload: {'version': entry.version},
        baseVersion: entry.version,
      );
    }
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
        return;
      } on AppException catch (error) {
        if (!_isMissingRoute(error)) {
          rethrow;
        }
      }
      await _saveBudgetByPeriod(year: year, month: month, amount: amount);
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
    await _db.markDeleted(collection, id);
    try {
      await _api.delete(path, query: {'version': version});
    } on OfflineException {
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

  Future<ResponseBytes> exportConstruction({required DateRange range, required String format}) {
    return _export('/api/v1/reports/construction/export', range, format);
  }

  Future<void> pushPending() async {
    final pending = await _db.pendingChanges();
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
    final treatments = await _allPages('/api/v1/treatments', extra: {'page_size': 100});
    final treatmentCats = await _allPages('/api/v1/treatment-categories', extra: {'page_size': 100});
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
    final clinicCats = await _allPages('/api/v1/clinic-expense-categories', extra: {'page_size': 100});
    final homeCats = await _allPages('/api/v1/home-expense-categories', extra: {'page_size': 100});
    final patients = await _allPages('/api/v1/patients', extra: {'page_size': 100, 'sort': 'name'});
    await _db.upsertAll('treatment_categories', treatmentCats);
    await _db.upsertAll('clinic_expense_categories', clinicCats);
    await _db.upsertAll('home_expense_categories', homeCats);
    await _db.upsertAll('patients', patients);
    await _db.upsertAll(
      'treatment_transactions',
      await _namedTransactions(await _allPages('/api/v1/treatment-transactions', extra: {'page_size': 100, 'sort': '-transaction_date'})),
    );
    await _db.upsertAll(
      'clinic_expenses',
      await _namedExpenses(
        await _allPages('/api/v1/clinic-expenses', extra: {'page_size': 100, 'sort': '-expense_date'}),
        'clinic_expense_categories',
      ),
    );
    await _db.upsertAll(
      'home_expenses',
      await _namedExpenses(
        await _allPages('/api/v1/home-expenses', extra: {'page_size': 100, 'sort': '-expense_date'}),
        'home_expense_categories',
      ),
    );
    final budgets = await _allPages('/api/v1/home-budgets', extra: {'page_size': 100});
    await _db.upsertAll('home_budgets', budgets);
    await _hydrateConstruction();
    _serverCatalogIds
      ..addAll(treatments.map((item) => item['id'].toString()))
      ..addAll(treatmentCats.map((item) => item['id'].toString()))
      ..addAll(clinicCats.map((item) => item['id'].toString()))
      ..addAll(homeCats.map((item) => item['id'].toString()))
      ..addAll(patients.map((item) => item['id'].toString()))
      ..addAll(budgets.map((item) => item['id'].toString()));
    await _pruneDuplicateMonthBudgets();
  }

  Future<void> _hydrateConstruction() async {
    final categories = await _allPages('/api/v1/construction-material-categories', extra: {'page_size': 100});
    final materials = await _allPages('/api/v1/construction-materials', extra: {'page_size': 100});
    await _db.upsertAll('construction_material_categories', categories);
    await _db.upsertAll('construction_materials', materials);
    _serverCatalogIds
      ..addAll(categories.map((item) => item['id'].toString()))
      ..addAll(materials.map((item) => item['id'].toString()));
    await _db.upsertAll(
      'construction_purchases',
      await _decorateConstructionPurchases(
        await _allPages('/api/v1/construction-purchases', extra: {'page_size': 100}),
      ),
    );
  }

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
    await _decorateConstructionLocal();
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

  Future<void> _decorateConstructionLocal() async {
    final decorated = await _decorateConstructionPurchases(await _db.list('construction_purchases'));
    for (final row in decorated) {
      await _db.upsert('construction_purchases', row);
    }
    final categoryNames = {for (final item in await constructionMaterialCategories()) item.id: item.name};
    for (final row in await _db.list('construction_materials')) {
      row['category_name'] = categoryNames[row['category_id']?.toString()] ?? row['category_name'];
      await _db.upsert('construction_materials', row);
    }
  }

  Future<List<Map<String, dynamic>>> _decorateConstructionPurchases(List<Map<String, dynamic>> rows) async {
    final materials = {for (final item in await constructionMaterials()) item.id: item};
    final categories = {for (final item in await constructionMaterialCategories()) item.id: item.name};
    return [
      for (final row in rows)
        {
          ...row,
          'material_name': materials[row['material_id']?.toString()]?.name ?? row['material_name'] ?? 'Material',
          'category_name':
              materials[row['material_id']?.toString()]?.categoryName ??
              categories[materials[row['material_id']?.toString()]?.categoryId] ??
              row['category_name'],
        },
    ];
  }

  Future<List<Map<String, dynamic>>> _namedTransactions(List<Map<String, dynamic>> rows) async {
    final names = {for (final item in await treatments()) item.id: item.name};
    return [
      for (final row in rows) {...row, 'catalog_name': names[row['treatment_id'].toString()] ?? 'Treatment'},
    ];
  }

  Future<List<Map<String, dynamic>>> _namedExpenses(List<Map<String, dynamic>> rows, String collection) async {
    final names = {for (final item in await _categories(collection)) item.id: item.name};
    return [
      for (final row in rows) {...row, 'catalog_name': names[row['category_id'].toString()] ?? 'Category'},
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
    entries.sort((a, b) => b.date.compareTo(a.date));
    return entries;
  }

  double _sum(List<MoneyEntry> entries) => entries.fold(0, (sum, entry) => sum + moneyToDouble(entry.amount));

  List<NamedAmount> _materialSpend(List<ConstructionPurchase> items) {
    final quantities = <String, double>{};
    final amounts = <String, double>{};
    final units = <String, String>{};
    for (final item in items) {
      final name = item.materialName ?? 'Material';
      quantities[name] = (quantities[name] ?? 0) + moneyToDouble(item.quantity);
      amounts[name] = (amounts[name] ?? 0) + moneyToDouble(item.amount);
      units[name] = item.unit;
    }
    final ranked = amounts.entries.map((entry) {
      final qty = formatQuantity(moneyFromDouble(quantities[entry.key] ?? 0));
      return NamedAmount(
        name: '$qty ${units[entry.key]} · ${entry.key}',
        amount: moneyFromDouble(entry.value),
      );
    }).toList()
      ..sort((a, b) => moneyToDouble(b.amount).compareTo(moneyToDouble(a.amount)));
    return ranked;
  }

  List<NamedAmount> _namedTotals(List<ConstructionPurchase> items, String Function(ConstructionPurchase item) nameOf) {
    final totals = <String, double>{};
    for (final item in items) {
      final name = nameOf(item);
      totals[name] = (totals[name] ?? 0) + moneyToDouble(item.amount);
    }
    final ranked = totals.entries.map((entry) => NamedAmount(name: entry.key, amount: moneyFromDouble(entry.value))).toList()
      ..sort((a, b) => moneyToDouble(b.amount).compareTo(moneyToDouble(a.amount)));
    return ranked;
  }

  List<NamedAmount> _monthlyTotals(List<ConstructionPurchase> items) {
    final totals = <String, double>{};
    for (final item in items) {
      final month = item.date.length >= 7 ? item.date.substring(0, 7) : item.date;
      totals[month] = (totals[month] ?? 0) + moneyToDouble(item.amount);
    }
    final ranked = totals.entries.map((entry) => NamedAmount(name: entry.key, amount: moneyFromDouble(entry.value))).toList()
      ..sort((a, b) => b.name.compareTo(a.name));
    return ranked.take(6).toList();
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
    return _saveBatch(
      path: path,
      collection: collection,
      entityType: entityType,
      items: items,
      names: {},
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
        row['catalog_name'] = lookup[row['treatment_id']?.toString() ?? row['category_id']?.toString()] ?? 'Item';
        await _db.upsert(collection, row);
      }
      return 'Saved and synced.';
    } on OfflineException {
      for (final row in items) {
        row['catalog_name'] = lookup[row['treatment_id']?.toString() ?? row['category_id']?.toString()] ?? 'Item';
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
  );
});
