class AppException implements Exception {
  const AppException(
    this.message, {
    this.code,
    this.statusCode,
    this.fieldErrors = const {},
  });

  final String message;
  final String? code;
  final int? statusCode;
  final Map<String, String> fieldErrors;

  @override
  String toString() => message;
}

class OfflineException extends AppException {
  const OfflineException()
      : super(
          'No internet connection. Please check your connection and try again.',
          code: 'NETWORK',
        );
}

class UnauthorizedException extends AppException {
  const UnauthorizedException([super.message = 'Please sign in again.']);
}
