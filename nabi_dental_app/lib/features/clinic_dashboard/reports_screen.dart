import 'dart:math' as math;

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
          const SizedBox(height: 12),
          _periodPanel(),
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
                      StatStrip(items: _stats(currency)),
                      const SizedBox(height: 4),
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
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
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
      chart: _ReportChart.columns,
    );
    if (_isHome) {
      return [
        _ReportBoard(
          wide: [
            _panel(
              title: 'Expenses by category',
              subtitle: 'Where household money went',
              icon: Icons.category_rounded,
              color: AppColors.aqua,
              soft: AppColors.aquaSoft,
              items: _expenseBreakdown,
              currency: currency,
              empty: 'No household spending in this range.',
              chart: _shareChart(_expenseBreakdown),
            ),
            timeline,
          ],
          flexes: const [5, 6],
        ),
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
      chart: _ReportChart.bars,
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
      chart: _shareChart(_expenseBreakdown),
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
      chart: _labChart(_labBreakdown),
    );
    return [
      LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 980) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                income,
                const SizedBox(height: 12),
                expenses,
                const SizedBox(height: 12),
                labs,
                const SizedBox(height: 12),
                timeline,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 6, child: income),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 5,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        expenses,
                        const SizedBox(height: 12),
                        labs,
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              timeline,
            ],
          );
        },
      ),
    ];
  }

  _ReportChart _shareChart(List<NamedAmount> items) {
    if (items.length >= 2 && items.length <= 6) {
      return _ReportChart.ring;
    }
    return _ReportChart.bars;
  }

  _ReportChart _labChart(List<NamedAmount> items) {
    if (items.length >= 2 && items.length <= 4) {
      return _ReportChart.share;
    }
    return _ReportChart.bars;
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
    required _ReportChart chart,
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
          : _ReportChartView(
              items: items,
              currency: currency,
              color: color,
              soft: soft,
              icon: icon,
              total: total,
              chart: chart,
            ),
    );
  }
}

enum _ReportChart { bars, ring, share, columns }

class _ReportBoard extends StatelessWidget {
  const _ReportBoard({required this.wide, this.flexes = const [1, 1]});

  final List<Widget> wide;
  final List<int> flexes;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 900 || wide.length < 2) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < wide.length; i++) ...[
                if (i > 0) const SizedBox(height: 12),
                wide[i],
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < wide.length; i++) ...[
              if (i > 0) const SizedBox(width: 12),
              Expanded(flex: flexes[i], child: wide[i]),
            ],
          ],
        );
      },
    );
  }
}

class _ReportChartView extends StatelessWidget {
  const _ReportChartView({
    required this.items,
    required this.currency,
    required this.color,
    required this.soft,
    required this.icon,
    required this.total,
    required this.chart,
  });

  final List<NamedAmount> items;
  final String currency;
  final Color color;
  final Color soft;
  final IconData icon;
  final double total;
  final _ReportChart chart;

  @override
  Widget build(BuildContext context) {
    return switch (chart) {
      _ReportChart.bars => _RankedBars(items: items, currency: currency, color: color, total: total),
      _ReportChart.ring => _ShareRing(
          items: items,
          currency: currency,
          color: color,
          soft: soft,
          icon: icon,
          total: total,
        ),
      _ReportChart.share => _StackedShare(items: items, currency: currency, color: color, total: total),
      _ReportChart.columns => _ColumnChart(items: items, currency: currency, color: color, soft: soft),
    };
  }
}

class _RankedBars extends StatelessWidget {
  const _RankedBars({required this.items, required this.currency, required this.color, required this.total});

  final List<NamedAmount> items;
  final String currency;
  final Color color;
  final double total;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        children: [
          for (final item in items)
            _BarRow(item: item, currency: currency, color: color, total: total),
        ],
      ),
    );
  }
}

class _BarRow extends StatelessWidget {
  const _BarRow({required this.item, required this.currency, required this.color, required this.total});

  final NamedAmount item;
  final String currency;
  final Color color;
  final double total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final amount = moneyToDouble(item.amount);
    final share = total > 0 ? amount / total : 0.0;
    final label = formatDisplayDateLabel(item.name);
    final money = formatMoney(item.amount, currency: currency);
    final percent = _percentLabel(share);
    return Tooltip(
      message: _chartTip(label, money, percent),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                Text(percent, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.muted)),
                const SizedBox(width: 10),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 148),
                  child: Text(
                    money,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadii.full),
              child: SizedBox(
                height: 8,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(color: color.withValues(alpha: 0.12)),
                    FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: share.clamp(0, 1).toDouble(),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [color.withValues(alpha: 0.72), color]),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShareRing extends StatelessWidget {
  const _ShareRing({
    required this.items,
    required this.currency,
    required this.color,
    required this.soft,
    required this.icon,
    required this.total,
  });

  final List<NamedAmount> items;
  final String currency;
  final Color color;
  final Color soft;
  final IconData icon;
  final double total;

  @override
  Widget build(BuildContext context) {
    final colors = _chartColors(color, items.length);
    final shares = [for (final item in items) total > 0 ? moneyToDouble(item.amount) / total : 0.0];
    final ring = SizedBox(
      width: 124,
      height: 124,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size.square(124),
            painter: _DonutPainter(shares: shares, colors: colors),
          ),
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(color: soft, shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 26),
          ),
        ],
      ),
    );
    final legend = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < items.length; i++)
          _LegendLine(
            color: colors[i],
            label: formatDisplayDateLabel(items[i].name),
            amount: formatMoney(items[i].amount, currency: currency),
            percent: _percentLabel(shares[i]),
          ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 380) {
            return Column(
              children: [
                ring,
                const SizedBox(height: 8),
                legend,
              ],
            );
          }
          return Row(
            children: [
              ring,
              const SizedBox(width: 16),
              Expanded(child: legend),
            ],
          );
        },
      ),
    );
  }
}

class _StackedShare extends StatelessWidget {
  const _StackedShare({required this.items, required this.currency, required this.color, required this.total});

  final List<NamedAmount> items;
  final String currency;
  final Color color;
  final double total;

  @override
  Widget build(BuildContext context) {
    final colors = _chartColors(color, items.length);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 14,
              child: Row(
                children: [
                  for (var i = 0; i < items.length; i++)
                    Expanded(
                      flex: math.max(1, (total > 0 ? moneyToDouble(items[i].amount) / total * 1000 : 1).round()),
                      child: Tooltip(
                        message: _chartTip(
                          formatDisplayDateLabel(items[i].name),
                          formatMoney(items[i].amount, currency: currency),
                          _percentLabel(total > 0 ? moneyToDouble(items[i].amount) / total : 0),
                        ),
                        child: ColoredBox(color: colors[i]),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < items.length; i++)
            _LegendLine(
              color: colors[i],
              label: formatDisplayDateLabel(items[i].name),
              amount: formatMoney(items[i].amount, currency: currency),
              percent: _percentLabel(total > 0 ? moneyToDouble(items[i].amount) / total : 0),
            ),
        ],
      ),
    );
  }
}

class _ColumnChart extends StatelessWidget {
  const _ColumnChart({
    required this.items,
    required this.currency,
    required this.color,
    required this.soft,
  });

  final List<NamedAmount> items;
  final String currency;
  final Color color;
  final Color soft;

  @override
  Widget build(BuildContext context) {
    final maxAmount = items.fold<double>(0, (max, item) {
      final value = moneyToDouble(item.amount);
      return value > max ? value : max;
    });
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const slot = 116.0;
          final scroll = items.length > 12;
          final expand = !scroll && items.length * slot > constraints.maxWidth;
          final showAmount = items.length <= 8;
          final columns = [
            for (final item in items)
              _ColumnMark(
                label: formatDisplayDateLabel(item.name),
                amount: formatMoney(item.amount, currency: currency),
                factor: maxAmount > 0 ? moneyToDouble(item.amount) / maxAmount : 0,
                color: color,
                showAmount: showAmount,
                expand: expand,
              ),
          ];
          final row = Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: columns,
          );
          final chart = DecoratedBox(
            decoration: BoxDecoration(
              color: soft.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 12, 8, 10),
              child: scroll ? SingleChildScrollView(scrollDirection: Axis.horizontal, child: row) : row,
            ),
          );
          if (expand || scroll) {
            return chart;
          }
          return Align(alignment: Alignment.center, child: chart);
        },
      ),
    );
  }
}

class _ColumnMark extends StatelessWidget {
  const _ColumnMark({
    required this.label,
    required this.amount,
    required this.factor,
    required this.color,
    required this.showAmount,
    required this.expand,
  });

  final String label;
  final String amount;
  final double factor;
  final Color color;
  final bool showAmount;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final heightFactor = factor <= 0 ? 0.0 : factor.clamp(0.08, 1.0).toDouble();
    final mark = Tooltip(
        message: _chartTip(label, amount, null),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (showAmount)
                Text(
                  amount,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700, color: AppColors.text),
                ),
              const SizedBox(height: 6),
              SizedBox(
                height: 78,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: FractionallySizedBox(
                    heightFactor: heightFactor,
                    child: Container(
                      width: 28,
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [color, color.withValues(alpha: 0.55)],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Container(height: 1, color: color.withValues(alpha: 0.18)),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.muted),
              ),
            ],
          ),
        ),
    );
    if (!expand) {
      return SizedBox(width: 116, child: mark);
    }
    return Expanded(child: mark);
  }
}

class _LegendLine extends StatelessWidget {
  const _LegendLine({required this.color, required this.label, required this.amount, required this.percent});

  final Color color;
  final String label;
  final String amount;
  final String percent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: _chartTip(label, amount, percent),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 8),
            Text(percent, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.muted)),
            const SizedBox(width: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 132),
              child: Text(
                amount,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  const _DonutPainter({required this.shares, required this.colors});

  final List<double> shares;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 16.0;
    final rect = Offset.zero & size;
    final arc = rect.deflate(stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;
    final gaps = shares.where((share) => share > 0).length > 1 ? 0.045 : 0.0;
    var start = -math.pi / 2;
    for (var i = 0; i < shares.length; i++) {
      final sweep = math.max(0.0, shares[i] * math.pi * 2 - gaps);
      if (sweep <= 0) {
        continue;
      }
      paint.color = colors[i % colors.length];
      canvas.drawArc(arc, start, sweep, false, paint);
      start += shares[i] * math.pi * 2;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) {
    return oldDelegate.shares != shares || oldDelegate.colors != colors;
  }
}

List<Color> _chartColors(Color base, int count) {
  final hsl = HSLColor.fromColor(base);
  return [
    for (var i = 0; i < count; i++)
      i == 0
          ? base
          : hsl
              .withLightness((hsl.lightness + i * 0.09).clamp(0.34, 0.74))
              .withSaturation((hsl.saturation - i * 0.06).clamp(0.32, 1))
              .toColor(),
  ];
}

String _percentLabel(double share) {
  return '${(share * 100).toStringAsFixed(share >= 0.1 ? 0 : 1)}%';
}

String _chartTip(String label, String amount, String? percent) {
  if (percent == null) {
    return '$label\n$amount';
  }
  return '$label\n$amount · $percent';
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
