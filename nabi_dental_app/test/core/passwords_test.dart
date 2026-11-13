import 'package:flutter_test/flutter_test.dart';
import 'package:nabi_dental_app/core/auth/passwords.dart';

void main() {
  test('detects the example owner password', () {
    expect(isExampleOwnerPassword('ChangeMeNow!1'), isTrue);
    expect(isExampleOwnerPassword('ClinicOwnerPass9'), isFalse);
  });
}
