import 'dart:typed_data';
import 'dart:ui' as ui;

class AvatarLimits {
  static const maxBytes = 2000000;
  static const minPx = 64;
  static const maxPx = 4096;
  static const allowedExtensions = {'.jpg', '.jpeg', '.png', '.webp'};
}

String? validateAvatarFile({required String filename, required int byteLength}) {
  final name = filename.trim().toLowerCase();
  final dot = name.lastIndexOf('.');
  final extension = dot >= 0 ? name.substring(dot) : '';
  if (!AvatarLimits.allowedExtensions.contains(extension)) {
    return 'Use a JPG, PNG, or WebP image.';
  }
  if (byteLength <= 0) {
    return 'The selected file is empty.';
  }
  if (byteLength > AvatarLimits.maxBytes) {
    return 'The image must be 2 MB or smaller.';
  }
  return null;
}

String? validateAvatarSize(int width, int height) {
  if (width < AvatarLimits.minPx || height < AvatarLimits.minPx) {
    return 'The image is too small. Use at least 64×64 pixels.';
  }
  if (width > AvatarLimits.maxPx || height > AvatarLimits.maxPx) {
    return 'The image is too large. Use at most 4096×4096 pixels.';
  }
  return null;
}

Future<String?> validateAvatarImage(Uint8List bytes) async {
  if (bytes.isEmpty) {
    return 'The selected file is empty.';
  }
  if (bytes.length > AvatarLimits.maxBytes) {
    return 'The image must be 2 MB or smaller.';
  }
  try {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final width = image.width;
    final height = image.height;
    image.dispose();
    return validateAvatarSize(width, height);
  } catch (_) {
    return 'That file is not a valid image.';
  }
}
