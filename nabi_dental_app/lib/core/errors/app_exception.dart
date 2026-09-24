class AppException implements Exception {
  const AppException(this.message, {this.code, this.fieldErrors = const {}});

  final String message;
  final String? code;
  final Map<String, String> fieldErrors;

  @override
  String toString() => message;
}

class OfflineException extends AppException {
  const OfflineException()
      : super('Could not reach the server. Keep the phone connected and confirm the API is running.');
}

class UnauthorizedException extends AppException {
  const UnauthorizedException([super.message = 'Please sign in again.']);
}
