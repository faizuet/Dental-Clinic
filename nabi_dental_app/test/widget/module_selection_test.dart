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

SessionController _session() {
  return SessionController(
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
}

GoRouter _router({required String initialLocation}) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      ShellRoute(
        builder: (context, state, child) => ClinicAppShell(child: child),
        routes: [
          GoRoute(
            path: '/clinic',
            builder: (_, __) => const Scaffold(body: Text('Clinic dashboard')),
          ),
          GoRoute(
            path: '/home',
            builder: (_, __) => const Scaffold(body: Text('Home dashboard')),
          ),
          GoRoute(
            path: '/settings',
            builder: (_, __) => const Scaffold(body: Text('Settings')),
          ),
        ],
      ),
    ],
  );
}

void main() {
  testWidgets('desktop shell shows clinic navigation without construction', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionProvider.overrideWith((ref) => _session()),
        ],
        child: MaterialApp.router(routerConfig: _router(initialLocation: '/clinic')),
      ),
    );

    expect(find.text('Clinic'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Dashboard'), findsWidgets);
    expect(find.text('Patients'), findsOneWidget);
    expect(find.text('Treatments'), findsOneWidget);
    expect(find.text('Expenses'), findsOneWidget);
    expect(find.text('Lab charges'), findsOneWidget);
    expect(find.text('Reports'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Nabi Dental'), findsWidgets);
    expect(find.text('Construction Finance'), findsNothing);
    expect(find.text('Home Finance'), findsNothing);
    expect(find.text('Clinic dashboard'), findsOneWidget);
  });

  testWidgets('desktop shell shows independent home navigation', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionProvider.overrideWith((ref) => _session()),
        ],
        child: MaterialApp.router(routerConfig: _router(initialLocation: '/home')),
      ),
    );

    expect(find.text('Home grocery'), findsOneWidget);
    expect(find.text('Dashboard'), findsWidgets);
    expect(find.text('Expenses'), findsOneWidget);
    expect(find.text('Reports'), findsOneWidget);
    expect(find.text('Settings'), findsWidgets);
    expect(find.text('Patients'), findsNothing);
    expect(find.text('Treatments'), findsNothing);
    expect(find.text('Lab charges'), findsNothing);
    expect(find.text('Construction Finance'), findsNothing);
    expect(find.text('Home dashboard'), findsOneWidget);
  });
}
