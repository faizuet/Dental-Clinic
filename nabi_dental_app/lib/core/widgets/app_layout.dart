import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../errors/friendly_error.dart';

class AppLayout {
  static const double compactWidth = 360;
  static const double desktopWidth = 900;
  static const double wideWidth = 1180;

  static bool isCompact(BuildContext context) => MediaQuery.sizeOf(context).width < compactWidth;

  static bool isDesktop(BuildContext context) => MediaQuery.sizeOf(context).width >= desktopWidth;

  static bool isWide(BuildContext context) => MediaQuery.sizeOf(context).width >= wideWidth;

  static bool showSidebar(BuildContext context) => MediaQuery.sizeOf(context).width >= 840;

  static bool showExtendedSidebar(BuildContext context) => MediaQuery.sizeOf(context).width >= 1100;

  static double horizontalPadding(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < compactWidth) {
      return 16;
    }
    if (width >= wideWidth) {
      return 32;
    }
    if (width >= desktopWidth) {
      return 28;
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

  static double maxContent(BuildContext context) {
    if (isWide(context)) {
      return 1280;
    }
    if (isDesktop(context)) {
      return 1080;
    }
    return AppSpacing.maxContent;
  }

  static double dialogWidth(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < 480) {
      return width - 32;
    }
    if (isDesktop(context)) {
      return 520;
    }
    return 400;
  }

  static int columnsFor(BuildContext context, {double minWidth = 280}) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= minWidth * 3 + 48) {
      return 3;
    }
    if (width >= minWidth * 2 + 24) {
      return 2;
    }
    return 1;
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

class AppSplit extends StatelessWidget {
  const AppSplit({
    super.key,
    required this.primary,
    required this.secondary,
    this.breakpoint = 840,
    this.spacing = 20,
    this.primaryFlex = 5,
    this.secondaryFlex = 6,
  });

  final Widget primary;
  final Widget secondary;
  final double breakpoint;
  final double spacing;
  final int primaryFlex;
  final int secondaryFlex;

  Widget _shrink(Widget child) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [child],
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < breakpoint) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              primary,
              SizedBox(height: spacing),
              secondary,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: primaryFlex, child: _shrink(primary)),
            SizedBox(width: spacing),
            Expanded(flex: secondaryFlex, child: _shrink(secondary)),
          ],
        );
      },
    );
  }
}

class ResponsiveGrid extends StatelessWidget {
  const ResponsiveGrid({
    super.key,
    required this.children,
    this.minItemWidth = 260,
    this.spacing = 12,
    this.runSpacing = 0,
  });

  final List<Widget> children;
  final double minItemWidth;
  final double spacing;
  final double runSpacing;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) {
      return const SizedBox.shrink();
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        var columns = (width / minItemWidth).floor();
        if (columns < 1) {
          columns = 1;
        }
        if (columns > children.length) {
          columns = children.length;
        }
        final itemWidth = columns == 1 ? width : (width - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: runSpacing,
          children: [
            for (final child in children)
              SizedBox(width: itemWidth, child: child),
          ],
        );
      },
    );
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
  required List<Widget> Function(BuildContext dialogContext) actions,
  IconData? icon,
  AppDialogTone tone = AppDialogTone.neutral,
  bool barrierDismissible = true,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    useRootNavigator: true,
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
          width: AppLayout.dialogWidth(dialogContext),
          child: SingleChildScrollView(
            child: DefaultTextStyle(
              style: Theme.of(dialogContext).textTheme.bodyMedium!.copyWith(color: AppColors.muted, height: 1.45),
              child: content,
            ),
          ),
        ),
        actions: actions(dialogContext),
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
    actions: (dialogContext) => [
      TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(cancelLabel)),
      FilledButton(
        style: destructive ? FilledButton.styleFrom(backgroundColor: AppColors.danger) : null,
        onPressed: () => Navigator.pop(dialogContext, true),
        child: Text(confirmLabel),
      ),
    ],
  );
  return result ?? false;
}

Future<bool> showAppDeleteDialog({
  required BuildContext context,
  required String title,
  required String message,
  String cancelLabel = 'Cancel',
  String confirmLabel = 'Delete',
  required Future<void> Function() onConfirm,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (dialogContext) => _DeleteConfirmDialog(
      title: title,
      message: message,
      cancelLabel: cancelLabel,
      confirmLabel: confirmLabel,
      onConfirm: onConfirm,
    ),
  );
  return result ?? false;
}

class _DeleteConfirmDialog extends StatefulWidget {
  const _DeleteConfirmDialog({
    required this.title,
    required this.message,
    required this.cancelLabel,
    required this.confirmLabel,
    required this.onConfirm,
  });

  final String title;
  final String message;
  final String cancelLabel;
  final String confirmLabel;
  final Future<void> Function() onConfirm;

  @override
  State<_DeleteConfirmDialog> createState() => _DeleteConfirmDialogState();
}

class _DeleteConfirmDialogState extends State<_DeleteConfirmDialog> {
  var _busy = false;
  String? _error;

  Future<void> _confirm() async {
    if (_busy) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onConfirm();
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = friendlyError(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final inset = size.width < 360 ? 16.0 : 24.0;
    return AlertDialog(
      insetPadding: EdgeInsets.symmetric(horizontal: inset, vertical: 24),
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
      actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: AppColors.dangerSoft, borderRadius: BorderRadius.circular(AppRadii.md)),
            child: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
          ),
          const SizedBox(height: 14),
          Text(widget.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        ],
      ),
      content: SizedBox(
        width: AppLayout.dialogWidth(context),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.message, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.muted, height: 1.45)),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.danger)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: Text(widget.cancelLabel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
          onPressed: _busy ? null : _confirm,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Text(widget.confirmLabel),
        ),
      ],
    );
  }
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

