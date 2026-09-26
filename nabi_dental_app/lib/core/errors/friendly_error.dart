import 'app_exception.dart';

const _offline = 'No internet connection. Please check your connection and try again.';
const _timeout = 'The request timed out. Please try again.';
const _upload = 'The selected image could not be uploaded. Please try another image.';
const _report = 'Unable to generate the report. Please try again.';
const _budget = 'Unable to update the budget. Please try again.';
const _generic = 'Something went wrong. Please try again.';

String friendlyError(Object error, {String? feature}) {
  if (error is OfflineException) {
    return error.message;
  }
  if (error is UnauthorizedException) {
    return error.message;
  }
  if (error is AppException) {
    final mapped = _featureMessage(feature, error);
    if (mapped != null) {
      return mapped;
    }
    return error.message;
  }
  final text = error.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
  final lower = text.toLowerCase();
  if (lower.contains('is not a subtype of type') ||
      lower.contains('typeerror') ||
      lower.contains('in type cast') ||
      lower.contains('null check operator')) {
    return _generic;
  }
  if (lower.contains('timed out') || lower.contains('timeout')) {
    return _timeout;
  }
  if (lower.contains('socket') ||
      lower.contains('failed host lookup') ||
      lower.contains('network is unreachable') ||
      lower.contains('connection refused') ||
      lower.contains('connection reset')) {
    return _offline;
  }
  return _generic;
}

String? _featureMessage(String? feature, AppException error) {
  if (feature == 'budget' && (error.code == 'NOT_FOUND' || error.statusCode == 404 || error.code == 'SERVER')) {
    return _budget;
  }
  if (feature == 'upload' && (error.statusCode == null || error.statusCode! >= 400)) {
    if (error.code == 'VALIDATION_ERROR' && error.message.isNotEmpty) {
      return error.message;
    }
    return _upload;
  }
  if (feature == 'report') {
    return _report;
  }
  return null;
}
