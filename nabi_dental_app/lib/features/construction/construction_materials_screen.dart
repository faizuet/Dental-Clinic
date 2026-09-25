import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_colors.dart';
import 'package:intl/intl.dart';

import '../../core/errors/friendly_error.dart';
import '../../core/finance/finance_repository.dart';
import '../../core/models/finance_models.dart';
import '../../core/utils/money.dart';
import '../../core/widgets/app_layout.dart';
import '../../core/widgets/app_navigation.dart';
import '../../core/widgets/empty_state.dart';

const constructionUnits = ['bag', 'kg', 'ton', 'piece', 'cft', 'rft', 'meter', 'truck', 'liter', 'sqft', 'load'];

class ConstructionMaterialsScreen extends ConsumerStatefulWidget {
  const ConstructionMaterialsScreen({super.key});

  @override
  ConsumerState<ConstructionMaterialsScreen> createState() => _ConstructionMaterialsScreenState();
}

class _ConstructionMaterialsScreenState extends ConsumerState<ConstructionMaterialsScreen> {
  List<CatalogItem> _categories = [];
  List<ConstructionMaterial> _materials = [];
  bool _loading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final repo = ref.read(financeRepositoryProvider);
      try {
        await repo.refresh();
      } catch (_) {}
      await repo.ensureConstructionCatalog();
      final categories = await repo.constructionMaterialCategories();
      final materials = await repo.constructionMaterials();
      if (mounted) {
        setState(() {
          _categories = categories;
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

  Future<void> _addCategory() async {
    final name = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add category'),
          content: TextField(controller: name, decoration: const InputDecoration(labelText: 'Category name'), autofocus: true),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
          ],
        );
      },
    );
    if (ok != true || name.text.trim().isEmpty) {
      name.dispose();
      return;
    }
    try {
      await ref.read(financeRepositoryProvider).createCatalog(
            path: '/api/v1/construction-material-categories',
            collection: 'construction_material_categories',
            entityType: 'construction_material_category',
            body: {'name': name.text.trim()},
          );
      await _load();
    } catch (error) {
      if (mounted) {
        showAppSnack(context, friendlyError(error), error: true);
      }
    } finally {
      name.dispose();
    }
  }

  Future<void> _editCategory(CatalogItem category) async {
    final name = TextEditingController(text: category.name);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Edit category'),
          content: TextField(controller: name, decoration: const InputDecoration(labelText: 'Category name')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
          ],
        );
      },
    );
    if (ok != true || name.text.trim().isEmpty) {
      name.dispose();
      return;
    }
    try {
      await ref.read(financeRepositoryProvider).updateCatalog(
            path: '/api/v1/construction-material-categories/${category.id}',
            collection: 'construction_material_categories',
            entityType: 'construction_material_category',
            id: category.id,
            version: category.version,
            patch: {'name': name.text.trim()},
          );
      await _load();
    } catch (error) {
      if (mounted) {
        showAppSnack(context, friendlyError(error), error: true);
      }
    } finally {
      name.dispose();
    }
  }

  Future<void> _deleteCategory(CatalogItem category) async {
    final ok = await showAppConfirmDialog(
      context: context,
      title: 'Delete ${category.name}?',
      message: 'This category will be removed. Categories that still have materials cannot be deleted.',
      confirmLabel: 'Delete',
      destructive: true,
      icon: Icons.delete_outline_rounded,
    );
    if (ok != true) {
      return;
    }
    try {
      await ref.read(financeRepositoryProvider).deleteCatalog(
            path: '/api/v1/construction-material-categories/${category.id}',
            collection: 'construction_material_categories',
            entityType: 'construction_material_category',
            id: category.id,
            version: category.version,
          );
      await _load();
    } catch (error) {
      if (mounted) {
        showAppSnack(context, friendlyError(error), error: true);
      }
    }
  }

  Future<void> _editMaterial({ConstructionMaterial? existing}) async {
    if (_categories.isEmpty) {
      showAppSnack(context, 'Add a category first.', error: true);
      return;
    }
    final name = TextEditingController(text: existing?.name ?? '');
    final unit = TextEditingController(text: existing?.unit ?? 'piece');
    final quantity = TextEditingController();
    final unitPrice = TextEditingController();
    final supplier = TextEditingController();
    final notes = TextEditingController();
    var categoryId = existing?.categoryId ?? _categories.first.id;
    var purchaseDate = DateTime.now();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final units = {...constructionUnits, if (unit.text.trim().isNotEmpty) unit.text.trim()}.toList();
            final total = (isValidQuantity(quantity.text) ? moneyToDouble(quantity.text) : 0.0) *
                (isValidMoney(unitPrice.text) ? moneyToDouble(unitPrice.text) : 0.0);
            return AlertDialog(
              title: Text(existing == null ? 'Add material' : 'Edit material'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: _categories.any((item) => item.id == categoryId) ? categoryId : null,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Category'),
                      items: [
                        for (final item in _categories)
                          DropdownMenuItem(value: item.id, child: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: (value) => setDialogState(() => categoryId = value ?? categoryId),
                    ),
                    const SizedBox(height: 12),
                    TextField(controller: name, decoration: const InputDecoration(labelText: 'Material name')),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: units.contains(unit.text.trim()) ? unit.text.trim() : null,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Unit'),
                      items: [
                        for (final item in units) DropdownMenuItem(value: item, child: Text(item)),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          unit.text = value;
                          setDialogState(() {});
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: unit,
                      decoration: const InputDecoration(labelText: 'Custom unit'),
                    ),
                    if (existing == null) ...[
                      const SizedBox(height: 16),
                      Text('Optional first purchase', style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 12),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Purchase date'),
                        subtitle: Text(DateFormat('yyyy-MM-dd').format(purchaseDate)),
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: purchaseDate,
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now().add(const Duration(days: 30)),
                          );
                          if (picked != null) {
                            setDialogState(() => purchaseDate = picked);
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
                      TextField(controller: supplier, decoration: const InputDecoration(labelText: 'Supplier / shop')),
                      const SizedBox(height: 12),
                      TextField(controller: notes, decoration: const InputDecoration(labelText: 'Notes')),
                    ],
                  ],
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
    if (ok != true || name.text.trim().isEmpty || unit.text.trim().isEmpty) {
      name.dispose();
      unit.dispose();
      quantity.dispose();
      unitPrice.dispose();
      supplier.dispose();
      notes.dispose();
      return;
    }
    final recordPurchase = existing == null && quantity.text.trim().isNotEmpty && unitPrice.text.trim().isNotEmpty;
    if (recordPurchase && (!isValidQuantity(quantity.text) || !isValidMoney(unitPrice.text))) {
      name.dispose();
      unit.dispose();
      quantity.dispose();
      unitPrice.dispose();
      supplier.dispose();
      notes.dispose();
      if (mounted) {
        showAppSnack(context, 'Enter a valid quantity and unit price.', error: true);
      }
      return;
    }
    try {
      final repo = ref.read(financeRepositoryProvider);
      if (existing == null) {
        final materialId = await repo.createCatalog(
          path: '/api/v1/construction-materials',
          collection: 'construction_materials',
          entityType: 'construction_material',
          body: {
            'category_id': categoryId,
            'name': name.text.trim(),
            'unit': unit.text.trim(),
          },
        );
        if (recordPurchase) {
          await repo.saveConstructionPurchases(
            date: DateFormat('yyyy-MM-dd').format(purchaseDate),
            rows: [
              (
                materialId: materialId,
                quantity: formatQuantity(quantity.text),
                unit: unit.text.trim(),
                unitPrice: moneyFromDouble(moneyToDouble(unitPrice.text)),
                supplier: supplier.text.trim().isEmpty ? null : supplier.text.trim(),
                notes: notes.text.trim().isEmpty ? null : notes.text.trim(),
              ),
            ],
          );
        }
      } else {
        await repo.updateCatalog(
          path: '/api/v1/construction-materials/${existing.id}',
          collection: 'construction_materials',
          entityType: 'construction_material',
          id: existing.id,
          version: existing.version,
          patch: {
            'category_id': categoryId,
            'name': name.text.trim(),
            'unit': unit.text.trim(),
          },
        );
      }
      await _load();
    } catch (error) {
      if (mounted) {
        showAppSnack(context, friendlyError(error), error: true);
      }
    } finally {
      name.dispose();
      unit.dispose();
      quantity.dispose();
      unitPrice.dispose();
      supplier.dispose();
      notes.dispose();
    }
  }

  Future<void> _deleteMaterial(ConstructionMaterial material) async {
    final ok = await showAppConfirmDialog(
      context: context,
      title: 'Delete ${material.name}?',
      message: 'This material will be removed. Materials with purchase history cannot be deleted.',
      confirmLabel: 'Delete',
      destructive: true,
      icon: Icons.delete_outline_rounded,
    );
    if (ok != true) {
      return;
    }
    try {
      await ref.read(financeRepositoryProvider).deleteCatalog(
            path: '/api/v1/construction-materials/${material.id}',
            collection: 'construction_materials',
            entityType: 'construction_material',
            id: material.id,
            version: material.version,
          );
      await _load();
    } catch (error) {
      if (mounted) {
        showAppSnack(context, friendlyError(error), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final grouped = <String, List<ConstructionMaterial>>{};
    for (final category in _categories) {
      grouped[category.id] = [];
    }
    for (final material in _materials) {
      grouped.putIfAbsent(material.categoryId, () => []).add(material);
    }

    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(fallback: '/construction'),
        title: const AppBarTitle('Construction materials'),
        actions: [
          IconButton(tooltip: 'Add category', onPressed: _addCategory, icon: const Icon(Icons.create_new_folder_outlined)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editMaterial(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add material'),
      ),
      body: _loading
          ? const Center(child: LoadingView(message: 'Loading materials…'))
          : _loadError != null
              ? Center(
                  child: EmptyState(
                    message: _loadError!,
                    title: 'Could not load materials',
                    icon: Icons.wifi_off_rounded,
                    actionLabel: 'Retry',
                    onAction: _load,
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _categories.isEmpty && _materials.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: const [
                            EmptyState(
                              message: 'Add a category, then add any material you buy for the house.',
                              title: 'No materials yet',
                              icon: Icons.hardware_outlined,
                            ),
                          ],
                        )
                      : ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: EdgeInsets.fromLTRB(
                            AppLayout.horizontalPadding(context),
                            8,
                            AppLayout.horizontalPadding(context),
                            96,
                          ),
                          children: [
                            for (final category in _categories) ...[
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(category.name, style: Theme.of(context).textTheme.titleMedium),
                                trailing: PopupMenuButton<String>(
                                  onSelected: (value) {
                                    if (value == 'edit') {
                                      _editCategory(category);
                                    } else {
                                      _deleteCategory(category);
                                    }
                                  },
                                  itemBuilder: (context) => const [
                                    PopupMenuItem(value: 'edit', child: Text('Edit category')),
                                    PopupMenuItem(value: 'delete', child: Text('Delete category')),
                                  ],
                                ),
                              ),
                              if ((grouped[category.id] ?? []).isEmpty)
                                Card(
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Text(
                                      'No materials in this category yet.',
                                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
                                    ),
                                  ),
                                )
                              else
                                for (final material in grouped[category.id]!)
                                  Card(
                                    child: ListTile(
                                      leading: CircleAvatar(
                                        backgroundColor: AppColors.tealSoft,
                                        foregroundColor: AppColors.teal,
                                        child: Text(material.name.isEmpty ? '?' : material.name[0].toUpperCase()),
                                      ),
                                      title: Text(material.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                                      subtitle: Text('Unit: ${material.unit}', maxLines: 1, overflow: TextOverflow.ellipsis),
                                      trailing: PopupMenuButton<String>(
                                        onSelected: (value) {
                                          if (value == 'edit') {
                                            _editMaterial(existing: material);
                                          } else {
                                            _deleteMaterial(material);
                                          }
                                        },
                                        itemBuilder: (context) => const [
                                          PopupMenuItem(value: 'edit', child: Text('Edit')),
                                          PopupMenuItem(value: 'delete', child: Text('Delete')),
                                        ],
                                      ),
                                    ),
                                  ),
                              const SizedBox(height: 12),
                            ],
                          ],
                        ),
                ),
    );
  }
}
