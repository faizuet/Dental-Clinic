import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nabi_dental_app/core/profile/avatar_validation.dart';

void main() {
  test('rejects unsupported files and oversized payloads', () {
    expect(
      validateAvatarFile(filename: 'notes.txt', byteLength: 120),
      'Use a JPG, PNG, or WebP image.',
    );
    expect(
      validateAvatarFile(filename: 'owner.png', byteLength: 0),
      'The selected file is empty.',
    );
    expect(
      validateAvatarFile(filename: 'owner.jpg', byteLength: AvatarLimits.maxBytes + 1),
      'The image must be 2 MB or smaller.',
    );
    expect(validateAvatarFile(filename: 'owner.webp', byteLength: 24000), isNull);
  });

  test('rejects invalid dimensions with plain language', () {
    expect(validateAvatarSize(16, 16), 'The image is too small. Use at least 64×64 pixels.');
    expect(validateAvatarSize(5000, 200), 'The image is too large. Use at most 4096×4096 pixels.');
    expect(validateAvatarSize(128, 128), isNull);
  });

  testWidgets('rejects corrupted bytes as an invalid image', (tester) async {
    final message = await validateAvatarImage(Uint8List.fromList([1, 2, 3, 4]));
    expect(message, 'That file is not a valid image.');
  });
}
