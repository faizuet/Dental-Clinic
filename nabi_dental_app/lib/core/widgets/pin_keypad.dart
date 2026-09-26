import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/app_colors.dart';
import 'app_layout.dart';

class PinDots extends StatelessWidget {
  const PinDots({super.key, required this.length, required this.filled});

  final int length;
  final int filled;

  @override
  Widget build(BuildContext context) {
    final compact = AppLayout.isCompact(context);
    final size = compact ? 14.0 : 16.0;
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(length, (index) {
          final active = index < filled;
          return AnimatedContainer(
            duration: AppMotion.of(context, AppMotion.fast),
            curve: AppMotion.standard,
            margin: EdgeInsets.symmetric(horizontal: compact ? 6 : 8),
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active ? AppColors.purple : Colors.transparent,
              border: Border.all(color: active ? AppColors.purple : AppColors.border, width: 2),
            ),
          );
        }),
      ),
    );
  }
}

class PinKeypad extends StatelessWidget {
  const PinKeypad({
    super.key,
    required this.onDigit,
    required this.onBackspace,
    this.onBiometric,
  });

  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback? onBiometric;

  @override
  Widget build(BuildContext context) {
    const keys = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['bio', '0', 'back'],
    ];
    final keySize = AppLayout.keySize(context);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Column(
        children: keys.map((row) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: row
                  .map(
                    (key) => _Key(
                      label: key,
                      size: keySize,
                      onDigit: onDigit,
                      onBackspace: onBackspace,
                      onBiometric: onBiometric,
                    ),
                  )
                  .toList(),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({
    required this.label,
    required this.size,
    required this.onDigit,
    required this.onBackspace,
    this.onBiometric,
  });

  final String label;
  final double size;
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback? onBiometric;

  @override
  Widget build(BuildContext context) {
    if (label == 'bio') {
      return _CircleButton(
        size: size,
        onTap: onBiometric,
        child: Icon(
          Icons.fingerprint_rounded,
          color: onBiometric == null ? AppColors.border : AppColors.purple,
        ),
      );
    }
    if (label == 'back') {
      return _CircleButton(
        size: size,
        onTap: onBackspace,
        child: const Icon(Icons.backspace_outlined, color: AppColors.text),
      );
    }
    return _CircleButton(
      size: size,
      onTap: () => onDigit(label),
      child: Text(label, style: TextStyle(fontSize: size * 0.32, fontWeight: FontWeight.w600)),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({required this.child, required this.size, this.onTap});

  final Widget child;
  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      elevation: 0,
      shadowColor: AppColors.shadow,
      shape: const CircleBorder(side: BorderSide(color: AppColors.border)),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap!();
              },
        child: SizedBox(width: size, height: size, child: Center(child: child)),
      ),
    );
  }
}
