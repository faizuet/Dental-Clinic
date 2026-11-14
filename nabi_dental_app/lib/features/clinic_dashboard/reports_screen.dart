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
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/page_kit.dart';
import '../../core/widgets/period_selector.dart';
import '../../core/widgets/status_banner.dart';
enum ReportKind { clinic, home }

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({
    super.key,
    this.title = 'Clinic reports',
    this.backTo = '/clinic',
    this.kind = ReportKind.clinic,
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
  String _labCharges = '0.00';
  List<NamedAmount> _incomeBreakdown = [];
  List<NamedAmount> _expenseBreakdown = [];
  List<NamedAmount> _labBreakdown = [];
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
        _load(silent: true, localOnly: true);
      }
    });
    _load();
  }

  bool get _isHome => widget.kind == ReportKind.home;

  Future<void> _apply(FinanceRepository repo) async {
    final token = _loadToken;
    if (_isHome) {
      final expenses = await repo.homeExpenseHistory(range: _range);
      final expenseTotal = expenses.fold<double>(0, (sum, item) => sum + moneyToDouble(item.amount));
      final byCategory = await repo.breakdown(expenses);
      final expenseTimeline = await repo.timeline(expenses);
      final totals = await repo.homeTotals(
        _range,
        defaultBudget: ref.read(sessionProvider).user?.defaultHomeBudget ?? '30000.00',
      );
      if (!mounted || token != _loadToken) {
        return;
      }
      setState(() {
        _income = totals.budget;
        _expenses = moneyFromDouble(expenseTotal);
        _profit = totals.remaining;
        _incomeBreakdown = const [];
        _expenseBreakdown = byCategory;
        _timeline = expenseTimeline;
        _loading = false;
      });
      return;
    }
    final income = await repo.incomeHistory(range: _range);
    final expenses = await repo.clinicExpenseHistory(range: _range);
    final labCharges = await repo.labChargeHistory(range: _range);
    final incomeTotal = income.fold<double>(0, (sum, item) => sum + moneyToDouble(item.amount));
    final expenseTotal = expenses.fold<double>(0, (sum, item) => sum + moneyToDouble(item.amount));
    final labTotal = labCharges.fold<double>(0, (sum, item) => sum + moneyToDouble(item.amount));
    final byTreatment = await repo.breakdown(income);
    final byCategory = await repo.breakdown(expenses);
    final byLab = await repo.breakdown(labCharges);
    final incomeTimeline = await repo.timeline(income);
    final expenseTimeline = await repo.timeline(expenses);
    if (!mounted || token != _loadToken) {
      return;
    }
    setState(() {
      _income = moneyFromDouble(incomeTotal);
      _expenses = moneyFromDouble(expenseTotal);
      _labCharges = moneyFromDouble(labTotal);
      _profit = moneyFromDouble(incomeTotal - expenseTotal - labTotal);
      _incomeBreakdown = byTreatment;
      _expenseBreakdown = byCategory;
      _labBreakdown = byLab;
      _timeline = [...incomeTimeline, ...expenseTimeline];
      _loading = false;
    });
  }

  var _loadToken = 0;

  Future<void> _load({bool silent = false, bool force = false, bool localOnly = false}) async {
    final token = ++_loadToken;
    if (!silent && _incomeBreakdown.isEmpty && _expenseBreakdown.isEmpty) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    try {
      final repo = ref.read(financeRepositoryProvider);
      await _apply(repo);
      if (!mounted || token != _loadToken) {
        return;
      }
      if (localOnly) {
        setState(() => _syncing = false);
        return;
      }
      setState(() => _syncing = true);
      await repo.refresh(force: force);
      await _apply(repo);
      if (!mounted || token != _loadToken) {
        return;
      }
      setState(() => _syncing = false);
    } catch (error) {
      if (mounted && token == _loadToken) {
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
      final repo = ref.read(financeRepositoryProvider);
      final file = _isHome
          ? await repo.exportHome(range: _range, format: format)
          : await repo.exportClinic(range: _range, format: format);
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
    return Scaffold(
      appBar: buildAppBar(
        context: context,
        title: widget.title,
        fallback: widget.backTo,
      ),
      body: PageScaffoldBody(
        onRefresh: () => _load(force: true),
        children: [
          PageHeader(
            icon: _isHome ? Icons.pie_chart_rounded : Icons.insert_chart_rounded,
            title: _isHome ? 'Home Reports' : 'Reports & Analytics',
            subtitle: _isHome
                ? 'Household spending against your monthly budget'
                : 'Income, clinic expenses, lab charges, and profit for any period',
            color: _isHome ? AppColors.aqua : AppColors.primary,
            soft: _isHome ? AppColors.aquaSoft : AppColors.primarySoft,
            actions: [
              AppBusyButton(
                outlined: true,
                onPressed: _exporting ? null : () => _export('xlsx'),
                busy: _exporting && _exportFormat == 'xlsx',
                busyLabel: 'Exporting…',
                icon: Icons.table_view_outlined,
                label: 'Export Excel',
              ),
              AppBusyButton(
                onPressed: _exporting ? null : () => _export('pdf'),
                busy: _exporting && _exportFormat == 'pdf',
                busyLabel: 'Exporting…',
                icon: Icons.picture_as_pdf_outlined,
                label: 'Export PDF',
              ),
            ],
          ),
          const SizedBox(height: 20),
          _periodPanel(),
          const SizedBox(height: 16),
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
                      StatStrip(items: _stats(currency)),
                      const SizedBox(height: 20),
                      ..._breakdowns(currency),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _periodPanel() {
    return TablePanel(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Wrap(
          spacing: 16,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          alignment: WrapAlignment.spaceBetween,
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
            IconText(
              icon: Icons.calendar_month_rounded,
              text: '${formatDisplayDateRange(_range.from, _range.to)} (inclusive)',
              muted: true,
            ),
          ],
        ),
      ),
    );
  }

  List<MiniStat> _stats(String currency) {
    final negative = moneyToDouble(_profit) < 0;
    if (_isHome) {
      return [
        MiniStat(
          label: 'Spending',
          value: formatMoney(_expenses, currency: currency),
          icon: Icons.shopping_bag_rounded,
          color: AppColors.orange,
          soft: AppColors.warningSoft,
        ),
        MiniStat(
          label: 'Monthly Budget',
          value: formatMoney(_income, currency: currency),
          icon: Icons.savings_rounded,
          color: AppColors.primary,
          soft: AppColors.primarySoft,
        ),
        MiniStat(
          label: negative ? 'Over Budget' : 'Remaining',
          value: formatMoney(_profit, currency: currency),
          icon: Icons.account_balance_wallet_rounded,
          color: negative ? AppColors.danger : AppColors.success,
          soft: negative ? AppColors.dangerSoft : AppColors.mintSoft,
        ),
      ];
    }
    return [
      MiniStat(
        label: 'Income',
        value: formatMoney(_income, currency: currency),
        icon: Icons.trending_up_rounded,
        color: AppColors.success,
        soft: AppColors.mintSoft,
      ),
      MiniStat(
        label: 'Clinic Expenses',
        value: formatMoney(_expenses, currency: currency),
        icon: Icons.trending_down_rounded,
        color: AppColors.orange,
        soft: AppColors.warningSoft,
      ),
      MiniStat(
        label: 'Lab Charges',
        value: formatMoney(_labCharges, currency: currency),
        icon: Icons.science_rounded,
        color: AppColors.violet,
        soft: AppColors.violetSoft,
      ),
      MiniStat(
        label: negative ? 'Loss' : 'Profit',
        value: formatMoney(_profit, currency: currency),
        icon: Icons.account_balance_wallet_rounded,
        color: negative ? AppColors.danger : AppColors.primary,
        soft: negative ? AppColors.dangerSoft : AppColors.primarySoft,
        caption: 'After lab',
      ),
    ];
  }

  List<Widget> _breakdowns(String currency) {
    final timeline = _panel(
      title: 'Timeline',
      subtitle: 'Daily totals in this period',
      icon: Icons.timeline_rounded,
      color: AppColors.primary,
      soft: AppColors.primarySoft,
      items: _timeline,
      currency: currency,
      empty: 'No daily totals yet.',
      bars: false,
    );
    if (_isHome) {
      return [
        _panel(
          title: 'Expenses by category',
          subtitle: 'Where household money went',
          icon: Icons.category_rounded,
          color: AppColors.aqua,
          soft: AppColors.aquaSoft,
          items: _expenseBreakdown,
          currency: currency,
          empty: 'No household spending in this range.',
        ),
        const SizedBox(height: 20),
        timeline,
      ];
    }
    final income = _panel(
      title: 'Income by treatment',
      subtitle: 'Fees collected per treatment',
      icon: Icons.medical_services_rounded,
      color: AppColors.success,
      soft: AppColors.mintSoft,
      items: _incomeBreakdown,
      currency: currency,
      empty: 'No income in this range.',
    );
    final expenses = _panel(
      title: 'Expenses by category',
      subtitle: 'Clinic running costs',
      icon: Icons.receipt_long_rounded,
      color: AppColors.orange,
      soft: AppColors.warningSoft,
      items: _expenseBreakdown,
      currency: currency,
      empty: 'No activity in this range.',
    );
    final labs = _panel(
      title: 'Lab charges by lab',
      subtitle: 'Lab work costs per lab',
      icon: Icons.science_rounded,
      color: AppColors.violet,
      soft: AppColors.violetSoft,
      items: _labBreakdown,
      currency: currency,
      empty: 'No lab charges in this range.',
    );
    return [
      AppSplit(breakpoint: 900, primaryFlex: 1, secondaryFlex: 1, primary: income, secondary: expenses),
      const SizedBox(height: 20),
      AppSplit(breakpoint: 900, primaryFlex: 1, secondaryFlex: 1, primary: labs, secondary: timeline),
    ];
  }

  Widget _panel({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required Color soft,
    required List<NamedAmount> items,
    required String currency,
    required String empty,
    bool bars = true,
  }) {
    final total = items.fold<double>(0, (sum, item) => sum + moneyToDouble(item.amount));
    return TablePanel(
      header: PanelTitle(
        title: title,
        subtitle: subtitle,
        icon: icon,
        color: color,
        soft: soft,
        trailing: items.isEmpty ? null : StatusPill(label: '${items.length}', color: color, soft: soft),
      ),
      footer: items.isEmpty
          ? null
          : Row(
              children: [
                const Expanded(child: Text('Total', style: TextStyle(fontWeight: FontWeight.w700))),
                MoneyText(
                  formatMoney(moneyFromDouble(total), currency: currency),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                  color: color,
                ),
              ],
            ),
      child: items.isEmpty
          ? EmptyState(message: empty)
          : Column(
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) const Divider(height: 1, indent: 20, endIndent: 20),
                  _row(items[i], currency, color: color, share: bars && total > 0 ? moneyToDouble(items[i].amount) / total : null),
                ],
              ],
            ),
    );
  }

  Widget _row(NamedAmount item, String currency, {required Color color, double? share}) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  formatDisplayDateLabel(item.name),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              if (share != null) ...[
                Text('${(share * 100).toStringAsFixed(share >= 0.1 ? 0 : 1)}%', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.muted)),
                const SizedBox(width: 12),
              ],
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 160),
                child: MoneyText(formatMoney(item.amount, currency: currency), style: theme.textTheme.titleSmall),
              ),
            ],
          ),
          if (share != null) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadii.full),
              child: LinearProgressIndicator(
                value: share.clamp(0, 1).toDouble(),
                minHeight: 6,
                color: color,
                backgroundColor: color.withValues(alpha: 0.12),
              ),
            ),
          ],
        ],
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

class HomeReportsScreen extends StatelessWidget {
  const HomeReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ReportsScreen(
      title: 'Home reports',
      backTo: '/home',
      kind: ReportKind.home,
    );
  }
}
