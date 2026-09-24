import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_colors.dart';
import '../../core/finance/finance_repository.dart';
import '../../core/models/finance_models.dart';
import '../../core/utils/money.dart';
import '../../core/errors/friendly_error.dart';
import '../../core/widgets/app_layout.dart';
import '../../core/widgets/app_navigation.dart';
import '../../core/widgets/empty_state.dart';

class CatalogsScreen extends ConsumerStatefulWidget {
  const CatalogsScreen({super.key});

  @override
  ConsumerState<CatalogsScreen> createState() => _CatalogsScreenState();
}

class _CatalogsScreenState extends ConsumerState<CatalogsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  List<CatalogItem> _categories = [];
  List<CatalogItem> _treatments = [];
  List<CatalogItem> _clinic = [];
  List<CatalogItem> _home = [];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final repo = ref.read(financeRepositoryProvider);
    await repo.refresh();
    final categories = await repo.treatmentCategories();
    final treatments = await repo.treatments();
    final clinic = await repo.clinicExpenseCategories();
    final home = await repo.homeExpenseCategories();
    if (mounted) {
      setState(() {
        _categories = categories;
        _treatments = treatments;
        _clinic = clinic;
        _home = home;
      });
    }
  }

  Future<void> _add({
    required String path,
    required String collection,
    required String entityType,
    required String label,
    bool needsCategory = false,
    bool needsPrice = false,
  }) async {
    final name = TextEditingController();
    final price = TextEditingController();
    String? categoryId;
    final categories = needsCategory ? await ref.read(financeRepositoryProvider).treatmentCategories() : <CatalogItem>[];
    if (!mounted) {
      name.dispose();
      price.dispose();
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              insetPadding: EdgeInsets.symmetric(
                horizontal: MediaQuery.sizeOf(context).width < 360 ? 16 : 24,
                vertical: 24,
              ),
              title: Text('Add $label', maxLines: 2, overflow: TextOverflow.ellipsis),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (needsCategory)
                      DropdownButtonFormField<String>(
                        initialValue: categoryId,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Category'),
                        items: [
                          for (final item in categories)
                            DropdownMenuItem(
                              value: item.id,
                              child: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                            ),
                        ],
                        onChanged: (value) => setDialogState(() => categoryId = value),
                      ),
                    if (needsCategory) const SizedBox(height: 12),
                    TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
                    if (needsPrice) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: price,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Default price (optional)'),
                      ),
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
    if (ok != true || name.text.trim().isEmpty || (needsCategory && categoryId == null)) {
      name.dispose();
      price.dispose();
      return;
    }
    if (needsPrice && price.text.trim().isNotEmpty && !isValidMoney(price.text)) {
      name.dispose();
      price.dispose();
      if (mounted) {
        showAppSnack(context, 'Enter a valid default price.', error: true);
      }
      return;
    }
    try {
      await ref.read(financeRepositoryProvider).createCatalog(
            path: path,
            collection: collection,
            entityType: entityType,
            body: {
              'name': name.text.trim(),
              if (needsCategory) 'category_id': categoryId,
              if (needsPrice && price.text.trim().isNotEmpty) 'default_price': moneyFromDouble(moneyToDouble(price.text)),
            },
          );
      await _load();
    } catch (error) {
      if (mounted) {
        showAppSnack(context, friendlyError(error), error: true);
      }
    } finally {
      name.dispose();
      price.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(fallback: '/settings'),
        title: const AppBarTitle('Catalogs'),
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(text: 'Categories'),
            Tab(text: 'Treatments'),
            Tab(text: 'Clinic'),
            Tab(text: 'Home'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _list(
            _categories,
            onAdd: () => _add(
              path: '/api/v1/treatment-categories',
              collection: 'treatment_categories',
              entityType: 'treatment_category',
              label: 'treatment category',
            ),
          ),
          _list(
            _treatments,
            onAdd: () => _add(
              path: '/api/v1/treatments',
              collection: 'treatments',
              entityType: 'treatment',
              label: 'treatment',
              needsCategory: true,
              needsPrice: true,
            ),
          ),
          _list(
            _clinic,
            onAdd: () => _add(
              path: '/api/v1/clinic-expense-categories',
              collection: 'clinic_expense_categories',
              entityType: 'clinic_expense_category',
              label: 'clinic category',
            ),
          ),
          _list(
            _home,
            onAdd: () => _add(
              path: '/api/v1/home-expense-categories',
              collection: 'home_expense_categories',
              entityType: 'home_expense_category',
              label: 'home category',
            ),
          ),
        ],
      ),
    );
  }

  Widget _list(List<CatalogItem> items, {required VoidCallback onAdd}) {
    return Column(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: EdgeInsets.fromLTRB(AppLayout.horizontalPadding(context), 4, AppLayout.horizontalPadding(context), 4),
            child: TextButton.icon(onPressed: onAdd, icon: const Icon(Icons.add), label: const Text('Add')),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: items.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: const [
                    EmptyState(message: 'No catalog items yet.', title: 'Empty list', icon: Icons.category_outlined),
                  ],
                )
              : ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                    AppLayout.horizontalPadding(context),
                    0,
                    AppLayout.horizontalPadding(context),
                    24,
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final subtitle = [
                      if (item.categoryName != null && item.categoryName!.isNotEmpty) item.categoryName,
                      if (item.defaultPrice != null) item.defaultPrice,
                    ].whereType<String>().join(' · ');
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: AppColors.purpleSoft,
                          foregroundColor: AppColors.purple,
                          child: Text(item.name.isEmpty ? '?' : item.name[0].toUpperCase()),
                        ),
                        title: Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: subtitle.isEmpty ? null : Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
                      ),
                    );
                  },
                ),
          ),
        ),
      ],
    );
  }
}
