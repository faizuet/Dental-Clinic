import 'package:flutter_test/flutter_test.dart';
import 'package:nabi_dental_app/core/models/finance_models.dart';
import 'package:nabi_dental_app/core/utils/period.dart';

void main() {
  test('catalog and money entries parse API json', () {
    final item = CatalogItem.fromJson({
      'id': 't1',
      'name': 'RCT',
      'category_id': 'c1',
      'category_name': 'Endodontics',
      'default_price': '5000.00',
    });
    expect(item.categoryName, 'Endodontics');
    expect(item.defaultPrice, '5000.00');

    final entry = MoneyEntry.fromJson({
      'id': 'x1',
      'treatment_id': 't1',
      'catalog_name': 'RCT',
      'transaction_date': '2026-09-19',
      'amount': '5000.00',
      'quantity': 2,
    });
    expect(entry.catalogId, 't1');
    expect(entry.quantity, 2);
  });

  test('catalog and money entries accept mixed json types', () {
    final item = CatalogItem.fromJson({
      'id': 12,
      'name': 'Groceries',
      'version': '3',
    });
    expect(item.id, '12');
    expect(item.version, 3);

    final entry = MoneyEntry.fromJson({
      'id': 9,
      'category_id': 4,
      'expense_date': '2026-09-23',
      'amount': 300000,
      'quantity': '1',
      'notes': 0,
      'version': 1.0,
    });
    expect(entry.catalogId, '4');
    expect(entry.amount, '300000');
    expect(entry.quantity, 1);
    expect(entry.notes, '0');
    expect(entry.version, 1);
  });

  test('construction purchase parses quantity and money strings', () {
    final purchase = ConstructionPurchase.fromJson({
      'id': 21,
      'material_id': 8,
      'purchase_date': '2026-09-24',
      'quantity': 10,
      'unit': 'bag',
      'unit_price': 1450,
      'amount': 14500,
      'material_name': 'Cement',
      'category_name': 'Structure',
      'supplier': 'Local kiln',
      'notes': 0,
      'version': '2',
    });
    expect(purchase.materialId, '8');
    expect(purchase.quantity, '10');
    expect(purchase.unitPrice, '1450');
    expect(purchase.amount, '14500');
    expect(purchase.supplier, 'Local kiln');
    expect(purchase.notes, '0');
    expect(purchase.version, 2);
  });

  test('custom range includes both ends', () {
    final range = DateRange.forPeriod(
      FinancePeriod.custom,
      customFrom: DateTime(2026, 9, 1),
      customTo: DateTime(2026, 9, 19),
    );
    expect(range.containsIso('2026-09-01'), isTrue);
    expect(range.containsIso('2026-09-19'), isTrue);
    expect(range.containsIso('2026-09-20'), isFalse);
  });
}
