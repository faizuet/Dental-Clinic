import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/theme/app_colors.dart';
import '../../core/auth/session_controller.dart';
import '../../core/dental/tooth_catalog.dart';
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

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({
    super.key,
    required this.title,
    required this.backTo,
    required this.collection,
    required this.entityType,
    required this.deletePath,
    required this.updatePath,
    required this.loader,
    this.onOpen,
    this.onEdit,
    this.onAdd,
    this.addLabel,
    this.showPatient = false,
  });

  final String title;
  final String backTo;
  final String collection;
  final String entityType;
  final String Function(String id) deletePath;
  final String Function(String id) updatePath;
  final Future<List<MoneyEntry>> Function(FinanceRepository repo, {DateRange? range, String? search}) loader;
  final Future<void> Function(BuildContext context, MoneyEntry entry)? onOpen;
  final Future<void> Function(BuildContext context, MoneyEntry entry)? onEdit;
  final Future<void> Function()? onAdd;
  final String? addLabel;
  final bool showPatient;

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  List<MoneyEntry> _items = [];
  final _search = TextEditingController();
  DateTime? _from;
  DateTime? _to;
  bool _loading = true;
  bool _syncing = false;
  bool _deleting = false;
  String? _loadError;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false, bool network = true, bool force = false}) async {
    if (!silent && _items.isEmpty) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    final repo = ref.read(financeRepositoryProvider);
    final range = _from == null || _to == null ? null : DateRange(from: _from!, to: _to!, period: FinancePeriod.custom);
    try {
      final local = await widget.loader(repo, range: range, search: _search.text);
      if (mounted) {
        setState(() {
          _items = local;
          _loading = false;
          _syncing = network;
          _loadError = null;
        });
      }
      if (!network) {
        return;
      }
      await repo.refresh(force: force);
      final items = await widget.loader(repo, range: range, search: _search.text);
      if (mounted) {
        setState(() {
          _items = items;
          _loading = false;
          _syncing = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _loadError = friendlyError(error);
          _loading = false;
          _syncing = false;
        });
      }
    }
  }

  Future<void> _addRecord() async {
    if (widget.onAdd == null) {
      return;
    }
    await widget.onAdd!();
    if (mounted) {
      await _load(silent: true);
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

  ({String title, String message, String confirm, String success}) get _deleteCopy {
    switch (widget.entityType) {
      case 'treatment_transaction':
        return (
          title: 'Delete Treatment?',
          message:
              'Are you sure you want to delete this treatment record? The fee will be removed from clinic income. The patient record will be kept.',
          confirm: 'Delete Treatment',
          success: 'Treatment deleted successfully.',
        );
      case 'clinic_expense':
        return (
          title: 'Delete Clinic Expense?',
          message: 'Are you sure you want to delete this clinic expense? This action cannot be undone.',
          confirm: 'Delete Expense',
          success: 'Clinic expense deleted successfully.',
        );
      case 'home_expense':
        return (
          title: 'Delete Home Expense?',
          message: 'Are you sure you want to delete this home expense? This action cannot be undone.',
          confirm: 'Delete Expense',
          success: 'Home expense deleted successfully.',
        );
      default:
        return (
          title: 'Delete Record?',
          message: 'Are you sure you want to delete this record? This action cannot be undone.',
          confirm: 'Delete',
          success: 'Record deleted successfully.',
        );
    }
  }

  Future<void> _delete(MoneyEntry entry) async {
    if (_deleting) {
      return;
    }
    _deleting = true;
    final copy = _deleteCopy;
    final ok = await showAppDeleteDialog(
      context: context,
      title: copy.title,
      message: copy.message,
      confirmLabel: copy.confirm,
      onConfirm: () => ref.read(financeRepositoryProvider).deleteEntry(
            collection: widget.collection,
            path: widget.deletePath(entry.id),
            entityType: widget.entityType,
            entry: entry,
          ),
    );
    _deleting = false;
    if (!mounted || !ok) {
      return;
    }
    setState(() {
      _items = [for (final item in _items) if (item.id != entry.id) item];
    });
    ref.read(financeEpochProvider.notifier).state++;
    showAppSnack(context, copy.success);
  }

  Future<void> _open(MoneyEntry entry) async {
    if (widget.onOpen == null) {
      return;
    }
    await widget.onOpen!(context, entry);
    if (mounted) {
      await _load(silent: true, network: false);
    }
  }

  Future<void> _edit(MoneyEntry entry) async {
    if (widget.onEdit != null) {
      await widget.onEdit!(context, entry);
      if (mounted) {
        await _load(silent: true, network: false);
      }
      return;
    }
    final amount = TextEditingController(text: entry.amount);
    final notes = TextEditingController(text: entry.notes ?? '');
    DateTime date = DateTime.tryParse(entry.date) ?? DateTime.now();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final size = MediaQuery.sizeOf(context);
            final inset = size.width < 360 ? 16.0 : 24.0;
            return AlertDialog(
              insetPadding: EdgeInsets.symmetric(horizontal: inset, vertical: 24),
              title: const Text('Edit record'),
              content: SizedBox(
                width: AppLayout.dialogWidth(context),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
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
                        controller: amount,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Amount'),
                      ),
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
      amount.dispose();
      notes.dispose();
      return;
    }
    if (!isValidMoney(amount.text)) {
      amount.dispose();
      notes.dispose();
      if (mounted) {
        showAppSnack(context, 'Enter a valid amount.', error: true);
      }
      return;
    }
    final dateKey = widget.entityType.contains('transaction') ? 'transaction_date' : 'expense_date';
    final message = await ref.read(financeRepositoryProvider).updateEntry(
          collection: widget.collection,
          path: widget.updatePath(entry.id),
          entityType: widget.entityType,
          entry: entry,
          patch: {
            dateKey: DateFormat('yyyy-MM-dd').format(date),
            'amount': moneyFromDouble(moneyToDouble(amount.text)),
            'notes': notes.text.trim().isEmpty ? null : notes.text.trim(),
          },
        );
    amount.dispose();
    notes.dispose();
    if (mounted) {
      showAppSnack(context, message);
    }
    await _load(silent: true, network: false);
  }

  String _subtitle(MoneyEntry item) {
    final detail = item.detailsText ??
        clinicalSummary(
          item.details,
          subTreatment: displaySubTreatment(
            subTreatment: item.subTreatment,
            details: item.details,
            catalogName: item.catalogName,
          ),
        );
    return [
      if (item.serialNo != null) '#${item.serialNo}',
      if (item.patientPhone != null) item.patientPhone,
      formatDisplayDate(item.date),
      if (detail.isNotEmpty) detail,
      if (item.notes != null && item.notes!.isNotEmpty) item.notes,
    ].join(' · ');
  }

  String _recordLabel(MoneyEntry item) {
    final items = explicitVisitItems(item.details);
    if (items != null && items.length > 1) {
      final names = displaySubTreatment(details: item.details, catalogName: item.catalogName);
      final extra = [
        if (item.serialNo != null) '#${item.serialNo}',
        '${items.length} treatments',
        if (names != null) names,
      ].join(' · ');
      return extra;
    }
    final extra = [
      if (item.serialNo != null) '#${item.serialNo}',
      if (item.subTreatment != null &&
          item.subTreatment!.isNotEmpty &&
          item.subTreatment != item.catalogName)
        item.subTreatment,
    ].join(' · ');
    if (extra.isEmpty) {
      return item.catalogName;
    }
    return '${item.catalogName} · $extra';
  }

  Widget _historyCard(MoneyEntry item, String currency) {
    return Card(
      child: InkWell(
        onTap: widget.onOpen == null ? null : () => _open(item),
        borderRadius: BorderRadius.circular(AppRadii.lg),
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
                        if (widget.showPatient) ...[
                          Text(
                            item.displayPatientName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                        ],
                        Text(
                          visitMainLabel(
                            catalogName: item.catalogName,
                            categoryName: item.categoryName,
                            details: item.details,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: widget.showPatient
                              ? Theme.of(context).textTheme.bodyMedium
                              : Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _subtitle(item),
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
                  if (widget.onOpen != null)
                    TextButton.icon(
                      onPressed: () => _open(item),
                      icon: const Icon(Icons.visibility_outlined, size: 18),
                      label: const Text('View'),
                    ),
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
  }

  Widget _desktopTable(String currency) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            AppLayout.horizontalPadding(context),
            8,
            AppLayout.horizontalPadding(context),
            24,
          ),
          child: Card(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: math.max(720, constraints.maxWidth - AppLayout.horizontalPadding(context) * 2)),
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(AppColors.primarySoft),
                  columns: [
                    const DataColumn(label: Text('#')),
                    const DataColumn(label: Text('Date')),
                    if (widget.showPatient) const DataColumn(label: Text('Patient')),
                    const DataColumn(label: Text('Record')),
                    const DataColumn(label: Text('Amount'), numeric: true),
                    const DataColumn(label: Text('Actions')),
                  ],
                  rows: [
                    for (var index = 0; index < _items.length; index++)
                      DataRow(
                        cells: [
                          DataCell(Text('${index + 1}')),
                          DataCell(Text(formatDisplayDate(_items[index].date))),
                          if (widget.showPatient)
                            DataCell(
                              SizedBox(
                                width: 180,
                                child: Text(
                                  _items[index].displayPatientName,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                              ),
                            ),
                          DataCell(
                            SizedBox(
                              width: 280,
                              child: Text(
                                widget.showPatient ? _recordLabel(_items[index]) : _items[index].catalogName,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          DataCell(
                            MoneyText(
                              formatMoney(_items[index].amount, currency: currency),
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                          DataCell(
                            Row(
                              children: [
                                if (widget.onOpen != null)
                                  IconButton(
                                    tooltip: 'View',
                                    onPressed: () => _open(_items[index]),
                                    icon: const Icon(Icons.visibility_outlined),
                                  ),
                                IconButton(
                                  tooltip: 'Edit',
                                  onPressed: () => _edit(_items[index]),
                                  icon: const Icon(Icons.edit_outlined),
                                ),
                                IconButton(
                                  tooltip: 'Delete',
                                  onPressed: () => _delete(_items[index]),
                                  icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final currency = ref.watch(sessionProvider).clinic?.currency ?? 'PKR';
    return Scaffold(
      appBar: buildAppBar(
        context: context,
        title: widget.title,
        fallback: widget.backTo,
        actions: [
          if (widget.onAdd != null)
            IconButton(
              tooltip: widget.addLabel ?? 'Add',
              onPressed: _addRecord,
              icon: const Icon(Icons.add_rounded),
            ),
          IconButton(tooltip: 'Filter dates', onPressed: _pickRange, icon: const Icon(Icons.filter_alt_outlined)),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: AppLayout.maxContent(context)),
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(AppLayout.horizontalPadding(context), 8, AppLayout.horizontalPadding(context), 8),
                child: TextField(
                  controller: _search,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    labelText: 'Search',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: IconButton(
                      tooltip: 'Search',
                      onPressed: () => _load(network: false),
                      icon: const Icon(Icons.arrow_forward_rounded),
                    ),
                  ),
                  onSubmitted: (_) => _load(network: false),
                  onChanged: (_) {
                    _searchDebounce?.cancel();
                    _searchDebounce = Timer(const Duration(milliseconds: 160), () {
                      if (mounted) {
                        _load(silent: true, network: false);
                      }
                    });
                  },
                ),
              ),
              if (_syncing) const LinearProgressIndicator(minHeight: 2),
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
                  child: _loading && _items.isEmpty
                    ? const Center(key: ValueKey('history-loading'), child: SkeletonCards())
                    : _items.isEmpty && _loadError != null
                        ? Center(
                            key: const ValueKey('history-error'),
                            child: EmptyState(
                              message: _loadError!,
                              title: 'Could not load records',
                              icon: Icons.wifi_off_rounded,
                              actionLabel: 'Retry',
                              onAction: _load,
                            ),
                          )
                    : _items.isEmpty
                        ? Center(
                            key: const ValueKey('history-empty'),
                            child: EmptyState(
                              message: 'No records for this filter yet.',
                              title: 'Nothing here',
                              icon: Icons.receipt_long_outlined,
                              actionLabel: widget.addLabel,
                              onAction: widget.onAdd == null ? null : _addRecord,
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: () => _load(force: true),
                            child: AppLayout.isDesktop(context)
                                ? _desktopTable(currency)
                                : ListView.builder(
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
                                return AppReveal(
                                  index: index,
                                  child: _historyCard(item, currency),
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

class TreatmentHistoryScreen extends StatelessWidget {
  const TreatmentHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return HistoryScreen(
      title: 'Treatment history',
      backTo: '/clinic',
      collection: 'treatment_transactions',
      entityType: 'treatment_transaction',
      deletePath: (id) => '/api/v1/treatment-transactions/$id',
      updatePath: (id) => '/api/v1/treatment-transactions/$id',
      loader: (repo, {range, search}) => repo.incomeHistory(range: range, search: search),
      showPatient: true,
      addLabel: 'Add treatment',
      onAdd: () => context.push('/clinic/income'),
      onOpen: (context, entry) async {
        await context.push('/clinic/income/${entry.id}');
      },
      onEdit: (context, entry) async {
        await context.push('/clinic/income/${entry.id}/edit');
      },
    );
  }
}

class ClinicExpenseHistoryScreen extends StatelessWidget {
  const ClinicExpenseHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return HistoryScreen(
      title: 'Clinic expense history',
      backTo: '/clinic',
      collection: 'clinic_expenses',
      entityType: 'clinic_expense',
      deletePath: (id) => '/api/v1/clinic-expenses/$id',
      updatePath: (id) => '/api/v1/clinic-expenses/$id',
      loader: (repo, {range, search}) => repo.clinicExpenseHistory(range: range, search: search),
      addLabel: 'Add expense',
      onAdd: () => context.push('/clinic/expenses'),
    );
  }
}

class HomeExpenseHistoryScreen extends StatelessWidget {
  const HomeExpenseHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return HistoryScreen(
      title: 'Home expense history',
      backTo: '/home',
      collection: 'home_expenses',
      entityType: 'home_expense',
      deletePath: (id) => '/api/v1/home-expenses/$id',
      updatePath: (id) => '/api/v1/home-expenses/$id',
      loader: (repo, {range, search}) => repo.homeExpenseHistory(range: range, search: search),
      addLabel: 'Add expense',
      onAdd: () => context.push('/home/expenses'),
    );
  }
}
