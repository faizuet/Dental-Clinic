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
import '../../core/widgets/page_kit.dart';

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
    this.totalLabel,
    this.icon = Icons.receipt_long_rounded,
    this.subtitle = 'Search, review, and manage saved records',
    this.accent = AppColors.primary,
    this.accentSoft = AppColors.primarySoft,
    this.recordNoun = 'records',
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
  final String? totalLabel;
  final IconData icon;
  final String subtitle;
  final Color accent;
  final Color accentSoft;
  final String recordNoun;

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
      case 'lab_charge':
        return (
          title: 'Delete Lab Charge?',
          message: 'Are you sure you want to delete this lab charge? It will be removed from lab charge totals.',
          confirm: 'Delete Lab Charge',
          success: 'Lab charge deleted successfully.',
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

  List<Widget> _rowActions(MoneyEntry item) {
    return [
      if (widget.onOpen != null) RowAction(icon: Icons.visibility_rounded, tooltip: 'View', onPressed: () => _open(item)),
      RowAction(icon: Icons.edit_rounded, tooltip: 'Edit', onPressed: () => _edit(item)),
      RowAction.danger(icon: Icons.delete_outline_rounded, tooltip: 'Delete', onPressed: () => _delete(item)),
    ];
  }

  Widget _historyCard(MoneyEntry item, String currency) {
    return InkWell(
      onTap: widget.onOpen == null ? null : () => _open(item),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.showPatient) ...[
                  InitialsAvatar(name: item.displayPatientName, size: 40),
                  const SizedBox(width: 12),
                ],
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
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: Row(mainAxisSize: MainAxisSize.min, children: _rowActions(item)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _desktopTable(String currency) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: math.max(760, constraints.maxWidth)),
            child: DataTable(
              showCheckboxColumn: false,
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
                    onSelectChanged: widget.onOpen == null ? null : (_) => _open(_items[index]),
                    cells: [
                      DataCell(Text('${index + 1}')),
                      DataCell(IconText(icon: Icons.event_note_rounded, text: formatDisplayDate(_items[index].date))),
                      if (widget.showPatient)
                        DataCell(
                          SizedBox(
                            width: 200,
                            child: Row(
                              children: [
                                InitialsAvatar(name: _items[index].displayPatientName, size: 32),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _items[index].displayPatientName,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.w700),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      DataCell(
                        SizedBox(
                          width: 280,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.showPatient ? _recordLabel(_items[index]) : _items[index].catalogName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              if (_items[index].notes != null && _items[index].notes!.isNotEmpty)
                                Text(
                                  _items[index].notes!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted),
                                ),
                            ],
                          ),
                        ),
                      ),
                      DataCell(
                        MoneyText(
                          formatMoney(_items[index].amount, currency: currency),
                          style: Theme.of(context).textTheme.titleSmall,
                          color: widget.accent,
                        ),
                      ),
                      DataCell(Row(mainAxisSize: MainAxisSize.min, children: _rowActions(_items[index]))),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _stats(String currency) {
    final total = _items.fold<double>(0, (sum, item) => sum + moneyToDouble(item.amount));
    final now = DateTime.now();
    final month = _items.where((item) {
      final date = parseFlexibleDate(item.date);
      return date != null && date.year == now.year && date.month == now.month;
    }).fold<double>(0, (sum, item) => sum + moneyToDouble(item.amount));
    final average = _items.isEmpty ? 0.0 : total / _items.length;
    return StatStrip(
      items: [
        MiniStat(
          label: widget.totalLabel ?? 'Total amount',
          value: formatMoney(moneyFromDouble(total), currency: currency),
          icon: widget.icon,
          color: widget.accent,
          soft: widget.accentSoft,
        ),
        MiniStat(
          label: 'Entries',
          value: '${_items.length}',
          icon: Icons.format_list_numbered_rounded,
          color: AppColors.primary,
          soft: AppColors.primarySoft,
        ),
        MiniStat(
          label: 'This Month',
          value: formatMoney(moneyFromDouble(month), currency: currency),
          icon: Icons.calendar_month_rounded,
          color: AppColors.success,
          soft: AppColors.mintSoft,
        ),
        MiniStat(
          label: 'Average Entry',
          value: formatMoney(moneyFromDouble(average), currency: currency),
          icon: Icons.analytics_rounded,
          color: AppColors.orange,
          soft: AppColors.warningSoft,
        ),
      ],
    );
  }

  Widget _records(String currency) {
    if (_loading && _items.isEmpty) {
      return const SkeletonTable(key: ValueKey('history-loading'));
    }
    if (_items.isEmpty && _loadError != null) {
      return EmptyState(
        key: const ValueKey('history-error'),
        message: _loadError!,
        title: 'Could not load records',
        icon: Icons.wifi_off_rounded,
        actionLabel: 'Retry',
        onAction: _load,
      );
    }
    if (_items.isEmpty) {
      return EmptyState(
        key: const ValueKey('history-empty'),
        message: 'No records for this filter yet.',
        title: 'Nothing here',
        icon: widget.icon,
        actionLabel: widget.addLabel,
        onAction: widget.onAdd == null ? null : _addRecord,
      );
    }
    if (AppLayout.isDesktop(context)) {
      return KeyedSubtree(key: const ValueKey('history-table'), child: _desktopTable(currency));
    }
    return Column(
      key: const ValueKey('history-list'),
      children: [
        for (var index = 0; index < _items.length; index++) ...[
          if (index > 0) const Divider(height: 1),
          AppReveal(index: index, child: _historyCard(_items[index], currency)),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final currency = ref.watch(sessionProvider).clinic?.currency ?? 'PKR';
    final ranged = _from != null && _to != null;
    return Scaffold(
      appBar: buildAppBar(context: context, title: widget.title, fallback: widget.backTo),
      body: PageScaffoldBody(
        onRefresh: () => _load(force: true),
        children: [
          PageHeader(
            icon: widget.icon,
            title: widget.title,
            subtitle: widget.subtitle,
            color: widget.accent,
            soft: widget.accentSoft,
            actions: [
              if (widget.onAdd != null)
                Tooltip(
                  message: widget.addLabel ?? 'Add',
                  child: PrimaryAction(label: widget.addLabel ?? 'Add', icon: Icons.add_rounded, onPressed: _addRecord),
                ),
            ],
          ),
          _stats(currency),
          if (_syncing) ...[
            const LinearProgressIndicator(minHeight: 2),
            const SizedBox(height: 8),
          ],
          TablePanel(
            header: FilterBar(
              filters: [
                Tooltip(
                  message: 'Filter dates',
                  child: FilterButton(
                    label: ranged ? formatDisplayDateRange(_from, _to, separator: ' → ') : 'All Time',
                    icon: Icons.calendar_month_rounded,
                    trailingIcon: Icons.expand_more_rounded,
                    onPressed: _pickRange,
                  ),
                ),
                if (ranged)
                  FilterButton(
                    label: 'Clear',
                    icon: Icons.close_rounded,
                    onPressed: () {
                      setState(() {
                        _from = null;
                        _to = null;
                      });
                      _load();
                    },
                  ),
                FilterSearch(
                  controller: _search,
                  hint: widget.showPatient ? 'Search by patient, phone, or record...' : 'Search records...',
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
              ],
              trailing: [
                FilterButton(
                  label: 'Refresh',
                  icon: Icons.refresh_rounded,
                  onPressed: _syncing ? null : () => _load(force: true),
                ),
              ],
            ),
            footer: TableFooterText(
              shown: _items.length,
              total: _items.length,
              noun: widget.recordNoun,
              trailing: _items.isEmpty
                  ? null
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Total  ', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.muted)),
                        MoneyText(
                          formatMoney(
                            moneyFromDouble(_items.fold<double>(0, (sum, item) => sum + moneyToDouble(item.amount))),
                            currency: currency,
                          ),
                          style: Theme.of(context).textTheme.titleMedium,
                          color: widget.accent,
                        ),
                      ],
                    ),
            ),
            child: AppStateSwitch(child: _records(currency)),
          ),
        ],
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
      icon: Icons.medical_services_rounded,
      subtitle: 'Every treatment visit, fee, and patient in one place',
      accent: AppColors.success,
      accentSoft: AppColors.mintSoft,
      totalLabel: 'Treatment Fees',
      recordNoun: 'treatments',
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
      icon: Icons.receipt_long_rounded,
      subtitle: 'Track clinic spending by category, separate from lab charges',
      accent: AppColors.orange,
      accentSoft: AppColors.warningSoft,
      totalLabel: 'Clinic Expenses',
      recordNoun: 'expenses',
      addLabel: 'Add expense',
      onAdd: () => context.push('/clinic/expenses'),
    );
  }
}

class LabChargeHistoryScreen extends StatelessWidget {
  const LabChargeHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return HistoryScreen(
      title: 'Lab charges',
      backTo: '/clinic',
      collection: 'lab_charges',
      entityType: 'lab_charge',
      deletePath: (id) => '/api/v1/lab-charges/$id',
      updatePath: (id) => '/api/v1/lab-charges/$id',
      loader: (repo, {range, search}) => repo.labChargeHistory(range: range, search: search),
      showPatient: true,
      icon: Icons.science_rounded,
      subtitle: 'Lab work costs, linked to patients and visits where needed',
      accent: AppColors.violet,
      accentSoft: AppColors.violetSoft,
      totalLabel: 'Total Lab Charges',
      recordNoun: 'lab charges',
      addLabel: 'Add lab charge',
      onAdd: () => context.push('/clinic/lab-charges/new'),
      onEdit: (context, entry) async {
        await context.push('/clinic/lab-charges/${entry.id}/edit');
      },
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
      icon: Icons.shopping_bag_rounded,
      subtitle: 'Household grocery spending, kept separate from the clinic',
      accent: AppColors.aqua,
      accentSoft: AppColors.aquaSoft,
      totalLabel: 'Home Spending',
      recordNoun: 'expenses',
      addLabel: 'Add expense',
      onAdd: () => context.push('/home/expenses'),
    );
  }
}
