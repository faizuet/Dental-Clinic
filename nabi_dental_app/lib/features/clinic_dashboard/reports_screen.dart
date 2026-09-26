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

enum ReportKind { clinic, home, construction }

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({
    super.key,
    required this.title,
    required this.backTo,
    required this.kind,
  });

  final String title;
  final String backTo;
  final ReportKind kind;

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
  int _purchaseCount = 0;
  List<NamedAmount> _incomeBreakdown = [];
  List<NamedAmount> _expenseBreakdown = [];
  List<NamedAmount> _materialBreakdown = [];
  List<NamedAmount> _supplierBreakdown = [];
  List<NamedAmount> _topMaterials = [];
  List<NamedAmount> _timeline = [];
  List<ConstructionPurchase> _recentPurchases = [];
  bool _loading = true;
  bool _exporting = false;
  String? _exportFormat;
  String? _loadError;

  DateRange get _range => DateRange.forPeriod(_period, customFrom: _from, customTo: _to);
  bool get _isClinic => widget.kind == ReportKind.clinic;
  bool get _isHome => widget.kind == ReportKind.home;
  bool get _isConstruction => widget.kind == ReportKind.construction;

  Color get _accent => _isConstruction ? AppColors.teal : AppColors.purple;

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
      if (_isClinic) {
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
      } else if (_isHome) {
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
      } else {
        await repo.ensureConstructionCatalog();
        final totals = await repo.constructionTotals(_range);
        if (mounted) {
          setState(() {
            _expenses = totals.spent;
            _purchaseCount = totals.purchaseCount;
            _expenseBreakdown = totals.byCategory;
            _materialBreakdown = totals.byMaterial;
            _supplierBreakdown = totals.bySupplier;
            _topMaterials = totals.topMaterials;
            _timeline = totals.monthly;
            _recentPurchases = totals.recent;
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
    if (_exporting) {
      return;
    }
    setState(() {
      _exporting = true;
      _exportFormat = format;
    });
    try {
      final repo = ref.read(financeRepositoryProvider);
      final file = switch (widget.kind) {
        ReportKind.clinic => await repo.exportClinic(range: _range, format: format),
        ReportKind.home => await repo.exportHome(range: _range, format: format),
        ReportKind.construction => await repo.exportConstruction(range: _range, format: format),
      };
      await saveBytes(bytes: file.bytes, filename: file.filename, mime: file.mime);
      if (mounted) {
        showAppSnack(context, '${format.toUpperCase()} saved to Downloads');
      }
    } on OfflineException {
      if (mounted) {
        showAppSnack(context, 'PDF and Excel need an internet connection.', error: true);
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
              if (_loadError != null) ...[
                StatusBanner.error(_loadError!, onRetry: _load),
                const SizedBox(height: 12),
              ],
              AppStateSwitch(
                child: _loading
                ? const SkeletonCards(key: ValueKey('report-skeleton'), count: 3)
                : Column(
                    key: const ValueKey('report-body'),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                if (_isClinic) ...[
                  SummaryCard(label: 'Income', value: formatMoney(_income, currency: currency), color: AppColors.success, icon: Icons.trending_up_rounded),
                  SummaryCard(label: 'Expenses', value: formatMoney(_expenses, currency: currency), color: AppColors.danger, icon: Icons.trending_down_rounded),
                  SummaryCard(label: 'Profit', value: formatMoney(_profit, currency: currency), icon: Icons.account_balance_wallet_outlined),
                ] else if (_isHome) ...[
                  SummaryCard(label: 'Spending', value: formatMoney(_expenses, currency: currency), color: AppColors.danger, icon: Icons.shopping_bag_outlined),
                  SummaryCard(label: 'Budget', value: formatMoney(_budget, currency: currency), icon: Icons.savings_outlined),
                  SummaryCard(label: 'Remaining', value: formatMoney(_remaining, currency: currency), color: AppColors.success, icon: Icons.account_balance_wallet_outlined),
                ] else ...[
                  SummaryCard(
                    label: 'Total construction expenses',
                    value: formatMoney(_expenses, currency: currency),
                    color: AppColors.teal,
                    icon: Icons.foundation_outlined,
                  ),
                  SummaryCard(
                    label: 'Purchases',
                    value: '$_purchaseCount',
                    color: AppColors.teal,
                    icon: Icons.inventory_2_outlined,
                  ),
                ],
                const SizedBox(height: 8),
                if (_isClinic) ...[
                  const SectionHeader('Income by treatment'),
                  _amountCard(_incomeBreakdown, currency, empty: 'No income in this range.'),
                  const SectionHeader('Expenses by category'),
                ] else if (_isHome)
                  const SectionHeader('Spending by category')
                else
                  const SectionHeader('Expenses by material category'),
                _amountCard(_expenseBreakdown, currency, empty: 'No activity in this range.', color: _accent),
                if (_isConstruction) ...[
                  const SectionHeader('Material-wise quantity and cost'),
                  _amountCard(_materialBreakdown, currency, empty: 'No material purchases in this range.', color: AppColors.teal),
                  const SectionHeader('Supplier-wise expenses'),
                  _amountCard(_supplierBreakdown, currency, empty: 'No supplier totals in this range.', color: AppColors.teal),
                  const SectionHeader('Highest-cost materials'),
                  _amountCard(_topMaterials, currency, empty: 'No high-cost materials yet.', color: AppColors.teal),
                  const SectionHeader('Recent purchase history'),
                  if (_recentPurchases.isEmpty)
                    const EmptyState(message: 'No purchases in this range yet.')
                  else
                    Card(
                      child: Column(
                        children: [
                          for (final item in _recentPurchases) _purchaseRow(item, currency),
                        ],
                      ),
                    ),
                ],
                SectionHeader(_isConstruction ? 'Monthly expense summary' : 'Timeline'),
                _amountCard(_timeline, currency, empty: 'No daily totals yet.', color: _accent),
                const SizedBox(height: 8),
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

  Widget _purchaseRow(ConstructionPurchase item, String currency) {
    final detail = [
      formatDisplayDate(item.date),
      '${formatQuantity(item.quantity)} ${item.unit}',
      if ((item.categoryName ?? '').isNotEmpty) item.categoryName,
      if ((item.supplier ?? '').isNotEmpty) item.supplier,
    ].join(' · ');
    return ListTile(
      title: Text(item.materialName ?? 'Material', maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(detail, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 140),
        child: MoneyText(
          formatMoney(item.amount, currency: currency),
          style: Theme.of(context).textTheme.titleSmall,
          color: AppColors.teal,
        ),
      ),
    );
  }
}

class ClinicReportsScreen extends StatelessWidget {
  const ClinicReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ReportsScreen(title: 'Clinic reports', backTo: '/clinic', kind: ReportKind.clinic);
  }
}

class HomeReportsScreen extends StatelessWidget {
  const HomeReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ReportsScreen(title: 'Home reports', backTo: '/home', kind: ReportKind.home);
  }
}

class ConstructionReportsScreen extends StatelessWidget {
  const ConstructionReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ReportsScreen(title: 'Construction reports', backTo: '/construction', kind: ReportKind.construction);
  }
}
