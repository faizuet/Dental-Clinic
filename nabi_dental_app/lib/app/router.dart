import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/auth/session_controller.dart';
import '../features/authentication/login_screen.dart';
import '../features/authentication/pin_setup_screen.dart';
import '../features/authentication/splash_screen.dart';
import '../features/authentication/unlock_screen.dart';
import '../features/clinic_dashboard/clinic_dashboard_screen.dart';
import '../features/clinic_dashboard/expense_entry_screen.dart';
import '../features/clinic_dashboard/history_screen.dart';
import '../features/clinic_dashboard/reports_screen.dart';
import '../features/clinic_dashboard/treatment_detail_screen.dart';
import '../features/clinic_dashboard/treatment_entry_screen.dart';
import '../features/construction/construction_dashboard_screen.dart';
import '../features/construction/construction_history_screen.dart';
import '../features/construction/construction_materials_screen.dart';
import '../features/construction/construction_purchase_screen.dart';
import '../features/home_dashboard/home_budget_screen.dart';
import '../features/home_dashboard/home_dashboard_screen.dart';
import '../features/module_selection/module_selection_screen.dart';
import '../features/settings/catalogs_screen.dart';
import '../features/settings/conflict_review_screen.dart';
import '../features/settings/pin_change_screen.dart';
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
      const authRoutes = {'/splash', '/login', '/pin-setup', '/unlock'};

      switch (gate) {
        case AppRouteGate.splash:
          return location == '/splash' ? null : '/splash';
        case AppRouteGate.login:
          return location == '/login' ? null : '/login';
        case AppRouteGate.pinSetup:
          return location == '/pin-setup' ? null : '/pin-setup';
        case AppRouteGate.unlock:
          return location == '/unlock' ? null : '/unlock';
        case AppRouteGate.ready:
          if (authRoutes.contains(location) || location == '/') {
            return '/modules';
          }
          return null;
      }
    },
    routes: [
      GoRoute(path: '/splash', builder: (context, state) => const SplashScreen()),
      appRoute('/login', () => const LoginScreen()),
      appRoute('/pin-setup', () => const PinSetupScreen()),
      appRoute('/unlock', () => const UnlockScreen()),
      appRoute('/modules', () => const ModuleSelectionScreen()),
      appRoute('/clinic', () => const ClinicDashboardScreen()),
      appRoute('/clinic/income', () => const TreatmentEntryScreen()),
      appRoute('/clinic/income/history', () => const TreatmentHistoryScreen()),
      GoRoute(
        path: '/clinic/income/:id',
        pageBuilder: (context, state) => buildAppPage(state, TreatmentDetailScreen(id: state.pathParameters['id']!)),
      ),
      appRoute('/clinic/expenses', () => const ClinicExpenseEntryScreen()),
      appRoute('/clinic/expenses/history', () => const ClinicExpenseHistoryScreen()),
      appRoute('/clinic/reports', () => const ClinicReportsScreen()),
      appRoute('/home', () => const HomeDashboardScreen()),
      appRoute('/home/expenses', () => const HomeExpenseEntryScreen()),
      appRoute('/home/expenses/history', () => const HomeExpenseHistoryScreen()),
      appRoute('/home/budget', () => const HomeBudgetScreen()),
      appRoute('/home/reports', () => const HomeReportsScreen()),
      appRoute('/construction', () => const ConstructionDashboardScreen()),
      appRoute('/construction/purchases', () => const ConstructionPurchaseScreen()),
      appRoute('/construction/purchases/history', () => const ConstructionHistoryScreen()),
      appRoute('/construction/materials', () => const ConstructionMaterialsScreen()),
      appRoute('/construction/reports', () => const ConstructionReportsScreen()),
      appRoute('/settings', () => const SettingsScreen()),
      appRoute('/settings/profile', () => const ProfileScreen()),
      appRoute('/settings/catalogs', () => const CatalogsScreen()),
      appRoute('/settings/pin', () => const PinChangeScreen()),
      appRoute('/settings/conflicts', () => const ConflictReviewScreen()),
    ],
  );
  ref.onDispose(() {
    refresh.dispose();
    router.dispose();
  });
  return router;
});
