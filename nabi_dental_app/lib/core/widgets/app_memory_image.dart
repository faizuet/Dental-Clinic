import 'dart:typed_data';

import 'package:flutter/material.dart';

class AppMemoryImage extends StatelessWidget {
  const AppMemoryImage({
    super.key,
    required this.bytes,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.filterQuality = FilterQuality.low,
  });

  final List<int> bytes;
  final double? width;
  final double? height;
  final BoxFit fit;
  final FilterQuality filterQuality;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final data = bytes is Uint8List ? bytes as Uint8List : Uint8List.fromList(bytes);
    return Image.memory(
      data,
      width: width,
      height: height,
      fit: fit,
      cacheWidth: width == null ? null : (width! * dpr).round().clamp(1, 4096),
      cacheHeight: height == null ? null : (height! * dpr).round().clamp(1, 4096),
      filterQuality: filterQuality,
      gaplessPlayback: true,
    );
  }
}
