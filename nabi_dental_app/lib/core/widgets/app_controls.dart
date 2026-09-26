import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

class AppPressScale extends StatefulWidget {
  const AppPressScale({super.key, required this.child});

  final Widget child;

  @override
  State<AppPressScale> createState() => _AppPressScaleState();
}

class _AppPressScaleState extends State<AppPressScale> {
  var _pressed = false;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    return Listener(
      onPointerDown: (_) => setState(() => _pressed = true),
      onPointerUp: (_) => setState(() => _pressed = false),
      onPointerCancel: (_) => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed && !reduce ? 0.985 : 1,
        duration: AppMotion.fast,
        curve: AppMotion.standard,
        child: widget.child,
      ),
    );
  }
}

class AppBusyButton extends StatelessWidget {
  const AppBusyButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.busyLabel,
    this.icon,
    this.outlined = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final String? busyLabel;
  final IconData? icon;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final text = busy ? (busyLabel ?? label) : label;
    final child = busy
        ? Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: outlined ? AppColors.primary : Colors.white,
                ),
              ),
              const SizedBox(width: 10),
              Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
          )
        : icon == null
            ? Text(text, maxLines: 1, overflow: TextOverflow.ellipsis)
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 20),
                  const SizedBox(width: 8),
                  Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis)),
                ],
              );

    final style = busy
        ? FilledButton.styleFrom(
            disabledBackgroundColor: outlined ? AppColors.card : AppColors.primary.withValues(alpha: 0.72),
            disabledForegroundColor: outlined ? AppColors.primary : Colors.white,
          )
        : null;

    if (outlined) {
      return OutlinedButton(
        onPressed: busy ? null : onPressed,
        style: style,
        child: child,
      );
    }
    return FilledButton(
      onPressed: busy ? null : onPressed,
      style: style,
      child: child,
    );
  }
}

class SkeletonCards extends StatelessWidget {
  const SkeletonCards({super.key, this.count = 3, this.height = 92});

  final int count;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < count; i++)
          Card(
            child: SizedBox(
              height: height,
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.primarySoft,
                        borderRadius: BorderRadius.circular(AppRadii.sm),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            height: 10,
                            width: 92,
                            decoration: BoxDecoration(
                              color: AppColors.border,
                              borderRadius: BorderRadius.circular(AppRadii.full),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            height: 16,
                            width: 148,
                            decoration: BoxDecoration(
                              color: AppColors.primarySoft,
                              borderRadius: BorderRadius.circular(AppRadii.full),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class AppStateSwitch extends StatelessWidget {
  const AppStateSwitch({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: AppMotion.of(context, AppMotion.medium),
      switchInCurve: AppMotion.standard,
      switchOutCurve: AppMotion.accelerate,
      child: child,
    );
  }
}
