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

  test('replaces generic not-found copy and hides technical text', () {
    final missing = parseApiError({
      'error': {'code': 'NOT_FOUND', 'message': 'The requested resource was not found.'},
    }, 404);
    expect(missing.message, contains('could not be found'));
    expect(missing.statusCode, 404);

    final technical = parseApiError({
      'error': {'code': 'INTERNAL_ERROR', 'message': 'sqlalchemy.exc.ProgrammingError'},
    }, 500);
    expect(technical.message, contains('unavailable'));
  });
}
