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
import 'package:nabi_dental_app/features/clinic_dashboard/treatment_entry_screen.dart';

class _Auth extends Mock implements AuthRepository {}

class _Tokens extends Mock implements TokenStorage {}

class _Db extends Mock implements AppDatabase {}

class _Finance extends Mock implements FinanceRepository {}

void main() {
  testWidgets('new visit prefills the patient from the query', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final finance = _Finance();
    when(() => finance.treatments()).thenAnswer(
      (_) async => const [
        CatalogItem(id: 't1', name: 'Check Up / Consultation', defaultPrice: '1000.00'),
      ],
    );
    when(() => finance.patients()).thenAnswer(
      (_) async => const [
        PatientRecord(id: 'patient-a', name: 'faiz khan', phone: '03189253385'),
        PatientRecord(id: 'patient-b', name: 'Sara Ahmed', phone: '03001234567'),
      ],
    );
    when(() => finance.refresh(force: any(named: 'force'))).thenAnswer((_) async => true);

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
          financeRepositoryProvider.overrideWithValue(finance),
        ],
        child: MaterialApp.router(
          theme: buildAppTheme(),
          routerConfig: GoRouter(
            initialLocation: '/clinic/income?patientId=patient-a',
            routes: [
              GoRoute(path: '/clinic', builder: (_, __) => const SizedBox()),
              GoRoute(
                path: '/clinic/income',
                builder: (_, state) => TreatmentEntryScreen(
                  patientId: state.uri.queryParameters['patientId'],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('faiz khan  ·  03189253385'), findsOneWidget);
    expect(find.text('Sara Ahmed'), findsNothing);
  });
}
