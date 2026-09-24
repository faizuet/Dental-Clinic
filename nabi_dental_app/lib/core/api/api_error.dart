import '../errors/app_exception.dart';

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
    return AppException(
      '${error['message'] ?? 'The request failed.'}',
      code: error['code']?.toString(),
      fieldErrors: details,
    );
  }
  if (statusCode == 401) {
    return const UnauthorizedException();
  }
  return const AppException('Something went wrong. Please try again.');
}
