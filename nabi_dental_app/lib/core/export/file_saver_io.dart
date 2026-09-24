import 'dart:io';

import 'package:path_provider/path_provider.dart';

Future<String?> saveBytes({
  required List<int> bytes,
  required String filename,
  required String mime,
}) async {
  final directory = await getApplicationDocumentsDirectory();
  final file = File('${directory.path}/$filename');
  await file.writeAsBytes(bytes);
  return file.path;
}
