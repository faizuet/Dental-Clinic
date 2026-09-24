import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nabi_dental_app/core/auth/auth_repository.dart';
import 'package:nabi_dental_app/core/auth/session_controller.dart';
import 'package:nabi_dental_app/core/auth/token_storage.dart';
import 'package:nabi_dental_app/core/database/app_database.dart';
import 'package:nabi_dental_app/core/models/session_models.dart';
import 'package:nabi_dental_app/core/security/pin_service.dart';

class _Auth extends Mock implements AuthRepository {}

class _Tokens extends Mock implements TokenStorage {}

class _Pin extends Mock implements PinService {}

class _Db extends Mock implements AppDatabase {}

void main() {
  const user = UserProfile(
    id: '1',
    fullName: 'Owner',
    email: 'owner@example.com',
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
  late _Pin pin;
  late _Db database;
  late SessionController controller;

  setUp(() {
    auth = _Auth();
    tokens = _Tokens();
    pin = _Pin();
    database = _Db();
    controller = SessionController(auth: auth, tokens: tokens, pin: pin, database: database);
  });

  test('first login without a PIN goes to PIN setup', () async {
    when(() => auth.login(email: any(named: 'email'), password: any(named: 'password')))
        .thenAnswer((_) async => (user, clinic));
    when(() => pin.hasPin()).thenAnswer((_) async => false);

    final ok = await controller.login('owner@example.com', 'ChangeMeNow!1');

    expect(ok, isTrue);
    expect(controller.state.gate, AppRouteGate.pinSetup);
    expect(controller.state.user?.email, 'owner@example.com');
  });

  test('logout returns to login even if a profile snapshot remains', () async {
    when(() => auth.logout(allDevices: false)).thenAnswer((_) async {});
    when(() => pin.clear()).thenAnswer((_) async {});
    when(() => database.readSnapshot()).thenAnswer((_) async => (user, clinic));

    await controller.logout();

    expect(controller.state.user?.fullName, 'Owner');
    expect(controller.state.gate, AppRouteGate.login);
  });
}
