import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/theme/app_colors.dart';
import '../../core/errors/friendly_error.dart';
import '../../core/finance/finance_repository.dart';
import '../../core/models/finance_models.dart';
import '../../core/utils/dates.dart';
import '../../core/utils/money.dart';
import '../../core/widgets/app_controls.dart';
import '../../core/widgets/app_layout.dart';
import '../../core/widgets/app_motion.dart';
import '../../core/widgets/app_navigation.dart';
import '../../core/widgets/app_page.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/error_banner.dart';
import '../../core/widgets/summary_card.dart';
import 'construction_material_picker.dart';

class ConstructionPurchaseScreen extends ConsumerStatefulWidget {
  const ConstructionPurchaseScreen({super.key});

  @override
  ConsumerState<ConstructionPurchaseScreen> createState() => _ConstructionPurchaseScreenState();
}

class _Row {
  String? materialId;
  final quantity = TextEditingController();
  final unitPrice = TextEditingController();
  final unit = TextEditingController();
  final supplier = TextEditingController();
  final notes = TextEditingController();

  void dispose() {
    quantity.dispose();
    unitPrice.dispose();
    unit.dispose();
    supplier.dispose();
    notes.dispose();
  }
}

class _ConstructionPurchaseScreenState extends ConsumerState<ConstructionPurchaseScreen> {
  DateTime _date = DateTime.now();
  final _rows = [_Row()];
  List<ConstructionMaterial> _materials = [];
  bool _busy = false;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final repo = ref.read(financeRepositoryProvider);
    try {
      try {
        await repo.refresh();
      } catch (_) {}
      await repo.ensureConstructionCatalog();
      final items = await repo.constructionMaterials();
      if (mounted) {
        setState(() {
          _materials = items;
          _loading = false;
          if (items.isEmpty) {
            _error = 'Could not load construction materials. Tap retry, or add one manually.';
          }
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = friendlyError(error);
          _loading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  double get _total {
    var sum = 0.0;
    for (final row in _rows) {
      if (row.materialId != null && isValidQuantity(row.quantity.text) && isValidMoney(row.unitPrice.text)) {
        sum += moneyToDouble(row.quantity.text) * moneyToDouble(row.unitPrice.text);
      }
    }
    return sum;
  }

  bool get _canSave => _rows.any(
        (row) => row.materialId != null && isValidQuantity(row.quantity.text) && isValidMoney(row.unitPrice.text),
      );

  ConstructionMaterial? _materialOf(String? id) {
    if (id == null) {
      return null;
    }
    for (final item in _materials) {
      if (item.id == id) {
        return item;
      }
    }
    return null;
  }

  Future<void> _save() async {
    final payload = <({
      String materialId,
      String quantity,
      String unit,
      String unitPrice,
      String? supplier,
      String? notes,
    })>[];
    for (final row in _rows) {
      if (row.materialId == null || row.quantity.text.trim().isEmpty || row.unitPrice.text.trim().isEmpty) {
        continue;
      }
      if (!isValidQuantity(row.quantity.text) || !isValidMoney(row.unitPrice.text)) {
        setState(() => _error = 'Enter a quantity and unit price greater than 0.');
        return;
      }
      final material = _materialOf(row.materialId);
      payload.add((
        materialId: row.materialId!,
        quantity: formatQuantity(row.quantity.text),
        unit: row.unit.text.trim().isEmpty ? (material?.unit ?? 'piece') : row.unit.text.trim(),
        unitPrice: moneyFromDouble(moneyToDouble(row.unitPrice.text)),
        supplier: row.supplier.text.trim().isEmpty ? null : row.supplier.text.trim(),
        notes: row.notes.text.trim().isEmpty ? null : row.notes.text.trim(),
      ));
    }
    if (payload.isEmpty) {
      setState(() => _error = 'Add at least one material purchase.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final message = await ref.read(financeRepositoryProvider).saveConstructionPurchases(
            date: DateFormat('yyyy-MM-dd').format(_date),
            rows: payload,
          );
      if (mounted) {
        showAppSnack(context, message);
        appPop(context, fallback: '/construction');
      }
    } catch (error) {
      setState(() => _error = friendlyError(error));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  bool get _dirty => _rows.any(
        (row) =>
            row.materialId != null ||
            row.quantity.text.trim().isNotEmpty ||
            row.unitPrice.text.trim().isNotEmpty ||
            row.supplier.text.trim().isNotEmpty ||
            row.notes.text.trim().isNotEmpty,
      );

  @override
  Widget build(BuildContext context) {
    return AppDiscardScope(
      dirty: _dirty,
      fallback: '/construction',
      child: Scaffold(
        appBar: AppBar(
          leading: const AppBackButton(fallback: '/construction'),
          title: const AppBarTitle('Material purchase'),
        ),
        body: AppPageBody(
          padding: AppLayout.pagePadding(context, top: 8, bottom: 8),
          child: AppStateSwitch(
            child: _loading
              ? const LoadingView(key: ValueKey('purchase-loading'), message: 'Loading materials…')
              : ListView(
            key: const ValueKey('purchase-form'),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.only(bottom: AppLayout.pagePadding(context).bottom),
            children: [
              DatePickerTile(
                label: 'Purchase date',
                value: formatDisplayDate(_date),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _date,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 30)),
                  );
                  if (picked != null) {
                    setState(() => _date = picked);
                  }
                },
              ),
              if (_error != null) ...[
                ErrorBanner(message: _error!),
                TextButton(onPressed: _bootstrap, child: const Text('Retry')),
              ],
              const SizedBox(height: 8),
              AppExpand(
                child: Column(
                  children: [
              for (var i = 0; i < _rows.length; i++)
                Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ConstructionMaterialField(
                          materials: _materials,
                          selectedId: _rows[i].materialId,
                          onSelected: (material) {
                            setState(() {
                              _rows[i].materialId = material.id;
                              _rows[i].unit.text = material.unit;
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _rows[i].quantity,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                textInputAction: TextInputAction.next,
                                decoration: InputDecoration(
                                  labelText: 'Quantity',
                                  suffixText: _rows[i].unit.text.trim().isEmpty ? null : _rows[i].unit.text.trim(),
                                ),
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: _rows[i].unitPrice,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                textInputAction: TextInputAction.next,
                                decoration: const InputDecoration(labelText: 'Unit price'),
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: AppColors.tealSoft,
                            borderRadius: BorderRadius.circular(AppRadii.sm),
                          ),
                          child: Row(
                            children: [
                              Text('Line total', style: Theme.of(context).textTheme.titleSmall?.copyWith(color: AppColors.teal)),
                              const Spacer(),
                              Text(
                                formatMoney(moneyFromDouble(
                                  (isValidQuantity(_rows[i].quantity.text) ? moneyToDouble(_rows[i].quantity.text) : 0.0) *
                                      (isValidMoney(_rows[i].unitPrice.text) ? moneyToDouble(_rows[i].unitPrice.text) : 0.0),
                                )),
                                style: Theme.of(context).textTheme.titleSmall?.copyWith(color: AppColors.teal),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _rows[i].supplier,
                          textInputAction: TextInputAction.next,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(labelText: 'Supplier / shop (optional)'),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _rows[i].notes,
                          textInputAction: TextInputAction.done,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(labelText: 'Notes (optional)'),
                        ),
                        if (_rows.length > 1)
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () => setState(() => _rows.removeAt(i)),
                              child: const Text('Remove', style: TextStyle(color: AppColors.danger)),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: () => setState(() => _rows.add(_Row())),
                icon: const Icon(Icons.add),
                label: const Text('Add another purchase'),
              ),
              const SizedBox(height: 8),
              TotalBar(label: 'Total', value: formatMoney(moneyFromDouble(_total))),
              const SizedBox(height: 12),
              Stretch(
                child: AppBusyButton(
                  busy: _busy,
                  busyLabel: 'Saving…',
                  onPressed: _busy || !_canSave ? null : _save,
                  label: 'Save',
                ),
              ),
            ],
          ),
          ),
        ),
      ),
    );
  }
}
