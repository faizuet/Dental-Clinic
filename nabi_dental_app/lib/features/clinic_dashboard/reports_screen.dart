import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_colors.dart';
import '../../core/auth/session_controller.dart';
import '../../core/errors/app_exception.dart';
import '../../core/export/file_saver.dart';
import '../../core/finance/finance_repository.dart';
import '../../core/models/finance_models.dart';
import '../../core/utils/money.dart';
import '../../core/utils/period.dart';
import '../../core/errors/friendly_error.dart';
import '../../core/widgets/app_layout.dart';
import '../../core/widgets/app_navigation.dart';
import '../../core/widgets/app_page.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/period_selector.dart';
import '../../core/widgets/status_banner.dart';
import '../../core/widgets/summary_card.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({
    super.key,
    required this.title,
    required this.backTo,
    required this.clinic,
  });

  final String title;
  final String backTo;
  final bool clinic;

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  FinancePeriod _period = FinancePeriod.monthly;
  DateTime? _from;
  DateTime? _to;
  String _income = '0.00';
  String _expenses = '0.00';
  String _profit = '0.00';
  String _budget = '0.00';
  String _remaining = '0.00';
  List<NamedAmount> _incomeBreakdown = [];
  List<NamedAmount> _expenseBreakdown = [];
  List<NamedAmount> _timeline = [];
  bool _loading = true;
  String? _loadError;

  DateRange get _range => DateRange.forPeriod(_period, customFrom: _from, customTo: _to);

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
    await repo.refresh();
    if (widget.clinic) {
      final totals = await repo.clinicTotals(_range);
      final income = await repo.incomeHistory(range: _range);
      final expenses = await repo.clinicExpenseHistory(range: _range);
      final byTreatment = await repo.breakdown(income);
      final byCategory = await repo.breakdown(expenses);
      final incomeTimeline = await repo.timeline(income);
      final expenseTimeline = await repo.timeline(expenses);
      if (mounted) {
        setState(() {
          _income = totals.income;
          _expenses = totals.expenses;
          _profit = totals.profit;
          _incomeBreakdown = byTreatment;
          _expenseBreakdown = byCategory;
          _timeline = [...incomeTimeline, ...expenseTimeline];
          _loading = false;
        });
      }
    } else {
      final defaultBudget = ref.read(sessionProvider).user?.defaultHomeBudget ?? '30000.00';
      final totals = await repo.homeTotals(_range, defaultBudget: defaultBudget);
      final expenses = await repo.homeExpenseHistory(range: _range);
      final byCategory = await repo.breakdown(expenses);
      final days = await repo.timeline(expenses);
      if (mounted) {
        setState(() {
          _expenses = totals.spent;
          _budget = totals.budget;
          _remaining = totals.remaining;
          _expenseBreakdown = byCategory;
          _timeline = days;
          _loading = false;
        });
      }
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

  Future<void> _export(String format) async {
    try {
      final repo = ref.read(financeRepositoryProvider);
      final file = widget.clinic ? await repo.exportClinic(range: _range, format: format) : await repo.exportHome(range: _range, format: format);
      final path = await saveBytes(bytes: file.bytes, filename: file.filename, mime: file.mime);
      if (mounted) {
        showAppSnack(context, '${format.toUpperCase()} saved${path == null ? '.' : ': $path'}');
      }
    } on OfflineException {
      if (mounted) {
        showAppSnack(context, 'PDF and Excel need an internet connection.', error: true);
      }
    } catch (error) {
      if (mounted) {
        showAppSnack(context, friendlyError(error), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = ref.watch(sessionProvider).clinic?.currency ?? 'PKR';
    return Scaffold(
      appBar: AppBar(
        leading: AppBackButton(fallback: widget.backTo),
        title: AppBarTitle(widget.title),
      ),
      body: AppPageBody(
        padding: AppLayout.pagePadding(context, top: 8, bottom: 8),
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(bottom: AppLayout.pagePadding(context).bottom),
          children: [
          PeriodSelector(
            value: _period,
            onChanged: (value) async {
              if (value == FinancePeriod.custom) {
                final from = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime.now());
                if (from == null || !context.mounted) {
                  return;
                }
                final to = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: from, lastDate: DateTime.now());
                if (to == null) {
                  return;
                }
                _from = from;
                _to = to;
              }
              setState(() => _period = value);
              await _load();
            },
          ),
          const SizedBox(height: 12),
          Text(
            '${_range.fromIso} to ${_range.toIso}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 12),
          if (_loadError != null) ...[
            StatusBanner.error(_loadError!, onRetry: _load),
            const SizedBox(height: 12),
          ],
          if (_loading)
            const LoadingView(message: 'Building this report…')
          else ...[
            if (widget.clinic) ...[
              SummaryCard(label: 'Income', value: formatMoney(_income, currency: currency), color: AppColors.success, icon: Icons.trending_up_rounded),
              SummaryCard(label: 'Expenses', value: formatMoney(_expenses, currency: currency), color: AppColors.danger, icon: Icons.trending_down_rounded),
              SummaryCard(label: 'Profit', value: formatMoney(_profit, currency: currency), icon: Icons.account_balance_wallet_outlined),
            ] else ...[
              SummaryCard(label: 'Spending', value: formatMoney(_expenses, currency: currency), color: AppColors.danger, icon: Icons.shopping_bag_outlined),
              SummaryCard(label: 'Budget', value: formatMoney(_budget, currency: currency), icon: Icons.savings_outlined),
              SummaryCard(label: 'Remaining', value: formatMoney(_remaining, currency: currency), color: AppColors.success, icon: Icons.account_balance_wallet_outlined),
            ],
            const SizedBox(height: 8),
            if (widget.clinic) ...[
              const SectionHeader('Income by treatment'),
              Card(
                child: _incomeBreakdown.isEmpty
                    ? const EmptyState(message: 'No income in this range.')
                    : Column(children: [for (final item in _incomeBreakdown) _row(item, currency)]),
              ),
              const SectionHeader('Expenses by category'),
            ] else
              const SectionHeader('Spending by category'),
            Card(
              child: _expenseBreakdown.isEmpty
                  ? const EmptyState(message: 'No activity in this range.')
                  : Column(children: [for (final item in _expenseBreakdown) _row(item, currency)]),
            ),
            const SectionHeader('Timeline'),
            Card(
              child: _timeline.isEmpty
                  ? const EmptyState(message: 'No daily totals yet.')
                  : Column(children: [for (final item in _timeline) _row(item, currency)]),
            ),
            const SizedBox(height: 8),
            Stretch(
              child: FilledButton.icon(
                onPressed: () => _export('pdf'),
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('Export PDF', maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ),
            const SizedBox(height: 8),
            Stretch(
              child: OutlinedButton.icon(
                onPressed: () => _export('xlsx'),
                icon: const Icon(Icons.table_view_outlined),
                label: const Text('Export Excel', maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ),
          ],
        ],
        ),
        ),
      ),
    );
  }

  Widget _row(NamedAmount item, String currency) {
    return ListTile(
      title: Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 140),
        child: MoneyText(
          formatMoney(item.amount, currency: currency),
          style: Theme.of(context).textTheme.titleSmall,
        ),
      ),
    );
  }
}

class ClinicReportsScreen extends StatelessWidget {
  const ClinicReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ReportsScreen(title: 'Clinic reports', backTo: '/clinic', clinic: true);
  }
}

class HomeReportsScreen extends StatelessWidget {
  const HomeReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ReportsScreen(title: 'Home reports', backTo: '/home', clinic: false);
  }
}
