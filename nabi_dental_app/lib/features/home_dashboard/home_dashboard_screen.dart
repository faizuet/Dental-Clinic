import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_colors.dart';
import '../../core/auth/session_controller.dart';
import '../../core/finance/finance_repository.dart';
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
  bool _loading = true;
  bool _online = true;
  String? _loadError;

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
      final online = await ref.read(financeRepositoryProvider).refresh();
      final range = DateRange.forPeriod(_period, customFrom: _customFrom, customTo: _customTo);
      final totals = await ref.read(financeRepositoryProvider).homeTotals(
            range,
            defaultBudget: ref.read(sessionProvider).user?.defaultHomeBudget ?? '30000.00',
          );
      if (mounted) {
        setState(() {
          _online = online;
          _totals = totals;
          _loading = false;
        });
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

  @override
  Widget build(BuildContext context) {
    final currency = ref.watch(sessionProvider).clinic?.currency ?? 'PKR';
    final totals = _totals;
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(fallback: '/modules'),
        title: const AppBarTitle('Home Finance'),
        actions: [IconButton(tooltip: 'Refresh', onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: AppPageBody(
        padding: AppLayout.pagePadding(context, top: 0, bottom: 8),
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
                    final from = await showDatePicker(
                      context: context,
                      initialDate: _customFrom ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (from == null || !context.mounted) {
                      return;
                    }
                    final to = await showDatePicker(
                      context: context,
                      initialDate: _customTo ?? DateTime.now(),
                      firstDate: from,
                      lastDate: DateTime.now(),
                    );
                    if (to == null) {
                      return;
                    }
                    _customFrom = from;
                    _customTo = to;
                  }
                  setState(() => _period = value);
                  await _load();
                },
              ),
              if (_loadError != null) ...[
                const SizedBox(height: 12),
                StatusBanner.error(_loadError!, onRetry: _load),
              ] else if (!_online) ...[
                const SizedBox(height: 12),
                StatusBanner.offline('Showing local household records.', onRetry: _load),
              ],
              const SizedBox(height: 16),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: _loading
                    ? const LoadingView(message: 'Updating home totals…')
                    : totals == null
                        ? const EmptyState(message: 'No household totals yet.')
                        : Column(
                            key: const ValueKey('home-totals'),
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SummaryCard(
                                label: 'Spending',
                                value: formatMoney(totals.spent, currency: currency),
                                color: AppColors.danger,
                                icon: Icons.shopping_bag_outlined,
                              ),
                              SummaryCard(
                                label: 'Monthly budget',
                                value: formatMoney(totals.budget, currency: currency),
                                icon: Icons.savings_outlined,
                              ),
                              SummaryCard(
                                label: 'Remaining',
                                value: formatMoney(totals.remaining, currency: currency),
                                color: AppColors.success,
                                icon: Icons.account_balance_wallet_outlined,
                              ),
                              if (totals.percentageUsed != null)
                                Card(
                                  child: Padding(
                                    padding: const EdgeInsets.all(18),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('${totals.percentageUsed}% used', style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600)),
                                        const SizedBox(height: 10),
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(AppRadii.full),
                                          child: LinearProgressIndicator(
                                            minHeight: 8,
                                            value: ((double.tryParse(totals.percentageUsed!) ?? 0) / 100).clamp(0, 1),
                                            color: AppColors.pink,
                                            backgroundColor: AppColors.pinkSoft,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
              ),
              const SectionHeader('Quick actions'),
              Stretch(
                child: FilledButton.icon(
                  onPressed: () => appPush(context, '/home/expenses'),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add home expense', maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
              const SizedBox(height: 10),
              Stretch(
                child: OutlinedButton.icon(
                  onPressed: () => appPush(context, '/home/budget'),
                  icon: const Icon(Icons.savings_outlined),
                  label: const Text('Set monthly budget', maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
              const SizedBox(height: 16),
              ActionCard(
                title: 'Expense history',
                subtitle: 'Search and edit household spending',
                icon: Icons.history_rounded,
                color: AppColors.pink,
                soft: AppColors.pinkSoft,
                onTap: () => appPush(context, '/home/expenses/history'),
              ),
              ActionCard(
                title: 'Reports and exports',
                subtitle: 'Category breakdown, PDF and Excel',
                icon: Icons.picture_as_pdf_outlined,
                onTap: () => appPush(context, '/home/reports'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
