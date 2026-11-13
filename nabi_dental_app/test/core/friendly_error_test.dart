import 'package:flutter_test/flutter_test.dart';
import 'package:nabi_dental_app/core/errors/app_exception.dart';
import 'package:nabi_dental_app/core/errors/friendly_error.dart';

void main() {
  test('maps offline and technical errors to readable copy', () {
    expect(friendlyError(const OfflineException()), contains('connection'));
    expect(friendlyError(const AppException('Invalid amount.')), 'Invalid amount.');
    expect(friendlyError(Exception('Failed host lookup')), contains('connection'));
    expect(
      friendlyError(Exception("type 'int' is not a subtype of type 'String?' of 'value'")),
      contains('try again'),
    );
  });

  test('keeps the X-ray offline rule even when the caller asked for upload copy', () {
    expect(
      friendlyError(
        const AppException(
          'X-ray images can only be saved while the clinic is online. Remove the images, or start Docker and save again.',
          code: 'XRAY_OFFLINE',
        ),
        feature: 'upload',
      ),
      contains('online'),
    );
  });

  test('maps generic not-found budget failures to a budget message', () {
    expect(
      friendlyError(const AppException('The requested resource was not found.', code: 'NOT_FOUND', statusCode: 404), feature: 'budget'),
      contains('budget'),
    );
  });
}
