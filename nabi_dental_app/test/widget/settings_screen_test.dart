import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nabi_dental_app/app/theme/app_theme.dart';
import 'package:nabi_dental_app/core/auth/auth_repository.dart';
import 'package:nabi_dental_app/core/auth/session_controller.dart';
import 'package:nabi_dental_app/core/auth/token_storage.dart';
import 'package:nabi_dental_app/core/database/app_database.dart';
import 'package:nabi_dental_app/core/finance/finance_repository.dart';
import 'package:nabi_dental_app/core/models/session_models.dart';
import 'package:nabi_dental_app/core/security/pin_service.dart';
import 'package:nabi_dental_app/features/settings/settings_screen.dart';

class _Auth extends Mock implements AuthRepository {}

class _Tokens extends Mock implements TokenStorage {}

class _Pin extends Mock implements PinService {}

class _Db extends Mock implements AppDatabase {}

class _Finance extends Mock implements FinanceRepository {}

void main() {
  testWidgets('settings stays focused on working owner actions', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final pin = _Pin();
    final finance = _Finance();
    when(() => pin.canUseBiometrics()).thenAnswer((_) async => true);
    when(() => pin.biometricsEnabled()).thenAnswer((_) async => false);
    when(() => finance.syncStatus()).thenAnswer(
      (_) async => const SyncStatus(pending: 2, conflicts: 0, state: 'idle'),
    );

    final controller = SessionController(
      auth: _Auth(),
      tokens: _Tokens(),
      pin: pin,
      database: _Db(),
    )..state = const SessionState(
        initialized: true,
        hasTokens: true,
        hasPin: true,
        unlocked: true,
        user: UserProfile(
          id: '1',
          fullName: 'Dr Owner',
          email: 'owner@example.com',
          role: 'owner',
          defaultHomeBudget: '50000.00',
        ),
        clinic: ClinicProfile(
          id: '1',
          name: 'Nabi Dental',
          currency: 'PKR',
          timezone: 'Asia/Karachi',
        ),
      );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionProvider.overrideWith((ref) => controller),
          pinServiceProvider.overrideWithValue(pin),
          financeRepositoryProvider.overrideWithValue(finance),
          pendingCountProvider.overrideWith((ref) async => 2),
        ],
        child: MaterialApp.router(
          theme: buildAppTheme(),
          routerConfig: GoRouter(
            initialLocation: '/settings',
            routes: [
              GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
              GoRoute(path: '/settings/profile', builder: (_, __) => const SizedBox()),
              GoRoute(path: '/modules', builder: (_, __) => const SizedBox()),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Dr Owner'), findsOneWidget);
    expect(find.text('owner@example.com'), findsOneWidget);
    expect(find.text('View profile and photo'), findsOneWidget);
    expect(find.text('Catalogs'), findsOneWidget);
    expect(find.text('Retry sync'), findsOneWidget);
    expect(find.text('2 changes waiting to sync'), findsOneWidget);
    expect(find.text('Change PIN'), findsOneWidget);
    expect(find.text('Unlock with biometrics'), findsOneWidget);
    expect(find.text('Change password'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Sign out this device'), 200);
    expect(find.text('Sign out this device'), findsOneWidget);
    expect(find.text('Sign out all devices'), findsOneWidget);
    expect(find.text('API'), findsNothing);
    expect(find.text('Sync state'), findsNothing);
    expect(find.text('Clinic and owner'), findsNothing);
  });
}
