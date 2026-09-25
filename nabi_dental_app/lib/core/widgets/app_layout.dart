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

enum AppDialogTone { neutral, warning, danger }

Future<T?> showAppDialog<T>({
  required BuildContext context,
  required String title,
  required Widget content,
  required List<Widget> actions,
  IconData? icon,
  AppDialogTone tone = AppDialogTone.neutral,
}) {
  return showDialog<T>(
    context: context,
    builder: (dialogContext) {
      final size = MediaQuery.sizeOf(dialogContext);
      final inset = size.width < 360 ? 16.0 : 24.0;
      final color = switch (tone) {
        AppDialogTone.danger => AppColors.danger,
        AppDialogTone.warning => AppColors.warning,
        AppDialogTone.neutral => AppColors.purple,
      };
      final soft = switch (tone) {
        AppDialogTone.danger => AppColors.dangerSoft,
        AppDialogTone.warning => AppColors.warningSoft,
        AppDialogTone.neutral => AppColors.purpleSoft,
      };
      return AlertDialog(
        insetPadding: EdgeInsets.symmetric(horizontal: inset, vertical: 24),
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
        actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (icon != null) ...[
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: soft, borderRadius: BorderRadius.circular(AppRadii.md)),
                child: Icon(icon, color: color),
              ),
              const SizedBox(height: 14),
            ],
            Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ),
        content: SizedBox(
          width: size.width < 480 ? size.width - inset * 2 : 400,
          child: SingleChildScrollView(
            child: DefaultTextStyle(
              style: Theme.of(dialogContext).textTheme.bodyMedium!.copyWith(color: AppColors.muted, height: 1.45),
              child: content,
            ),
          ),
        ),
        actions: actions,
        actionsOverflowButtonSpacing: 8,
        actionsAlignment: MainAxisAlignment.end,
      );
    },
  );
}

Future<bool> showAppConfirmDialog({
  required BuildContext context,
  required String title,
  required String message,
  String cancelLabel = 'Cancel',
  String confirmLabel = 'Confirm',
  bool destructive = false,
  IconData? icon,
}) async {
  final result = await showAppDialog<bool>(
    context: context,
    title: title,
    icon: icon ?? (destructive ? Icons.warning_amber_rounded : Icons.help_outline_rounded),
    tone: destructive ? AppDialogTone.danger : AppDialogTone.neutral,
    content: Text(message),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context, false), child: Text(cancelLabel)),
      FilledButton(
        style: destructive ? FilledButton.styleFrom(backgroundColor: AppColors.danger) : null,
        onPressed: () => Navigator.pop(context, true),
        child: Text(confirmLabel),
      ),
    ],
  );
  return result ?? false;
}

Future<DateTimeRange?> pickInclusiveDateRange(
  BuildContext context, {
  DateTime? from,
  DateTime? to,
}) {
  final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
  final monthStart = DateTime(today.year, today.month, 1);
  final start = DateTime((from ?? monthStart).year, (from ?? monthStart).month, (from ?? monthStart).day);
  final end = DateTime((to ?? today).year, (to ?? today).month, (to ?? today).day);
  return showDateRangePicker(
    context: context,
    firstDate: DateTime(2020),
    lastDate: today.add(const Duration(days: 30)),
    initialDateRange: DateTimeRange(start: start.isAfter(end) ? end : start, end: end),
    helpText: 'Select start and end dates',
    saveText: 'Apply',
    builder: (context, child) {
      return Theme(
        data: Theme.of(context).copyWith(colorScheme: Theme.of(context).colorScheme.copyWith(primary: AppColors.purple)),
        child: child!,
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
