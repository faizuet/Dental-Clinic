import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_colors.dart';
import '../../core/auth/session_controller.dart';
import '../../core/finance/finance_repository.dart';
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
  int _patientCount = 0;
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
    _load();
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
    try {
      final local = await repo.clinicTotals(range);
      final localCounts = await _counts(repo);
      if (mounted) {
        setState(() {
          _totals = local;
          _patientCount = localCounts;
          _loading = false;
          _syncing = true;
          _loadError = null;
        });
      }
      final online = await repo.refresh(force: force);
      final totals = await repo.clinicTotals(range);
      final counts = await _counts(repo);
      if (mounted) {
        setState(() {
          _online = online;
          _totals = totals;
          _patientCount = counts;
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
        fallback: '/clinic',
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
                subtitle: '${session.clinic?.name ?? 'Nabi Dental Clinic'}  ·  Clinic overview',
              ),
              const SizedBox(height: 20),
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
              if (_syncing) ...[
                const SizedBox(height: 8),
                const LinearProgressIndicator(minHeight: 2),
              ],
              if (_loadError != null) ...[
                const SizedBox(height: 12),
                StatusBanner.error(_loadError!, onRetry: () => _load(force: true)),
              ] else if (!_online) ...[
                const SizedBox(height: 12),
                StatusBanner.offline('Showing local records. Sync when you are back online.', onRetry: () => _load(force: true)),
              ],
              const SizedBox(height: 16),
              AppStateSwitch(
                child: _loading && totals == null
                    ? const SkeletonCards(key: ValueKey('clinic-skeleton'))
                    : totals == null
                        ? const EmptyState(key: ValueKey('clinic-empty'), message: 'No clinic totals yet.')
                        : AppReveal(
                            child: Column(
                            key: const ValueKey('clinic-totals'),
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
                                    label: 'Total patients',
                                    value: '$_patientCount',
                                    color: AppColors.primary,
                                    background: AppColors.lavenderSoft,
                                    icon: Icons.people_outline_rounded,
                                  ),
                                  SummaryCard(
                                    label: 'Total payments',
                                    value: formatMoney(totals.income, currency: currency),
                                    color: AppColors.success,
                                    background: AppColors.mintSoft,
                                    icon: Icons.payments_outlined,
                                  ),
                                  SummaryCard(
                                    label: 'Total clinic expenses',
                                    value: formatMoney(totals.expenses, currency: currency),
                                    color: AppColors.warning,
                                    background: AppColors.warningSoft,
                                    icon: Icons.receipt_long_outlined,
                                  ),
                                  SummaryCard(
                                    label: moneyToDouble(totals.profit) < 0 ? 'Loss' : 'Profit',
                                    value: formatMoney(totals.profit, currency: currency),
                                    color: moneyToDouble(totals.profit) < 0 ? AppColors.danger : AppColors.primary,
                                    background: moneyToDouble(totals.profit) < 0 ? AppColors.dangerSoft : AppColors.tealSoft,
                                    icon: Icons.account_balance_wallet_outlined,
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
                        onPressed: () => appPushAndRefresh(context, '/clinic/income', () => _load(silent: true)),
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Add treatment', maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        style: _expenseActionStyle,
                        onPressed: () => appPushAndRefresh(context, '/clinic/expenses', () => _load(silent: true)),
                        icon: const Icon(Icons.receipt_long_outlined),
                        label: const Text('Clinic expense', maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ],
                )
              else ...[
                Stretch(
                  child: FilledButton.icon(
                    style: _primaryActionStyle,
                    onPressed: () => appPushAndRefresh(context, '/clinic/income', () => _load(silent: true)),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add treatment', maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ),
                const SizedBox(height: 10),
                Stretch(
                  child: FilledButton.icon(
                    style: _expenseActionStyle,
                    onPressed: () => appPushAndRefresh(context, '/clinic/expenses', () => _load(silent: true)),
                    icon: const Icon(Icons.receipt_long_outlined),
                    label: const Text('Clinic expense', maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              ResponsiveGrid(
                minItemWidth: 280,
                runSpacing: 0,
                children: [
                  ActionCard(
                    title: 'Patients',
                    subtitle: 'Registered names, phone numbers, and records',
                    icon: Icons.people_outline_rounded,
                    color: AppColors.primary,
                    background: AppColors.lavenderSoft,
                    onTap: () => appPushAndRefresh(context, '/clinic/patients', () => _load(silent: true)),
                  ),
                  ActionCard(
                    title: 'Treatment history',
                    subtitle: 'Patient visits, X-rays, and treatment fees',
                    icon: Icons.history_rounded,
                    color: AppColors.primaryDark,
                    background: AppColors.primarySoft,
                    onTap: () => appPushAndRefresh(context, '/clinic/income/history', () => _load(silent: true)),
                  ),
                  ActionCard(
                    title: 'Expense history',
                    subtitle: 'Review clinic spending by category',
                    icon: Icons.list_alt_rounded,
                    color: AppColors.warning,
                    background: AppColors.warningSoft,
                    onTap: () => appPushAndRefresh(context, '/clinic/expenses/history', () => _load(silent: true)),
                  ),
                  ActionCard(
                    title: 'Reports and exports',
                    subtitle: 'Breakdowns, timeline, PDF and Excel',
                    icon: Icons.picture_as_pdf_outlined,
                    color: AppColors.success,
                    background: AppColors.mintSoft,
                    onTap: () => appPushAndRefresh(context, '/clinic/reports', () => _load(silent: true)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<int> _counts(FinanceRepository repo) async {
    final patients = await repo.patients();
    return patients.length;
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

  static final ButtonStyle _expenseActionStyle = FilledButton.styleFrom(
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
