import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import 'app_layout.dart';

class AppPageBody extends StatelessWidget {
  const AppPageBody({
    super.key,
    required this.child,
    this.padding,
  });

  final Widget child;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSpacing.maxContent),
          child: SizedBox(
            width: double.infinity,
            child: Padding(padding: padding ?? AppLayout.pagePadding(context), child: child),
          ),
        ),
      ),
    );
  }
}
