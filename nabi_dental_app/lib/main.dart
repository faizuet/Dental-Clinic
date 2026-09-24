import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/database/sqlite_init_io.dart' if (dart.library.html) 'core/database/sqlite_init_web.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  initDesktopSqlite();
  runApp(const ProviderScope(child: NabiDentalApp()));
}
