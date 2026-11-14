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
    required this.branch,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final String path;
  final bool Function(String location) matches;
  final int branch;
}

const clinicDestinations = [
  ClinicDestination(
    label: 'Dashboard',
    icon: Icons.space_dashboard_outlined,
    selectedIcon: Icons.space_dashboard_rounded,
    path: '/clinic',
    matches: _isDashboard,
    branch: 0,
  ),
  ClinicDestination(
    label: 'Patients',
    icon: Icons.people_outline_rounded,
    selectedIcon: Icons.people_rounded,
    path: '/clinic/patients',
    matches: _isPatients,
    branch: 1,
  ),
  ClinicDestination(
    label: 'Treatments',
    icon: Icons.healing_outlined,
    selectedIcon: Icons.healing_rounded,
    path: '/clinic/income/history',
    matches: _isTreatments,
    branch: 2,
  ),
  ClinicDestination(
    label: 'Expenses',
    icon: Icons.receipt_long_outlined,
    selectedIcon: Icons.receipt_long_rounded,
    path: '/clinic/expenses/history',
    matches: _isExpenses,
    branch: 3,
  ),
  ClinicDestination(
    label: 'Lab charges',
    icon: Icons.science_outlined,
    selectedIcon: Icons.science_rounded,
    path: '/clinic/lab-charges',
    matches: _isLabCharges,
    branch: 9,
  ),
  ClinicDestination(
    label: 'Reports',
    icon: Icons.picture_as_pdf_outlined,
    selectedIcon: Icons.picture_as_pdf_rounded,
    path: '/clinic/reports',
    matches: _isReports,
    branch: 4,
  ),
  ClinicDestination(
    label: 'Settings',
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings_rounded,
    path: '/settings',
    matches: _isSettings,
    branch: 5,
  ),
];

const homeDestinations = [
  ClinicDestination(
    label: 'Dashboard',
    icon: Icons.space_dashboard_outlined,
    selectedIcon: Icons.space_dashboard_rounded,
    path: '/home',
    matches: _isHomeDashboard,
    branch: 6,
  ),
  ClinicDestination(
    label: 'Expenses',
    icon: Icons.shopping_bag_outlined,
    selectedIcon: Icons.shopping_bag_rounded,
    path: '/home/expenses/history',
    matches: _isHomeExpenses,
    branch: 7,
  ),
  ClinicDestination(
    label: 'Reports',
    icon: Icons.picture_as_pdf_outlined,
    selectedIcon: Icons.picture_as_pdf_rounded,
    path: '/home/reports',
    matches: _isHomeReports,
    branch: 8,
  ),
  ClinicDestination(
    label: 'Settings',
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings_rounded,
    path: '/settings',
    matches: _isSettings,
    branch: 5,
  ),
];

bool _isDashboard(String location) => location == '/clinic';
bool _isPatients(String location) => location.startsWith('/clinic/patients');
bool _isTreatments(String location) => location.startsWith('/clinic/income');
bool _isExpenses(String location) => location.startsWith('/clinic/expenses');
bool _isLabCharges(String location) => location.startsWith('/clinic/lab-charges');
bool _isReports(String location) => location.startsWith('/clinic/reports');
bool _isSettings(String location) => location.startsWith('/settings');
bool _isHomeDashboard(String location) => location == '/home' || location == '/home/budget';
bool _isHomeExpenses(String location) => location.startsWith('/home/expenses');
bool _isHomeReports(String location) => location.startsWith('/home/reports');

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
  var _homeModule = false;

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

  bool get _homeActive => _location.startsWith('/home') || (_homeModule && _location.startsWith('/settings'));

  List<ClinicDestination> get _destinations => _homeActive ? homeDestinations : clinicDestinations;

  void _open(String path) {
    if (path.startsWith('/home')) {
      _homeModule = true;
    } else if (!path.startsWith('/settings')) {
      _homeModule = false;
    }
    final shell = widget.navigationShell;
    final branch = _branchFor(path);
    if (shell != null && branch != null) {
      shell.goBranch(branch, initialLocation: branch == shell.currentIndex);
      return;
    }
    if (_location == path) {
      return;
    }
    context.go(path);
  }

  int? _branchFor(String path) {
    for (final item in _destinations) {
      if (item.path == path) {
        return item.branch;
      }
    }
    for (final item in [...clinicDestinations, ...homeDestinations]) {
      if (item.path == path) {
        return item.branch;
      }
    }
    return null;
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
        tools: _TopBarTools(
          name: name,
          showSearch: _location == '/clinic',
          onSearch: (query) => context.go('/clinic/patients?q=${Uri.encodeQueryComponent(query)}'),
          onProfile: () => context.go('/settings/profile'),
        ),
        child: Scaffold(
          key: _scaffoldKey,
          backgroundColor: AppColors.background,
          drawer: showSidebar
              ? null
              : Drawer(
                  backgroundColor: AppColors.navy,
                  child: SafeArea(
                    child: _Sidebar(
                      extended: true,
                      clinic: clinic,
                      userName: name,
                      location: _location,
                      homeActive: _homeActive,
                      destinations: _destinations,
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
                  homeActive: _homeActive,
                  destinations: _destinations,
                  onSelect: _open,
                  onProfile: () => context.go('/settings/profile'),
                ),
              ],
              Expanded(child: widget.child),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBarTools extends StatefulWidget {
  const _TopBarTools({required this.name, required this.showSearch, required this.onSearch, required this.onProfile});

  final String name;
  final bool showSearch;
  final ValueChanged<String> onSearch;
  final VoidCallback onProfile;

  @override
  State<_TopBarTools> createState() => _TopBarToolsState();
}

class _TopBarToolsState extends State<_TopBarTools> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _submit(String value) {
    widget.onSearch(value.trim());
    _search.clear();
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1180;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.showSearch && wide) ...[
          SizedBox(
            width: 300,
            height: 44,
            child: TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              onSubmitted: _submit,
              decoration: InputDecoration(
                hintText: 'Search patients by name, phone...',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                fillColor: AppColors.card,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadii.full),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadii.full),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadii.full),
                  borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
        ],
        Tooltip(
          message: 'Open profile',
          child: Material(
            color: AppColors.card,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.full),
              side: const BorderSide(color: AppColors.border),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadii.full),
              onTap: widget.onProfile,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SessionAvatar(size: 34, onTap: widget.onProfile),
                    const SizedBox(width: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 160),
                      child: Text(
                        widget.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                      ),
                    ),
                    const SizedBox(width: 2),
                    const Icon(Icons.expand_more_rounded, size: 18, color: AppColors.muted),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SidebarColors {
  static const text = Color(0xFFDCE6F5);
  static const muted = Color(0xFF9AACC8);
  static const line = Color(0x1FFFFFFF);
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.extended,
    required this.clinic,
    required this.userName,
    required this.location,
    required this.homeActive,
    required this.destinations,
    required this.onSelect,
    required this.onProfile,
  });

  final bool extended;
  final String clinic;
  final String userName;
  final String location;
  final bool homeActive;
  final List<ClinicDestination> destinations;
  final ValueChanged<String> onSelect;
  final VoidCallback onProfile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedContainer(
      duration: AppMotion.fast,
      width: extended ? 248 : 84,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.navy, AppColors.navyDeep],
        ),
      ),
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
                              style: theme.textTheme.titleSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
                            ),
                            Text(
                              homeActive ? 'Home grocery' : clinic,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(color: _SidebarColors.muted),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                : const Center(child: ClinicMark(size: 40)),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: EdgeInsets.fromLTRB(extended ? 12 : 10, 0, extended ? 12 : 10, 10),
            child: _DomainSwitcher(
              extended: extended,
              homeActive: homeActive,
              onClinic: () => onSelect('/clinic'),
              onHome: () => onSelect('/home'),
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.symmetric(horizontal: extended ? 12 : 10),
              children: [
                for (final item in destinations)
                  _NavTile(
                    item: item,
                    extended: extended,
                    selected: item.matches(location),
                    onTap: () => onSelect(item.path),
                  ),
              ],
            ),
          ),
          const Divider(height: 1, color: _SidebarColors.line),
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
                                  style: theme.textTheme.titleSmall?.copyWith(color: Colors.white),
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
    final color = selected ? Colors.white : _SidebarColors.muted;
    final tile = Material(
      color: selected ? AppColors.primary : Colors.transparent,
      elevation: selected ? 3 : 0,
      shadowColor: AppColors.primary.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.sm)),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.sm),
        hoverColor: Colors.white.withValues(alpha: 0.06),
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
                          color: selected ? Colors.white : _SidebarColors.text,
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

class _DomainSwitcher extends StatelessWidget {
  const _DomainSwitcher({
    required this.extended,
    required this.homeActive,
    required this.onClinic,
    required this.onHome,
  });

  final bool extended;
  final bool homeActive;
  final VoidCallback onClinic;
  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) {
    if (!extended) {
      return Column(
        children: [
          _iconButton(
            tooltip: 'Clinic',
            icon: Icons.local_hospital_outlined,
            selected: !homeActive,
            onTap: onClinic,
          ),
          const SizedBox(height: 6),
          _iconButton(
            tooltip: 'Home',
            icon: Icons.home_outlined,
            selected: homeActive,
            onTap: onHome,
          ),
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: _chip(label: 'Clinic', selected: !homeActive, onTap: onClinic)),
        const SizedBox(width: 8),
        Expanded(child: _chip(label: 'Home', selected: homeActive, onTap: onHome)),
      ],
    );
  }

  Widget _chip({required String label, required bool selected, required VoidCallback onTap}) {
    return Material(
      color: selected ? Colors.white.withValues(alpha: 0.12) : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.sm),
        side: BorderSide(color: selected ? AppColors.secondary : _SidebarColors.line),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.sm),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? Colors.white : _SidebarColors.muted,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  Widget _iconButton({
    required String tooltip,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: selected ? Colors.white.withValues(alpha: 0.12) : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.sm),
          side: selected ? const BorderSide(color: AppColors.secondary) : BorderSide.none,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadii.sm),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Icon(icon, color: selected ? Colors.white : _SidebarColors.muted, size: 22),
          ),
        ),
      ),
    );
  }
}
