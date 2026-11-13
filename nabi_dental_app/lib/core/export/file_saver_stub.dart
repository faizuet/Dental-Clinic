Future<String?> saveBytes({
  required List<int> bytes,
  required String filename,
  required String mime,
}) async {
  return filename;
}

Future<String?> saveBytesWithPicker({
  required List<int> bytes,
  required String filename,
  required String mime,
  String label = 'File',
  List<String> extensions = const [],
}) {
  return saveBytes(bytes: bytes, filename: filename, mime: mime);
}
