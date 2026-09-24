import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/theme/app_colors.dart';
import '../../core/finance/finance_repository.dart';
import '../../core/models/finance_models.dart';
import '../../core/utils/money.dart';
import '../../core/errors/friendly_error.dart';
import '../../core/widgets/app_layout.dart';
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
      await repo.refresh();
    } catch (error) {
      if (mounted) {
        setState(() => _error = friendlyError(error));
      }
    }
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

  @override
  Widget build(BuildContext context) {
    return AppDiscardScope(
      dirty: _dirty,
      fallback: widget.backTo,
      child: Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: AppBarTitle(widget.title),
      ),
      body: AppPageBody(
        padding: AppLayout.pagePadding(context, top: 8, bottom: 8),
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.only(bottom: AppLayout.pagePadding(context).bottom),
          children: [
          DatePickerTile(
            label: 'Date',
            value: DateFormat('yyyy-MM-dd').format(_date),
            onTap: () async {
              final picked = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 30)));
              if (picked != null) {
                setState(() => _date = picked);
              }
            },
          ),
          if (_error != null) ErrorBanner(message: _error!),
          const SizedBox(height: 8),
          for (var i = 0; i < _rows.length; i++)
            Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    DropdownButtonFormField<String>(
                      key: ValueKey('expense-category-$i-${_rows[i].categoryId}'),
                      initialValue: _categoryValue(_rows[i].categoryId),
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Category'),
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
                      decoration: const InputDecoration(labelText: 'Amount'),
                      onChanged: (_) => setState(() {}),
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
          TextButton.icon(
            onPressed: () => setState(() => _rows.add(_Row())),
            icon: const Icon(Icons.add),
            label: const Text('Add another row'),
          ),
          const SizedBox(height: 8),
          TotalBar(label: 'Total', value: formatMoney(moneyFromDouble(_total))),
          const SizedBox(height: 12),
          Stretch(
            child: FilledButton(onPressed: _busy || !_canSave ? null : _save, child: Text(_busy ? 'Saving…' : 'Save')),
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
