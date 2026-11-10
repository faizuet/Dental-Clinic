import 'package:flutter_test/flutter_test.dart';
import 'package:nabi_dental_app/core/auth/session_controller.dart';
import 'package:nabi_dental_app/core/models/session_models.dart';

void main() {
  const user = UserProfile(
    id: '1',
    fullName: 'Owner',
    email: 'owner@example.com',
    role: 'owner',
    defaultHomeBudget: '50000.00',
  );

  test('cold start stays on splash until bootstrap finishes', () {
    expect(const SessionState().gate, AppRouteGate.splash);
  });

  test('signed-out snapshot still routes to login', () {
    const state = SessionState(initialized: true, user: user);
    expect(state.gate, AppRouteGate.login);
  });

  test('tokens take the owner to the clinic dashboard', () {
    const state = SessionState(initialized: true, hasTokens: true);
    expect(state.gate, AppRouteGate.ready);
  });
}
