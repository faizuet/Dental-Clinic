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
import 'package:nabi_dental_app/core/models/finance_models.dart';
import 'package:nabi_dental_app/core/models/session_models.dart';
import 'package:nabi_dental_app/features/clinic_dashboard/patients_screen.dart';

class _Auth extends Mock implements AuthRepository {}

class _Tokens extends Mock implements TokenStorage {}

class _Db extends Mock implements AppDatabase {}

class _Finance extends Mock implements FinanceRepository {}

void main() {
  testWidgets('patients list shows numbered names from the server', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final finance = _Finance();
    when(() => finance.patients()).thenAnswer(
      (_) async => const [
        PatientRecord(
          id: '1',
          name: 'faiz khan',
          phone: '03189253385',
          createdAt: '2026-11-10T05:58:41.365692+00:00',
        ),
        PatientRecord(id: '2', name: 'Sara Ahmed', phone: '03001234567'),
      ],
    );

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
          financeRepositoryProvider.overrideWithValue(finance),
        ],
        child: MaterialApp.router(
          theme: buildAppTheme(),
          routerConfig: GoRouter(
            initialLocation: '/clinic/patients',
            routes: [
              GoRoute(path: '/clinic', builder: (_, __) => const SizedBox()),
              GoRoute(path: '/clinic/patients', builder: (_, __) => const PatientsScreen()),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('faiz khan'), findsOneWidget);
    expect(find.text('Sara Ahmed'), findsOneWidget);
    expect(find.text('1'), findsWidgets);
    expect(find.text('2'), findsWidgets);
    expect(find.text('Patient'), findsWidgets);
  });
}
