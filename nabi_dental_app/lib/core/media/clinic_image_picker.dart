import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

class ClinicPickedImage {
  const ClinicPickedImage({required this.bytes, required this.filename});

  final Uint8List bytes;
  final String filename;
}

bool get clinicCameraAvailable =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

String clinicUploadFilename(String raw) {
  var name = raw.replaceAll('\\', '/').split('/').last.trim();
  name = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  if (name.isEmpty || name == '.' || name == '..') {
    name = 'image.jpg';
  }
  final lower = name.toLowerCase();
  if (!(lower.endsWith('.jpg') || lower.endsWith('.jpeg') || lower.endsWith('.png') || lower.endsWith('.webp'))) {
    name = '$name.jpg';
  }
  if (name.length > 80) {
    final ext = name.substring(name.lastIndexOf('.'));
    name = 'image$ext';
  }
  return name;
}

String sniffImageContentType(List<int> bytes, String filename) {
  if (bytes.length >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
    return 'image/jpeg';
  }
  if (bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47) {
    return 'image/png';
  }
  if (bytes.length >= 12 && bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[8] == 0x57 && bytes[9] == 0x45) {
    return 'image/webp';
  }
  final lower = filename.toLowerCase();
  if (lower.endsWith('.png')) {
    return 'image/png';
  }
  if (lower.endsWith('.webp')) {
    return 'image/webp';
  }
  return 'image/jpeg';
}

Future<ClinicPickedImage?> pickClinicImage({bool fromCamera = false}) async {
  if (fromCamera && clinicCameraAvailable) {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.camera,
      maxWidth: 1600,
      imageQuality: 80,
    );
    if (picked == null) {
      return null;
    }
    return ClinicPickedImage(
      bytes: await picked.readAsBytes(),
      filename: clinicUploadFilename(picked.name),
    );
  }

  const group = XTypeGroup(
    label: 'Images',
    extensions: ['jpg', 'jpeg', 'png', 'webp'],
  );
  final file = await openFile(acceptedTypeGroups: [group]);
  if (file == null) {
    return null;
  }
  final name = file.name.isNotEmpty ? file.name : file.path;
  return ClinicPickedImage(
    bytes: await file.readAsBytes(),
    filename: clinicUploadFilename(name),
  );
}
