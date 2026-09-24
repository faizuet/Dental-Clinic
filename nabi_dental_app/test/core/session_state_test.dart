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

  test('tokens without a PIN require setup', () {
    const state = SessionState(initialized: true, hasTokens: true);
    expect(state.gate, AppRouteGate.pinSetup);
  });

  test('tokens and PIN require local unlock', () {
    const state = SessionState(initialized: true, hasTokens: true, hasPin: true);
    expect(state.gate, AppRouteGate.unlock);
  });

  test('unlocked session is ready', () {
    const state = SessionState(
      initialized: true,
      hasTokens: true,
      hasPin: true,
      unlocked: true,
    );
    expect(state.gate, AppRouteGate.ready);
  });
}
