import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/theme/app_colors.dart';
import '../../core/finance/finance_repository.dart';
import '../../core/models/finance_models.dart';
import '../../core/utils/dates.dart';
import '../../core/utils/money.dart';
import '../../core/errors/friendly_error.dart';
import '../../core/widgets/page_kit.dart';
import '../../core/widgets/app_controls.dart';
import '../../core/widgets/app_layout.dart';
import '../../core/widgets/app_motion.dart';
import '../../core/widgets/app_navigation.dart';
import '../../core/widgets/app_page.dart';
import '../../core/widgets/error_banner.dart';
import '../../core/widgets/summary_card.dart';

class ExpenseEntryScreen extends ConsumerStatefulWidget {
  const ExpenseEntryScreen({
    super.key,
    required this.title,
    required this.backTo,
    required this.loadCategories,
    required this.save,
  });

  final String title;
  final String backTo;
  final Future<List<CatalogItem>> Function(FinanceRepository repo) loadCategories;
  final Future<String> Function(
    FinanceRepository repo, {
    required String date,
    required List<({String categoryId, String amount, String? notes})> rows,
  }) save;

  @override
  ConsumerState<ExpenseEntryScreen> createState() => _ExpenseEntryScreenState();
}

class _Row {
  String? categoryId;
  final amount = TextEditingController();
  final notes = TextEditingController();
}

class _ExpenseEntryScreenState extends ConsumerState<ExpenseEntryScreen> {
  DateTime _date = DateTime.now();
  final _rows = [_Row()];
  List<CatalogItem> _categories = [];
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final repo = ref.read(financeRepositoryProvider);
    try {
      final items = await widget.loadCategories(repo);
      if (mounted) {
        setState(() => _categories = items);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = friendlyError(error));
      }
    }
    try {
      await repo.refresh();
      final items = await widget.loadCategories(repo);
      if (mounted) {
        setState(() => _categories = items);
      }
    } catch (error) {
      if (mounted && _categories.isEmpty) {
        setState(() => _error = friendlyError(error));
      }
    }
  }

  @override
  void dispose() {
    for (final row in _rows) {
      row.amount.dispose();
      row.notes.dispose();
    }
    super.dispose();
  }

  double get _total {
    var sum = 0.0;
    for (final row in _rows) {
      if (row.categoryId != null && isValidMoney(row.amount.text)) {
        sum += moneyToDouble(row.amount.text);
      }
    }
    return sum;
  }

  bool get _canSave => _rows.any((row) => row.categoryId != null && isValidMoney(row.amount.text));

  String? _categoryValue(String? id) {
    if (id == null) {
      return null;
    }
    for (final item in _categories) {
      if (item.id == id) {
        return item.id;
      }
    }
    return null;
  }

  Future<void> _save() async {
    final payload = <({String categoryId, String amount, String? notes})>[];
    for (final row in _rows) {
      if (row.categoryId == null || row.amount.text.trim().isEmpty) {
        continue;
      }
      if (!isValidMoney(row.amount.text)) {
        setState(() => _error = 'Enter amounts greater than 0 with up to two decimals.');
        return;
      }
      payload.add((
        categoryId: row.categoryId!,
        amount: moneyFromDouble(moneyToDouble(row.amount.text)),
        notes: row.notes.text.trim().isEmpty ? null : row.notes.text.trim(),
      ));
    }
    if (payload.isEmpty) {
      setState(() => _error = 'Add at least one expense row.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final message = await widget.save(
        ref.read(financeRepositoryProvider),
        date: DateFormat('yyyy-MM-dd').format(_date),
        rows: payload,
      );
      if (mounted) {
        showAppSnack(context, message);
        appPop(context, fallback: widget.backTo);
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
        (row) => row.categoryId != null || row.amount.text.trim().isNotEmpty || row.notes.text.trim().isNotEmpty,
      );

  bool get _home => widget.backTo == '/home';

  @override
  Widget build(BuildContext context) {
    return AppDiscardScope(
      dirty: _dirty,
      fallback: widget.backTo,
      child: Scaffold(
      appBar: buildAppBar(
        context: context,
        title: widget.title,
        fallback: widget.backTo,
      ),
      body: AppPageBody(
        padding: AppLayout.pagePadding(context, top: 8, bottom: 8),
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.only(bottom: AppLayout.pagePadding(context).bottom),
          children: [
          PageHeader(
            icon: _home ? Icons.shopping_bag_rounded : Icons.receipt_long_rounded,
            title: _home ? 'Add Home Expense' : 'Add Clinic Expense',
            subtitle: _home
                ? 'Record grocery and household spending in one go'
                : 'Record clinic running costs. Lab work goes under Lab charges.',
            color: _home ? AppColors.aqua : AppColors.orange,
            soft: _home ? AppColors.aquaSoft : AppColors.warningSoft,
          ),
          const SizedBox(height: 20),
          DatePickerTile(
            label: 'Date',
            value: formatDisplayDate(_date),
            onTap: () async {
              final picked = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 30)));
              if (picked != null) {
                setState(() => _date = picked);
              }
            },
          ),
          if (_error != null) ErrorBanner(message: _error!),
          const SizedBox(height: 8),
          AppExpand(
            child: Column(
              children: [
          for (var i = 0; i < _rows.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TablePanel(
              header: PanelTitle(
                title: 'Expense ${i + 1}',
                subtitle: 'Category, amount, and an optional note',
                icon: Icons.edit_note_rounded,
                color: _home ? AppColors.aqua : AppColors.orange,
                soft: _home ? AppColors.aquaSoft : AppColors.warningSoft,
                trailing: _rows.length > 1
                    ? RowAction.danger(
                        icon: Icons.delete_outline_rounded,
                        tooltip: 'Remove',
                        onPressed: () => setState(() => _rows.removeAt(i)),
                      )
                    : null,
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    if (AppLayout.isDesktop(context))
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 4,
                            child: DropdownButtonFormField<String>(
                              key: ValueKey('expense-category-$i-${_rows[i].categoryId}'),
                              initialValue: _categoryValue(_rows[i].categoryId),
                              isExpanded: true,
                              menuMaxHeight: 420,
                              decoration: const InputDecoration(labelText: 'Category', prefixIcon: Icon(Icons.category_outlined)),
                              items: [
                                for (final item in _categories)
                                  DropdownMenuItem<String>(
                                    value: item.id,
                                    child: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                                  ),
                              ],
                              onChanged: (value) => setState(() => _rows[i].categoryId = value),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: _rows[i].amount,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(labelText: 'Amount', prefixIcon: Icon(Icons.payments_outlined)),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 3,
                            child: TextField(
                              controller: _rows[i].notes,
                              textInputAction: TextInputAction.done,
                              textCapitalization: TextCapitalization.sentences,
                              decoration: const InputDecoration(labelText: 'Notes (optional)', prefixIcon: Icon(Icons.notes_rounded)),
                            ),
                          ),
                        ],
                      )
                    else ...[
                    DropdownButtonFormField<String>(
                      key: ValueKey('expense-category-$i-${_rows[i].categoryId}'),
                      initialValue: _categoryValue(_rows[i].categoryId),
                      isExpanded: true,
                      menuMaxHeight: 420,
                      decoration: const InputDecoration(labelText: 'Category', prefixIcon: Icon(Icons.category_outlined)),
                      items: [
                        for (final item in _categories)
                          DropdownMenuItem<String>(
                            value: item.id,
                            child: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: (value) => setState(() => _rows[i].categoryId = value),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _rows[i].amount,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'Amount', prefixIcon: Icon(Icons.payments_outlined)),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _rows[i].notes,
                      textInputAction: TextInputAction.done,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(labelText: 'Notes (optional)', prefixIcon: Icon(Icons.notes_rounded)),
                    ),
                    ],
                  ],
                ),
              ),
            ),
            ),
              ],
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => setState(() => _rows.add(_Row())),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add another row'),
            ),
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
    );
  }
}

class ClinicExpenseEntryScreen extends StatelessWidget {
  const ClinicExpenseEntryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ExpenseEntryScreen(
      title: 'Clinic expense',
      backTo: '/clinic',
      loadCategories: (repo) => repo.clinicExpenseCategories(),
      save: (repo, {required date, required rows}) => repo.saveClinicExpenses(date: date, rows: rows),
    );
  }
}

class HomeExpenseEntryScreen extends StatelessWidget {
  const HomeExpenseEntryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ExpenseEntryScreen(
      title: 'Home expense',
      backTo: '/home',
      loadCategories: (repo) => repo.homeExpenseCategories(),
      save: (repo, {required date, required rows}) => repo.saveHomeExpenses(date: date, rows: rows),
    );
  }
}
