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
import '../../core/widgets/app_controls.dart';
import '../../core/widgets/app_layout.dart';
import '../../core/widgets/app_navigation.dart';
import '../../core/widgets/app_page.dart';
import '../../core/widgets/dashboard_tiles.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/app_motion.dart';
import '../../core/widgets/period_selector.dart';
import '../../core/widgets/status_banner.dart';
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
  List<ClinicActivity> _activity = const [];
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
      final localActivity = await repo.recentClinicActivity();
      final backup = await repo.backupStatus();
      if (mounted) {
        setState(() {
          _totals = local;
          _patientCount = localCounts;
          _recent = localRecent;
          _activity = localActivity;
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
      final activity = await repo.recentClinicActivity();
      if (mounted) {
        setState(() {
          _online = online;
          _totals = totals;
          _patientCount = counts;
          _recent = recent;
          _activity = activity;
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

  Future<void> _open(String path) => appPushAndRefresh(context, path, () => _load(silent: true));

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
                title: 'Hello, ${session.clinic?.name ?? 'Nabi Dental Clinic'}',
                subtitle: 'Manage your clinic efficiently and provide the best care',
                icon: Icons.health_and_safety_rounded,
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
                    title: 'Add Treatment',
                    subtitle: 'Record new treatment',
                    icon: Icons.add_rounded,
                    colors: const [AppColors.secondary, AppColors.primaryDark],
                    onTap: () => _open('/clinic/income'),
                  ),
                  QuickActionTile(
                    title: 'Add Patient',
                    subtitle: 'Register new patient',
                    icon: Icons.person_add_alt_1_rounded,
                    colors: const [Color(0xFF3DB87E), AppColors.success],
                    onTap: () => _open('/clinic/patients?add=1'),
                  ),
                  QuickActionTile(
                    title: 'Add Lab Charge',
                    subtitle: 'Record lab charges',
                    icon: Icons.science_rounded,
                    colors: const [Color(0xFF9479E0), AppColors.violet],
                    onTap: () => _open('/clinic/lab-charges/new'),
                  ),
                  QuickActionTile(
                    title: 'Add Expense',
                    subtitle: 'Record clinic expense',
                    icon: Icons.receipt_long_rounded,
                    colors: const [Color(0xFFF7AE5C), AppColors.orange],
                    onTap: () => _open('/clinic/expenses'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              AppSplit(
                breakpoint: 900,
                primaryFlex: 3,
                secondaryFlex: 2,
                primary: _recentPatients(),
                secondary: _recentActivity(currency),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statCards(ClinicTotals totals, String currency) {
    final loss = moneyToDouble(totals.profit) < 0;
    return ResponsiveGrid(
      minItemWidth: 196,
      runSpacing: 12,
      children: [
        StatCard(
          label: 'Total Patients',
          value: '$_patientCount',
          color: AppColors.primary,
          background: AppColors.primarySoft,
          icon: Icons.groups_rounded,
          actionLabel: 'View all',
          onTap: () => _open('/clinic/patients'),
        ),
        StatCard(
          label: 'Treatment Fees',
          value: formatMoney(totals.income, currency: currency),
          color: AppColors.success,
          background: AppColors.mintSoft,
          icon: Icons.account_balance_wallet_rounded,
          onTap: () => _open('/clinic/income/history'),
        ),
        StatCard(
          label: 'Clinic Expenses',
          value: formatMoney(totals.expenses, currency: currency),
          color: AppColors.orange,
          background: AppColors.warningSoft,
          icon: Icons.calculate_rounded,
          onTap: () => _open('/clinic/expenses/history'),
        ),
        StatCard(
          label: 'Lab Charges',
          value: formatMoney(totals.labCharges, currency: currency),
          color: AppColors.violet,
          background: AppColors.violetSoft,
          icon: Icons.science_rounded,
          onTap: () => _open('/clinic/lab-charges'),
        ),
        StatCard(
          label: loss ? 'Loss' : 'Profit',
          value: formatMoney(totals.profit, currency: currency),
          color: loss ? AppColors.danger : AppColors.aqua,
          background: loss ? AppColors.dangerSoft : AppColors.aquaSoft,
          icon: Icons.insights_rounded,
          onTap: () => _open('/clinic/reports'),
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

  Widget _recentPatients() {
    final theme = Theme.of(context);
    final header = theme.textTheme.bodySmall?.copyWith(color: AppColors.muted, fontWeight: FontWeight.w700);
    return DashboardPanel(
      title: 'Recent Patients',
      actionLabel: 'View all',
      onAction: () => _open('/clinic/patients'),
      child: _recent.isEmpty
          ? Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
              child: Text(
                'Patients you treat will show up here.',
                style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.muted),
              ),
            )
          : Column(
              children: [
                Container(
                  color: AppColors.background,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  child: Row(
                    children: [
                      Expanded(flex: 4, child: Text('Patient Name', style: header)),
                      Expanded(flex: 3, child: Text('Phone', style: header)),
                      Expanded(flex: 3, child: Text('Last Visit', style: header)),
                      const SizedBox(width: 40),
                    ],
                  ),
                ),
                for (var index = 0; index < _recent.length; index++) ...[
                  if (index > 0) const Divider(height: 1),
                  _recentRow(_recent[index]),
                ],
              ],
            ),
    );
  }

  Widget _recentRow(RecentClinicPatient item) {
    final patient = item.patient;
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => _open('/clinic/patients/${patient.id}'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 8, 8, 8),
        child: Row(
          children: [
            Expanded(
              flex: 4,
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: AppColors.primarySoft,
                    foregroundColor: AppColors.primary,
                    child: Text(_initials(patient.name), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(patient.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
                        if (item.lastTreatment != null && item.lastTreatment!.isNotEmpty)
                          Text(
                            item.lastTreatment!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(color: AppColors.muted),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(patient.phone ?? '—', maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            Expanded(
              flex: 3,
              child: Text(
                item.lastVisitDate == null ? 'No visits yet' : formatDisplayDate(item.lastVisitDate),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: item.lastVisitDate == null ? theme.textTheme.bodySmall?.copyWith(color: AppColors.muted) : null,
              ),
            ),
            SizedBox(
              width: 40,
              child: IconButton(
                tooltip: 'Add treatment',
                onPressed: () => _open('/clinic/income?patientId=${Uri.encodeQueryComponent(patient.id)}'),
                icon: const Icon(Icons.add_circle_outline_rounded, color: AppColors.primary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _recentActivity(String currency) {
    final theme = Theme.of(context);
    return DashboardPanel(
      title: 'Recent Activities',
      actionLabel: 'View all',
      onAction: () => _open('/clinic/income/history'),
      child: _activity.isEmpty
          ? Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
              child: Text(
                'New treatments, expenses, and lab charges will show up here.',
                style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.muted),
              ),
            )
          : Column(
              children: [
                for (var index = 0; index < _activity.length; index++) ...[
                  if (index > 0) const Divider(height: 1, indent: 18, endIndent: 18),
                  _activityRow(_activity[index], currency),
                ],
                const SizedBox(height: 6),
              ],
            ),
    );
  }

  Widget _activityRow(ClinicActivity item, String currency) {
    final theme = Theme.of(context);
    final (icon, color, soft) = switch (item.kind) {
      ClinicActivityKind.treatment => (Icons.medical_services_rounded, AppColors.primary, AppColors.primarySoft),
      ClinicActivityKind.expense => (Icons.receipt_long_rounded, AppColors.orange, AppColors.warningSoft),
      ClinicActivityKind.labCharge => (Icons.science_rounded, AppColors.violet, AppColors.violetSoft),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: soft, borderRadius: BorderRadius.circular(AppRadii.sm)),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                Text(
                  formatMoney(item.amount, currency: currency),
                  maxLines: 1,
                  style: theme.textTheme.bodySmall?.copyWith(color: AppColors.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(formatDisplayDate(item.date), style: theme.textTheme.bodySmall?.copyWith(color: AppColors.muted)),
        ],
      ),
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((part) => part.isNotEmpty).toList();
    if (parts.isEmpty) {
      return '?';
    }
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  Future<int> _counts(FinanceRepository repo) async {
    final patients = await repo.patients();
    return patients.length;
  }
}
