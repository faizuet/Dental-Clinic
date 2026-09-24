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

class CatalogItem {
  const CatalogItem({
    required this.id,
    required this.name,
    this.categoryId,
    this.categoryName,
    this.defaultPrice,
    this.isActive = true,
    this.version = 1,
  });

  final String id;
  final String name;
  final String? categoryId;
  final String? categoryName;
  final String? defaultPrice;
  final bool isActive;
  final int version;

  factory CatalogItem.fromJson(Map<String, dynamic> json, {String? categoryName}) {
    return CatalogItem(
      id: json['id'].toString(),
      name: json['name'].toString(),
      categoryId: json['category_id']?.toString(),
      categoryName: categoryName ?? json['category_name']?.toString(),
      defaultPrice: json['default_price']?.toString(),
      isActive: json['is_active'] != false,
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
        'version': version,
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
  });

  final String id;
  final String catalogId;
  final String catalogName;
  final String date;
  final String amount;
  final int quantity;
  final String? notes;
  final int version;

  factory MoneyEntry.fromJson(Map<String, dynamic> json) {
    return MoneyEntry(
      id: json['id'].toString(),
      catalogId: (json['treatment_id'] ?? json['category_id']).toString(),
      catalogName: (json['catalog_name'] ?? json['treatment_name'] ?? json['category_name'] ?? 'Item').toString(),
      date: (json['transaction_date'] ?? json['expense_date']).toString(),
      amount: json['amount'].toString(),
      quantity: jsonInt(json['quantity'], fallback: 1),
      notes: jsonText(json['notes']),
      version: jsonInt(json['version'], fallback: 1),
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
      };
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

class ConstructionMaterial {
  const ConstructionMaterial({
    required this.id,
    required this.categoryId,
    required this.name,
    required this.unit,
    this.categoryName,
    this.displayOrder = 0,
    this.isActive = true,
    this.version = 1,
    this.localSeed = false,
  });

  final String id;
  final String categoryId;
  final String name;
  final String unit;
  final String? categoryName;
  final int displayOrder;
  final bool isActive;
  final int version;
  final bool localSeed;

  factory ConstructionMaterial.fromJson(Map<String, dynamic> json) {
    return ConstructionMaterial(
      id: json['id'].toString(),
      categoryId: json['category_id'].toString(),
      name: json['name']?.toString() ?? '',
      unit: json['unit']?.toString() ?? 'piece',
      categoryName: jsonText(json['category_name']),
      displayOrder: jsonInt(json['display_order']),
      isActive: json['is_active'] != false,
      version: jsonInt(json['version'], fallback: 1),
      localSeed: json['local_seed'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'category_id': categoryId,
        'name': name,
        'unit': unit,
        'category_name': categoryName,
        'display_order': displayOrder,
        'is_active': isActive,
        'version': version,
      };
}

class ConstructionPurchase {
  const ConstructionPurchase({
    required this.id,
    required this.materialId,
    required this.date,
    required this.quantity,
    required this.unit,
    required this.unitPrice,
    required this.amount,
    this.materialName,
    this.categoryName,
    this.supplier,
    this.notes,
    this.version = 1,
  });

  final String id;
  final String materialId;
  final String date;
  final String quantity;
  final String unit;
  final String unitPrice;
  final String amount;
  final String? materialName;
  final String? categoryName;
  final String? supplier;
  final String? notes;
  final int version;

  factory ConstructionPurchase.fromJson(Map<String, dynamic> json) {
    return ConstructionPurchase(
      id: json['id'].toString(),
      materialId: json['material_id'].toString(),
      date: json['purchase_date']?.toString() ?? json['date']?.toString() ?? '',
      quantity: json['quantity']?.toString() ?? '0',
      unit: json['unit']?.toString() ?? '',
      unitPrice: json['unit_price']?.toString() ?? '0',
      amount: json['amount']?.toString() ?? '0',
      materialName: jsonText(json['material_name']),
      categoryName: jsonText(json['category_name']),
      supplier: jsonText(json['supplier']),
      notes: jsonText(json['notes']),
      version: jsonInt(json['version'], fallback: 1),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'material_id': materialId,
        'purchase_date': date,
        'quantity': quantity,
        'unit': unit,
        'unit_price': unitPrice,
        'amount': amount,
        'material_name': materialName,
        'category_name': categoryName,
        'supplier': supplier,
        'notes': notes,
        'version': version,
      };
}
