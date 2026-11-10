import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/auth/session_controller.dart';
import '../core/widgets/app_shell.dart';
import '../features/authentication/login_screen.dart';
import '../features/authentication/splash_screen.dart';
import '../features/clinic_dashboard/clinic_dashboard_screen.dart';
import '../features/clinic_dashboard/expense_entry_screen.dart';
import '../features/clinic_dashboard/history_screen.dart';
import '../features/clinic_dashboard/patients_screen.dart';
import '../features/clinic_dashboard/reports_screen.dart';
import '../features/clinic_dashboard/treatment_detail_screen.dart';
import '../features/clinic_dashboard/treatment_entry_screen.dart';
import '../features/settings/catalogs_screen.dart';
import '../features/settings/conflict_review_screen.dart';
import '../features/settings/profile_screen.dart';
import '../features/settings/settings_screen.dart';
import 'app_page.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = SessionListenable(ref);
  final router = GoRouter(
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) {
      final gate = ref.read(sessionProvider).gate;
      final location = state.matchedLocation;
      const authRoutes = {'/splash', '/login'};

      switch (gate) {
        case AppRouteGate.splash:
          return location == '/splash' ? null : '/splash';
        case AppRouteGate.login:
          return location == '/login' ? null : '/login';
        case AppRouteGate.ready:
          if (authRoutes.contains(location) ||
              location == '/' ||
              location == '/modules' ||
              location == '/pin-setup' ||
              location == '/unlock' ||
              location.startsWith('/home') ||
              location.startsWith('/construction')) {
            return '/clinic';
          }
          return null;
      }
    },
    routes: [
      GoRoute(path: '/splash', builder: (context, state) => const SplashScreen()),
      appRoute('/login', () => const LoginScreen()),
      ShellRoute(
        builder: (context, state, child) => ClinicAppShell(child: child),
        routes: [
          appRoute('/clinic', () => const ClinicDashboardScreen()),
          appRoute('/clinic/patients', () => const PatientsScreen()),
          appRoute('/clinic/income', () => const TreatmentEntryScreen()),
          appRoute('/clinic/income/history', () => const TreatmentHistoryScreen()),
          GoRoute(
            path: '/clinic/income/:id',
            pageBuilder: (context, state) => buildAppPage(state, TreatmentDetailScreen(id: state.pathParameters['id']!)),
          ),
          appRoute('/clinic/expenses', () => const ClinicExpenseEntryScreen()),
          appRoute('/clinic/expenses/history', () => const ClinicExpenseHistoryScreen()),
          appRoute('/clinic/reports', () => const ClinicReportsScreen()),
          appRoute('/settings', () => const SettingsScreen()),
          appRoute('/settings/profile', () => const ProfileScreen()),
          appRoute('/settings/catalogs', () => const CatalogsScreen()),
          appRoute('/settings/conflicts', () => const ConflictReviewScreen()),
        ],
      ),
    ],
  );
  ref.onDispose(() {
    refresh.dispose();
    router.dispose();
  });
  return router;
});
