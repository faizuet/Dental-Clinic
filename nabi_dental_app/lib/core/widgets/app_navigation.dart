import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import 'app_layout.dart';

class AppShellController extends InheritedWidget {
  const AppShellController({
    super.key,
    required this.hasSidebar,
    required this.openDrawer,
    required super.child,
    this.tools,
  });

  final bool hasSidebar;
  final VoidCallback? openDrawer;
  final Widget? tools;

  static AppShellController? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<AppShellController>();
  }

  @override
  bool updateShouldNotify(AppShellController oldWidget) {
    return hasSidebar != oldWidget.hasSidebar || openDrawer != oldWidget.openDrawer || tools != oldWidget.tools;
  }
}

Future<T?> appPush<T extends Object?>(BuildContext context, String location) {
  return context.push<T>(location);
}

Future<void> appPushAndRefresh(
  BuildContext context,
  String location,
  Future<void> Function() refresh,
) async {
  await appPush(context, location);
  if (context.mounted) {
    await refresh();
  }
}

void appPop(BuildContext context, {String? fallback}) {
  if (context.canPop()) {
    context.pop();
    return;
  }
  if (fallback != null) {
    context.go(fallback);
  }
}

class AppBackButton extends StatelessWidget {
  const AppBackButton({super.key, this.fallback});

  final String? fallback;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Back',
      icon: const Icon(Icons.arrow_back_rounded),
      onPressed: () => appPop(context, fallback: fallback),
    );
  }
}

AppBar buildAppBar({
  required BuildContext context,
  required String title,
  String? fallback,
  bool isRoot = false,
  List<Widget>? actions,
  PreferredSizeWidget? bottom,
}) {
  final shell = AppShellController.maybeOf(context);
  Widget? leading;
  var imply = true;
  if (isRoot && shell != null && shell.hasSidebar) {
    leading = null;
    imply = false;
  } else if (isRoot && shell?.openDrawer != null) {
    leading = IconButton(
      tooltip: 'Menu',
      icon: const Icon(Icons.menu_rounded),
      onPressed: shell!.openDrawer,
    );
    imply = false;
  } else {
    leading = AppBackButton(fallback: fallback);
  }
  final tools = shell != null && shell.hasSidebar ? shell.tools : null;
  return AppBar(
    automaticallyImplyLeading: imply,
    leading: leading,
    toolbarHeight: tools == null ? kToolbarHeight : 68,
    titleSpacing: leading == null && !imply ? AppLayout.horizontalPadding(context) : 0,
    title: AppBarTitle(title),
    actions: [
      ...?actions,
      if (tools != null) ...[
        const SizedBox(width: 8),
        tools,
      ],
      const SizedBox(width: 12),
    ],
    bottom: bottom,
  );
}

Future<bool> showExitAppDialog(BuildContext context) {
  return showAppConfirmDialog(
    context: context,
    title: 'Exit the app?',
    message: 'Are you sure you want to exit? You can open Nabi Dental Clinic again whenever you need it.',
    cancelLabel: 'Cancel',
    confirmLabel: 'Exit',
    icon: Icons.logout_rounded,
  );
}

class AppExitScope extends StatelessWidget {
  const AppExitScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) {
          return;
        }
        final shouldExit = await showExitAppDialog(context);
        if (shouldExit && context.mounted) {
          await SystemNavigator.pop();
        }
      },
      child: child,
    );
  }
}

Future<bool> confirmDiscardChanges(BuildContext context) {
  return showAppConfirmDialog(
    context: context,
    title: 'Discard these changes?',
    message: 'What you typed will not be saved.',
    cancelLabel: 'Keep editing',
    confirmLabel: 'Discard',
    destructive: true,
    icon: Icons.edit_off_rounded,
  );
}

class AppDiscardScope extends StatefulWidget {
  const AppDiscardScope({
    super.key,
    required this.dirty,
    required this.child,
    this.fallback,
  });

  final bool dirty;
  final Widget child;
  final String? fallback;

  @override
  State<AppDiscardScope> createState() => _AppDiscardScopeState();
}

class _AppDiscardScopeState extends State<AppDiscardScope> {
  var _allowPop = false;

  Future<void> _confirmAndLeave() async {
    final discard = await confirmDiscardChanges(context);
    if (!discard || !mounted) {
      return;
    }
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        appPop(context, fallback: widget.fallback);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !widget.dirty || _allowPop,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || !widget.dirty || _allowPop) {
          return;
        }
        await _confirmAndLeave();
      },
      child: widget.child,
    );
  }
}

void showAppSnack(BuildContext context, String message, {bool error = false}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(error ? Icons.error_outline_rounded : Icons.check_circle_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: error ? AppColors.danger : AppColors.navy,
        width: MediaQuery.sizeOf(context).width >= 840 ? 460 : null,
      ),
    );
}
