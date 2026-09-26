import '../errors/app_exception.dart';

const _genericFailure = 'Something went wrong. Please try again.';
const _notFound = 'The requested item could not be found. Please refresh and try again.';
const _serverUnavailable = 'The server is temporarily unavailable. Please try again.';

AppException parseApiError(Object? data, int? statusCode) {
  if (data is Map && data['error'] is Map) {
    final error = data['error'] as Map;
    final details = <String, String>{};
    final rawDetails = error['details'];
    if (rawDetails is List) {
      for (final item in rawDetails) {
        if (item is Map && item['field'] != null) {
          details['${item['field']}'] = '${item['message'] ?? 'Invalid value.'}';
        }
      }
    }
    final code = error['code']?.toString();
    return AppException(
      sanitizeErrorMessage(error['message'], statusCode: statusCode, code: code),
      code: code,
      statusCode: statusCode,
      fieldErrors: details,
    );
  }
  if (statusCode == 401) {
    return const UnauthorizedException();
  }
  return AppException(
    sanitizeErrorMessage(null, statusCode: statusCode),
    code: _codeForStatus(statusCode),
    statusCode: statusCode,
  );
}

String sanitizeErrorMessage(Object? raw, {int? statusCode, String? code}) {
  final text = raw?.toString().trim() ?? '';
  if (text.isNotEmpty && !_looksTechnical(text) && !_isGenericNotFound(text)) {
    return text;
  }
  return _fallbackMessage(statusCode: statusCode, code: code);
}

bool _isGenericNotFound(String text) {
  final lower = text.toLowerCase();
  return lower == 'not found' || lower == 'the requested resource was not found.';
}

bool _looksTechnical(String text) {
  final lower = text.toLowerCase();
  return lower.contains('exception') ||
      lower.contains('traceback') ||
      lower.contains('stack') ||
      lower.contains('sqlalchemy') ||
      lower.contains('asyncpg') ||
      lower.contains('postgres') ||
      lower.contains('socketexception') ||
      lower.contains('is not a subtype') ||
      lower.contains('typeerror') ||
      lower.contains('null check operator') ||
      lower.contains('file://') ||
      lower.contains('package:flutter');
}

String _fallbackMessage({int? statusCode, String? code}) {
  if (code == 'NOT_FOUND' || statusCode == 404) {
    return _notFound;
  }
  if (code == 'FORBIDDEN' || statusCode == 403) {
    return 'You do not have permission to do that.';
  }
  if (code == 'RATE_LIMITED' || statusCode == 429) {
    return 'Too many attempts. Please wait and try again.';
  }
  if (code == 'CONFLICT' || statusCode == 409) {
    return 'This record conflicts with an existing save. Please refresh and try again.';
  }
  if (code == 'INTERNAL_ERROR' || code == 'DEPENDENCY_UNAVAILABLE' || (statusCode != null && statusCode >= 500)) {
    return _serverUnavailable;
  }
  return _genericFailure;
}

String? _codeForStatus(int? statusCode) {
  return switch (statusCode) {
    403 => 'FORBIDDEN',
    404 => 'NOT_FOUND',
    409 => 'CONFLICT',
    422 => 'VALIDATION_ERROR',
    429 => 'RATE_LIMITED',
    final value when value != null && value >= 500 => 'SERVER',
    _ => null,
  };
}
