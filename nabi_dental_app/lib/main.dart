import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/database/sqlite_init_io.dart' if (dart.library.html) 'core/database/sqlite_init_web.dart';
import 'core/logging/app_logger.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  initDesktopSqlite();
  FlutterError.onError = (details) {
    AppLogger.error('widget', details.exceptionAsString());
    FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    AppLogger.error('uncaught', error);
    return !kDebugMode;
  };
  runApp(const ProviderScope(child: NabiDentalApp()));
}
