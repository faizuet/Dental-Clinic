import 'dart:typed_data';
import 'dart:ui' as ui;

class XrayLimits {
  static const maxBytes = 5000000;
  static const minPx = 64;
  static const maxPx = 8192;
  static const allowedExtensions = {'.jpg', '.jpeg', '.png', '.webp'};
}

String? validateXrayFile({required String filename, required int byteLength}) {
  final name = filename.trim().toLowerCase();
  final dot = name.lastIndexOf('.');
  final extension = dot >= 0 ? name.substring(dot) : '';
  if (!XrayLimits.allowedExtensions.contains(extension)) {
    return 'Use a JPG, PNG, or WebP image.';
  }
  if (byteLength <= 0) {
    return 'The selected file is empty.';
  }
  if (byteLength > XrayLimits.maxBytes) {
    return 'The X-ray must be 5 MB or smaller.';
  }
  return null;
}

Future<String?> validateXrayImage(Uint8List bytes) async {
  if (bytes.isEmpty) {
    return 'The selected file is empty.';
  }
  if (bytes.length > XrayLimits.maxBytes) {
    return 'The X-ray must be 5 MB or smaller.';
  }
  try {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final width = image.width;
    final height = image.height;
    image.dispose();
    if (width < XrayLimits.minPx || height < XrayLimits.minPx) {
      return 'The image is too small. Use at least 64×64 pixels.';
    }
    if (width > XrayLimits.maxPx || height > XrayLimits.maxPx) {
      return 'The image is too large. Use at most 8192×8192 pixels.';
    }
    return null;
  } catch (_) {
    return 'That file is not a valid image.';
  }
}
