import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

const _channel = MethodChannel('nabi.files');

Future<String?> saveBytes({
  required List<int> bytes,
  required String filename,
  required String mime,
}) async {
  if (Platform.isAndroid) {
    final saved = await _channel.invokeMethod<String>('saveToDownloads', {
      'filename': filename,
      'bytes': Uint8List.fromList(bytes),
      'mime': mime,
    });
    if (saved == null || saved.isEmpty) {
      throw Exception('Could not save $filename to Downloads.');
    }
    return 'Downloads/$filename';
  }

  final directory = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
  final file = File('${directory.path}/$filename');
  await file.writeAsBytes(bytes, flush: true);
  await OpenFilex.open(file.path, type: mime);
  return file.path;
}

Future<String?> saveBytesWithPicker({
  required List<int> bytes,
  required String filename,
  required String mime,
  String label = 'File',
  List<String> extensions = const [],
}) async {
  final location = await getSaveLocation(
    suggestedName: filename,
    acceptedTypeGroups: [
      XTypeGroup(label: label, extensions: extensions),
    ],
  );
  if (location == null) {
    return null;
  }
  await File(location.path).writeAsBytes(bytes, flush: true);
  return location.path;
}
