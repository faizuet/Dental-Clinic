import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../auth/session_controller.dart';
import '../../features/settings/change_password_dialog.dart';
import '../../features/settings/profile_avatar.dart';
import 'app_layout.dart';
import 'app_navigation.dart';
import 'brand_header.dart';

class ClinicDestination {
  const ClinicDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.path,
    required this.matches,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final String path;
  final bool Function(String location) matches;
}

const clinicDestinations = [
  ClinicDestination(
    label: 'Dashboard',
    icon: Icons.space_dashboard_outlined,
    selectedIcon: Icons.space_dashboard_rounded,
    path: '/clinic',
    matches: _isDashboard,
  ),
  ClinicDestination(
    label: 'Patients',
    icon: Icons.people_outline_rounded,
    selectedIcon: Icons.people_rounded,
    path: '/clinic/patients',
    matches: _isPatients,
  ),
  ClinicDestination(
    label: 'Treatments',
    icon: Icons.healing_outlined,
    selectedIcon: Icons.healing_rounded,
    path: '/clinic/income/history',
    matches: _isTreatments,
  ),
  ClinicDestination(
    label: 'Expenses',
    icon: Icons.receipt_long_outlined,
    selectedIcon: Icons.receipt_long_rounded,
    path: '/clinic/expenses/history',
    matches: _isExpenses,
  ),
  ClinicDestination(
    label: 'Reports',
    icon: Icons.picture_as_pdf_outlined,
    selectedIcon: Icons.picture_as_pdf_rounded,
    path: '/clinic/reports',
    matches: _isReports,
  ),
  ClinicDestination(
    label: 'Settings',
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings_rounded,
    path: '/settings',
    matches: _isSettings,
  ),
];

bool _isDashboard(String location) => location == '/clinic';
bool _isPatients(String location) => location.startsWith('/clinic/patients');
bool _isTreatments(String location) => location.startsWith('/clinic/income');
bool _isExpenses(String location) => location.startsWith('/clinic/expenses');
bool _isReports(String location) => location.startsWith('/clinic/reports');
bool _isSettings(String location) => location.startsWith('/settings');

class ClinicAppShell extends ConsumerStatefulWidget {
  const ClinicAppShell({super.key, required this.child, this.navigationShell});

  final Widget child;
  final StatefulNavigationShell? navigationShell;

  @override
  ConsumerState<ClinicAppShell> createState() => _ClinicAppShellState();
}

class _ClinicAppShellState extends ConsumerState<ClinicAppShell> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  var _forcingPassword = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _forcePasswordChange();
      }
    });
  }

  String get _location => GoRouterState.of(context).uri.path;

  void _open(String path) {
    final shell = widget.navigationShell;
    final index = clinicDestinations.indexWhere((item) => item.path == path);
    if (shell != null && index >= 0) {
      shell.goBranch(index, initialLocation: index == shell.currentIndex);
      return;
    }
    if (_location == path) {
      return;
    }
    context.go(path);
  }

  Future<void> _forcePasswordChange() async {
    if (_forcingPassword || !mounted) {
      return;
    }
    final session = ref.read(sessionProvider);
    if (!session.hasTokens || session.user?.mustChangePassword != true) {
      return;
    }
    _forcingPassword = true;
    try {
      await promptChangePassword(context, ref, requiredChange: true);
    } catch (_) {
      // Keep the clinic usable; the dialog already shows a friendly error.
    } finally {
      if (mounted) {
        _forcingPassword = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    ref.listen<SessionState>(sessionProvider, (previous, next) {
      final needed = next.hasTokens && next.user?.mustChangePassword == true;
      final wasNeeded = previous?.hasTokens == true && previous?.user?.mustChangePassword == true;
      if (needed && !wasNeeded) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _forcePasswordChange();
          }
        });
      }
    });
    final clinic = session.clinic?.name ?? 'Nabi Dental Clinic';
    final name = session.user?.fullName ?? 'Owner';
    final showSidebar = AppLayout.showSidebar(context);
    final extended = AppLayout.showExtendedSidebar(context);

    return AppExitScope(
      child: AppShellController(
        hasSidebar: showSidebar,
        openDrawer: showSidebar ? null : () => _scaffoldKey.currentState?.openDrawer(),
        child: Scaffold(
          key: _scaffoldKey,
          backgroundColor: AppColors.background,
          drawer: showSidebar
              ? null
              : Drawer(
                  backgroundColor: AppColors.sidebar,
                  child: SafeArea(
                    child: _Sidebar(
                      extended: true,
                      clinic: clinic,
                      userName: name,
                      location: _location,
                      onSelect: (path) {
                        Navigator.of(context).pop();
                        _open(path);
                      },
                      onProfile: () {
                        Navigator.of(context).pop();
                        context.go('/settings/profile');
                      },
                    ),
                  ),
                ),
          body: Row(
            children: [
              if (showSidebar) ...[
                _Sidebar(
                  extended: extended,
                  clinic: clinic,
                  userName: name,
                  location: _location,
                  onSelect: _open,
                  onProfile: () => context.go('/settings/profile'),
                ),
                const VerticalDivider(width: 1, color: AppColors.border),
              ],
              Expanded(child: widget.child),
            ],
          ),
        ),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.extended,
    required this.clinic,
    required this.userName,
    required this.location,
    required this.onSelect,
    required this.onProfile,
  });

  final bool extended;
  final String clinic;
  final String userName;
  final String location;
  final ValueChanged<String> onSelect;
  final VoidCallback onProfile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedContainer(
      duration: AppMotion.fast,
      width: extended ? 248 : 84,
      color: AppColors.sidebar,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(extended ? 16 : 12, 20, extended ? 16 : 12, 12),
            child: extended
                ? Row(
                    children: [
                      const ClinicMark(size: 40),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Nabi Dental',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall,
                            ),
                            Text(
                              clinic,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(color: AppColors.muted),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                : const Center(child: ClinicMark(size: 40)),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              padding: EdgeInsets.symmetric(horizontal: extended ? 12 : 10),
              children: [
                for (final item in clinicDestinations)
                  _NavTile(
                    item: item,
                    extended: extended,
                    selected: item.matches(location),
                    onTap: () => onSelect(item.path),
                  ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          Padding(
            padding: EdgeInsets.fromLTRB(extended ? 8 : 8, 8, extended ? 8 : 8, 12),
            child: Tooltip(
              message: 'Open profile',
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(AppRadii.sm),
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                  onTap: onProfile,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(extended ? 8 : 4, 8, extended ? 8 : 4, 8),
                    child: extended
                        ? Row(
                            children: [
                              SessionAvatar(size: 40, onTap: onProfile),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  userName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleSmall,
                                ),
                              ),
                            ],
                          )
                        : Center(child: SessionAvatar(size: 40, onTap: onProfile)),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.item,
    required this.extended,
    required this.selected,
    required this.onTap,
  });

  final ClinicDestination item;
  final bool extended;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primary : AppColors.muted;
    final tile = Material(
      color: selected ? AppColors.card : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.sm),
        side: selected ? const BorderSide(color: AppColors.border) : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.sm),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: extended ? 12 : 0, vertical: 12),
          child: extended
              ? Row(
                  children: [
                    Icon(selected ? item.selectedIcon : item.icon, color: color, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        item.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: selected ? AppColors.primary : AppColors.text,
                          fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                )
              : Center(child: Icon(selected ? item.selectedIcon : item.icon, color: color, size: 22)),
        ),
      ),
    );
    if (extended) {
      return Padding(padding: const EdgeInsets.only(bottom: 6), child: tile);
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Tooltip(message: item.label, child: tile),
    );
  }
}
