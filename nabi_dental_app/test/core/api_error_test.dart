import 'package:flutter_test/flutter_test.dart';
import 'package:nabi_dental_app/core/api/api_error.dart';
import 'package:nabi_dental_app/core/errors/app_exception.dart';

void main() {
  test('parses API error envelopes', () {
    final error = parseApiError({
      'error': {
        'code': 'VALIDATION_ERROR',
        'message': 'Check the form.',
        'details': [
          {'field': 'email', 'message': 'Invalid email.'},
        ],
      },
    }, 422);

    expect(error.message, 'Check the form.');
    expect(error.code, 'VALIDATION_ERROR');
    expect(error.fieldErrors['email'], 'Invalid email.');
  });

  test('maps 401 without a body to unauthorized', () {
    final error = parseApiError(null, 401);
    expect(error, isA<UnauthorizedException>());
  });
}
