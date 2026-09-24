import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

class AppLayout {
  static bool isCompact(BuildContext context) => MediaQuery.sizeOf(context).width < 360;

  static double horizontalPadding(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < 360) {
      return 16;
    }
    if (width >= 600) {
      return 24;
    }
    return AppSpacing.page;
  }

  static EdgeInsets pagePadding(BuildContext context, {double top = 8, double bottom = 32}) {
    final horizontal = horizontalPadding(context);
    return EdgeInsets.fromLTRB(horizontal, top, horizontal, bottom);
  }

  static double keySize(BuildContext context) {
    final shortest = MediaQuery.sizeOf(context).shortestSide;
    return (shortest / 5.2).clamp(56.0, 76.0);
  }
}

class Stretch extends StatelessWidget {
  const Stretch({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(width: double.infinity, child: child);
  }
}

class MoneyText extends StatelessWidget {
  const MoneyText(
    this.value, {
    super.key,
    this.style,
    this.color,
    this.align = TextAlign.right,
  });

  final String value;
  final TextStyle? style;
  final Color? color;
  final TextAlign align;

  @override
  Widget build(BuildContext context) {
    final resolved = (style ?? Theme.of(context).textTheme.titleMedium)?.copyWith(color: color);
    return Text(
      value,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      softWrap: false,
      textAlign: align,
      style: resolved,
    );
  }
}

class AppBarTitle extends StatelessWidget {
  const AppBarTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, maxLines: 1, overflow: TextOverflow.ellipsis);
  }
}

Future<T?> showAppDialog<T>({
  required BuildContext context,
  required String title,
  required Widget content,
  required List<Widget> actions,
}) {
  return showDialog<T>(
    context: context,
    builder: (dialogContext) {
      final size = MediaQuery.sizeOf(dialogContext);
      final inset = size.width < 360 ? 16.0 : 24.0;
      return AlertDialog(
        insetPadding: EdgeInsets.symmetric(horizontal: inset, vertical: 24),
        title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
        content: SizedBox(
          width: size.width < 480 ? size.width - inset * 2 : 400,
          child: SingleChildScrollView(child: content),
        ),
        actions: actions,
        actionsOverflowButtonSpacing: 8,
      );
    },
  );
}

class PinScreenScaffold extends StatelessWidget {
  const PinScreenScaffold({
    super.key,
    required this.header,
    required this.keypad,
    this.footer,
  });

  final Widget header;
  final Widget keypad;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final padding = AppLayout.pagePadding(context, top: 12, bottom: 16);
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            padding: padding,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: (constraints.maxHeight - padding.vertical).clamp(0.0, double.infinity),
                  maxWidth: AppSpacing.maxContent,
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      header,
                      keypad,
                      if (footer != null) footer!,
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
