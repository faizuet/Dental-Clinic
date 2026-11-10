import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

class XrayLimits {
  static const maxBytes = 5000000;
  static const minPx = 64;
  static const maxPx = 8192;
  static const allowedExtensions = {'.jpg', '.jpeg', '.png', '.webp'};
}

String? validateXrayFile({required String filename, required int byteLength}) {
  final name = filename.trim().toLowerCase().replaceAll('\\', '/').split('/').last;
  final dot = name.lastIndexOf('.');
  final extension = dot >= 0 ? name.substring(dot) : '';
  if (extension.isNotEmpty && !XrayLimits.allowedExtensions.contains(extension)) {
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
    final sampleCodec = await ui.instantiateImageCodec(bytes, targetWidth: 96);
    final sampleFrame = await sampleCodec.getNextFrame();
    final sample = sampleFrame.image;
    final dentalError = await _rejectNonDental(sample);
    sample.dispose();
    return dentalError;
  } catch (_) {
    return 'That file is not a valid image.';
  }
}

Future<String?> _rejectNonDental(ui.Image image) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (data == null) {
    return 'That file is not a valid image.';
  }
  final bytes = data.buffer.asUint8List();
  final count = bytes.lengthInBytes ~/ 4;
  if (count == 0) {
    return 'That file is not a valid image.';
  }

  var gray = 0;
  var tooth = 0;
  var gingival = 0;
  var sky = 0;
  var green = 0;
  var skin = 0;
  var luminanceSum = 0.0;
  final luminances = List<double>.filled(count, 0);

  for (var i = 0; i < count; i++) {
    final o = i * 4;
    final r = bytes[o] / 255.0;
    final g = bytes[o + 1] / 255.0;
    final b = bytes[o + 2] / 255.0;
    final mx = math.max(r, math.max(g, b));
    final mn = math.min(r, math.min(g, b));
    final diff = mx - mn;
    final saturation = mx == 0 ? 0.0 : diff / mx;
    final value = mx;
    final luminance = 0.299 * r + 0.587 * g + 0.114 * b;
    luminances[i] = luminance;
    luminanceSum += luminance;
    if (saturation < 0.12) {
      gray++;
    }
    final hue = _hue(r, g, b, mx, diff);
    if (value > 0.72 && saturation < 0.22 && luminance > 0.62) {
      tooth++;
    }
    if (saturation >= 0.15 && value >= 0.25 && value <= 0.92 && (hue <= 25 || hue >= 335)) {
      gingival++;
    }
    if (hue >= 190 && hue <= 245 && saturation > 0.25 && value > 0.35) {
      sky++;
    }
    if (hue >= 70 && hue <= 160 && saturation > 0.28 && value > 0.2) {
      green++;
    }
    if (hue >= 12 && hue <= 42 && saturation >= 0.18 && saturation <= 0.62 && value >= 0.28 && value <= 0.9) {
      skin++;
    }
  }

  final meanL = luminanceSum / count;
  var variance = 0.0;
  for (final item in luminances) {
    final d = item - meanL;
    variance += d * d;
  }
  final contrast = math.sqrt(variance / count);
  final grayRatio = gray / count;
  final toothRatio = tooth / count;
  final gingivalRatio = gingival / count;
  final skyRatio = sky / count;
  final greenRatio = green / count;
  final skinRatio = skin / count;

  final looksLikeXray = grayRatio >= 0.55 && meanL >= 0.06 && meanL <= 0.88;
  final looksIntraoral = toothRatio >= 0.02 && gingivalRatio >= 0.012;
  final looksTeethCloseup = toothRatio >= 0.07;
  final looksOralSoftTissue = gingivalRatio >= 0.07;
  final looksClinical = looksLikeXray || looksIntraoral || looksTeethCloseup || looksOralSoftTissue;

  const rejected = 'This does not look like a dental X-ray or intraoral photo. Choose a clinical image.';
  if (skyRatio >= 0.18 && greenRatio >= 0.12 && !looksClinical) {
    return rejected;
  }
  if (skyRatio >= 0.3 && !looksClinical) {
    return rejected;
  }
  if (greenRatio >= 0.38 && toothRatio < 0.02 && !looksLikeXray) {
    return rejected;
  }
  if (skinRatio >= 0.38 && toothRatio < 0.015 && gingivalRatio < 0.02 && !looksLikeXray) {
    return 'This looks like a personal photo rather than a dental image. Choose an X-ray or intraoral photo.';
  }
  if (contrast < 0.03 && grayRatio < 0.5 && !looksClinical) {
    return rejected;
  }
  if (!looksClinical) {
    return rejected;
  }
  return null;
}

double _hue(double r, double g, double b, double mx, double diff) {
  if (diff == 0) {
    return 0;
  }
  if (mx == r) {
    return (60 * ((g - b) / diff) + 360) % 360;
  }
  if (mx == g) {
    return (60 * ((b - r) / diff) + 120) % 360;
  }
  return (60 * ((r - g) / diff) + 240) % 360;
}
