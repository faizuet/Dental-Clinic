import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_colors.dart';
import '../../core/auth/session_controller.dart';
import '../../core/errors/app_exception.dart';
import '../../core/export/file_saver.dart';
import '../../core/finance/finance_repository.dart';
import '../../core/models/finance_models.dart';
import '../../core/utils/dates.dart';
import '../../core/utils/money.dart';
import '../../core/utils/period.dart';
import '../../core/errors/friendly_error.dart';
import '../../core/widgets/app_controls.dart';
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
    this.title = 'Clinic reports',
    this.backTo = '/clinic',
  });

  final String title;
  final String backTo;

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
  List<NamedAmount> _incomeBreakdown = [];
  List<NamedAmount> _expenseBreakdown = [];
  List<NamedAmount> _timeline = [];
  bool _loading = true;
  bool _syncing = false;
  bool _exporting = false;
  String? _exportFormat;
  String? _loadError;

  DateRange get _range => DateRange.forPeriod(_period, customFrom: _from, customTo: _to);

  @override
  void initState() {
    super.initState();
    ref.listenManual(financeEpochProvider, (previous, next) {
      if (previous != next) {
        _load(silent: true);
      }
    });
    _load();
  }

  Future<void> _apply(FinanceRepository repo) async {
    final income = await repo.incomeHistory(range: _range);
    final expenses = await repo.clinicExpenseHistory(range: _range);
    final incomeTotal = income.fold<double>(0, (sum, item) => sum + moneyToDouble(item.amount));
    final expenseTotal = expenses.fold<double>(0, (sum, item) => sum + moneyToDouble(item.amount));
    final byTreatment = await repo.breakdown(income);
    final byCategory = await repo.breakdown(expenses);
    final incomeTimeline = await repo.timeline(income);
    final expenseTimeline = await repo.timeline(expenses);
    if (!mounted) {
      return;
    }
    setState(() {
      _income = moneyFromDouble(incomeTotal);
      _expenses = moneyFromDouble(expenseTotal);
      _profit = moneyFromDouble(incomeTotal - expenseTotal);
      _incomeBreakdown = byTreatment;
      _expenseBreakdown = byCategory;
      _timeline = [...incomeTimeline, ...expenseTimeline];
      _loading = false;
    });
  }

  Future<void> _load({bool silent = false, bool force = false}) async {
    if (!silent && _incomeBreakdown.isEmpty && _expenseBreakdown.isEmpty) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    try {
      final repo = ref.read(financeRepositoryProvider);
      await _apply(repo);
      if (mounted) {
        setState(() => _syncing = true);
      }
      await repo.refresh(force: force);
      await _apply(repo);
      if (mounted) {
        setState(() => _syncing = false);
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

  Future<void> _export(String format) async {
    if (_exporting) {
      return;
    }
    setState(() {
      _exporting = true;
      _exportFormat = format;
    });
    try {
      final file = await ref.read(financeRepositoryProvider).exportClinic(range: _range, format: format);
      await saveBytes(bytes: file.bytes, filename: file.filename, mime: file.mime);
      if (mounted) {
        showAppSnack(context, '${format.toUpperCase()} saved to Downloads');
      }
    } on OfflineException {
      if (mounted) {
        showAppSnack(context, 'PDF and Excel need the local clinic server.', error: true);
      }
    } catch (error) {
      if (mounted) {
        showAppSnack(context, friendlyError(error, feature: 'report'), error: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _exporting = false;
          _exportFormat = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = ref.watch(sessionProvider).clinic?.currency ?? 'PKR';
    final desktop = AppLayout.isDesktop(context);
    return Scaffold(
      appBar: buildAppBar(
        context: context,
        title: widget.title,
        fallback: widget.backTo,
      ),
      body: AppPageBody(
        padding: AppLayout.pagePadding(context, top: 8, bottom: 8),
        child: RefreshIndicator(
          onRefresh: () => _load(force: true),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.only(bottom: AppLayout.pagePadding(context).bottom),
            children: [
              PeriodSelector(
                value: _period,
                onChanged: (value) async {
                  if (value == FinancePeriod.custom) {
                    final picked = await pickInclusiveDateRange(context, from: _from, to: _to);
                    if (picked == null) {
                      return;
                    }
                    _from = DateTime(picked.start.year, picked.start.month, picked.start.day);
                    _to = DateTime(picked.end.year, picked.end.month, picked.end.day);
                  }
                  setState(() => _period = value);
                  await _load();
                },
              ),
              const SizedBox(height: 12),
              Text(
                'Report dates: ${formatDisplayDateRange(_range.from, _range.to)} (inclusive)',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 12),
              if (_syncing) ...[
                const LinearProgressIndicator(minHeight: 2),
                const SizedBox(height: 12),
              ],
              if (_loadError != null) ...[
                StatusBanner.error(_loadError!, onRetry: () => _load(force: true)),
                const SizedBox(height: 12),
              ],
              AppStateSwitch(
                child: _loading
                ? const SkeletonCards(key: ValueKey('report-skeleton'), count: 3)
                : Column(
                    key: const ValueKey('report-body'),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                ResponsiveGrid(
                  minItemWidth: 240,
                  children: [
                    SummaryCard(label: 'Income', value: formatMoney(_income, currency: currency), color: AppColors.success, icon: Icons.trending_up_rounded),
                    SummaryCard(label: 'Expenses', value: formatMoney(_expenses, currency: currency), color: AppColors.danger, icon: Icons.trending_down_rounded),
                    SummaryCard(label: 'Profit', value: formatMoney(_profit, currency: currency), icon: Icons.account_balance_wallet_outlined),
                  ],
                ),
                const SizedBox(height: 8),
                if (desktop)
                  AppSplit(
                    primary: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SectionHeader('Income by treatment'),
                        _amountCard(_incomeBreakdown, currency, empty: 'No income in this range.'),
                      ],
                    ),
                    secondary: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SectionHeader('Expenses by category'),
                        _amountCard(_expenseBreakdown, currency, empty: 'No activity in this range.'),
                      ],
                    ),
                  )
                else ...[
                  const SectionHeader('Income by treatment'),
                  _amountCard(_incomeBreakdown, currency, empty: 'No income in this range.'),
                  const SectionHeader('Expenses by category'),
                  _amountCard(_expenseBreakdown, currency, empty: 'No activity in this range.'),
                ],
                const SectionHeader('Timeline'),
                _amountCard(_timeline, currency, empty: 'No daily totals yet.'),
                const SizedBox(height: 8),
                if (desktop)
                  Row(
                    children: [
                      Expanded(
                        child: AppBusyButton(
                          onPressed: _exporting ? null : () => _export('pdf'),
                          busy: _exporting && _exportFormat == 'pdf',
                          busyLabel: 'Exporting…',
                          icon: Icons.picture_as_pdf_outlined,
                          label: 'Export PDF',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: AppBusyButton(
                          outlined: true,
                          onPressed: _exporting ? null : () => _export('xlsx'),
                          busy: _exporting && _exportFormat == 'xlsx',
                          busyLabel: 'Exporting…',
                          icon: Icons.table_view_outlined,
                          label: 'Export Excel',
                        ),
                      ),
                    ],
                  )
                else ...[
                  Stretch(
                    child: AppBusyButton(
                      onPressed: _exporting ? null : () => _export('pdf'),
                      busy: _exporting && _exportFormat == 'pdf',
                      busyLabel: 'Exporting…',
                      icon: Icons.picture_as_pdf_outlined,
                      label: 'Export PDF',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Stretch(
                    child: AppBusyButton(
                      outlined: true,
                      onPressed: _exporting ? null : () => _export('xlsx'),
                      busy: _exporting && _exportFormat == 'xlsx',
                      busyLabel: 'Exporting…',
                      icon: Icons.table_view_outlined,
                      label: 'Export Excel',
                    ),
                  ),
                ],
                    ],
                  ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _amountCard(List<NamedAmount> items, String currency, {required String empty, Color? color}) {
    return Card(
      child: items.isEmpty
          ? EmptyState(message: empty)
          : Column(children: [for (final item in items) _row(item, currency, color: color)]),
    );
  }

  Widget _row(NamedAmount item, String currency, {Color? color}) {
    return ListTile(
      title: Text(formatDisplayDateLabel(item.name), maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 140),
        child: MoneyText(
          formatMoney(item.amount, currency: currency),
          style: Theme.of(context).textTheme.titleSmall,
          color: color,
        ),
      ),
    );
  }
}

class ClinicReportsScreen extends StatelessWidget {
  const ClinicReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ReportsScreen();
  }
}
