import 'app_exception.dart';

const _serverUnreachable =
    'Could not reach the server. Keep the phone connected and confirm the API is running.';

String friendlyError(Object error) {
  if (error is OfflineException) {
    return _serverUnreachable;
  }
  if (error is AppException) {
    return error.message;
  }
  final text = error.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
  final lower = text.toLowerCase();
  if (lower.contains('is not a subtype of type') ||
      lower.contains('typeerror') ||
      lower.contains('in type cast')) {
    return 'Something went wrong while saving. Please try again.';
  }
  if (lower.contains('socket') ||
      lower.contains('failed host lookup') ||
      lower.contains('network is unreachable') ||
      lower.contains('connection refused') ||
      lower.contains('timed out') ||
      lower.contains('timeout')) {
    return _serverUnreachable;
  }
  return text;
}
