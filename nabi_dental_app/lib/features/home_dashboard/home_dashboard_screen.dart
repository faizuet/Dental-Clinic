import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_colors.dart';
import '../../core/auth/session_controller.dart';
import '../../core/finance/finance_repository.dart';
import '../../core/models/finance_models.dart';
import '../../core/utils/dates.dart';
import '../../core/utils/money.dart';
import '../../core/utils/period.dart';
import '../../core/errors/friendly_error.dart';
import '../../core/widgets/app_layout.dart';
import '../../core/widgets/app_navigation.dart';
import '../../core/widgets/app_page.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/app_controls.dart';
import '../../core/widgets/app_motion.dart';
import '../../core/widgets/period_selector.dart';
import '../../core/widgets/status_banner.dart';
import '../../core/widgets/dashboard_tiles.dart';
import '../../core/widgets/page_kit.dart';
import '../../core/widgets/welcome_header.dart';

class HomeDashboardScreen extends ConsumerStatefulWidget {
  const HomeDashboardScreen({super.key});

  @override
  ConsumerState<HomeDashboardScreen> createState() => _HomeDashboardScreenState();
}

class _HomeDashboardScreenState extends ConsumerState<HomeDashboardScreen> {
  FinancePeriod _period = FinancePeriod.monthly;
  DateTime? _customFrom;
  DateTime? _customTo;
  HomeTotals? _totals;
  List<MoneyEntry> _recent = const [];
  bool _loading = true;
  bool _syncing = false;
  bool _online = true;
  String? _loadError;
  var _loadToken = 0;

  @override
  void initState() {
    super.initState();
    ref.listenManual(financeEpochProvider, (previous, next) {
      if (previous != next) {
        _load(silent: true, localOnly: true);
      }
    });
    _load(force: true);
  }

  Future<void> _load({bool silent = false, bool force = false, bool localOnly = false}) async {
    final token = ++_loadToken;
    if (!silent && _totals == null) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    final repo = ref.read(financeRepositoryProvider);
    final range = DateRange.forPeriod(_period, customFrom: _customFrom, customTo: _customTo);
    final defaultBudget = ref.read(sessionProvider).user?.defaultHomeBudget ?? '30000.00';
    try {
      final local = await repo.homeTotals(range, defaultBudget: defaultBudget);
      final localRecent = await repo.recentHomeExpenses();
      if (!mounted || token != _loadToken) {
        return;
      }
      setState(() {
        _totals = local;
        _recent = localRecent;
        _loading = false;
        _syncing = !localOnly;
        _loadError = null;
      });
      if (localOnly) {
        return;
      }
      final online = await repo.refresh(force: force);
      final totals = await repo.homeTotals(range, defaultBudget: defaultBudget);
      final recent = await repo.recentHomeExpenses();
      if (!mounted || token != _loadToken) {
        return;
      }
      setState(() {
        _online = online;
        _totals = totals;
        _recent = recent;
        _loading = false;
        _syncing = false;
      });
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

  @override
  Widget build(BuildContext context) {
    final currency = ref.watch(sessionProvider).clinic?.currency ?? 'PKR';
    final totals = _totals;
    final session = ref.watch(sessionProvider);
    return Scaffold(
      appBar: buildAppBar(
        context: context,
        title: 'Dashboard',
        isRoot: true,
        fallback: '/home',
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _syncing ? null : () => _load(force: true),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: AppPageBody(
        padding: AppLayout.pagePadding(context, top: 0, bottom: 8),
        child: RefreshIndicator(
          onRefresh: () => _load(force: true),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.only(bottom: AppLayout.pagePadding(context).bottom),
            children: [
              WelcomeHeader(
                title: 'Hello, ${session.user?.fullName ?? 'there'}',
                subtitle: 'Home grocery  ·  Household spending',
                icon: Icons.home_rounded,
              ),
              const SizedBox(height: 20),
              PeriodSelector(
                value: _period,
                onChanged: (value) async {
                  if (value == FinancePeriod.custom) {
                    final picked = await pickInclusiveDateRange(context, from: _customFrom, to: _customTo);
                    if (picked == null) {
                      return;
                    }
                    _customFrom = DateTime(picked.start.year, picked.start.month, picked.start.day);
                    _customTo = DateTime(picked.end.year, picked.end.month, picked.end.day);
                  }
                  setState(() => _period = value);
                  await _load();
                },
              ),
              if (_syncing) ...[
                const SizedBox(height: 8),
                const LinearProgressIndicator(minHeight: 2),
              ],
              if (_loadError != null) ...[
                const SizedBox(height: 12),
                StatusBanner.error(_loadError!, onRetry: () => _load(force: true)),
              ] else if (!_online) ...[
                const SizedBox(height: 12),
                StatusBanner.offline('Showing local household records. Sync when you are back online.', onRetry: () => _load(force: true)),
              ],
              const SizedBox(height: 16),
              AppStateSwitch(
                child: _loading && totals == null
                    ? const SkeletonCards(key: ValueKey('home-skeleton'))
                    : totals == null
                        ? const EmptyState(key: ValueKey('home-empty'), message: 'No household totals yet.')
                        : AppReveal(
                            child: Column(
                              key: const ValueKey('home-totals'),
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                IconText(
                                  icon: Icons.calendar_month_rounded,
                                  text: formatDisplayDateRange(totals.range.from, totals.range.to),
                                  muted: true,
                                ),
                                const SizedBox(height: 12),
                                _statCards(totals, currency),
                              ],
                            ),
                          ),
              ),
              const SizedBox(height: 12),
              _sectionTitle(Icons.bolt_rounded, 'Quick Actions'),
              ResponsiveGrid(
                minItemWidth: 230,
                runSpacing: 12,
                children: [
                  QuickActionTile(
                    title: 'Add Home Expense',
                    subtitle: 'Record grocery spending',
                    icon: Icons.add_shopping_cart_rounded,
                    colors: const [Color(0xFF2DBFA6), AppColors.aqua],
                    onTap: () => _open('/home/expenses'),
                  ),
                  QuickActionTile(
                    title: 'Set Monthly Budget',
                    subtitle: 'Plan household spending',
                    icon: Icons.savings_rounded,
                    colors: const [AppColors.secondary, AppColors.primaryDark],
                    onTap: () => _open('/home/budget'),
                  ),
                  QuickActionTile(
                    title: 'All Expenses',
                    subtitle: 'Search and edit records',
                    icon: Icons.receipt_long_rounded,
                    colors: const [Color(0xFFF7AE5C), AppColors.orange],
                    onTap: () => _open('/home/expenses/history'),
                  ),
                  QuickActionTile(
                    title: 'Home Reports',
                    subtitle: 'Spending by category',
                    icon: Icons.pie_chart_rounded,
                    colors: const [Color(0xFF9479E0), AppColors.violet],
                    onTap: () => _open('/home/reports'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (totals != null)
                AppSplit(
                  breakpoint: 900,
                  primaryFlex: 3,
                  secondaryFlex: 2,
                  primary: _recentExpenses(currency),
                  secondary: _budgetPanel(totals, currency),
                )
              else
                _recentExpenses(currency),
            ],
          ),
        ),
      ),
    );
  }

  void _open(String path) => appPushAndRefresh(context, path, () => _load(silent: true));

  Widget _statCards(HomeTotals totals, String currency) {
    final over = moneyToDouble(totals.remaining) < 0;
    return ResponsiveGrid(
      minItemWidth: 220,
      runSpacing: 12,
      children: [
        StatCard(
          label: 'Spending',
          value: formatMoney(totals.spent, currency: currency),
          color: AppColors.orange,
          background: AppColors.warningSoft,
          icon: Icons.shopping_bag_rounded,
          onTap: () => _open('/home/expenses/history'),
        ),
        StatCard(
          label: 'Monthly Budget',
          value: formatMoney(totals.budget, currency: currency),
          color: AppColors.primary,
          background: AppColors.primarySoft,
          icon: Icons.savings_rounded,
          actionLabel: 'Change',
          onTap: () => _open('/home/budget'),
        ),
        StatCard(
          label: over ? 'Over Budget' : 'Remaining',
          value: formatMoney(totals.remaining, currency: currency),
          color: over ? AppColors.danger : AppColors.success,
          background: over ? AppColors.dangerSoft : AppColors.mintSoft,
          icon: Icons.account_balance_wallet_rounded,
          onTap: () => _open('/home/reports'),
        ),
        StatCard(
          label: 'Budget Used',
          value: totals.percentageUsed == null ? '—' : '${totals.percentageUsed}%',
          color: AppColors.aqua,
          background: AppColors.aquaSoft,
          icon: Icons.donut_large_rounded,
          onTap: () => _open('/home/reports'),
        ),
      ],
    );
  }

  Widget _sectionTitle(IconData icon, String label) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 12),
      child: Row(
        children: [
          Icon(icon, color: AppColors.warning, size: 22),
          const SizedBox(width: 6),
          Text(label, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }

  Widget _budgetPanel(HomeTotals totals, String currency) {
    final theme = Theme.of(context);
    final used = double.tryParse(totals.percentageUsed ?? '');
    final over = moneyToDouble(totals.remaining) < 0;
    final color = over ? AppColors.danger : (used != null && used >= 80 ? AppColors.orange : AppColors.success);
    return DashboardPanel(
      title: 'Budget Overview',
      actionLabel: 'Change',
      onAction: () => _open('/home/budget'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    used == null ? 'No budget set' : '${totals.percentageUsed}% used',
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: color),
                  ),
                ),
                StatusPill(
                  label: over ? 'Over budget' : 'On track',
                  color: over ? AppColors.danger : AppColors.success,
                  soft: over ? AppColors.dangerSoft : AppColors.successSoft,
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadii.full),
              child: LinearProgressIndicator(
                value: ((used ?? 0) / 100).clamp(0, 1).toDouble(),
                minHeight: 10,
                color: color,
                backgroundColor: color.withValues(alpha: 0.12),
              ),
            ),
            const SizedBox(height: 16),
            _budgetLine('Spent', formatMoney(totals.spent, currency: currency), AppColors.orange),
            const Divider(height: 20),
            _budgetLine('Budget', formatMoney(totals.budget, currency: currency), AppColors.primary),
            const Divider(height: 20),
            _budgetLine(over ? 'Over by' : 'Remaining', formatMoney(totals.remaining, currency: currency), over ? AppColors.danger : AppColors.success),
          ],
        ),
      ),
    );
  }

  Widget _budgetLine(String label, String value, Color color) {
    return Row(
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 10),
        Expanded(child: Text(label, style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600))),
        MoneyText(value, style: Theme.of(context).textTheme.titleSmall),
      ],
    );
  }

  Widget _recentExpenses(String currency) {
    final theme = Theme.of(context);
    final header = theme.textTheme.bodySmall?.copyWith(color: AppColors.muted, fontWeight: FontWeight.w700);
    return DashboardPanel(
      title: 'Recent Home Expenses',
      actionLabel: 'All expenses',
      onAction: () => _open('/home/expenses/history'),
      child: _recent.isEmpty
          ? Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
              child: Text(
                'Grocery and household spending will show up here.',
                style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.muted),
              ),
            )
          : Column(
              children: [
                Container(
                  color: AppColors.tableHeader,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  child: Row(
                    children: [
                      Expanded(flex: 5, child: Text('Item', style: header)),
                      Expanded(flex: 3, child: Text('Date', style: header)),
                      Expanded(flex: 3, child: Text('Amount', style: header, textAlign: TextAlign.right)),
                    ],
                  ),
                ),
                for (var index = 0; index < _recent.length; index++) ...[
                  if (index > 0) const Divider(height: 1),
                  _recentRow(_recent[index], currency),
                ],
              ],
            ),
    );
  }

  Widget _recentRow(MoneyEntry item, String currency) {
    final theme = Theme.of(context);
    final name = item.catalogName.isEmpty ? 'Home expense' : item.catalogName;
    return InkWell(
      onTap: () => _open('/home/expenses/history'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        child: Row(
          children: [
            Expanded(
              flex: 5,
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(color: AppColors.aquaSoft, borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.shopping_basket_rounded, size: 18, color: AppColors.aqua),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
                        if ((item.notes ?? '').isNotEmpty)
                          Text(item.notes!, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.muted)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(flex: 3, child: Text(formatDisplayDate(item.date), maxLines: 1, overflow: TextOverflow.ellipsis)),
            Expanded(
              flex: 3,
              child: MoneyText(formatMoney(item.amount, currency: currency), style: theme.textTheme.titleSmall, color: AppColors.aqua),
            ),
          ],
        ),
      ),
    );
  }
}
