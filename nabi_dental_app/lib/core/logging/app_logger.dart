import 'package:flutter/foundation.dart';

class AppLogger {
  static void info(String operation, {String? path}) {
    debugPrint(_line(operation, path: path));
  }

  static void error(
    String operation,
    Object error, {
    String? path,
    int? status,
  }) {
    debugPrint(_line(operation, path: path, status: status, error: error));
  }

  static String _line(String operation, {String? path, int? status, Object? error}) {
    final parts = <String>['[nabi]', operation];
    if (path != null && path.isNotEmpty) {
      parts.add('path=${_safe(path)}');
    }
    if (status != null) {
      parts.add('status=$status');
    }
    if (error != null) {
      parts.add('error=${_safe(error.toString())}');
    }
    return parts.join(' ');
  }

  static String _safe(String value) {
    return value
        .replaceAll(RegExp(r'Bearer\s+[A-Za-z0-9._\-]+'), 'Bearer [redacted]')
        .replaceAll(RegExp(r'password["\s:=]+[^,\s}]+', caseSensitive: false), 'password=[redacted]')
        .replaceAll(RegExp(r'refresh_token["\s:=]+[^,\s}]+', caseSensitive: false), 'refresh_token=[redacted]');
  }
}
