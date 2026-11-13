import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../core/auth/session_controller.dart';
import '../../core/backup/backup_status.dart';
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
  List<RecentClinicPatient> _recent = const [];
  bool _loading = true;
  bool _syncing = false;
  bool _online = true;
  String? _loadError;
  BackupStatus _backup = const BackupStatus();

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
      final localRecent = await repo.recentClinicPatients();
      final backup = await repo.backupStatus();
      if (mounted) {
        setState(() {
          _totals = local;
          _patientCount = localCounts;
          _recent = localRecent;
          _backup = backup;
          _loading = false;
          _syncing = true;
          _loadError = null;
        });
      }
      final online = await repo.refresh(force: force);
      final totals = await repo.clinicTotals(range);
      final counts = await _counts(repo);
      final recent = await repo.recentClinicPatients();
      if (mounted) {
        setState(() {
          _online = online;
          _totals = totals;
          _patientCount = counts;
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
                StatusBanner.offline('Showing local records. Sync when you are back online.', onRetry: () => _load(force: true)),
              ],
              if (!_loading && _backup.isOverdue) ...[
                const SizedBox(height: 12),
                StatusBanner(
                  message: _backup.lastBackupAt == null
                      ? 'Save a clinic backup and keep a copy on a USB drive.'
                      : 'Clinic backup is more than a week old. Save a new copy.',
                  tone: StatusTone.warning,
                  icon: Icons.backup_outlined,
                  actionLabel: 'Backup',
                  onRetry: () => context.go('/settings'),
                ),
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
                                    label: 'Treatment fees',
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
              const SizedBox(height: 8),
              _recentPatients(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _recentPatients() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Recent patients', style: Theme.of(context).textTheme.titleMedium),
            ),
            TextButton(
              onPressed: () => appPushAndRefresh(context, '/clinic/patients', () => _load(silent: true)),
              child: const Text('All patients'),
            ),
          ],
        ),
        if (_recent.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Patients you treat will show up here.',
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
                  _recentTile(_recent[index], index),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _recentTile(RecentClinicPatient item, int index) {
    final patient = item.patient;
    final details = [
      if (patient.phone != null && patient.phone!.isNotEmpty) patient.phone,
      if (item.lastVisitDate != null) 'Last visit ${formatDisplayDate(item.lastVisitDate)}',
      if (item.lastTreatment != null && item.lastTreatment!.isNotEmpty) item.lastTreatment,
      if (item.lastVisitDate == null) 'No treatments yet',
    ].join(' · ');
    return ListTile(
      onTap: () => appPushAndRefresh(context, '/clinic/patients/${patient.id}', () => _load(silent: true)),
      leading: CircleAvatar(
        backgroundColor: AppColors.primarySoft,
        foregroundColor: AppColors.primary,
        child: Text('${index + 1}', style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
      title: Text(patient.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(details, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: IconButton(
        tooltip: 'Add treatment',
        onPressed: () => appPushAndRefresh(
          context,
          '/clinic/income?patientId=${Uri.encodeQueryComponent(patient.id)}',
          () => _load(silent: true),
        ),
        icon: const Icon(Icons.add_rounded),
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
