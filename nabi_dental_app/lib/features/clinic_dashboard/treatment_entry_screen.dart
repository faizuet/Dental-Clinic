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

class TreatmentEntryScreen extends ConsumerStatefulWidget {
  const TreatmentEntryScreen({super.key});

  @override
  ConsumerState<TreatmentEntryScreen> createState() => _TreatmentEntryScreenState();
}

class _EntryRow {
  String? treatmentId;
  final amount = TextEditingController();
  final quantity = TextEditingController(text: '1');
  final notes = TextEditingController();
}

class _TreatmentEntryScreenState extends ConsumerState<TreatmentEntryScreen> {
  DateTime _date = DateTime.now();
  final _rows = [_EntryRow()];
  List<CatalogItem> _treatments = [];
  String _query = '';
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await ref.read(financeRepositoryProvider).refresh();
    final items = await ref.read(financeRepositoryProvider).treatments();
    if (mounted) {
      setState(() => _treatments = items);
    }
  }

  List<CatalogItem> _optionsFor(String? selectedId) {
    final needle = _query.trim().toLowerCase();
    final matches = needle.isEmpty
        ? _treatments
        : _treatments
            .where(
              (item) =>
                  item.name.toLowerCase().contains(needle) ||
                  (item.categoryName ?? '').toLowerCase().contains(needle),
            )
            .toList();
    final selected = _treatments.where((item) => item.id == selectedId);
    final seen = <String>{};
    return [...selected, ...matches].where((item) => seen.add(item.id)).toList();
  }

  @override
  void dispose() {
    for (final row in _rows) {
      row.amount.dispose();
      row.quantity.dispose();
      row.notes.dispose();
    }
    super.dispose();
  }

  double get _total {
    var sum = 0.0;
    for (final row in _rows) {
      if (row.treatmentId == null || !isValidMoney(row.amount.text)) {
        continue;
      }
      final quantity = int.tryParse(row.quantity.text) ?? 1;
      sum += moneyToDouble(row.amount.text) * quantity;
    }
    return sum;
  }

  bool get _canSave => _rows.any((row) => row.treatmentId != null && isValidMoney(row.amount.text));

  Future<void> _save() async {
    final payload = <({String treatmentId, String amount, int quantity, String? notes})>[];
    for (final row in _rows) {
      if (row.treatmentId == null || row.amount.text.trim().isEmpty) {
        continue;
      }
      if (!isValidMoney(row.amount.text)) {
        setState(() => _error = 'Enter amounts greater than 0 with up to two decimals.');
        return;
      }
      final quantity = int.tryParse(row.quantity.text);
      if (quantity == null || quantity < 1 || quantity > 999) {
        setState(() => _error = 'Quantity must be between 1 and 999.');
        return;
      }
      payload.add((
        treatmentId: row.treatmentId!,
        amount: moneyFromDouble(moneyToDouble(row.amount.text)),
        quantity: quantity,
        notes: row.notes.text.trim().isEmpty ? null : row.notes.text.trim(),
      ));
    }
    if (payload.isEmpty) {
      setState(() => _error = 'Add at least one treatment row.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final message = await ref.read(financeRepositoryProvider).saveIncomeBatch(
            date: DateFormat('yyyy-MM-dd').format(_date),
            rows: payload,
          );
      if (mounted) {
        showAppSnack(context, message);
        appPop(context, fallback: '/clinic');
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
        (row) => row.treatmentId != null || row.amount.text.trim().isNotEmpty || row.notes.text.trim().isNotEmpty,
      );

  @override
  Widget build(BuildContext context) {
    return AppDiscardScope(
      dirty: _dirty,
      fallback: '/clinic',
      child: Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: const AppBarTitle('Treatment income'),
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
          const SizedBox(height: 12),
          TextField(
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(labelText: 'Search treatments', prefixIcon: Icon(Icons.search_rounded)),
            onChanged: (value) => setState(() => _query = value),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            ErrorBanner(message: _error!),
          ],
          const SizedBox(height: 12),
          for (var i = 0; i < _rows.length; i++) _rowEditor(i),
          TextButton.icon(
            onPressed: () => setState(() => _rows.add(_EntryRow())),
            icon: const Icon(Icons.add),
            label: const Text('Add another treatment'),
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

  Widget _rowEditor(int index) {
    final row = _rows[index];
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            DropdownButtonFormField<String>(
              initialValue: row.treatmentId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Treatment'),
              items: [
                for (final item in _optionsFor(row.treatmentId))
                  DropdownMenuItem<String>(
                    value: item.id,
                    child: Text(
                      '${item.name}${item.defaultPrice == null ? '' : ' (${item.defaultPrice})'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) {
                setState(() {
                  row.treatmentId = value;
                  final match = _treatments.where((item) => item.id == value).toList();
                  if (match.isNotEmpty && match.first.defaultPrice != null && row.amount.text.isEmpty) {
                    row.amount.text = match.first.defaultPrice!;
                  }
                });
              },
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: row.amount,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'Amount'),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: row.quantity,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'Quantity'),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: row.notes,
              textInputAction: TextInputAction.done,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
            ),
            if (_rows.length > 1)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => setState(() => _rows.removeAt(index)),
                  child: const Text('Remove', style: TextStyle(color: AppColors.danger)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
