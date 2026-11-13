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
import '../../core/widgets/summary_card.dart';
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

  @override
  void initState() {
    super.initState();
    ref.listenManual(financeEpochProvider, (previous, next) {
      if (previous != next) {
        _load(silent: true);
      }
    });
    _load(force: true);
  }

  Future<void> _load({bool silent = false, bool force = false}) async {
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
      if (mounted) {
        setState(() {
          _totals = local;
          _recent = localRecent;
          _loading = false;
          _syncing = true;
          _loadError = null;
        });
      }
      final online = await repo.refresh(force: force);
      final totals = await repo.homeTotals(range, defaultBudget: defaultBudget);
      final recent = await repo.recentHomeExpenses();
      if (mounted) {
        setState(() {
          _online = online;
          _totals = totals;
          _recent = recent;
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

  @override
  Widget build(BuildContext context) {
    final currency = ref.watch(sessionProvider).clinic?.currency ?? 'PKR';
    final totals = _totals;
    final desktop = AppLayout.isDesktop(context);
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
                                Text(
                                  formatDisplayDateRange(totals.range.from, totals.range.to),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w500),
                                ),
                                const SizedBox(height: 12),
                                ResponsiveGrid(
                                  minItemWidth: 240,
                                  children: [
                                    SummaryCard(
                                      label: 'Spending',
                                      value: formatMoney(totals.spent, currency: currency),
                                      color: AppColors.warning,
                                      background: AppColors.warningSoft,
                                      icon: Icons.shopping_bag_outlined,
                                    ),
                                    SummaryCard(
                                      label: 'Monthly budget',
                                      value: formatMoney(totals.budget, currency: currency),
                                      color: AppColors.primary,
                                      background: AppColors.lavenderSoft,
                                      icon: Icons.savings_outlined,
                                    ),
                                    SummaryCard(
                                      label: moneyToDouble(totals.remaining) < 0 ? 'Over budget' : 'Remaining',
                                      value: formatMoney(totals.remaining, currency: currency),
                                      color: moneyToDouble(totals.remaining) < 0 ? AppColors.danger : AppColors.success,
                                      background: moneyToDouble(totals.remaining) < 0 ? AppColors.dangerSoft : AppColors.mintSoft,
                                      icon: Icons.account_balance_wallet_outlined,
                                    ),
                                    SummaryCard(
                                      label: 'Budget used',
                                      value: totals.percentageUsed == null ? '—' : '${totals.percentageUsed}%',
                                      color: AppColors.primary,
                                      background: AppColors.tealSoft,
                                      icon: Icons.pie_chart_outline_rounded,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
              ),
              const SectionHeader('Quick actions'),
              if (desktop)
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        style: _primaryActionStyle,
                        onPressed: () => appPushAndRefresh(context, '/home/expenses', () => _load(silent: true)),
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Add home expense', maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        style: _budgetActionStyle,
                        onPressed: () => appPushAndRefresh(context, '/home/budget', () => _load(silent: true)),
                        icon: const Icon(Icons.savings_outlined),
                        label: const Text('Set monthly budget', maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ],
                )
              else ...[
                Stretch(
                  child: FilledButton.icon(
                    style: _primaryActionStyle,
                    onPressed: () => appPushAndRefresh(context, '/home/expenses', () => _load(silent: true)),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add home expense', maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ),
                const SizedBox(height: 10),
                Stretch(
                  child: FilledButton.icon(
                    style: _budgetActionStyle,
                    onPressed: () => appPushAndRefresh(context, '/home/budget', () => _load(silent: true)),
                    icon: const Icon(Icons.savings_outlined),
                    label: const Text('Set monthly budget', maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              _recentExpenses(currency),
            ],
          ),
        ),
      ),
    );
  }

  Widget _recentExpenses(String currency) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Recent home expenses', style: Theme.of(context).textTheme.titleMedium),
            ),
            TextButton(
              onPressed: () => appPushAndRefresh(context, '/home/expenses/history', () => _load(silent: true)),
              child: const Text('All expenses'),
            ),
          ],
        ),
        if (_recent.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Grocery and household spending will show up here.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
            ),
          )
        else
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var index = 0; index < _recent.length; index++) ...[
                  if (index > 0) const Divider(height: 1),
                  _recentTile(_recent[index], index, currency),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _recentTile(MoneyEntry item, int index, String currency) {
    final details = [
      if (item.catalogName.isNotEmpty) item.catalogName,
      formatDisplayDate(item.date),
    ].join(' · ');
    return ListTile(
      onTap: () => appPushAndRefresh(context, '/home/expenses/history', () => _load(silent: true)),
      leading: CircleAvatar(
        backgroundColor: AppColors.primarySoft,
        foregroundColor: AppColors.primary,
        child: Text('${index + 1}', style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
      title: Text(item.catalogName, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(details, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: Text(
        formatMoney(item.amount, currency: currency),
        style: Theme.of(context).textTheme.titleSmall,
      ),
    );
  }

  static final ButtonStyle _primaryActionStyle = FilledButton.styleFrom(
    minimumSize: const Size(64, 48),
    backgroundColor: AppColors.primary,
    foregroundColor: Colors.white,
    disabledBackgroundColor: AppColors.primarySoft,
    disabledForegroundColor: AppColors.muted,
  ).copyWith(
    overlayColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.pressed)) {
        return Colors.white.withValues(alpha: 0.18);
      }
      if (states.contains(WidgetState.hovered) || states.contains(WidgetState.focused)) {
        return Colors.white.withValues(alpha: 0.10);
      }
      return null;
    }),
  );

  static final ButtonStyle _budgetActionStyle = FilledButton.styleFrom(
    minimumSize: const Size(64, 48),
    backgroundColor: AppColors.primaryDark,
    foregroundColor: Colors.white,
    disabledBackgroundColor: AppColors.primarySoft,
    disabledForegroundColor: AppColors.muted,
  ).copyWith(
    overlayColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.pressed)) {
        return Colors.white.withValues(alpha: 0.18);
      }
      if (states.contains(WidgetState.hovered) || states.contains(WidgetState.focused)) {
        return Colors.white.withValues(alpha: 0.12);
      }
      return null;
    }),
  );
}
