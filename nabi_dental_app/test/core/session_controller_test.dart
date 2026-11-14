import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nabi_dental_app/core/auth/auth_repository.dart';
import 'package:nabi_dental_app/core/auth/session_controller.dart';
import 'package:nabi_dental_app/core/auth/token_storage.dart';
import 'package:nabi_dental_app/core/database/app_database.dart';
import 'package:nabi_dental_app/core/errors/app_exception.dart';
import 'package:nabi_dental_app/core/models/session_models.dart';

class _Auth extends Mock implements AuthRepository {}

class _Tokens extends Mock implements TokenStorage {}

class _Db extends Mock implements AppDatabase {}

void main() {
  const user = UserProfile(
    id: '1',
    fullName: 'Owner',
    email: 'nabidentalclinic@gmail.com',
    role: 'owner',
    defaultHomeBudget: '50000.00',
  );
  const clinic = ClinicProfile(
    id: '1',
    name: 'Nabi Dental Clinic',
    currency: 'PKR',
    timezone: 'Asia/Karachi',
  );

  late _Auth auth;
  late _Tokens tokens;
  late _Db database;
  late SessionController controller;

  setUp(() {
    auth = _Auth();
    tokens = _Tokens();
    database = _Db();
    controller = SessionController(auth: auth, tokens: tokens, database: database);
  });

  test('bootstrap without tokens stays on login', () async {
    when(() => tokens.hasTokens()).thenAnswer((_) async => false);
    when(() => auth.loadCachedProfile()).thenAnswer((_) async => null);

    await controller.bootstrap();

    expect(controller.state.gate, AppRouteGate.login);
    expect(controller.state.hasTokens, isFalse);
  });

  test('bootstrap with a valid session is ready for the dashboard', () async {
    when(() => tokens.hasTokens()).thenAnswer((_) async => true);
    when(() => auth.loadCachedProfile()).thenAnswer((_) async => (user, clinic));
    when(() => auth.restoreSession()).thenAnswer((_) async => (user, clinic));

    await controller.bootstrap();

    expect(controller.state.gate, AppRouteGate.ready);
    expect(controller.state.hasTokens, isTrue);
    expect(controller.state.user?.email, 'nabidentalclinic@gmail.com');
  });

  test('bootstrap with an expired session returns to login', () async {
    when(() => tokens.hasTokens()).thenAnswer((_) async => true);
    when(() => tokens.clear()).thenAnswer((_) async {});
    when(() => auth.loadCachedProfile()).thenAnswer((_) async => (user, clinic));
    when(() => auth.restoreSession()).thenThrow(const UnauthorizedException());

    await controller.bootstrap();

    expect(controller.state.gate, AppRouteGate.login);
    expect(controller.state.hasTokens, isFalse);
    verify(() => tokens.clear()).called(1);
  });

  test('successful login is ready for the clinic dashboard', () async {
    when(() => auth.login(email: any(named: 'email'), password: any(named: 'password')))
        .thenAnswer((_) async => (user, clinic));

    final ok = await controller.login('nabidentalclinic@gmail.com', 'ChangeMeNow!1');

    expect(ok, isTrue);
    expect(controller.state.gate, AppRouteGate.ready);
    expect(controller.state.hasTokens, isTrue);
    expect(controller.state.user?.email, 'nabidentalclinic@gmail.com');
    expect(controller.state.clinic?.name, 'Nabi Dental Clinic');
  });

  test('invalid credentials stay on login with an error', () async {
    when(() => auth.login(email: any(named: 'email'), password: any(named: 'password')))
        .thenThrow(const UnauthorizedException('Invalid email or password.'));

    final ok = await controller.login('nabidentalclinic@gmail.com', 'wrong');

    expect(ok, isFalse);
    expect(controller.state.gate, AppRouteGate.login);
    expect(controller.state.error, 'Invalid email or password.');
  });

  test('logout returns to login even if a profile snapshot remains', () async {
    when(() => auth.logout(allDevices: false)).thenAnswer((_) async {});
    when(() => database.readSnapshot()).thenAnswer((_) async => (user, clinic));

    await controller.logout();

    expect(controller.state.user?.fullName, 'Owner');
    expect(controller.state.hasTokens, isFalse);
    expect(controller.state.gate, AppRouteGate.login);
  });

  test('markUnauthenticated drops a ready session back to login', () {
    controller.state = const SessionState(initialized: true, hasTokens: true, user: user, clinic: clinic);

    controller.markUnauthenticated();

    expect(controller.state.gate, AppRouteGate.login);
    expect(controller.state.hasTokens, isFalse);
  });
}
