import 'dart:io';

import 'package:flutter/foundation.dart';

class AppConfig {
  static const String appName = 'Nabi Dental Clinic';

  static String get apiBaseUrl {
    const fromDefine = String.fromEnvironment('API_BASE_URL');
    if (fromDefine.isNotEmpty) {
      return fromDefine;
    }
    if (!kIsWeb && Platform.isAndroid) {
      return 'http://10.0.2.2:8001';
    }
    return 'http://localhost:8001';
  }
}
