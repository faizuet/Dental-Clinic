import 'package:flutter_test/flutter_test.dart';
import 'package:nabi_dental_app/core/auth/session_controller.dart';

void main() {
  test('cold start stays on splash', () {
    expect(const SessionState().gate, AppRouteGate.splash);
  });
}
