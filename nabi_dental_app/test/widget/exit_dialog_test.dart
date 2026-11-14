import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nabi_dental_app/core/auth/auth_repository.dart';
import 'package:nabi_dental_app/core/auth/session_controller.dart';
import 'package:nabi_dental_app/core/auth/token_storage.dart';
import 'package:nabi_dental_app/core/database/app_database.dart';
import 'package:nabi_dental_app/core/models/session_models.dart';
import 'package:nabi_dental_app/core/widgets/app_shell.dart';

class _Auth extends Mock implements AuthRepository {}

class _Tokens extends Mock implements TokenStorage {}

class _Db extends Mock implements AppDatabase {}

void main() {
  testWidgets('root back asks before exiting', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = SessionController(
      auth: _Auth(),
      tokens: _Tokens(),
      database: _Db(),
    )..state = const SessionState(
        initialized: true,
        hasTokens: true,
        user: UserProfile(
          id: '1',
          fullName: 'Dr Owner',
          email: 'nabidentalclinic@gmail.com',
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
        ],
        child: MaterialApp.router(
          routerConfig: GoRouter(
            initialLocation: '/clinic',
            routes: [
              ShellRoute(
                builder: (context, state, child) => ClinicAppShell(child: child),
                routes: [
                  GoRoute(
                    path: '/clinic',
                    builder: (_, __) => const Scaffold(body: Text('Clinic dashboard')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
    navigator.maybePop();
    await tester.pumpAndSettle();

    expect(find.text('Exit the app?'), findsOneWidget);
    expect(find.textContaining('Are you sure you want to exit?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Dashboard'), findsWidgets);
    expect(find.text('Clinic dashboard'), findsOneWidget);
  });

  testWidgets('exit confirm closes the dialog without emptying the navigator', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = SessionController(
      auth: _Auth(),
      tokens: _Tokens(),
      database: _Db(),
    )..state = const SessionState(
        initialized: true,
        hasTokens: true,
        user: UserProfile(
          id: '1',
          fullName: 'Dr Owner',
          email: 'nabidentalclinic@gmail.com',
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
        ],
        child: MaterialApp.router(
          routerConfig: GoRouter(
            initialLocation: '/clinic',
            routes: [
              ShellRoute(
                builder: (context, state, child) => ClinicAppShell(child: child),
                routes: [
                  GoRoute(
                    path: '/clinic',
                    builder: (_, __) => const Scaffold(body: Text('Clinic dashboard')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
    navigator.maybePop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Exit'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Clinic dashboard'), findsOneWidget);
  });
}
