import 'package:flutter_test/flutter_test.dart';
import 'package:nabi_dental_app/core/errors/app_exception.dart';
import 'package:nabi_dental_app/core/errors/friendly_error.dart';

void main() {
  test('maps offline and technical errors to readable copy', () {
    expect(friendlyError(const OfflineException()), contains('server'));
    expect(friendlyError(const AppException('Invalid amount.')), 'Invalid amount.');
    expect(friendlyError(Exception('Failed host lookup')), contains('server'));
    expect(
      friendlyError(Exception("type 'int' is not a subtype of type 'String?' of 'value'")),
      contains('saving'),
    );
  });
}
