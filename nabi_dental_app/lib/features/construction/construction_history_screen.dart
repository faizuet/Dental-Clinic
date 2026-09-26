import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/theme/app_colors.dart';
import '../../core/auth/session_controller.dart';
import '../../core/errors/friendly_error.dart';
import '../../core/finance/finance_repository.dart';
import '../../core/models/finance_models.dart';
import '../../core/utils/dates.dart';
import '../../core/utils/money.dart';
import '../../core/utils/period.dart';
import '../../core/widgets/app_controls.dart';
import '../../core/widgets/app_layout.dart';
import '../../core/widgets/app_motion.dart';
import '../../core/widgets/app_navigation.dart';
import '../../core/widgets/empty_state.dart';
import 'construction_material_picker.dart';

class ConstructionHistoryScreen extends ConsumerStatefulWidget {
  const ConstructionHistoryScreen({super.key});

  @override
  ConsumerState<ConstructionHistoryScreen> createState() => _ConstructionHistoryScreenState();
}

class _ConstructionHistoryScreenState extends ConsumerState<ConstructionHistoryScreen> {
  List<ConstructionPurchase> _items = [];
  List<ConstructionMaterial> _materials = [];
  final _search = TextEditingController();
  DateTime? _from;
  DateTime? _to;
  bool _loading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent || _items.isEmpty) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    try {
      await ref.read(financeRepositoryProvider).refresh();
      final range = _from == null || _to == null ? null : DateRange(from: _from!, to: _to!, period: FinancePeriod.custom);
      final repo = ref.read(financeRepositoryProvider);
      final items = await repo.constructionPurchases(range: range, search: _search.text);
      final materials = await repo.constructionMaterials();
      if (mounted) {
        setState(() {
          _items = items;
          _materials = materials;
          _loading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _loadError = friendlyError(error);
          _loading = false;
        });
      }
    }
  }

  Future<void> _pickRange() async {
    final picked = await pickInclusiveDateRange(context, from: _from, to: _to);
    if (picked == null) {
      return;
    }
    setState(() {
      _from = DateTime(picked.start.year, picked.start.month, picked.start.day);
      _to = DateTime(picked.end.year, picked.end.month, picked.end.day);
    });
    await _load();
  }

  Future<void> _delete(ConstructionPurchase entry) async {
    final ok = await showAppConfirmDialog(
      context: context,
      title: 'Delete this purchase?',
      message: 'This purchase will be removed from the list and synced when you are online.',
      confirmLabel: 'Delete',
      destructive: true,
      icon: Icons.delete_outline_rounded,
    );
    if (ok != true) {
      return;
    }
    await ref.read(financeRepositoryProvider).deleteConstructionPurchase(entry);
    await _load(silent: true);
  }

  Future<void> _edit(ConstructionPurchase entry) async {
    final quantity = TextEditingController(text: formatQuantity(entry.quantity));
    final unitPrice = TextEditingController(text: entry.unitPrice);
    final unit = TextEditingController(text: entry.unit);
    final supplier = TextEditingController(text: entry.supplier ?? '');
    final notes = TextEditingController(text: entry.notes ?? '');
    DateTime date = DateTime.tryParse(entry.date) ?? DateTime.now();
    var materialId = entry.materialId;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final size = MediaQuery.sizeOf(context);
            final inset = size.width < 360 ? 16.0 : 24.0;
            final total = (isValidQuantity(quantity.text) ? moneyToDouble(quantity.text) : 0.0) *
                (isValidMoney(unitPrice.text) ? moneyToDouble(unitPrice.text) : 0.0);
            return AlertDialog(
              insetPadding: EdgeInsets.symmetric(horizontal: inset, vertical: 24),
              title: const Text('Edit purchase'),
              content: SizedBox(
                width: size.width < 480 ? size.width - inset * 2 : 400,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ConstructionMaterialField(
                        materials: _materials,
                        selectedId: materialId,
                        onSelected: (material) {
                          setDialogState(() {
                            materialId = material.id;
                            unit.text = material.unit;
                          });
                        },
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Date'),
                        subtitle: Text(formatDisplayDate(date)),
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: date,
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now().add(const Duration(days: 30)),
                          );
                          if (picked != null) {
                            setDialogState(() => date = picked);
                          }
                        },
                      ),
                      TextField(
                        controller: quantity,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Quantity'),
                        onChanged: (_) => setDialogState(() {}),
                      ),
                      const SizedBox(height: 12),
                      TextField(controller: unit, decoration: const InputDecoration(labelText: 'Unit')),
                      const SizedBox(height: 12),
                      TextField(
                        controller: unitPrice,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Unit price'),
                        onChanged: (_) => setDialogState(() {}),
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text('Total  ${formatMoney(moneyFromDouble(total))}'),
                      ),
                      const SizedBox(height: 12),
                      TextField(controller: supplier, decoration: const InputDecoration(labelText: 'Supplier')),
                      const SizedBox(height: 12),
                      TextField(controller: notes, decoration: const InputDecoration(labelText: 'Notes')),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
              ],
            );
          },
        );
      },
    );
    if (ok != true) {
      quantity.dispose();
      unitPrice.dispose();
      unit.dispose();
      supplier.dispose();
      notes.dispose();
      return;
    }
    if (!isValidQuantity(quantity.text) || !isValidMoney(unitPrice.text)) {
      quantity.dispose();
      unitPrice.dispose();
      unit.dispose();
      supplier.dispose();
      notes.dispose();
      if (mounted) {
        showAppSnack(context, 'Enter a valid quantity and unit price.', error: true);
      }
      return;
    }
    final message = await ref.read(financeRepositoryProvider).updateConstructionPurchase(
          entry: entry,
          patch: {
            'material_id': materialId,
            'purchase_date': DateFormat('yyyy-MM-dd').format(date),
            'quantity': formatQuantity(quantity.text),
            'unit': unit.text.trim().isEmpty ? entry.unit : unit.text.trim(),
            'unit_price': moneyFromDouble(moneyToDouble(unitPrice.text)),
            'supplier': supplier.text.trim().isEmpty ? null : supplier.text.trim(),
            'notes': notes.text.trim().isEmpty ? null : notes.text.trim(),
          },
        );
    quantity.dispose();
    unitPrice.dispose();
    unit.dispose();
    supplier.dispose();
    notes.dispose();
    if (mounted) {
      showAppSnack(context, message);
    }
    await _load(silent: true);
  }

  @override
  Widget build(BuildContext context) {
    final currency = ref.watch(sessionProvider).clinic?.currency ?? 'PKR';
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(fallback: '/construction'),
        title: const AppBarTitle('Purchase history'),
        actions: [
          IconButton(tooltip: 'Filter dates', onPressed: _pickRange, icon: const Icon(Icons.filter_alt_outlined)),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSpacing.maxContent),
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(AppLayout.horizontalPadding(context), 8, AppLayout.horizontalPadding(context), 8),
                child: TextField(
                  controller: _search,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    labelText: 'Search material, supplier, or notes',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: IconButton(
                      tooltip: 'Search',
                      onPressed: _load,
                      icon: const Icon(Icons.arrow_forward_rounded),
                    ),
                  ),
                  onSubmitted: (_) => _load(),
                ),
              ),
              if (_from != null && _to != null)
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: AppLayout.horizontalPadding(context)),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: ActionChip(
                      avatar: const Icon(Icons.close_rounded, size: 18),
                      label: Text(
                        formatDisplayDateRange(_from, _to, separator: ' → '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onPressed: () {
                        setState(() {
                          _from = null;
                          _to = null;
                        });
                        _load();
                      },
                    ),
                  ),
                ),
              Expanded(
                child: AppStateSwitch(
                  child: _loading
                    ? const Center(key: ValueKey('purchase-history-loading'), child: SkeletonCards())
                    : _loadError != null
                        ? Center(
                            key: const ValueKey('purchase-history-error'),
                            child: EmptyState(
                              message: _loadError!,
                              title: 'Could not load purchases',
                              icon: Icons.wifi_off_rounded,
                              actionLabel: 'Retry',
                              onAction: _load,
                            ),
                          )
                        : _items.isEmpty
                            ? const Center(
                                key: ValueKey('purchase-history-empty'),
                                child: EmptyState(
                                  message: 'No purchases for this filter yet.',
                                  title: 'Nothing here',
                                  icon: Icons.receipt_long_outlined,
                                ),
                              )
                            : RefreshIndicator(
                                onRefresh: _load,
                                child: ListView.builder(
                                  physics: const AlwaysScrollableScrollPhysics(),
                                  padding: EdgeInsets.fromLTRB(
                                    AppLayout.horizontalPadding(context),
                                    8,
                                    AppLayout.horizontalPadding(context),
                                    24,
                                  ),
                                  itemCount: _items.length,
                                  itemBuilder: (context, index) {
                                    final item = _items[index];
                                    final detail = [
                                      formatDisplayDate(item.date),
                                      '${formatQuantity(item.quantity)} ${item.unit} × ${formatMoney(item.unitPrice, currency: currency)}',
                                      if (item.supplier != null && item.supplier!.isNotEmpty) item.supplier,
                                      if (item.notes != null && item.notes!.isNotEmpty) item.notes,
                                    ].join(' · ');
                                    return AppReveal(
                                      index: index,
                                      child: Card(
                                      child: Padding(
                                        padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text(
                                                        item.materialName ?? 'Material',
                                                        maxLines: 2,
                                                        overflow: TextOverflow.ellipsis,
                                                        style: Theme.of(context).textTheme.titleMedium,
                                                      ),
                                                      const SizedBox(height: 4),
                                                      Text(
                                                        detail,
                                                        maxLines: 3,
                                                        overflow: TextOverflow.ellipsis,
                                                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                ConstrainedBox(
                                                  constraints: const BoxConstraints(maxWidth: 128, minWidth: 72),
                                                  child: MoneyText(
                                                    formatMoney(item.amount, currency: currency),
                                                    style: Theme.of(context).textTheme.titleSmall,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            OverflowBar(
                                              alignment: MainAxisAlignment.end,
                                              children: [
                                                TextButton.icon(
                                                  onPressed: () => _edit(item),
                                                  icon: const Icon(Icons.edit_outlined, size: 18),
                                                  label: const Text('Edit'),
                                                ),
                                                TextButton.icon(
                                                  onPressed: () => _delete(item),
                                                  icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.danger),
                                                  label: const Text('Delete', style: TextStyle(color: AppColors.danger)),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    );
                                  },
                                ),
                              ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
