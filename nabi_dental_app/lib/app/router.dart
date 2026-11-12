import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/auth/session_controller.dart';
import '../core/widgets/app_shell.dart';
import '../features/authentication/login_screen.dart';
import '../features/authentication/splash_screen.dart';
import '../features/clinic_dashboard/clinic_dashboard_screen.dart';
import '../features/clinic_dashboard/expense_entry_screen.dart';
import '../features/clinic_dashboard/history_screen.dart';
import '../features/clinic_dashboard/patient_record_screen.dart';
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
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => ClinicAppShell(
          navigationShell: navigationShell,
          child: navigationShell,
        ),
        branches: [
          StatefulShellBranch(
            routes: [
              appRoute('/clinic', () => const ClinicDashboardScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/clinic/patients',
                pageBuilder: (context, state) => buildAppPage(state, const PatientsScreen()),
                routes: [
                  GoRoute(
                    path: ':id',
                    pageBuilder: (context, state) => buildAppPage(
                      state,
                      PatientRecordScreen(patientId: state.pathParameters['id']!),
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              appRoute('/clinic/income/history', () => const TreatmentHistoryScreen()),
              GoRoute(
                path: '/clinic/income',
                pageBuilder: (context, state) => buildAppPage(state, const TreatmentEntryScreen()),
                routes: [
                  GoRoute(
                    path: ':id/edit',
                    pageBuilder: (context, state) => buildAppPage(
                      state,
                      TreatmentEntryScreen(visitId: state.pathParameters['id']!),
                    ),
                  ),
                  GoRoute(
                    path: ':id',
                    pageBuilder: (context, state) => buildAppPage(
                      state,
                      TreatmentDetailScreen(id: state.pathParameters['id']!),
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              appRoute('/clinic/expenses/history', () => const ClinicExpenseHistoryScreen()),
              appRoute('/clinic/expenses', () => const ClinicExpenseEntryScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              appRoute('/clinic/reports', () => const ClinicReportsScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                pageBuilder: (context, state) => buildAppPage(state, const SettingsScreen()),
                routes: [
                  appRoute('profile', () => const ProfileScreen()),
                  appRoute('catalogs', () => const CatalogsScreen()),
                  appRoute('conflicts', () => const ConflictReviewScreen()),
                ],
              ),
            ],
          ),
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
