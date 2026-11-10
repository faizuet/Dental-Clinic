import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:nabi_dental_app/core/dental/xray_validation.dart';
import 'package:nabi_dental_app/core/media/clinic_image_picker.dart';

Future<Uint8List> _png({
  required int width,
  required int height,
  required void Function(ui.Canvas canvas, ui.Size size) paint,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  paint(canvas, ui.Size(width.toDouble(), height.toDouble()));
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return bytes!.buffer.asUint8List();
}

void main() {
  test('rejects unsupported files and empty payloads', () {
    expect(validateXrayFile(filename: 'notes.txt', byteLength: 120), 'Use a JPG, PNG, or WebP image.');
    expect(validateXrayFile(filename: 'scan.png', byteLength: 0), 'The selected file is empty.');
    expect(validateXrayFile(filename: 'scan.jpg', byteLength: XrayLimits.maxBytes + 1), 'The X-ray must be 5 MB or smaller.');
    expect(validateXrayFile(filename: r'C:\Clinic\scan.JPG', byteLength: 24000), isNull);
  });

  test('sanitizes Windows paths for upload', () {
    expect(clinicUploadFilename(r'C:\Users\Owner\Pictures\xray 1.png'), 'xray_1.png');
    expect(clinicUploadFilename('photo'), 'photo.jpg');
  });

  testWidgets('rejects corrupted bytes as an invalid image', (tester) async {
    await tester.runAsync(() async {
      final message = await validateXrayImage(Uint8List.fromList([1, 2, 3, 4]));
      expect(message, 'That file is not a valid image.');
    });
  });

  testWidgets('accepts an X-ray-like grayscale image', (tester) async {
    await tester.runAsync(() async {
      final bytes = await _png(
        width: 160,
        height: 160,
        paint: (canvas, size) {
          canvas.drawRect(Offset.zero & size, ui.Paint()..color = const ui.Color(0xFF121212));
          canvas.drawCircle(Offset(size.width / 2, size.height / 2), 48, ui.Paint()..color = const ui.Color(0xFFC8C8C8));
        },
      );
      expect(await validateXrayImage(bytes), isNull);
    });
  });

  testWidgets('accepts an intraoral-like photograph', (tester) async {
    await tester.runAsync(() async {
      final bytes = await _png(
        width: 160,
        height: 160,
        paint: (canvas, size) {
          canvas.drawRect(Offset.zero & size, ui.Paint()..color = const ui.Color(0xFFB44650));
          canvas.drawRect(
            const ui.Rect.fromLTWH(36, 44, 88, 72),
            ui.Paint()..color = const ui.Color(0xFFF6F1E6),
          );
        },
      );
      expect(await validateXrayImage(bytes), isNull);
    });
  });

  testWidgets('rejects a landscape photograph', (tester) async {
    await tester.runAsync(() async {
      final bytes = await _png(
        width: 160,
        height: 160,
        paint: (canvas, size) {
          canvas.drawRect(ui.Rect.fromLTWH(0, 0, size.width, size.height / 2), ui.Paint()..color = const ui.Color(0xFF50A4EB));
          canvas.drawRect(ui.Rect.fromLTWH(0, size.height / 2, size.width, size.height / 2), ui.Paint()..color = const ui.Color(0xFF2E9438));
        },
      );
      final message = await validateXrayImage(bytes);
      expect(message, isNotNull);
      expect(message!.toLowerCase(), contains('dental'));
    });
  });
}
