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
import 'package:nabi_dental_app/core/errors/app_exception.dart';
import 'package:nabi_dental_app/core/finance/finance_repository.dart';
import 'package:nabi_dental_app/core/models/finance_models.dart';
import 'package:nabi_dental_app/core/models/session_models.dart';
import 'package:nabi_dental_app/core/utils/phone.dart';
import 'package:nabi_dental_app/features/clinic_dashboard/patients_screen.dart';

class _Auth extends Mock implements AuthRepository {}

class _Tokens extends Mock implements TokenStorage {}

class _Db extends Mock implements AppDatabase {}

class _Finance extends Mock implements FinanceRepository {}

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
}

Future<void> _pumpPatients(WidgetTester tester, _Finance finance) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sessionProvider.overrideWith((ref) => _session()),
        financeRepositoryProvider.overrideWithValue(finance),
      ],
      child: MaterialApp.router(
        theme: buildAppTheme(),
        routerConfig: GoRouter(
          initialLocation: '/clinic/patients',
          routes: [
            GoRoute(path: '/clinic', builder: (_, __) => const SizedBox()),
            GoRoute(path: '/clinic/patients', builder: (_, __) => const PatientsScreen()),
            GoRoute(
              path: '/clinic/patients/:id',
              builder: (_, state) => Text('record-${state.pathParameters['id']}'),
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    registerFallbackValue(const PatientRecord(id: '0', name: 'fallback'));
  });

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
              GoRoute(
                path: '/clinic/patients/:id',
                builder: (_, state) => Text('record-${state.pathParameters['id']}'),
              ),
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

  testWidgets('clicking a patient name opens that patient record', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final finance = _Finance();
    when(() => finance.patients()).thenAnswer(
      (_) async => const [
        PatientRecord(id: 'patient-a', name: 'faiz khan', phone: '03189253385'),
        PatientRecord(id: 'patient-b', name: 'Sara Ahmed', phone: '03001234567'),
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
              GoRoute(
                path: '/clinic/patients/:id',
                builder: (_, state) => Text('record-${state.pathParameters['id']}'),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('faiz khan'));
    await tester.pumpAndSettle();

    expect(find.text('record-patient-a'), findsOneWidget);
    expect(find.text('record-patient-b'), findsNothing);
  });

  testWidgets('Open button opens that patient record', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final finance = _Finance();
    when(() => finance.patients()).thenAnswer(
      (_) async => const [
        PatientRecord(id: 'patient-a', name: 'faiz khan', phone: '03189253385'),
        PatientRecord(id: 'patient-b', name: 'Sara Ahmed', phone: '03001234567'),
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
              GoRoute(
                path: '/clinic/patients/:id',
                builder: (_, state) => Text('record-${state.pathParameters['id']}'),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Open').first);
    await tester.pumpAndSettle();

    expect(find.text('record-patient-a'), findsOneWidget);
    expect(find.text('record-patient-b'), findsNothing);
  });

  testWidgets('rejects an invalid Pakistani phone number on save', (tester) async {
    final finance = _Finance();
    when(() => finance.patients()).thenAnswer((_) async => const <PatientRecord>[]);
    when(() => finance.refresh(force: any(named: 'force'))).thenAnswer((_) async => true);

    await _pumpPatients(tester, finance);
    await tester.tap(find.byTooltip('Add patient'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Patient name'), 'Ali Khan');
    await tester.enterText(find.widgetWithText(TextFormField, 'Phone number'), '0300123456');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text(pakistaniMobileMessage), findsOneWidget);
    verifyNever(() => finance.savePatient(name: any(named: 'name'), phone: any(named: 'phone')));
  });

  testWidgets('warns when a new patient reuses a live mobile number', (tester) async {
    final finance = _Finance();
    when(() => finance.patients()).thenAnswer(
      (_) async => const [
        PatientRecord(id: '1', name: 'Sara Ahmed', phone: '03001234567'),
      ],
    );
    when(() => finance.refresh(force: any(named: 'force'))).thenAnswer((_) async => true);

    await _pumpPatients(tester, finance);
    await tester.tap(find.byTooltip('Add patient'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Patient name'), 'Ali Khan');
    await tester.enterText(find.widgetWithText(TextFormField, 'Phone number'), '03001234567');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.textContaining('already used by Sara Ahmed'), findsOneWidget);
    verifyNever(() => finance.savePatient(name: any(named: 'name'), phone: any(named: 'phone')));
  });

  testWidgets('canceling patient delete leaves the list unchanged', (tester) async {
    final finance = _Finance();
    when(() => finance.patients()).thenAnswer(
      (_) async => const [
        PatientRecord(id: '1', name: 'faiz khan', phone: '03189253385'),
        PatientRecord(id: '2', name: 'Sara Ahmed', phone: '03001234567'),
      ],
    );
    when(() => finance.refresh(force: any(named: 'force'))).thenAnswer((_) async => true);

    await _pumpPatients(tester, finance);
    await tester.tap(find.byTooltip('Delete').first);
    await tester.pumpAndSettle();
    expect(find.text('Delete Patient?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('faiz khan'), findsOneWidget);
    expect(find.text('Sara Ahmed'), findsOneWidget);
    verifyNever(() => finance.deletePatient(any()));
  });

  testWidgets('confirming patient delete removes the row immediately', (tester) async {
    final finance = _Finance();
    when(() => finance.patients()).thenAnswer(
      (_) async => const [
        PatientRecord(id: '1', name: 'faiz khan', phone: '03189253385'),
        PatientRecord(id: '2', name: 'Sara Ahmed', phone: '03001234567'),
      ],
    );
    when(() => finance.refresh(force: any(named: 'force'))).thenAnswer((_) async => true);
    when(() => finance.deletePatient(any())).thenAnswer((_) async {});

    await _pumpPatients(tester, finance);
    await tester.tap(find.byTooltip('Delete').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete Patient'));
    await tester.pumpAndSettle();

    expect(find.text('faiz khan'), findsNothing);
    expect(find.text('Sara Ahmed'), findsOneWidget);
    expect(find.text('Patient deleted successfully.'), findsOneWidget);
    verify(() => finance.deletePatient(any())).called(1);
  });

  testWidgets('failed patient delete keeps the row and shows an error', (tester) async {
    final finance = _Finance();
    when(() => finance.patients()).thenAnswer(
      (_) async => const [
        PatientRecord(id: '1', name: 'faiz khan', phone: '03189253385'),
      ],
    );
    when(() => finance.refresh(force: any(named: 'force'))).thenAnswer((_) async => true);
    when(() => finance.deletePatient(any())).thenThrow(
      const AppException('The patient could not be deleted.', code: 'SERVER', statusCode: 500),
    );

    await _pumpPatients(tester, finance);
    await tester.tap(find.byTooltip('Delete').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete Patient'));
    await tester.pumpAndSettle();

    expect(find.text('Delete Patient?'), findsOneWidget);
    expect(find.text('The patient could not be deleted.'), findsOneWidget);
    expect(find.text('faiz khan'), findsOneWidget);
    expect(find.text('Patient deleted successfully.'), findsNothing);
  });
}
