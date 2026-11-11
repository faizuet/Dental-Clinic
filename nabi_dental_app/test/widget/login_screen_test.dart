import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nabi_dental_app/app/theme/app_theme.dart';
import 'package:nabi_dental_app/core/auth/auth_repository.dart';
import 'package:nabi_dental_app/core/auth/session_controller.dart';
import 'package:nabi_dental_app/core/auth/token_storage.dart';
import 'package:nabi_dental_app/core/database/app_database.dart';
import 'package:nabi_dental_app/core/errors/app_exception.dart';
import 'package:nabi_dental_app/core/models/session_models.dart';
import 'package:nabi_dental_app/features/authentication/login_screen.dart';

class _Auth extends Mock implements AuthRepository {}

class _Tokens extends Mock implements TokenStorage {}

class _Db extends Mock implements AppDatabase {}

void main() {
  const clinic = ClinicProfile(
    id: '1',
    name: 'Nabi Dental Clinic',
    currency: 'PKR',
    timezone: 'Asia/Karachi',
  );

  late _Auth auth;
  late SessionController controller;

  setUp(() {
    auth = _Auth();
    controller = SessionController(auth: auth, tokens: _Tokens(), database: _Db())
      ..state = const SessionState(initialized: true, clinic: clinic);
  });

  Future<void> pumpLogin(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sessionProvider.overrideWith((ref) => controller)],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const LoginScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('desktop login shows clinic branding without PIN', (tester) async {
    await pumpLogin(tester);

    expect(find.text('Nabi Dental Clinic'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Image && widget.image is AssetImage && (widget.image as AssetImage).assetName.contains('clinic_portrait'),
      ),
      findsOneWidget,
    );
    expect(find.text('Sign in'), findsWidgets);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('PIN'), findsNothing);
    expect(find.textContaining('PIN'), findsNothing);
  });

  testWidgets('empty fields show validation messages', (tester) async {
    await pumpLogin(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('Email is required.'), findsOneWidget);
    expect(find.text('Password is required.'), findsOneWidget);
    verifyNever(() => auth.login(email: any(named: 'email'), password: any(named: 'password')));
  });

  testWidgets('invalid credentials show an error banner', (tester) async {
    when(() => auth.login(email: any(named: 'email'), password: any(named: 'password')))
        .thenThrow(const UnauthorizedException('Invalid email or password.'));

    await pumpLogin(tester);
    await tester.enterText(find.byType(TextFormField).at(0), 'owner@example.com');
    await tester.enterText(find.byType(TextFormField).at(1), 'wrong');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('Invalid email or password.'), findsOneWidget);
    expect(controller.state.hasTokens, isFalse);
  });

  testWidgets('successful login stores the session for the dashboard', (tester) async {
    const user = UserProfile(
      id: '1',
      fullName: 'Owner',
      email: 'owner@example.com',
      role: 'owner',
      defaultHomeBudget: '50000.00',
    );
    when(() => auth.login(email: any(named: 'email'), password: any(named: 'password')))
        .thenAnswer((_) async => (user, clinic));

    await pumpLogin(tester);
    await tester.enterText(find.byType(TextFormField).at(0), 'owner@example.com');
    await tester.enterText(find.byType(TextFormField).at(1), 'ChangeMeNow!1');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    expect(controller.state.gate, AppRouteGate.ready);
    expect(controller.state.hasTokens, isTrue);
  });
}
