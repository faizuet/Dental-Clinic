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

class ClinicDashboardScreen extends ConsumerStatefulWidget {
  const ClinicDashboardScreen({super.key});

  @override
  ConsumerState<ClinicDashboardScreen> createState() => _ClinicDashboardScreenState();
}

class _ClinicDashboardScreenState extends ConsumerState<ClinicDashboardScreen> {
  FinancePeriod _period = FinancePeriod.daily;
  DateTime? _customFrom;
  DateTime? _customTo;
  ClinicTotals? _totals;
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
      final totals = await ref.read(financeRepositoryProvider).clinicTotals(range);
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
        title: const AppBarTitle('Clinic Finance'),
        actions: [
          IconButton(tooltip: 'Refresh', onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
        ],
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
                StatusBanner.offline('Showing local records. Sync when you are back online.', onRetry: _load),
              ],
              const SizedBox(height: 16),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: _loading
                    ? const LoadingView(message: 'Updating clinic totals…')
                    : totals == null
                        ? const EmptyState(message: 'No clinic totals yet.')
                        : Column(
                            key: const ValueKey('clinic-totals'),
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                '${totals.range.fromIso} to ${totals.range.toIso}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w500),
                              ),
                              const SizedBox(height: 12),
                              SummaryCard(
                                label: 'Income',
                                value: formatMoney(totals.income, currency: currency),
                                color: AppColors.success,
                                icon: Icons.trending_up_rounded,
                              ),
                              SummaryCard(
                                label: 'Clinic expenses',
                                value: formatMoney(totals.expenses, currency: currency),
                                color: AppColors.danger,
                                icon: Icons.trending_down_rounded,
                              ),
                              SummaryCard(
                                label: moneyToDouble(totals.profit) < 0 ? 'Loss' : 'Profit',
                                value: formatMoney(totals.profit, currency: currency),
                                color: moneyToDouble(totals.profit) < 0 ? AppColors.danger : AppColors.purple,
                                icon: Icons.account_balance_wallet_outlined,
                              ),
                            ],
                          ),
              ),
              const SectionHeader('Quick actions'),
              Stretch(
                child: FilledButton.icon(
                  onPressed: () => appPush(context, '/clinic/income'),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add treatment', maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
              const SizedBox(height: 10),
              Stretch(
                child: OutlinedButton.icon(
                  onPressed: () => appPush(context, '/clinic/expenses'),
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: const Text('Add clinic expense', maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
              const SizedBox(height: 16),
              ActionCard(
                title: 'Treatment history',
                subtitle: 'Patient visits, X-rays, and treatment fees',
                icon: Icons.history_rounded,
                onTap: () => appPush(context, '/clinic/income/history'),
              ),
              ActionCard(
                title: 'Expense history',
                subtitle: 'Review clinic spending by category',
                icon: Icons.list_alt_rounded,
                color: AppColors.pink,
                soft: AppColors.pinkSoft,
                onTap: () => appPush(context, '/clinic/expenses/history'),
              ),
              ActionCard(
                title: 'Reports and exports',
                subtitle: 'Breakdowns, timeline, PDF and Excel',
                icon: Icons.picture_as_pdf_outlined,
                onTap: () => appPush(context, '/clinic/reports'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
