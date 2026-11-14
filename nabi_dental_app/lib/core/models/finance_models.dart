int jsonInt(Object? value, {int fallback = 0}) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

String? jsonText(Object? value) {
  if (value == null) {
    return null;
  }
  final text = value.toString().trim();
  if (text.isEmpty || text == 'null') {
    return null;
  }
  return text;
}

const _placeholderCatalogNames = {'item', 'category'};

String? usefulCatalogName(Object? value) {
  final text = jsonText(value);
  if (text == null || _placeholderCatalogNames.contains(text.toLowerCase())) {
    return null;
  }
  return text;
}

String _catalogName(Map<String, dynamic> json) {
  final stored = usefulCatalogName(json['catalog_name']) ?? usefulCatalogName(json['treatment_name']);
  final category = usefulCatalogName(json['category_name']);
  final isExpense = json['expense_date'] != null && json['treatment_id'] == null;
  if (isExpense && stored == null && category != null) {
    return category;
  }
  return stored ?? category ?? jsonText(json['catalog_name']) ?? 'Item';
}

class CatalogItem {
  const CatalogItem({
    required this.id,
    required this.name,
    this.categoryId,
    this.categoryName,
    this.defaultPrice,
    this.isActive = true,
    this.displayOrder = 0,
    this.version = 1,
  });

  final String id;
  final String name;
  final String? categoryId;
  final String? categoryName;
  final String? defaultPrice;
  final bool isActive;
  final int displayOrder;
  final int version;

  factory CatalogItem.fromJson(Map<String, dynamic> json, {String? categoryName}) {
    return CatalogItem(
      id: json['id'].toString(),
      name: json['name'].toString(),
      categoryId: json['category_id']?.toString(),
      categoryName: categoryName ?? json['category_name']?.toString(),
      defaultPrice: json['default_price']?.toString(),
      isActive: json['is_active'] != false,
      displayOrder: jsonInt(json['display_order']),
      version: jsonInt(json['version'], fallback: 1),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'category_id': categoryId,
        'category_name': categoryName,
        'default_price': defaultPrice,
        'is_active': isActive,
        'display_order': displayOrder,
        'version': version,
      };
}

CatalogItem? findCatalogMatch(
  List<CatalogItem> catalog, {
  String? id,
  String? name,
}) {
  if (id != null && id.isNotEmpty) {
    for (final item in catalog) {
      if (item.id == id) {
        return item;
      }
    }
  }
  final needle = name?.trim().toLowerCase();
  if (needle != null && needle.isNotEmpty) {
    for (final item in catalog) {
      if (item.name.trim().toLowerCase() == needle) {
        return item;
      }
    }
  }
  return null;
}

List<CatalogItem> uniqueCatalogById(List<CatalogItem> items, {CatalogItem? selected}) {
  final unique = <String, CatalogItem>{};
  for (final item in items) {
    unique[item.id] = item;
  }
  if (selected != null) {
    unique.putIfAbsent(selected.id, () => selected);
  }
  return unique.values.toList();
}

Map<String, dynamic> jsonMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  return {};
}

List<Map<String, dynamic>> jsonMapList(Object? value) {
  if (value is! List) {
    return const [];
  }
  return [
    for (final item in value)
      if (item is Map) Map<String, dynamic>.from(item),
  ];
}

class PatientRecord {
  const PatientRecord({
    required this.id,
    required this.name,
    this.phone,
    this.notes,
    this.version = 1,
    this.createdAt,
  });

  final String id;
  final String name;
  final String? phone;
  final String? notes;
  final int version;
  final String? createdAt;

  factory PatientRecord.fromJson(Map<String, dynamic> json) {
    return PatientRecord(
      id: json['id'].toString(),
      name: json['name']?.toString().trim().isNotEmpty == true ? json['name'].toString().trim() : 'Patient',
      phone: jsonText(json['phone']),
      notes: jsonText(json['notes']),
      version: jsonInt(json['version'], fallback: 1),
      createdAt: jsonText(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'phone': phone,
        'notes': notes,
        'version': version,
        'created_at': createdAt,
      };
}

String? duplicatePatientPhoneWarning({
  required List<PatientRecord> patients,
  required String? phone,
  String? excludeId,
}) {
  final trimmed = phone?.trim() ?? '';
  if (trimmed.length != 11) {
    return null;
  }
  for (final item in patients) {
    if (excludeId != null && item.id == excludeId) {
      continue;
    }
    if ((item.phone ?? '') == trimmed) {
      return 'This mobile number is already used by ${item.name}. Open that patient instead of adding another.';
    }
  }
  return null;
}

class RecentClinicPatient {
  const RecentClinicPatient({
    required this.patient,
    this.lastVisitDate,
    this.lastTreatment,
  });

  final PatientRecord patient;
  final String? lastVisitDate;
  final String? lastTreatment;
}

enum ClinicActivityKind { treatment, expense, labCharge }

class ClinicActivity {
  const ClinicActivity({required this.kind, required this.title, required this.date, required this.amount});

  final ClinicActivityKind kind;
  final String title;
  final String date;
  final String amount;
}

class TreatmentAttachment {
  const TreatmentAttachment({
    required this.id,
    required this.transactionId,
    this.label = 'other',
    this.originalName,
    this.byteSize = 0,
  });

  final String id;
  final String transactionId;
  final String label;
  final String? originalName;
  final int byteSize;

  factory TreatmentAttachment.fromJson(Map<String, dynamic> json) {
    return TreatmentAttachment(
      id: json['id'].toString(),
      transactionId: json['transaction_id'].toString(),
      label: jsonText(json['label']) ?? 'other',
      originalName: jsonText(json['original_name']),
      byteSize: jsonInt(json['byte_size']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'transaction_id': transactionId,
        'label': label,
        'original_name': originalName,
        'byte_size': byteSize,
      };
}

class MoneyEntry {
  const MoneyEntry({
    required this.id,
    required this.catalogId,
    required this.catalogName,
    required this.date,
    required this.amount,
    this.quantity = 1,
    this.notes,
    this.version = 1,
    this.patientId,
    this.patientName,
    this.patientPhone,
    this.serialNo,
    this.subTreatment,
    this.categoryName,
    this.details = const {},
    this.detailsText,
    this.attachments = const [],
    this.createdAt,
  });

  final String id;
  final String catalogId;
  final String catalogName;
  final String date;
  final String amount;
  final int quantity;
  final String? notes;
  final int version;
  final String? patientId;
  final String? patientName;
  final String? patientPhone;
  final int? serialNo;
  final String? subTreatment;
  final String? categoryName;
  final Map<String, dynamic> details;
  final String? detailsText;
  final List<TreatmentAttachment> attachments;
  final String? createdAt;

  String get displayPatientName {
    final name = patientName?.trim();
    if (name == null || name.isEmpty) {
      return 'Walk-in';
    }
    return name;
  }

  factory MoneyEntry.fromJson(Map<String, dynamic> json) {
    return MoneyEntry(
      id: json['id'].toString(),
      catalogId: (json['treatment_id'] ?? json['category_id']).toString(),
      catalogName: _catalogName(json),
      date: (json['transaction_date'] ?? json['expense_date']).toString(),
      amount: json['amount'].toString(),
      quantity: jsonInt(json['quantity'], fallback: 1),
      notes: jsonText(json['notes']),
      version: jsonInt(json['version'], fallback: 1),
      patientId: jsonText(json['patient_id']),
      patientName: jsonText(json['patient_name']),
      patientPhone: jsonText(json['patient_phone']),
      serialNo: json['serial_no'] == null ? null : jsonInt(json['serial_no']),
      subTreatment: jsonText(json['sub_treatment']),
      categoryName: jsonText(json['category_name']),
      details: jsonMap(json['details']),
      detailsText: jsonText(json['details_text']),
      attachments: [
        for (final item in jsonMapList(json['attachments'])) TreatmentAttachment.fromJson(item),
      ],
      createdAt: jsonText(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'treatment_id': catalogId,
        'category_id': catalogId,
        'catalog_name': catalogName,
        'transaction_date': date,
        'expense_date': date,
        'amount': amount,
        'quantity': quantity,
        'notes': notes,
        'version': version,
        'patient_id': patientId,
        'patient_name': patientName,
        'patient_phone': patientPhone,
        'serial_no': serialNo,
        'sub_treatment': subTreatment,
        'category_name': categoryName,
        'details': details,
        'details_text': detailsText,
        'attachments': [for (final item in attachments) item.toJson()],
        'created_at': createdAt,
      };
}

const labChargeCategoryNames = {'lab charges', 'lab charge', 'lab'};

bool isLabChargeCategoryName(String? name) => labChargeCategoryNames.contains((name ?? '').trim().toLowerCase());

class LabCharge {
  const LabCharge({
    required this.id,
    required this.date,
    required this.amount,
    this.patientId,
    this.transactionId,
    this.labName,
    this.notes,
    this.version = 1,
    this.patientName,
    this.patientPhone,
    this.visitLabel,
    this.createdAt,
  });

  final String id;
  final String date;
  final String amount;
  final String? patientId;
  final String? transactionId;
  final String? labName;
  final String? notes;
  final int version;
  final String? patientName;
  final String? patientPhone;
  final String? visitLabel;
  final String? createdAt;

  String get displayLab => labName ?? 'Lab charge';

  factory LabCharge.fromJson(Map<String, dynamic> json) {
    final raw = (json['charge_date'] ?? '').toString();
    return LabCharge(
      id: json['id'].toString(),
      date: raw.length >= 10 ? raw.substring(0, 10) : raw,
      amount: json['amount'].toString(),
      patientId: jsonText(json['patient_id']),
      transactionId: jsonText(json['transaction_id']),
      labName: jsonText(json['lab_name']),
      notes: jsonText(json['notes']),
      version: jsonInt(json['version'], fallback: 1),
      patientName: jsonText(json['patient_name']),
      patientPhone: jsonText(json['patient_phone']),
      visitLabel: jsonText(json['visit_label']),
      createdAt: jsonText(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'charge_date': date,
        'amount': amount,
        'patient_id': patientId,
        'transaction_id': transactionId,
        'lab_name': labName,
        'notes': notes,
        'version': version,
        'created_at': createdAt,
      };

  MoneyEntry toEntry() => MoneyEntry(
        id: id,
        catalogId: transactionId ?? '',
        catalogName: displayLab,
        date: date,
        amount: amount,
        notes: notes,
        version: version,
        patientId: patientId,
        patientName: patientName ?? 'No patient linked',
        patientPhone: patientPhone,
        subTreatment: visitLabel,
        createdAt: createdAt,
        detailsText: visitLabel == null ? null : 'Visit $visitLabel',
      );
}

class HomeBudget {
  const HomeBudget({
    required this.id,
    required this.year,
    required this.month,
    required this.amount,
    this.version = 1,
  });

  final String id;
  final int year;
  final int month;
  final String amount;
  final int version;

  factory HomeBudget.fromJson(Map<String, dynamic> json) {
    return HomeBudget(
      id: json['id'].toString(),
      year: jsonInt(json['year']),
      month: jsonInt(json['month']),
      amount: json['amount'].toString(),
      version: jsonInt(json['version'], fallback: 1),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'year': year,
        'month': month,
        'amount': amount,
        'version': version,
      };
}

class NamedAmount {
  const NamedAmount({required this.name, required this.amount});
  final String name;
  final String amount;
}
